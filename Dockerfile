# syntax=docker/dockerfile:1

# ============================================================
# Stage 1: builder
# Installs every Python dependency into an isolated virtualenv.
# Anything only needed to *install* packages stays in this stage.
# ============================================================
FROM python:3.11-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy ONLY requirements first, so this (slow, multi-GB) layer is reused
# from cache on every build where requirements.txt didn't change.
COPY requirements.txt .

# torch / torchvision are pinned to CUDA 13.0 builds (+cu130), which live on
# PyTorch's own package index, not PyPI.
RUN pip install --upgrade pip \
 && pip install \
      --extra-index-url https://download.pytorch.org/whl/cu130 \
      -r requirements.txt


# ============================================================
# Stage 2: runtime
# A fresh slim image that receives only the finished virtualenv + code.
# ============================================================
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    HF_HOME=/home/app/.cache/huggingface

# Run as an unprivileged user, never as root.
RUN useradd --create-home --uid 1000 app \
 && mkdir -p "$HF_HOME" \
 && chown -R app:app /home/app/.cache

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app

# Application code goes last: code changes often, deps rarely.
COPY --chown=app:app database.py ./
COPY --chown=app:app App ./App

USER app

EXPOSE 8000

# First boot downloads the embedding model and Gemma (several GB), so give
# the container a long grace period before health failures count.
HEALTHCHECK --interval=30s --timeout=10s --start-period=600s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/', timeout=5)" || exit 1

# One worker: every worker loads its own copy of both models onto the GPU.
CMD ["uvicorn", "App.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
