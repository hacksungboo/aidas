import json
import os
import boto3
import urllib.request
from urllib.error import HTTPError
from datetime import datetime, timezone

# ─── 환경변수 (죽지 않도록 안전하게 get 사용) ──────────────────────────
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL")
DYNAMODB_TABLE    = os.environ.get("DYNAMODB_TABLE", "aidas-incidents")
AWS_REGION        = os.environ.get("AWS_REGION", "ap-northeast-2")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table    = dynamodb.Table(DYNAMODB_TABLE)

def get_timestamp() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"

def send_slack(original_log: str, analysis: str, elapsed: float):
    if not SLACK_WEBHOOK_URL:
        print("[AIDAS] ❌ SLACK_WEBHOOK_URL 환경변수가 없어 슬랙 알림을 생략합니다.")
        return

    # 🌟 슬랙의 3000자 제한을 넘지 않도록 2500자에서 안전하게 자르기 + 빈 문자열 방어
    safe_log = original_log[:2500] + "\n...(생략됨)" if len(original_log) > 2500 else original_log
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
        # 🌟 슬랙이 왜 거절했는지 정확한 이유를 CloudWatch에 출력
        print(f"[AIDAS] ❌ Slack API 거절 (HTTP {e.code}): {e.read().decode('utf-8')}")
    except Exception as e:
        print(f"[AIDAS] ❌ Slack 전송 실패: {e}")

def save_dynamodb(original_log: str, analysis: str, timestamp: str, service_name: str):
    try:
        table.put_item(
            Item={
                "incident_id":       f"incident-{timestamp}",
                "timestamp":         timestamp,
                "status":            "OPEN",    # 🌟 테라폼 스키마에 맞게 이름 수정
                "severity":          "HIGH",    # 🌟 테라폼 스키마에 맞게 이름 수정
                "service_name":      service_name,
                "original_log":      original_log,
                "analysis":          analysis
            }
        )
        print("[AIDAS] DynamoDB 저장 완료")

    except Exception as e:
        print(f"[AIDAS] ❌ DynamoDB 저장 실패: {e}")

def lambda_handler(event, context):
    print(f"📥 수신된 이벤트: {json.dumps(event)}")
    
    original_log = event.get("original_log", "")
    analysis     = event.get("ai_analysis_result", "")
    elapsed      = event.get("elapsed", 0.0)
    service_name = event.get("service_name", "unknown")
    timestamp    = event.get("timestamp") or get_timestamp()

    send_slack(original_log, analysis, elapsed)
    save_dynamodb(original_log, analysis, timestamp, service_name)

    return {"statusCode": 200, "body": "OK"}