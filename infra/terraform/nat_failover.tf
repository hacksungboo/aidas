# nat_failover.tf
# AZ 장애 시 NAT EC2 트래픽 자동 전환
# ├── CloudWatch Alarm (StatusCheckFailed_System) — nat_ec2_a, nat_ec2_c
# ├── SNS Topic — NAT failover 전용
# ├── Lambda — 라우트 테이블 교체 + Slack 알림
# └── IAM — Lambda EC2 route 수정 권한

# ─── 1. NAT Failover 전용 SNS Topic ──────────────────────────────
resource "aws_sns_topic" "nat_failover_topic" {
  name = "${var.project_name}-nat-failover-topic"
  tags = { Name = "${var.project_name}-nat-failover-topic" }
}

# ─── 2. CloudWatch Alarm — StatusCheckFailed_System ─────────────
resource "aws_cloudwatch_metric_alarm" "nat_ec2_a_status" {
  alarm_name          = "${var.project_name}-nat-ec2-a-status"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "NAT EC2 AZ-A 시스템 장애 감지 → 라우트 자동 전환"
  alarm_actions       = [aws_sns_topic.nat_failover_topic.arn]
  ok_actions          = [aws_sns_topic.nat_failover_topic.arn]

  dimensions = {
    InstanceId = aws_instance.nat_ec2_a.id
  }

  tags = { Name = "${var.project_name}-nat-ec2-a-status" }
}

resource "aws_cloudwatch_metric_alarm" "nat_ec2_c_status" {
  alarm_name          = "${var.project_name}-nat-ec2-c-status"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "NAT EC2 AZ-C 시스템 장애 감지 → 라우트 자동 전환"
  alarm_actions       = [aws_sns_topic.nat_failover_topic.arn]
  ok_actions          = [aws_sns_topic.nat_failover_topic.arn]

  dimensions = {
    InstanceId = aws_instance.nat_ec2_c.id
  }

  tags = { Name = "${var.project_name}-nat-ec2-c-status" }
}

# ─── 3. IAM Role — Lambda용 ──────────────────────────────────────
resource "aws_iam_role" "nat_failover_role" {
  name = "${var.project_name}-nat-failover-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-nat-failover-role" }
}

resource "aws_iam_role_policy" "nat_failover_policy" {
  name = "${var.project_name}-nat-failover-policy"
  role = aws_iam_role.nat_failover_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeRouteTables", "ec2:ReplaceRoute"]
        Resource = "*"
      }
    ]
  })
}

# ─── 4. Lambda 패키징 ─────────────────────────────────────────────
data "archive_file" "nat_failover_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/nat_failover/handler.py"
  output_path = "${path.module}/lambda/nat_failover.zip"
}

# ─── 5. Lambda 함수 ──────────────────────────────────────────────
resource "aws_lambda_function" "nat_failover" {
  function_name    = "${var.project_name}-nat-failover"
  role             = aws_iam_role.nat_failover_role.arn
  filename         = data.archive_file.nat_failover_zip.output_path
  source_code_hash = data.archive_file.nat_failover_zip.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      PRIVATE_RT_A_ID   = aws_route_table.private_rt_a.id
      PRIVATE_RT_C_ID   = aws_route_table.private_rt_c.id
      NAT_A_ENI_ID      = aws_instance.nat_ec2_a.primary_network_interface_id
      NAT_C_ENI_ID      = aws_instance.nat_ec2_c.primary_network_interface_id
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  tags = { Name = "${var.project_name}-nat-failover" }
}

# ─── 6. SNS → Lambda 구독 ────────────────────────────────────────
resource "aws_sns_topic_subscription" "nat_failover_sub" {
  topic_arn = aws_sns_topic.nat_failover_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.nat_failover.arn
}

resource "aws_lambda_permission" "nat_failover_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nat_failover.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.nat_failover_topic.arn
}
