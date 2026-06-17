import json
import os
import boto3
import urllib.request
from urllib.error import HTTPError
from datetime import datetime, timezone, timedelta
import time

# ─── 환경변수 ──────────────────────────
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL")
DYNAMODB_TABLE    = os.environ.get("DYNAMODB_TABLE", "aidas-incidents")
AWS_REGION        = os.environ.get("AWS_REGION", "ap-northeast-2")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table    = dynamodb.Table(DYNAMODB_TABLE)

# 🌟 [리뷰 반영 2] Fallback 시간도 Loki와 동일한 '나노초 정수 문자열'로 통일
def get_nanosec_timestamp() -> str:
    return str(time.time_ns())

def send_slack(original_log: str, analysis: str, elapsed: float):
    if not SLACK_WEBHOOK_URL:
        print("[AIDAS] ❌ SLACK_WEBHOOK_URL 환경변수가 없어 슬랙 알림을 생략합니다.")
        return

    # 🌟 [리뷰 반영 3] 마크다운 충돌 방지: 로그 내의 백틱(```) 치환 (Sanitization)
    sanitized_log = original_log.replace("```", "'''")
    
    # 🌟 슬랙 3000자 제한 및 빈 문자열 방어
    safe_log = sanitized_log[:2500] + "\n...(생략됨)" if len(sanitized_log) > 2500 else sanitized_log
    safe_log = safe_log if safe_log.strip() else "로그 내용 없음"
    
    safe_analysis = analysis[:2500] + "\n...(생략됨)" if len(analysis) > 2500 else analysis
    safe_analysis = safe_analysis if safe_analysis.strip() else "AI 분석 결과가 비어있습니다."

    try:
        message = {
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": "🔍 AIDAS AI 분석 완료"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*원본 로그*\n```\n{safe_log}\n```"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*AI 분석 결과*\n{safe_analysis}"
                    }
                },
                {
                    "type": "context",
                    "elements": [
                        {
                            "type": "mrkdwn",
                            "text": f"⏱ 분석 소요 시간: {elapsed:.2f}초"
                        }
                    ]
                }
            ]
        }
        
        req = urllib.request.Request(
            SLACK_WEBHOOK_URL,
            data    = json.dumps(message).encode("utf-8"),
            headers = {"Content-Type": "application/json"},
            method  = "POST"
        )
        with urllib.request.urlopen(req) as res:
            print(f"[AIDAS] Slack 전송 완료: {res.status}")

    except HTTPError as e:
        print(f"[AIDAS] ❌ Slack API 거절 (HTTP {e.code}): {e.read().decode('utf-8')}")
    except Exception as e:
        print(f"[AIDAS] ❌ Slack 전송 실패: {e}")

def save_dynamodb(original_log: str, analysis: str, timestamp: str, service_name: str, host: str = "unknown", scenario: str = "unknown"):
    # 1. 시간 변환 및 에러 방어 (UnboundLocalError 해결)
    try:
        ts_sec = int(timestamp) / 1_000_000_000
        kst_tz = timezone(timedelta(hours=9))
        dt_kst = datetime.fromtimestamp(ts_sec, kst_tz)
        readable_time = dt_kst.strftime('%Y-%m-%d %H:%M')
        error_date = dt_kst.strftime('%Y-%m-%d')  # 🌟 try 안에서 미리 선언
    except Exception:
        readable_time = "Unknown Time"
        error_date = "Unknown Date"               # 🌟 except로 빠져도 변수가 존재하도록 방어!

    incident_id = f"incident-{timestamp}"

    # 2. 장애 유형 한글 매핑
    scenario_kr = {
        "db_timeout": "DB 연결 타임아웃",
        "oom": "메모리 부족(OOM)",
        "az_failure": "AZ 장애",
        "http_500": "HTTP 500 에러",
        "unknown": "미분류"
    }.get(scenario, "미분류")

    # 3. 요약 필드 생성
    summary = f"[{readable_time}] {host} - {scenario_kr}"

    # 4. DynamoDB 저장
    try:
        table.put_item(
            Item={
                "incident_id":   incident_id,
                "summary":       summary,             
                "error_date":    error_date,          # 🌟 수정된 안전한 변수 사용
                "error_time_kst": readable_time,
                "host":          host,                
                "scenario":      scenario,            
                "scenario_kr":   scenario_kr,
                "timestamp":     timestamp,
                "status":        "OPEN",
                "severity":      "HIGH",
                "service_name":  service_name,
                "original_log":  original_log,
                "analysis":      analysis
            }
        )
        print("[AIDAS] DynamoDB 저장 완료")
    except Exception as e:
        print(f"[AIDAS] ❌ DynamoDB 저장 실패: {e}")

def lambda_handler(event, context):
    print(f"📥 수신된 이벤트: {json.dumps(event)}")
    
    if not event.get("service_name"):
        print("[AIDAS] 👻 필수 데이터가 없는 유령 이벤트 감지 -> 무시함")
        return {"statusCode": 200, "body": "Ignored empty event"}
        
    if not event.get("ai_analysis_result") or not event.get("ai_analysis_result").strip():
        print("[AIDAS] ⚠️ AI 분석 결과가 비어있음 -> 슬랙 도배 방지를 위해 2차 알림/DB 저장 생략")
        return {"statusCode": 200, "body": "Ignored empty analysis"}

    original_log = event.get("original_log", "")
    analysis     = event.get("ai_analysis_result", "")
    elapsed      = event.get("elapsed", 0.0)
    service_name = event.get("service_name", "unknown")
    host         = event.get("host", "unknown")        # 🌟 추가
    scenario     = event.get("scenario", "unknown")    # 🌟 추가
    
    timestamp    = event.get("timestamp") or get_nanosec_timestamp()

    send_slack(original_log, analysis, elapsed)
    save_dynamodb(original_log, analysis, timestamp, service_name, host, scenario)  # 🌟 두 값 추가 전달

    return {"statusCode": 200, "body": "OK"}