# syntax=docker/dockerfile:1
FROM python:3.12-slim

# --- Runtime settings ----------------------------------------------------------
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    APP_HOME=/app PORT=8000 GUNICORN_WORKERS=3 GUNICORN_THREADS=2

WORKDIR ${APP_HOME}

# Install build deps only when we actually need them, then delete
RUN apt-get update && \
    apt-get install --no-install-recommends -y build-essential procps iproute2 net-tools gcc && \
    pip install --upgrade pip && \
    rm -rf /var/lib/apt/lists/*

# Layer-cache your dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Non-root for defence-in-depth                                  :contentReference[oaicite:0]{index=0}
RUN addgroup --system app && adduser --system --ingroup app app
USER app

# Copy application code last (keeps rebuilds fast)
COPY app/backend_app.py .

EXPOSE ${PORT}

ENTRYPOINT ["sh", "-c", "gunicorn -w ${GUNICORN_WORKERS} -k gthread --threads ${GUNICORN_THREADS}   --bind 0.0.0.0:${PORT} backend_app:app"]
