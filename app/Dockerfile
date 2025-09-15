FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Triggered by Terraform build_args (forces rebuild on requirements change)
ARG REQ_HASH

# Install deps first for better caching
COPY requirements.txt .
RUN python -m pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy the rest of the app
COPY . .

EXPOSE 8000

# Simple healthcheck (no heredoc)
HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD \
  python -c "import urllib.request,sys; \
r=urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=2); \
sys.exit(0 if r.getcode()==200 else 1)" || exit 1

CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8000"]
