# 🤖 AIDAS — AI 기반 장애 로그 자동 탐지·알림 운영 시스템

**AIDAS(AI-based Incident Detection and Automated Support)**는 클라우드·컨테이너 인프라의 장애 로그를 온프레미스 AI(Ollama)로 분석하여, 원인 요약과 조치 방안을 Slack으로 실시간 전달하는 운영 지원 시스템입니다.

기존 모니터링 도구가 시각화까지만 지원하여 수많은 로그 속에서 원인을 찾고 대응책을 고민하는 운영자의 피로도를 해결하기 위해 기획되었습니다.

---

## ✨ 핵심 기능 및 기대 효과

- **보안성 및 비용 제로 구현**
  - 외부 OpenAI API 등을 쓰지 않고 로컬 인프라 안에서만 LLM을 구동하므로 내부 소스코드/로그 정보 유출 위험이 원천 차단되며 추가 API 비용이 없습니다.
- **MTTR(장애 복구 시간) 획기적 단축**
  - 로그를 직접 뒤지는 과정을 AI가 대신하여 에러 인지부터 원인 파악까지 시간을 대폭 감소시킵니다. (SLA 목표: 60초 이내)
- **알림 품질 향상**
  - Promtail 레벨 기반 필터링(ERROR/WARN/FATAL)으로 무의미한 알림은 제외하고 진짜 중요한 장애 로그에 집중합니다.
- **장애 대응 프로세스 자산화**
  - 4대 장애 시나리오별 AI 분석 내용과 조치 로그를 DynamoDB에 저장하여 트러블슈팅 DB로 자산화합니다.
- **IaC 및 완전 자동화 파이프라인**
  - Terraform과 Ansible Playbook을 통해 멱등성이 보장된 인프라를 배포하며, GitHub Actions와 Blue/Green 배포를 활용하여 서비스 중단 없이 신버전을 배포합니다.

---

## 🏗️ 시스템 아키텍처

AIDAS는 퍼블릭 클라우드와 온프레미스를 결합한 **하이브리드 메쉬(Hybrid Mesh) 아키텍처**로 설계되었습니다.

```
[ AWS 퍼블릭 클라우드 ]                         [ VMware 온프레미스 ]
+-------------------------+                   +----------------------------------+
| Route53 / CloudFront    |                   | mgmt (172.16.8.200)              |
| ALB (Load Balancer)     |                   |  - Ansible 컨트롤 노드           |
|                         |                   +----------------------------------+
| Blue ASG / Green ASG    |    Tailscale      | rocky01 (172.16.8.201)           |
| +---------------------+ |   VPN 터널 전송   | +------------------------------+ |
| | EC2 Private Subnet  | +==================>+ | Loki / Prometheus / Grafana  | |
| | - FastAPI 웹 서비스 | |                   | | Ollama (qwen2.5-coder:7b)    | |
| | - Incident Injector | |                   | | handler.py (AI 파이프라인)   | |
| | - Promtail (필터링) | |                   | +------------------------------+ |
| +---------------------+ |                   +----------------------------------+
|                         |                   | rocky02 (172.16.8.202)           |
| Lambda                  |                   | +------------------------------+ |
| - Slack 전송            |                   | | PostgreSQL (Primary DB)      | |
| - DynamoDB 저장         |                   | +------------------------------+ |
+-------------------------+                   +----------------------------------+
```

### 서버 구성

| 서버 | IP | 역할 |
|---|---|---|
| mgmt | 172.16.8.200 | Ansible 컨트롤 노드, GitHub 연동 |
| rocky01 | 172.16.8.201 | Ollama(qwen2.5-coder), Loki, Grafana, Prometheus, handler.py |
| rocky02 | 172.16.8.202 | PostgreSQL Writable |
| ubuntu01| 172.16.8.203 | replica db readonly |
| rockyai | 172.16.8.210 |      NFS Volume     |  
| EC2 (AWS) | Private Subnet | FastAPI, Promtail |

---

## 🔄 지능형 장애 관제 파이프라인

```
1. 장애 유발 (Inject)
   관리자가 제어판에서 장애 버튼 클릭
   → FastAPI가 에러 로그 출력

2. 실시간 필터링 (Filter)
   Promtail이 ERROR/WARN/FATAL 키워드만 필터링
   → Tailscale VPN 터널로 Loki 전송

3. AI 분석 (Inference)
   handler.py가 5초마다 Loki 폴링
   → 시나리오 자동 판별
   → system_prompt.txt + 시나리오별 힌트 합쳐서 Ollama 호출
   → qwen2.5-coder:7b 분석 (평균 30~50초)

4. 스마트 알림 (Alert)
   handler.py → boto3 → AWS Lambda 호출
   → Slack 운영팀 채널 전송
   → DynamoDB 장애 이력 저장
```

