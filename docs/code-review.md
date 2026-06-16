# AIDAS 인프라 코드 리뷰

> 분석 대상: `infra/terraform/`, `deploy/onprem/ansible/`
> 작성일: 2026-06-15

---

## 목차
1. [보안 취약점](#1-보안-취약점) ← 즉시 수정 권장
2. [잘못된 설정](#2-잘못된-설정)
3. [하드코딩된 값](#3-하드코딩된-값)
4. [중복 코드](#4-중복-코드)
5. [구조 개선](#5-구조-개선)

---

## 1. 보안 취약점

### 1-1. NAT EC2 SSH 전체 공개
| 항목 | 내용 |
|---|---|
| 파일 | `security_group.tf:13~18` |
| 심각도 | 🔴 높음 |

**현재 코드:**
```hcl
ingress {
  description = "SSH from Tailscale only"  # 주석과 실제가 다름
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # 전체 인터넷 허용
}
```

**수정 후:**
```hcl
ingress {
  description = "SSH from Tailscale only"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["100.64.0.0/10"]  # Tailscale 대역만
}
```

**영향:** 수정 전 → 전 세계에서 SSH 공격 가능 / 수정 후 → Tailscale VPN 사용자만 접근

---

### 1-2. ASG ICMP 전체 공개
| 항목 | 내용 |
|---|---|
| 파일 | `security_group.tf:142~148` |
| 심각도 | 🟡 중간 |

**현재 코드:**
```hcl
ingress {
  description = "ICMP from onpremise"
  from_port   = -1
  to_port     = -1
  protocol    = "icmp"
  cidr_blocks = ["0.0.0.0/0"]  # 온프레미스라고 했는데 전체 허용
}
```

**수정 후:**
```hcl
  cidr_blocks = ["172.16.8.0/24"]  # 온프레미스 대역만
```

**영향:** 수정 전 → 외부에서 핑 스캔/네트워크 정찰 가능 / 수정 후 → 온프레미스 대역만 허용

---

### 1-3. Tailscale Auth Key 평문 노출
| 항목 | 내용 |
|---|---|
| 파일 | `main.tf:55` |
| 심각도 | 🔴 높음 |

**현재 코드:**
```bash
tailscale up --authkey=${tailscale_tailnet_key.ec2_join_key.key}
```

**문제:** EC2 user_data는 AWS 콘솔에서 평문 조회 가능, CloudTrail에도 기록됨

**수정 방법:** AWS Secrets Manager에서 authkey를 꺼내도록 변경하거나, ephemeral key 사용 후 즉시 폐기

---

### 1-4. Docker Hub 토큰 shell history 노출
| 항목 | 내용 |
|---|---|
| 파일 | `compute.tf:159` |
| 심각도 | 🟡 중간 |

**현재 코드:**
```bash
echo "${var.dockerhub_token}" | docker login -u "${var.dockerhub_username}" --password-stdin
```

**문제:** `echo` 명령이 shell history에 남을 수 있음, user_data에 토큰 평문 포함

**수정 방법:** AWS Secrets Manager에서 토큰 조회 후 사용
```bash
DOCKER_TOKEN=$(aws secretsmanager get-secret-value --secret-id dockerhub-token --query SecretString --output text)
echo "$DOCKER_TOKEN" | docker login -u "${var.dockerhub_username}" --password-stdin
```

---

### 1-5. Terraform 상태 파일에 시크릿 평문 저장
| 항목 | 내용 |
|---|---|
| 파일 | `github.tf` 전체 |
| 심각도 | 🔴 높음 |

**문제:** `plaintext_value`로 등록한 SSH 개인키, Docker 토큰, Slack Webhook 등이 `.tfstate` 파일에 평문 저장됨

**수정 방법:**
- S3 버킷에 SSE-KMS 암호화 적용
- tfstate 파일 접근 IAM 정책 제한
- `sensitive = true` 변수 확인

---

## 2. 잘못된 설정

### 2-1. 존재하지 않는 패키지 이름 (오타)
| 항목 | 내용 |
|---|---|
| 파일 | `compute.tf:64` |
| 심각도 | 🟡 중간 |

**현재 코드:**
```bash
dnf remove -y podman buildah cgroupby  # cgroupby는 없는 패키지
```

**수정 후:**
```bash
dnf remove -y podman buildah
```

**영향:** 수정 전 → dnf 경고 로그 발생 / 수정 후 → 깔끔한 실행

---

### 2-2. 주석과 실제 코드 불일치
| 항목 | 내용 |
|---|---|
| 파일 | `loadbalancer.tf:5` |
| 심각도 | 🟡 중간 |

**현재 코드:**
```hcl
# └── [비활성화] Route53, ACM, HTTPS 443 리스너 — 도메인 미설정 환경에서 비활성화
```
→ 실제로는 HTTPS 리스너가 **활성화** 되어 있음

**수정:** 주석 업데이트 또는 실제 비활성화 처리

---

### 2-3. 주석처리된 Ansible 실행 블록
| 항목 | 내용 |
|---|---|
| 파일 | `main.tf:131~145` |
| 심각도 | 🟢 낮음 |

**현재 상태:** `terraform_data.ansible_run` 전체 주석처리

**수정:** 사용 안 한다면 완전히 삭제 (주석처리 코드는 혼란 유발)

---

### 2-4. DB Replica 구성 방식 (구버전 PostgreSQL 방식)
| 항목 | 내용 |
|---|---|
| 파일 | `deploy/onprem/ansible/roles/db_replica/tasks/main.yml:39~43` |
| 심각도 | 🟡 중간 |

**현재 코드:**
```bash
pg_basebackup ... -R  # -R 플래그: recovery.conf 자동 생성 (구버전 방식)
```

**문제:** PostgreSQL 12+ 에서는 `standby.signal` + `postgresql.conf` 방식 권장

---

### 2-5. handler.py 서비스 관리 미흡
| 항목 | 내용 |
|---|---|
| 파일 | `deploy/onprem/ansible/roles/rocky01_handler/tasks/main.yml:64~66` |
| 심각도 | 🟡 중간 |

**현재 코드:**
```bash
nohup python3.11 {{ aidas_ai_dir }}/handler.py > {{ aidas_log_file }} 2>&1 &
```

**문제:** 재부팅 시 자동 실행 안 됨, 프로세스 죽어도 재시작 안 됨, 로그 로테이션 없음

**수정 방법:** systemd service로 전환
```ini
[Unit]
Description=AIDAS Handler

[Service]
ExecStart=/usr/bin/python3.11 /path/to/handler.py
Restart=always

[Install]
WantedBy=multi-user.target
```

---

## 3. 하드코딩된 값

### 3-1. Loki 엔드포인트 IP
| 파일 | 줄 | 현재값 | 제안 변수명 |
|---|---|---|---|
| `compute.tf:103` | 103 | `http://172.16.8.201:3100/loki/api/v1/push` | `var.loki_url` |
| `roles/promtail_agent/defaults/main.yml` | 16 | `"http://172.16.8.201:3100/loki/api/v1/push"` | `promtail_loki_url` |

**영향:** 온프레미스 IP 변경 시 두 곳 모두 수동 수정 필요

---

### 3-2. AWS 프로필 하드코딩
| 파일 | 줄 | 현재값 |
|---|---|---|
| `provider.tf:39` | 39 | `profile = "aidasProject2"` |
| `provider.tf:46` | 46 | `profile = "aidasProject2"` |

**영향:** 다른 AWS 계정/프로필로 배포 불가

**수정 방법:**
```hcl
variable "aws_profile" {
  default = "aidasProject2"
}

provider "aws" {
  profile = var.aws_profile
}
```

---

### 3-3. DB 관련 IP 하드코딩 (Ansible)
| 파일 | 현재값 |
|---|---|
| `roles/db_primary/defaults/main.yml` | `main_db_ip: "172.16.8.202"` |
| `roles/db_primary/defaults/main.yml` | `ubuntu_ip: "172.16.8.203"` |
| `roles/db_replica/defaults/main.yml` | 동일 (중복) |

**영향:** 서버 IP 변경 시 두 파일 모두 수정 필요 → `group_vars`로 통합 권장

---

### 3-4. Docker Compose 버전
| 파일 | 줄 | 현재값 |
|---|---|---|
| `compute.tf:70` | 70 | `v2.26.0` |

**수정 방법:** `var.docker_compose_version = "v2.26.0"` 으로 변수화

---

### 3-5. Ansible 사용자명 하드코딩
| 파일 | 현재값 |
|---|---|
| `roles/docker/tasks/main.yml` | `user: user1` |

**영향:** user1이 없는 서버에서 실패

---

## 4. 중복 코드

### 4-1. NAT EC2 user_data 중복
| 파일 | 줄 |
|---|---|
| `network.tf:70~92` | nat_ec2_a user_data |
| `network.tf:106~126` | nat_ec2_c user_data (거의 동일) |

**수정 방법:** locals로 user_data 통합 또는 `for_each` 활용

---

### 4-2. CloudWatch 알람 중복
| 파일 | 중복 항목 |
|---|---|
| `monitoring.tf:36~54` | cpu_high_blue |
| `monitoring.tf:56~74` | cpu_high_green (동일 구조) |
| `monitoring.tf:78~115` | cpu_low (blue/green 동일) |

**수정 방법:**
```hcl
locals {
  asg_names = {
    blue  = aws_autoscaling_group.asg_blue.name
    green = aws_autoscaling_group.asg_green.name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.asg_names
  ...
}
```

---

### 4-3. db_primary / db_replica defaults 중복
| 파일 | 내용 |
|---|---|
| `roles/db_primary/defaults/main.yml` | IP, DB명, 유저명 정의 |
| `roles/db_replica/defaults/main.yml` | 동일 내용 복사 |

**수정 방법:** `group_vars/all.yml`로 공통 변수 추출

---

## 5. 구조 개선

### 5-1. 환경별 tfvars 분리
**현재:** `terraform.tfvars` 하나로 모든 환경 관리

**개선:**
```
terraform.dev.tfvars   # 개발환경: t3.micro, desired=1
terraform.prod.tfvars  # 운영환경: t3.medium, desired=2
```

```bash
terraform apply -var-file="terraform.prod.tfvars"
```

---

### 5-2. 공통 태그 표준화
**현재:** 리소스마다 태그 형식이 다름

**개선:**
```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc" "main" {
  tags = merge(local.common_tags, { Name = "${var.project_name}-vpc" })
}
```

---

### 5-3. Ansible group_vars 구조화
**현재:** 모든 변수가 각 role의 defaults에 흩어져 있음

**개선:**
```
group_vars/
  all.yml          # 전체 공통 (loki_url, db_ip 등)
  rocky.yml        # Rocky Linux 전용
  ubuntu.yml       # Ubuntu 전용
host_vars/
  rocky01.yml      # 개별 호스트 설정
```

---

### 5-4. IAM 정책 문서 분리
**현재:** `iam.tf`에 JSON 정책이 `jsonencode`로 인라인 작성

**개선:** `data "aws_iam_policy_document"` 사용
```hcl
data "aws_iam_policy_document" "asg_policy" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.tf_state_bucket}/*"]
  }
}
```

---

## 우선순위 요약

| 순위 | 항목 | 파일 | 작업량 |
|---|---|---|---|
| 1 | NAT SG SSH 전체 공개 → Tailscale 대역 제한 | `security_group.tf:17` | 1줄 |
| 2 | ASG ICMP 전체 공개 → 온프레미스 대역 제한 | `security_group.tf:147` | 1줄 |
| 3 | `cgroupby` 오타 제거 | `compute.tf:64` | 1줄 |
| 4 | 주석처리된 ansible_run 블록 삭제 | `main.tf:131~145` | 15줄 삭제 |
| 5 | AWS 프로필 변수화 | `provider.tf`, `variables.tf` | 소규모 |
| 6 | Loki URL 변수화 | `compute.tf`, `ansible` | 소규모 |
| 7 | CloudWatch 알람 for_each 리팩토링 | `monitoring.tf` | 중규모 |
| 8 | handler.py → systemd service | `ansible roles` | 중규모 |
| 9 | 환경별 tfvars 분리 | 신규 파일 | 중규모 |
| 10 | group_vars 구조화 | `ansible` 전체 | 대규모 |
