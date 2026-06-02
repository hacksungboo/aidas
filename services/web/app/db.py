# [DB 연결 설정] PostgreSQL 데이터베이스와의 세션 연결 및 ORM 초기 설정을 관리하는 파일입니다.
#/home/user1/aidas/services/web/app/db.py
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# 우리 프로젝트의 공식 계정 정보인 aidas_user / aidas_password / aidas_db 규격을 반영합니다.
DATABASE_URL = os.getenv("DB_URL", "postgresql://aidas_user:aidas_password@localhost:5432/aidas_db")

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()