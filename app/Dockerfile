FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app
ARG REQ_HASH

# Install API deps first (cache-friendly)
# CHANGED: prefix with app/ now that context is repo root
COPY app/requirements.txt .
RUN python -m pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Dev tools
RUN pip install --no-cache-dir uvicorn[standard] watchfiles

# NEW: bring in khepri_utils and install (choose one of the two lines)
COPY khepri_utils /deps/khepri_utils
# Editable (handy for local development layers; mount will still override at runtime)
# RUN pip install --no-cache-dir -e "/deps/khepri_utils[alpaca,aws,db,fastapi,ml,tableau]"
# or non-editable (typical for prod images)
RUN pip install --no-cache-dir "/deps/khepri_utils"

# CHANGED: copy the app from app/ since context is repo root
COPY app /app

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD \
  python -c "import urllib.request,sys; r=urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=2); sys.exit(0 if r.getcode()==200 else 1)" || exit 1

CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8000"]
