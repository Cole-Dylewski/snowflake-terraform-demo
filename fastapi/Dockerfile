# fastapi/Dockerfile
FROM public.ecr.aws/docker/library/python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install minimal OS deps (no compilers needed for basic FastAPI)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
 && rm -rf /var/lib/apt/lists/*

# 1) Install Python deps first (leverages Docker layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
 && pip install --no-cache-dir -r requirements.txt

# 2) Copy app code (note: puts your code into /app/app)
COPY app ./app

# Expose FastAPI default port
EXPOSE 8000

# Dev-friendly: auto-reload. For prod, drop --reload and add workers.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--lifespan", "on", "--reload"]
