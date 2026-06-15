# lambda.tf

# ─── 1. Lambda 실행 IAM Role & 정책 ──────────────────────────────────
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

# 기본 실행 정책 (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 🌟 [추가] DynamoDB에 인시던트 로그를 저장할 수 있는 인라인 정책
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.project_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ]
      Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-incidents" # 혹은 var.dynamodb_table_arn
    }]
  })
}

# ─── 2. Lambda 소스코드 패키징 (외부 파일 참조형) ─────────────────────
# 🌟 인라인 텍스트 대신 외부의 lambda_function.py 파일을 직접 지정하여 압축합니다.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../../lambda/analyzer/lambda_function.py"
  output_path = "${path.module}/aidas_analyzer_lambda.zip"
}

# ─── 3. Lambda Function 생성 ───────────────────────────────────────
resource "aws_lambda_function" "slack_alert" {
  function_name    = "${var.project_name}-slack-alert"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  runtime = "python3.11"
  # 🌟 파일명이 lambda_function.py 이고 내부 진입점이 lambda_handler 이므로 아래와 같이 수정합니다.
  handler = "lambda_function.lambda_handler"
  timeout = 30  # AI 분석 데이터를 처리하고 외부 API 호출이 엮여있으므로 넉넉하게 30초 할당

  logging_config {
    log_group  = "/aws/lambda/${var.project_name}-slack-alert"
    log_format = "Text"
  }

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      DYNAMODB_TABLE    = "${var.project_name}-incidents"
    }
  }

  tags = { Name = "${var.project_name}-slack-alert" }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_dynamodb
  ]
}

# ─── 4. SNS → Lambda 구독 연결 (유지) ────────────────────────────────────
resource "aws_sns_topic_subscription" "lambda_sub" {
  topic_arn = aws_sns_topic.alarm_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_alert.arn
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarm_topic.arn
}