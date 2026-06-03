```
# 🤖 AIDAS — AI 기반 장애 로그 자동 탐지·알림 운영 시스템

**AIDAS(AI-based Incident Detection and Automated Support)**는 클라우드·컨테이너 인프라의 장애 로그를 온프레미스 AI(Ollama)로 분석하여, 원인 요약과 조치 방안을 Slack으로 실시간 전달하는 운영 지원 시스템 구축 프로젝트입니다.

기존 모니터링 도구가 시각화까지만 지원하여 수많은 로그 속에서 원인을 찾고 대응책을 고민하는 운영자의 피로도를 해결하기 위해 기획되었습니다.

---

## ✨ 핵심 기능 및 기대 효과 (Key Features)

* **보안성 및 비용 제로 구현 (FinOps & Security)**
  * 외부 OpenAI API 등을 쓰지 않고 로컬 인프라 안에서만 LLM을 구동하므로 내부 소스코드/로그 정보 유출 위험이 원천 차단되며 추가 API 비용이 없습니다.
* **MTTR(장애 복구 시간) 획기적 단축**
  * 로그를 직접 뒤지는 과정을 AI가 대신하여 에러 인지부터 원인 파악까지 시간을 대폭 감소시킵니다.
* **알림 품질 향상**
  * 빈도 비율 기반 필터링으로 무의미한 알림은 제외하고 진짜 중요한 장애로그에 집중합니다.
* **장애 대응 프로세스 자산화**
  * 주요 4대 장애 시나리오별 AI의 분석 내용과 조치 로그를 트러블슈팅 DB로 자산화하여 팀의 클라우드 운영 역량을 내재화합니다.
* **IaC 및 완전 자동화 파이프라인**
  * Terraform과 Ansible Playbook을 통해 멱등성이 보장된 인프라를 배포하며, GitHub Actions와 Docker Swarm의 롤링 업데이트(Rolling Update)를 활용하여 서비스 중단 없이(무중단) 신버전을 배포합니다.

---

## 🏗️ 시스템 아키텍처 (System Architecture)

AIDAS는 퍼블릭 클라우드와 온프레미스를 결합한 **하이브리드 메쉬(Hybrid Mesh) 아키텍처**로 설계되었습니다.

```text
[ AWS 퍼블릭 클라우드 ]                         [ VMware 온프레미스 ]
+-------------------------+                   +-------------------------+
| Route53 / CloudFront    |                   | PostgreSQL DB           |
| ALB (Load Balancer)     |                   |  - 시스템 상태/데이터   |
|                         |                   +-------------------------+
| +---------------------+ |    Tailscale      | +---------------------+ |
| | EC2 (Docker Swarm)  | |   VPN 터널 전송   | | PLG 통합 관제 스택  | |
| | - FastAPI 웹 서비스 | +==================>+ | - Loki (중앙 로그)    | |
| | - 제어판 (Injector) | |                   | | - Prometheus        | |
| | - Promtail (필터링) | |                   | | - Grafana 대시보드  | |
| +---------------------+ |                   | +----------+----------+ |
+-------------------------+                   |            | 신규 감지  |
                                              | +----------v----------+ |
                                              | | lambda분석 핸들러  | |
                                              | +----------+----------+ |
                                              |            | 분석 요청  |
                                              | +----------v----------+ |
                                              | | Ollama 로컬 LLM     | |
                                              | +----------+----------+ |
                                              +------------|------------+
                                                           |
                                                [ Slack 운영팀 알림 ]
