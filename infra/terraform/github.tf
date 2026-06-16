# github.tf
# Terraform apply 시 GitHub Actions Secrets 자동 등록


# ─── EC2 접속 정보 ────────────────────────────────────────────────
# → IP가 바뀌어도 이름이 고정되므로 재프로비저닝 시에도 자동 반영
resource "github_actions_secret" "ec2_host" {
  repository      = var.github_repo
  secret_name     = "EC2_HOST"
  plaintext_value = "${var.host_name}.${var.tailnet_name}"
}

resource "github_actions_secret" "ec2_user" {
  repository      = var.github_repo
  secret_name     = "EC2_USER"
  plaintext_value = "ec2-user"
}

# compute.tf에서 tls_private_key로 자동 생성된 키를 그대로 등록
resource "github_actions_secret" "ec2_ssh_key" {
  repository      = var.github_repo
  secret_name     = "EC2_SSH_KEY"
  plaintext_value = tls_private_key.pk.private_key_pem
}

# ─── Docker Hub ───────────────────────────────────────────────────
resource "github_actions_secret" "dockerhub_username" {
  repository      = var.github_repo
  secret_name     = "DOCKERHUB_USERNAME"
  plaintext_value = var.dockerhub_username
}

resource "github_actions_secret" "dockerhub_token" {
  repository      = var.github_repo
  secret_name     = "DOCKERHUB_TOKEN"
  plaintext_value = var.dockerhub_token
}

# ─── 애플리케이션 설정 ────────────────────────────────────────────
resource "github_actions_secret" "db_url" {
  repository      = var.github_repo
  secret_name     = "DB_URL"
  plaintext_value = var.db_url
}

# ─── AWS 자격증명 ─────────────────────────────────────────────────
resource "github_actions_secret" "aws_access_key" {
  repository      = var.github_repo
  secret_name     = "AWS_ACCESS_KEY_ID"
  plaintext_value = var.aws_access_key
}

resource "github_actions_secret" "aws_secret_key" {
  repository      = var.github_repo
  secret_name     = "AWS_SECRET_ACCESS_KEY"
  plaintext_value = var.aws_secret_key
}

resource "github_actions_secret" "alb_listener_arn" {
  repository      = var.github_repo
  secret_name     = "ALB_LISTENER_ARN"
  plaintext_value = aws_lb_listener.https.arn
}

resource "github_actions_secret" "blue_tg_arn" {
  repository      = var.github_repo
  secret_name     = "BLUE_TG_ARN"
  plaintext_value = aws_lb_target_group.blue_tg.arn
}

resource "github_actions_secret" "green_tg_arn" {
  repository      = var.github_repo
  secret_name     = "GREEN_TG_ARN"
  plaintext_value = aws_lb_target_group.green_tg.arn
}

resource "github_actions_secret" "blue_asg_name" {
  repository      = var.github_repo
  secret_name     = "BLUE_ASG_NAME"
  plaintext_value = aws_autoscaling_group.asg_blue.name
}

resource "github_actions_secret" "green_asg_name" {
  repository      = var.github_repo
  secret_name     = "GREEN_ASG_NAME"
  plaintext_value = aws_autoscaling_group.asg_green.name
}

resource "github_actions_secret" "tailscale_authkey" {
  repository      = var.github_repo
  secret_name     = "TAILSCALE_AUTHKEY"
  plaintext_value = var.tailscale_auth_key
}

resource "github_actions_secret" "slack_webhook_url" {
  repository      = var.github_repo
  secret_name     = "SLACK_WEBHOOK_URL"
  plaintext_value = var.slack_webhook_url
}

resource "github_actions_secret" "db_password" {
  repository      = var.github_repo
  secret_name     = "DB_PASSWORD"
  plaintext_value = var.db_password
}

resource "github_actions_secret" "tailscale_api_key" {
  repository      = var.github_repo
  secret_name     = "TAILSCALE_API_KEY"
  plaintext_value = var.tailscale_api_key
}

resource "github_actions_secret" "loki_url" {
  repository      = var.github_repo
  secret_name     = "LOKI_URL"
  plaintext_value = var.loki_url
}
