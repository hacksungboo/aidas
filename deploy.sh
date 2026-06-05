#!/bin/bash

echo "=================================================="
echo "🚀 AIDAS 쇼핑몰 원클릭 자동 배포 마법사 (Multi-OS 도커 버전)"
echo "=================================================="

# 1. 사용자로부터 IP 및 우분투 접속 계정 입력받기
read -p "▶ 내 대장 컴퓨터(rocky02 - Rocky)의 IP: " MANAGER_IP
read -p "▶ 내 일꾼 컴퓨터(203서버 - Ubuntu)의 IP: " WORKER_IP
read -p "▶ 203서버(우분투)의 SSH 접속 계정아이디 (예: user1 또는 ubuntu): " UBUNTU_USER

echo "--------------------------------------------------"
echo "🏗️ 1단계: 최신 도커 이미지 빌드 중..."
sudo docker build -t aidas-web:v1.0 -f services/web/Dockerfile .

echo "--------------------------------------------------"
echo "✈️ 2단계: 이미지를 파일로 포장 중..."
sudo docker save aidas-web:v1.0 > ~/aidas-web.tar

echo "--------------------------------------------------"
echo "📦 3단계: 203서버(우분투)로 설계도 배달 중..."
scp ~/aidas-web.tar ${UBUNTU_USER}@${WORKER_IP}:~

echo "--------------------------------------------------"
echo "🔓 4단계: 203서버(우분투) 원격 접속 후 이미지 등록 중..."
ssh -t ${UBUNTU_USER}@${WORKER_IP} "sudo docker load < ~/aidas-web.tar"

echo "--------------------------------------------------"
echo "🚀 5단계: 대장 컴퓨터(rocky02) 기존 웹 컨테이너 교체 중..."
sudo docker rm -f ccmall-web-service 2>/dev/null
sudo docker run -d \
  --name ccmall-web-service \
  -p 8000:8000 \
  -e DB_URL=postgresql://ccmall_user:user1@${MANAGER_IP}:5432/ccmall_db \
  aidas-web:v1.0

echo "--------------------------------------------------"
echo "🚀 6단계: 203서버(우분투) 웹 컨테이너 원격 교체 및 방화벽(UFW) 해제 중..."
# 우분투 환경에 맞게 docker run을 원격으로 때리고, ufw를 꺼버립니다.
ssh -t ${UBUNTU_USER}@${WORKER_IP} "sudo docker rm -f ccmall-web-service 2>/dev/null && sudo docker run -d --name ccmall-web-service -p 8000:8000 -e DB_URL=postgresql://ccmall_user:user1@${MANAGER_IP}:5432/ccmall_db aidas-web:v1.0 && sudo ufw disable"

echo "--------------------------------------------------"
echo "🧹 7단계: 대장 컴퓨터(rocky02) 방화벽 잠시 정지..."
sudo systemctl stop firewalld

echo "=================================================="
echo "🎉 [배포 완료] 딱 5초 뒤에 아래 주소들로 접속해봐!"
echo "👉 메인본점(rocky02) 확인: http://${MANAGER_IP}:8000/user"
echo "👉 분점서버(203우분투) 확인: http://${WORKER_IP}:8000/user"
echo "=================================================="
