# Multi-stage: Vite dashboard + Python backend (CPU PyTorch for cloud / Railway)

# --- Frontend (production static files) ---
FROM node:18-bookworm-slim AS frontend-build
WORKDIR /build
COPY dashboard/package.json dashboard/package-lock.json ./
RUN npm ci
COPY dashboard/ ./
RUN npm run build

# --- Python venv: CPU torch first, then rest (see requirements-docker.txt) ---
FROM python:3.11-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*
COPY requirements-docker.txt .
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip
# Railway and similar hosts have no GPU; avoid pulling CUDA wheels from default PyPI.
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir -r requirements-docker.txt

# --- Final image ---
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && if command -v node >/dev/null 2>&1; then true; else ln -sf "$(command -v nodejs)" /usr/local/bin/node; fi \
    && node --version

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1

RUN pip install --upgrade --no-cache-dir yt-dlp

COPY . .
COPY --from=frontend-build /build/dist ./dashboard/dist
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser

RUN mkdir -p /app/uploads /app/output /tmp/Ultralytics
RUN chown -R appuser:appuser /app /tmp/Ultralytics

USER appuser

RUN python -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"

EXPOSE 8000

ENTRYPOINT ["/docker-entrypoint.sh"]
