#/home/user1/aidas/services/web/app/routers/incidents.py
from fastapi import APIRouter, HTTPException
import os
import logging

router = APIRouter()
logger = logging.getLogger("aidas")

# 장애 주입 엔드포인트
@router.post("/incident/{incident_code}")
def trigger_incident(incident_codecode: str):
    logger.error(f"[FATAL] 장애 강제 주입 시작: {incident_code}")
    
    try:
        if incident_code == "disk-full":
            # 1. 디스크 공간 채우기 (500MB)
            with open("/tmp/dummy_disk_fill", "wb") as f:
                f.write(os.urandom(500 * 1024 * 1024))
            return {"message": "Disk Full 장애 주입 완료!"}
        
        elif incident_code == "oom":
            # 2. 메모리 부족(OOM) 유발
            # 엄청난 크기의 리스트를 메모리에 할당
            mem_bomb = ["o" * 1024 * 1024 for _ in range(2000)]
            return {"message": "OOM 장애 주입 완료!"}
        
        elif incident_code == "http-500":
            # 3. 강제 서버 에러
            raise Exception("서버 내부 강제 에러 발생!")
            
        else:
            raise HTTPException(status_code=404, detail="알 수 없는 장애 코드입니다.")
            
    except Exception as e:
        logger.error(f"[ERROR] 장애 처리 중 예외 발생: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))