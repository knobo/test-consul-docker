# syntax=docker/dockerfile:1
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    APP_HOME=/app PORT=8000 \
    BACKEND_URL=http://localhost:9191

WORKDIR ${APP_HOME}

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN apt-get update && \
    apt-get install --no-install-recommends -y procps iproute2 net-tools curl && \
    pip install --upgrade pip && \
    rm -rf /var/lib/apt/lists/*

RUN addgroup --system app && adduser --system --ingroup app app
USER app

COPY app/frontend_app.py .

EXPOSE ${PORT}

ENTRYPOINT ["sh","-c", "gunicorn -w ${GUNICORN_WORKERS:-3} -k gthread --threads ${GUNICORN_THREADS:-2} --bind 0.0.0.0:${PORT} frontend_app:app"]
