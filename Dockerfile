# Multi-stage Dockerfile pour FastAPI (TP 4 DevOps et IA)
# Stage 1: Build & installation des dependances
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Runtime allege et securise (non-root)
FROM python:3.12-slim
WORKDIR /app

# Copie des packages installes depuis le builder
COPY --from=builder /install /usr/local

# Copie du code applicatif
COPY app/ ./app/

# Creation et bascule vers l'utilisateur non-root pour le durcissement
RUN useradd -u 1000 -m appuser && chown -R appuser:appuser /app
USER appuser

# Verification periodique de l'etat de sante de l'API (Exercice 3)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
