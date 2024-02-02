FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .


EXPOSE 8000

CMD ["uvicorn", "adminapi:app", "--host", "0.0.0.0", "--port", "8000", "--ssl-keyfile=/app/certs/free2fa4rdg_admin_api.key", "--ssl-certfile=/app/certs/free2fa4rdg_admin_api.crt"]
