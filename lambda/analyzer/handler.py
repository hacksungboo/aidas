import os
import json
import httpx
import asyncio
import boto3
import re
import logging
import time
from datetime import datetime, timedelta
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

LOKI_URL = os.getenv("LOKI_URL", "http://localhost:3100")
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434/api/generate")
AI_MODEL_NAME = "qwen2.5-coder:7b"
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")

AWS_REGION = os.getenv("AWS_REGION", "ap-northeast-2")
LAMBDA_FUNCTION_NAME = os.getenv("LAMBDA_FUNCTION_NAME", "aidas-slack-alert")
lambda_client = boto3.client('lambda', region_name=AWS_REGION)
PROMPT_PATH = os.getenv("PROMPT_PATH", "/home/user1/aidas/prompts/system_prompt.md")
SCENARIO_PATH = "/home/user1/aidas/prompts/scenarios"

# 전역 변수: 서비스별 타임스탬프 격리 딕셔너리
last_processed_ts = {}


def get_system_prompt():
    try:
        with open(PROMPT_PATH, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        logger.warning(f"🚨 {PROMPT_PATH} 파일이 없습니다.")
        return "너는 시스템 에러를 분석하는 AI 엔지니어다."


def trigger_lambda_sync(log_data: dict, clean_ai_analysis: str, elapsed: float):
    payload = {
        "service_name":       log_data.get("service_name"),
        "timestamp":          log_data.get("timestamp"),
        "original_log":       log_data.get("message"),
        "ai_analysis_result": clean_ai_analysis,
        "elapsed":            elapsed
    }
    try:
        lambda_client.invoke(
            FunctionName=LAMBDA_FUNCTION_NAME,
            InvocationType='Event',
            Payload=json.dumps(payload)
        )
        logger.info("✅ AWS Lambda(boto3) 트리거 완료 -> Slack/DynamoDB 진행됨")
    except Exception as e:
        logger.error(f"❌ AWS Lambda 호출 실패: {e}")


async def send_slack_immediate_alert(log_data: dict):
    payload = {
        "text": (
            f"🚨 *[AIDAS 장애 감지]*\n"
            f"*서비스:* `{log_data.get('service_name')}`\n"
            f"*원본 로그:*\n```{log_data.get('message')}```\n"
            f"⏳ AI 분석 중..."
        )
    }
    async with httpx.AsyncClient() as client:
        await client.post(SLACK_WEBHOOK_URL, json=payload)
    logger.info("✅ 1차 Slack 알림 발송 완료 (원본 로그)")


async def send_slack_fallback_alert(log_data: dict, error_reason: str):
    payload = {
        "text": (
            f"⚠️ *[AIDAS AI 분석 실패]*\n"
            f"*에러 내용:* `{log_data.get('message')}`\n"
            f"*실패 사유:* {error_reason}"
        )
    }
    async with httpx.AsyncClient() as client:
        await client.post(SLACK_WEBHOOK_URL, json=payload)


def detect_scenario(log_message: str) -> str:
    if any(kw in log_message for kw in ["DB/Connection", "DB/Pool", "DB/Retry", "psycopg2"]):
        return "db_timeout"
    elif any(kw in log_message for kw in ["OOM/Kernel", "Memory", "OOM killed"]):
        return "oom"
    elif any(kw in log_message for kw in ["ALB/TargetGroup", "Failover", "ap-northeast-2a"]):
        return "az_failure"
    elif any(kw in log_message for kw in ["Traceback", "ZeroDivisionError", "Internal Server Error"]):
        return "http_500"
    else:
        return "unknown"


def load_scenario_prompt(scenario: str) -> str:
    path = f"{SCENARIO_PATH}/{scenario}.md"
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


async def analyze_with_ai(log_message: str):
    system_prompt = get_system_prompt()
    scenario = detect_scenario(log_message)
    scenario_prompt = load_scenario_prompt(scenario)
    logger.info(f"[AIDAS] 감지된 시나리오: {scenario}")

    full_prompt = f"{system_prompt}\n\n{scenario_prompt}\n\n[분석할 에러 로그]\n{log_message}"
    full_response = ""

    try:
        async with httpx.AsyncClient() as client:
            async with client.stream("POST", OLLAMA_API_URL, json={
                "model": AI_MODEL_NAME,
                "prompt": full_prompt,
                "stream": True,
                "options": {
                    "num_predict": 512,
                    "temperature": 0.1,
                    "top_p": 0.9
                }
            }, timeout=120.0) as response:
                # 스트리밍 청크 에러 해결: aiter_lines()로 안전하게 파싱
                async for line in response.aiter_lines():
                    if line:
                        try:
                            data = json.loads(line)
                            full_response += data.get("response", "")
                        except json.JSONDecodeError:
                            pass

        clean_response = re.sub(r'<thinking>.*?</thinking>', '', full_response, flags=re.DOTALL).strip()
        return clean_response
    except Exception as e:
        raise e


async def poll_loki_and_analyze():
    global last_processed_ts

    # 시간 오차 방어 윈도우: 10분(600초)
    end_ns = time.time_ns()
    start_ns = end_ns - (600 * 1_000_000_000)

    # Nginx 소문자 에러 포착: (?i) 추가
    query = '{job=~".+"} |~ "(?i)error|fatal|warn"'

    params = {
        'query': query,
        'start': str(start_ns),
        'end': str(end_ns),
        'limit': 100
    }

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{LOKI_URL}/loki/api/v1/query_range", params=params)
            resp.raise_for_status()
            data = resp.json()

        results = data.get('data', {}).get('result', [])

        # 에러 바구니 준비
        logs_by_service = {}

        for res in results:
            service_name = res.get('stream', {}).get('job', 'unknown')
            values = sorted(res.get('values', []), key=lambda x: int(x[0]))

            # 스트림 라벨 오작동 방지: 서비스명으로만 타임스탬프 체크
            service_last_ts = last_processed_ts.get(service_name, 0)
            max_ts_in_stream = service_last_ts

            for timestamp_str, message in values:
                ts_int = int(timestamp_str)
                if ts_int <= service_last_ts:
                    continue
                
                # 새로운 에러만 바구니에 담기
                if service_name not in logs_by_service:
                    logs_by_service[service_name] = {"messages": [], "max_ts": 0}
                    
                logs_by_service[service_name]["messages"].append(message)
                logs_by_service[service_name]["max_ts"] = max(logs_by_service[service_name]["max_ts"], ts_int)
                max_ts_in_stream = max(max_ts_in_stream, ts_int)

            # 타임스탬프 업데이트
            if service_name in logs_by_service:
                last_processed_ts[service_name] = max(last_processed_ts.get(service_name, 0), max_ts_in_stream)

        # 묶음으로 한 번만 전송
        for service_name, data in logs_by_service.items():
            if data["messages"]:
                combined_message = "\n".join(data["messages"])
                max_ts_in_batch = data["max_ts"]
                
                log_data = {
                    "service_name": service_name,
                    "timestamp": str(max_ts_in_batch),
                    "message": combined_message
                }

                logger.info(f"🚨 신규 에러 {len(data['messages'])}건 묶음 감지! ([{service_name}]) 1차 알림 발송...")

                await send_slack_immediate_alert(log_data)

                try:
                    start = time.time()
                    clean_analysis = await analyze_with_ai(combined_message)
                    elapsed = time.time() - start
                    trigger_lambda_sync(log_data, clean_analysis, elapsed)
                except Exception as ai_e:
                    await send_slack_fallback_alert(log_data, str(ai_e))

    except Exception as e:
        logger.error(f"Loki 폴링 실패: {e}")


async def main():
    logger.info("AIDAS Log Analyzer 시작됨 (5초 주기)")
    scheduler = AsyncIOScheduler()
    scheduler.add_job(poll_loki_and_analyze, 'interval', seconds=5)
    scheduler.start()
    await asyncio.Event().wait()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        logger.info("핸들러 안전하게 종료됨")