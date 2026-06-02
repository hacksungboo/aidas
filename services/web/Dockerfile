FROM python:3.10-slim
WORKDIR /app

# 의존성 설치
COPY services/web/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 코드 복사
COPY services/web/ .

# uvicorn 대신 python -m uvicorn 사용 (안정적임)
ENV PYTHONPATH=/app/services/web
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]