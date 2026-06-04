# lambda.tf
# ├── IAM Role & Policy
# ├── Lambda Function (Slack 알림)
# └── SNS → Lambda 구독 연결

# ─── 1. Lambda 실행 IAM Role ──────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-lambda-role" }
}

# Lambda 기본 실행 정책 (CloudWatch Logs 쓰기)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ─── 2. Lambda 소스코드 (Python) ──────────────────────────────────
# slack_alert.py 를 zip으로 패키징
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda/slack_alert.zip"

  source {
    filename = "slack_alert.py"
    content  = <<-PYTHON
      import json
      import os
      import urllib.request

      SLACK_WEBHOOK_URL = os.environ["SLACK_WEBHOOK_URL"]

      def lambda_handler(event, context):
          # SNS 메시지 파싱
          sns_message = event["Records"][0]["Sns"]
          subject     = sns_message.get("Subject", "AWS 알람")
          message_raw = sns_message.get("Message", "{}")

          try:
              message = json.loads(message_raw)
              alarm_name  = message.get("AlarmName", subject)
              state       = message.get("NewStateValue", "UNKNOWN")
              reason      = message.get("NewStateReason", "")
              region      = message.get("Region", "")
              account     = message.get("AWSAccountId", "")
          except (json.JSONDecodeError, KeyError):
              alarm_name = subject
              state      = "UNKNOWN"
              reason     = message_raw
              region     = ""
              account    = ""

          # 상태별 이모지 & 색상
          state_map = {
              "ALARM": {"emoji": ":red_circle:",  "color": "#FF0000"},
              "OK":    {"emoji": ":green_circle:", "color": "#36A64F"},
          }
          style = state_map.get(state, {"emoji": ":yellow_circle:", "color": "#FFA500"})

          # Slack 메시지 구성
          payload = {
              "attachments": [{
                  "color": style["color"],
                  "blocks": [
                      {
                          "type": "header",
                          "text": {
                              "type": "plain_text",
                              "text": f"{style['emoji']} {alarm_name}"
                          }
                      },
                      {
                          "type": "section",
                          "fields": [
                              {"type": "mrkdwn", "text": f"*상태:*\n{state}"},
                              {"type": "mrkdwn", "text": f"*리전:*\n{region}"},
                              {"type": "mrkdwn", "text": f"*계정:*\n{account}"},
                              {"type": "mrkdwn", "text": f"*원인:*\n{reason}"}
                          ]
                      }
                  ]
              }]
          }

          req = urllib.request.Request(
              SLACK_WEBHOOK_URL,
              data    = json.dumps(payload).encode("utf-8"),
              headers = {"Content-Type": "application/json"},
              method  = "POST"
          )

          with urllib.request.urlopen(req) as res:
              print(f"Slack 응답: {res.status}")

          return {"statusCode": 200, "body": "OK"}
    PYTHON
  }
}

# ─── 3. Lambda Function ───────────────────────────────────────────
resource "aws_lambda_function" "slack_alert" {
  function_name = "${var.project_name}-slack-alert"
  role          = aws_iam_role.lambda_role.arn
  filename      = data.archive_file.lambda_zip.output_path
  # 코드 변경 시 자동 재배포
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  runtime = "python3.12"
  handler = "slack_alert.lambda_handler"
  timeout = 10  # 초

  # monitoring.tf에서 미리 만든 Log Group 사용
  logging_config {
    log_group  = "/aws/lambda/${var.project_name}-slack-alert"
    log_format = "Text"
  }

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  tags = { Name = "${var.project_name}-slack-alert" }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda_logs  # monitoring.tf의 Log Group
  ]
}

# ─── 4. SNS → Lambda 구독 연결 ────────────────────────────────────
resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.alarm_topic.arn  # monitoring.tf의 SNS
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_alert.arn
}

# SNS가 Lambda를 호출할 수 있도록 권한 부여
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarm_topic.arn
}