```

### 1. AWS 퍼블릭 클라우드 영역 (Frontend & Web Layer)

- **Route53 / CloudFront / ALB:** 유저 인입의 최앞단에서 도메인 라우팅 및 정적 미디어 캐싱(CDN)을 담당하며, 트래픽을 백엔드 노드로 안정적으로 부하 분산합니다.
- **EC2 Cluster (Docker Swarm):** FastAPI 애플리케이션(피관제 서비스)과 에러 로그를 실시간으로 가로채는 Promtail 에이전트가 도커 컨테이너 환경으로 가동됩니다.

### 2. 하이브리드 보안 연결망

- **Tailscale VPN:** 클라우드와 온프레미스 AI 서버 간 안전한 통신 구성을 통해 징후성 로그를 터널링합니다.

### 3. VMware 온프레미스 영역 (Data & AI Analytics Layer)

- **Loki / Prometheus / Grafana:** AWS에서 넘어오는 실시간 시스템 메트릭과 에러 로그를 중앙 집중형으로 수집하고 시각화하는 통합 관제 센터입니다.
- **Ollama (로컬 LLM):** 가장 가볍고 강력한 로컬 LLM(예: Llama3 등)을 구동하여 외부 API 미사용 및 정보 유출 위험 0%를 달성합니다.

## 🖥️ 웹 서비스 화면 구성 (UI/UX Flow)

시연의 직관성을 극대화하기 위해 시스템의 프론트엔드는 두 가지 트랙으로 분기됩니다.

### 🛒 Track 1. 사용자용 심플 상품 리스트 뷰어 (User Portal)

- **목적:** 데이터베이스(PostgreSQL)에 저장된 가상의 상품 목록을 호출하여 화면에 렌더링함으로써 서비스가 살아있음을 보여주는 데모용 화면입니다.
- **시연 포인트:** 장애가 주입되면 즉시 페이지 로딩 속도가 느려지거나 에러 화면(HTTP 500/502 등)이 노출되며 관제 시스템(AIDAS)의 실시간 작동을 유도합니다.

### 🛠️ Track 2. 관리자 페이지: 장애 유발 제어판 (Incident Injector)

- **목적:** 시연 시 실제 장애 상황을 의도적으로 발생시키는 데모 전용 제어판입니다.
- **화면 흐름:**
    - **[좌측 장애 리스트]** 4대 주요 장애 시나리오 목록 중 하나를 선택합니다.
    - **[우측 상세 및 제어]** 선택된 장애 상세 화면에서 `[⚡ 장애 강제 주입]` 버튼을 클릭하여 고의 로그 생성을 유도합니다. 하단에 임베딩된 Grafana 통합 관제 대시보드(iframe)를 통해 메트릭 변화와 실시간 로그 스트림을 한 화면에서 즉시 확인합니다.

## 🔄 지능형 장애 관제 파이프라인 (Data Pipeline)

전체 시스템은 단 1바이트의 수동 개입 없이 아래의 순서로 자동화되어 동작합니다.

1. **장애 유발 (Inject):** 관리자가 제어판 웹페이지에서 특정 장애 버튼(예: 디스크 고갈)을 클릭하여 FastAPI가 표준 에러 스트림을 출력하도록 유도합니다.
2. **실시간 필터링 (Filter):** Promtail이 애플리케이션 로그 파일을 실시간 테일링하다가 ERROR 또는 FATAL 키워드가 매칭되는 징후성 로그만 즉시 필터링합니다.
3. **하이브리드 전송 (Transfer):** 필터링된 보안 에러 로그는 Tailscale 가상 VPN 터널을 타고 안전하게 온프레미스 Loki로 적재됩니다.
4. **AI 분석 (Inference):** Python 핸들러가 신규 에러를 감지하고 프롬프트를 결합하여 Ollama에 전달하면, 로컬 LLM이 소스코드를 추론하여 '직관적인 장애 요약'과 '맞춤형 인프라 조치 가이드'를 도출합니다.
5. **스마트 알림 (Alert):** 가공 완료된 AI 진단 보고서가 Slack Webhook을 통해 인프라 운영팀 슬랙 채널로 즉시 전송됩니다.

## 🚨 4대 주요 장애 시나리오 (Incident Scenarios)

| **장애 유형** | **비즈니스 상황** | **발생 로그** | **AI 가이드 기대 방향** |
| --- | --- | --- | --- |
| **DB Connection Timeout** | 가상망(VPN) 장애 및 동시 접속자 급증에 따른 연결 지연 | `OperationalError: connection to server at db.local failed`
 | Tailscale 상태 점검 및 DB 방화벽 규칙 확인 권고 |
| **Out of Memory** | 버그나 비정상적 자원 과점 프로세스로 인한 메모리(RAM) 고갈 | `kernel: Out of memory: Kill process (python)`
 | 프로세스 강제 종료 로그 식별 및 컨테이너 자원 리미트 재설정 |
| **Disk Full** | 대용량 더미 파일 연속 기입으로 인한 디스크 스토리지 0% | `OSError: [Errno 28] No space left on device`
 | 용량 고갈 상태 진단 및 S3 객체 스토리지 마이그레이션 크론탭 실행 권고 |
| **HTTP 500 Error** | 런타임 오류(Zero Division 등)로 인한 웹 서비스 다운 | `ZeroDivisionError: division by zero 및 Internal Server Error`
[cite: 2] | Stack Trace를 읽어 파일명/라인수 요약 및 CI/CD 소스코드 롤백 프로세스 제안[cite: 2] |

## 👥 팀 구성 및 역할 (Team 쉬지마EC 2)

- **이재혁 (팀장):** 요구사항 분석, 프로젝트 총괄, 온프레미스 환경 내부 로컬 AI 엔진(Ollama) 구축 및 프롬프트 최적화 전담[cite: 2].
- **부학성 (부팀장):** 하이브리드 인프라 아키텍처 설계 총괄, 개방형 관제 파이프라인(PLG Stack) 및 AWS CloudWatch 통합 연동 전담[cite: 2].
- **박다정:** Terraform 기반 AWS 클라우드 인프라(VPC, EC2, ALB, Route53 등) IaC 코드 자동화 및 프로비저닝 담당[cite: 2].
- **이창원:** FastAPI 기반 관찰 대상 웹 서비스 및 4대 장애 유발 제어판(Incident Injector) 백엔드/프론트엔드 개발 담당[cite: 2].
- **김민규:** Ansible Playbook 기반 인프라 배포 자동화(Docker Swarm 클러스터 구성), GitHub Actions CI/CD 구축 및 통합 테스트 담당[cite: 2].

## 🛠️ 기술 스택 (Tech Stack)

- **Cloud & Infra:** `AWS (EC2, VPC, ALB, S3, Route53, CloudFront)`, `VMware`
- **Network & Security:** `Tailscale VPN`
- **Container:** `Docker`, `Docker Swarm`
- **IaC & Automation:** `Terraform`, `Ansible`, `GitHub Actions`
- **Monitoring & Log:** `Prometheus`, `Grafana`, `Loki`, `Promtail`, `AWS CloudWatch`
- **Backend & DB:** `Python`, `FastAPI`, `PostgreSQL`
- **AI Engine:** `Ollama (Llama3)`

---

---

---

---

---

---

---

---

**1️⃣ 진입 구간: 사용자의 요청이 들어오는 길 (Edge & Routing)**
• **구조 (어디에 있는가?):** 다이어그램 최상단의 **AWS Route 53**, **AWS CloudFront**, 그리고 VPC 입구인 **Internet Gateway**와 AWS ALB(로드밸런서)입니다.
• **흐름 (어떻게 움직이는가?):**
    1. 사용자가 도메인을 입력하여 접속하면, **Route 53**이 목적지 주소를 안내합니다.  
    2. 정적인 데이터(이미지 등)는 CloudFront(CDN)가 캐싱하여 서버까지 가지 않고 빠르게 응답해 줍니다.  
    3. 실제 동적 서비스 요청은 인터넷 게이트웨이를 지나 **AWS ALB**로 들어와, 뒤에 있는 여러 대의 서버로 고르게 분산(Load Balancing)됩니다.  
**2️⃣ 처리 구간: 실제 서비스가 작동하는 심장부 (Processing)**
• **구조 (어디에 있는가?):** 외부 인터넷에서 직접 접근할 수 없는 **Private Subnet(프라이빗 서브넷)** 안에 격리된 **Auto Scaling Group**입니다. 이 안에는 Docker Swarm으로 묶인 여러 대의 EC2 인스턴스(FastAPI 및 Promtail 탑재)가 있습니다.  
• **흐름 (어떻게 움직이는가?):**
    1. ALB가 넘겨준 트래픽을 프라이빗 서브넷 안의 EC2(FastAPI)들이 받아서 실제 서비스 로직을 처리합니다.  
    2. 트래픽 부하가 임계치를 넘어가면, **Auto Scaling**이 작동하여 자동으로 EC2 서버 대수를 늘리고(Scale out), 트래픽이 줄어들면 다시 서버를 줄여서(Scale in) 안정성과 비용을 최적화합니다.
**3️⃣ 출구 및 비밀 통로 구간: 내부망에서 밖으로 나가는 길 (Outbound & VPN)**
• **구조 (어디에 있는가?):** 다이어그램 중앙 부근의 **NAT EC2**와 **Tailscale EC2** 게이트웨이, 그리고 오른쪽으로 이어지는 **Tailscale VPN** 터널입니다.
• **흐름 (어떻게 움직이는가?):**
    1. 
**외부 인터넷 통신:** 프라이빗 서브넷 안의 서버들이 외부로 나가야 할 때는 비싼 순정 서비스 대신 직접 구축한 **NAT EC2**를 거쳐서 나갑니다.
    2. 
**온프레미스(VMware) 통신:** EC2 내부에서 에러가 발생하면, **Promtail** 에이전트가 에러 로그를 낚아채어 **Tailscale EC2**를 통과시킵니다. 이 로그는 256비트 암호화된 **Tailscale VPN** 터널을 타고 우측의 온프레미스 환경으로 안전하게 전송됩니다.  
**4️⃣ 분석 및 데이터 관리 구간: 지능형 두뇌와 금고 (Data, AI & DB Replication) 🌟업데이트**
• **구조 (어디에 있는가?):** 다이어그램 오른쪽의 **On-Premise (VMware)** 구역입니다. 중앙 관제를 담당하는 **PLG 스택**, 분석을 담당하는 **Python 핸들러 및 Ollama LLM**, 그리고 데이터베이스인 DB Node 1(Primary)과 DB Node 2(ReadOnly Replica)가 있습니다.
• **흐름 (어떻게 움직이는가?):**
    1. 
**AI 분석 흐름:** VPN을 타고 날아온 에러 로그는 **Loki**에 적재됩니다. **Python 핸들러**가 이를 감지하여 프롬프트를 만들고 Ollama(로컬 AI)에게 분석을 요청하면, AI가 장애 원인과 조치 가이드를 만들어 냅니다.  
    2. 
**DB 이중화 흐름 (Primary/Replica):** 메인 데이터 쓰기 및 수정 작업은 **Primary DB**가 전담하고, 단순 조회 작업은 데이터가 동기화된 **ReadOnly Replica DB**가 전담하여 데이터베이스 부하를 분산시킵니다.
**5️⃣ 알림 및 지식 자산화 구간: 서버리스 비동기 처리 (Alert & Knowledge Assetization) 🌟업데이트**
• **구조 (어디에 있는가?):** 다이어그램 하단과 상단에 위치한 **Amazon CloudWatch**, **AWS Lambda (Slack 알림 핸들러)**, **Slack Webhook**, 그리고 **Amazon S3**와 **Amazon DynamoDB**입니다.
• **흐름 (어떻게 움직이는가?):**
    1. **이중 분기(Dual Action) 라우팅:** 온프레미스의 Python 핸들러가 AI 분석을 마치면, 그 결과물을 클라우드의 **AWS Lambda**로 던져줍니다.
    2. 
**갈래 1 (운영팀 알림):** Lambda는 즉시 **Slack Webhook**으로 데이터를 쏴서 운영팀 메신저로 장애 요약 및 조치 가이드를 전송합니다.  
    3. 
**갈래 2 (지식 자산화 - 핑크색 점선):** 동시에 Lambda는 에러 원문 등 무거운 데이터는 **Amazon S3**에, AI가 도출한 장애 원인 및 해결 코드 등의 메타데이터는 **Amazon DynamoDB**에 저장하여 향후 팀의 트러블슈팅 자산으로 영구 기록합니다.  
    4. 
*(보조 흐름)* AWS 인프라 자체의 상태 지표(CPU 등)는 **CloudWatch**로 수집되며, 이상 감지 시 동일하게 Lambda를 거쳐 Slack으로 전송됩니다.  
**💡 총정리 (완성된 하이브리드 흐름)**
요청은 `[클라우드 전방]`에서 부하 분산되어 처리됩니다. 장애 발생 시 에러 로그는 `[암호화된 VPN 터널]`을 타고 `[온프레미스의 로컬 AI]`로 넘어가 분석됩니다. 분석이 끝난 결과물은 다시 클라우드의 `[AWS Lambda]`로 넘겨져서, 하나는 **운영팀의 Slack**으로 날아가고, 다른 하나는 **S3/DynamoDB에 지식 자산으로 영구 저장**되는 완벽한 클라우드 네이티브 설계입니다!