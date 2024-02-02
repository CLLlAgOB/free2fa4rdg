FROM python:3.10-slim

COPY requirements.txt /app/
WORKDIR /app

RUN apt-get update \
    && apt-get install -y ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /venv
COPY requirements.txt /app/

RUN pip install --no-cache-dir -r requirements.txt

COPY ./files/app/ /app/

RUN mkdir -p /app/db /var/log

EXPOSE 5000

CMD ["python", "main.py"]
