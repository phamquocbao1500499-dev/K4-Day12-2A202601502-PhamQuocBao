# CP2 — Multi-stage production Dockerfile
# Đích: image dưới 400MB, chạy không-root, có layer cache tốt.

FROM python:3.11-slim AS builder

WORKDIR /app

# Cài dependency ở stage builder trong (cho phép dùng compiler nếu cần)
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.11-slim AS runtime

WORKDIR /app

# Mang site-packages từ builder sang — không kèm compiler, image gọn
COPY --from=builder /install /usr/local

# Copy source SAU khi pip install để tận dụng cache
COPY app ./app
COPY utils ./utils

# Không chạy bằng root
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app
USER appuser

ENV PORT=8000
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz').read()" || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]