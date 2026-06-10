# AZ Failure 장애 추가 컨텍스트

## 환경 정보
- AWS ap-northeast-2a 가용 영역 장애
- ALB가 자동으로 ap-northeast-2c로 페일오버 진행 중
- 롤백은 의미없음, 인프라 복구가 우선

## 즉시 조치 순서
1. AWS 콘솔에서 AZ 상태 확인
2. 페일오버 정상 완료 검증
3. ap-northeast-2c 헬스체크 확인