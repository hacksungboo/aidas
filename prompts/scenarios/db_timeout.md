# DB Timeout 장애 추가 컨텍스트

## 환경 정보
- DB는 온프레미스(172.16.8.202)에 있으며 Tailscale VPN 경유
- 연결 풀 고갈 또는 VPN 터널 불안정이 주요 원인

## 즉시 조치 순서
1. Tailscale VPN 터널 상태 확인
2. DB 연결 풀 재시작
3. max_connections 설정 확인