# github.tf
# Terraform apply 시 GitHub Actions Secrets 자동 등록

# ─── EC2 접속 정보 ────────────────────────────────────────────────
# → IP가 바뀌어도 이름이 고정되므로 재프로비저닝 시에도 자동 반영
resource "github_actions_secret" "ec2_host" {
  repository      = "aidas"
  secret_name     = "EC2_HOST"
  plaintext_value = "${var.host_name}.${var.tailnet_name}"
}

resource "github_actions_secret" "ec2_user" {
  repository      = "aidas"
  secret_name     = "EC2_USER"
  plaintext_value = "ec2-user"
}

# compute.tf에서 tls_private_key로 자동 생성된 키를 그대로 등록
resource "github_actions_secret" "ec2_ssh_key" {
  repository      = "aidas"
  secret_name     = "EC2_SSH_KEY"
  plaintext_value = tls_private_key.pk.private_key_pem
}

# ─── Docker Hub ───────────────────────────────────────────────────
resource "github_actions_secret" "dockerhub_username" {
  repository      = "aidas"
  secret_name     = "DOCKERHUB_USERNAME"
  plaintext_value = var.dockerhub_username
}

resource "github_actions_secret" "dockerhub_token" {
  repository      = "aidas"
  secret_name     = "DOCKERHUB_TOKEN"
  plaintext_value = var.dockerhub_token
}

# ─── 애플리케이션 설정 ────────────────────────────────────────────
resource "github_actions_secret" "db_url" {
  repository      = "aidas"
  secret_name     = "DB_URL"
  plaintext_value = var.db_url
}

# ─── AWS 자격증명 ─────────────────────────────────────────────────
resource "github_actions_secret" "aws_access_key" {
  repository      = "aidas"
  secret_name     = "AWS_ACCESS_KEY_ID"
  plaintext_value = var.aws_access_key
}

resource "github_actions_secret" "aws_secret_key" {
  repository      = "aidas"
  secret_name     = "AWS_SECRET_ACCESS_KEY"
  plaintext_value = var.aws_secret_key
}