---

## 🚨 4대 주요 장애 시나리오

| 장애 유형 | 비즈니스 상황 | AI 가이드 방향 |
|---|---|---|
| **DB Connection Timeout** | VPN 장애 및 동시 접속자 급증으로 인한 DB 연결 지연 | Tailscale 상태 점검 및 DB 연결 풀 재시작 권고 |
| **Out of Memory** | 버그나 비정상적 자원 과점으로 인한 메모리 고갈 | 컨테이너 재시작 및 메모리 리미트 재설정 권고 |
| **AZ Failure** | AWS ap-northeast-2a 가용 영역 장애로 인한 서비스 중단 | AWS 콘솔 AZ 상태 확인 및 페일오버 검증 권고 |
| **HTTP 500 Error** | 런타임 오류(ZeroDivisionError 등)로 인한 웹 서비스 다운 | 파일명/라인 요약 및 블루그린 롤백 권고 |

---

## 🖥️ 웹 서비스 화면 구성

### Track 1. 사용자용 쇼핑몰 (User Portal)
- PostgreSQL에 저장된 상품 목록 렌더링
- 장애 주입 시 HTTP 500/502 에러 화면 노출

### Track 2. 관리자 장애 제어판 (Incident Injector)
- 4대 장애 시나리오 버튼으로 고의 에러 로그 생성
- 하단 Grafana 대시보드(iframe)로 실시간 메트릭 확인

---

## 📁 프로젝트 구조

```
aidas/
├── terraform/               # AWS 인프라 IaC
│   ├── compute.tf           # Blue/Green ASG
│   ├── loadbalancer.tf      # ALB, 타겟그룹
│   ├── cloudfront.tf        # CloudFront, S3
│   ├── lambda.tf            # Lambda 함수
│   ├── database.tf          # DynamoDB
│   └── github_secrets.tf    # GitHub Secret 자동 등록
├── ansible/                 # 인프라 배포 자동화
│   ├── site.yml
│   ├── onpremise.yml        # rocky01, rocky02
│   ├── ec2.yml              # EC2 배포
│   └── templates/           # 환경변수 템플릿
├── lambda/analyzer/         # AI 분석 파이프라인
│   ├── handler.py           # Loki 폴링 + Ollama 호출
│   ├── lambda_function.py   # Slack + DynamoDB
│   └── requirements.txt
├── prompts/                 # AI 프롬프트
│   ├── system_prompt.txt    # 공통 프롬프트
│   └── scenarios/           # 시나리오별 특화 힌트
│       ├── db_timeout.txt
│       ├── oom.txt
│       ├── az_failure.txt
│       └── http_500.txt
└── services/web/            # FastAPI 웹 서비스
    ├── main.py
    ├── models.py
    └── routers/
        └── incidents.py     # 장애 시뮬레이터
```

---

## 🛠️ 기술 스택

| 분류 | 기술 |
|---|---|
| Cloud & Infra | AWS (EC2, VPC, ALB, S3, Route53, CloudFront, Lambda, DynamoDB) |
| Network | Tailscale VPN |
| Container | Docker, Docker Compose |
| IaC & Automation | Terraform, Ansible, GitHub Actions |
| Monitoring & Log | Prometheus, Grafana, Loki, Promtail |
| Backend & DB | Python, FastAPI, PostgreSQL |
| AI Engine | Ollama (qwen2.5-coder:7b) |
| Deployment | Blue/Green 배포 (ASG 기반) |

---

## 👥 팀 구성 (쉬지마EC 2)

| 이름 | 역할 |
|---|---|
| 이재혁 (팀장) | 프로젝트 총괄, Ollama AI 엔진 구축 및 프롬프트 최적화 |
| 부학성 (부팀장) | 하이브리드 인프라 아키텍처 설계, PLG 스택 구축 |
| 박다정 | Terraform 기반 AWS 인프라 IaC 자동화 |
| 이창원 | Ansible 배포 자동화, GitHub Actions CI/CD 구축 |
| 김민규 | FastAPI 웹 서비스 및 장애 제어판 개발 |