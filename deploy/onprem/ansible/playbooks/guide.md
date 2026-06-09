# 🚀 AIDAS 하이브리드 인프라 웹 서비스 & DB 복제본 통합 자동 배포 가이드

본 가이드는 앤서블(Ansible)을 활용하여 **메인 웹 서버 빌드/가동** 및 우분투 노드로의 **서브 웹 서버 이송**, 그리고 점수 상향의 핵심인 **데이터베이스 읽기 전용 복제본(ReadOnly Replica) 가동**까지 한 번에 자동화하는 플레이북(`deploy_web_services.yml`) 사용 설명서입니다.

각자 컴퓨터 환경에서 SSH 권한 에러나 장부 파일(`hosts.yml`) 매칭 에러 없이 **엔터 한 번에 완공**시키기 위해 아래 사전 작업을 반드시 수행해 주세요.

---

## 📂 [0단계] 현재 작업 디렉토리 위치 확인 (필수)

모든 작업은 플레이북 파일과 배포 스크립트가 모여 있는 **`playbooks` 폴더 내부로 이동한 상태에서 시작**해야 경로가 꼬이지 않습니다. 터미널을 열고 아래 명령어로 먼저 이동해 주세요.

```bash
cd ~/aidas/deploy/onprem/ansible/playbooks
🛠️ [1단계] 배포 전 필수 사전 작업 (최초 1회만)
이 플레이북은 내 컴퓨터(localhost) 내부 런타임에서 우분투 노드로 원격 ssh/scp 명령을 쏘는 오케스트레이션 구조입니다. 따라서 본인 PC의 SSH 열쇠(인증 키)가 우분투 서버에 등록되어 있어야 패스워드 입력창 없이 완전 자동 배포가 가능합니다.

playbooks 폴더 안에서 아래 두 명령어를 차례대로 실행해 주세요. (어느 폴더에서 치든 홈 디렉토리를 찾아가므로 안심하고 치셔도 됩니다.)

Bash
# 1. 내 컴퓨터에 SSH 열쇠 세트 생성 (질문이 나오면 엔터만 3~4번 연속으로 누르세요)
ssh-keygen -t rsa

# 2. 생성된 내 열쇠를 우분투 서버로 배달 (우분투 비밀번호 딱 한 번 입력)
ssh-copy-id user1@172.16.8.203
⚙️ [2단계] 플레이북 변수(IP) 확인
playbooks 폴더 내에 있는 deploy_web_services.yml 파일 상단을 열어 본인이 테스트하는 인프라 환경의 IP 주소와 맞게 설정되어 있는지 눈으로 슥 확인합니다.

YAML
  vars:
    main_db_ip: "172.16.8.202"  # 메인 데이터베이스(Primary)가 돌아가는 PC IP
    ubuntu_ip: "172.16.8.203"   # 서브 웹 및 ReadOnly DB 복제본이 돌아가는 우분투 IP
🏃‍♂️ [3단계] 올인원 자동 배포 명령어 실행
모든 준비가 끝났다면, 현재 위치가 playbooks 폴더 안인지 다시 한번 확인한 뒤 공용 장부 파일(hosts.yml)을 건드려 팀원 간 설정을 깨뜨리지 않고 나만 안전하게 배포를 관통시키는 아래 치트키 명령어를 날려줍니다.

Bash
# 🔥 반드시 ~/aidas/deploy/onprem/ansible/playbooks 폴더 안에서 실행!
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "localhost," deploy_web_services.yml
⚠️ 주의: "localhost," 뒤에 **쉼표(,)**를 반드시 붙여주어야 앤서블이 공용 장부 파일을 읽지 않고 로컬 엔진으로 다이렉트 배포를 시작합니다.

📊 완성되는 인프라 구조 (System Design)
배포가 완료되면 failed=0 리캡과 함께 다음과 같이 하이브리드 아키텍처가 자동으로 완공됩니다.

🏢 본인 메인 PC (rocky02 등)

최신 소스코드로 도커 이미지 자동 빌드

쇼핑몰 웹 서버 1번 복사본 가동 (aidas-web-service : 8000번 포트)

메인 PostgreSQL 단독 공장과 연결 완료 (my-postgres : 5432번 포트)

🏗️ 원격 서브 PC (ubuntu)

압축된 최신 웹 이미지가 네트워크를 타고 안전하게 원격 이송 및 로드 완료

쇼핑몰 웹 서버 2번 복사본 가동 (aidas-web-service : 8000번 포트 -> 메인 DB 원격 바인딩)

★ 읽기 전용 복제본 DB 가동 완공 ★ (aidas-db-replica : 5433번 포트)