FROM python:3.10-bookworm as base

WORKDIR /app

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --upgrade pip

COPY python/server/requirements.txt .

RUN --mount=type=cache,target=/root/.cache/pip \
    python -m pip install --requirement requirements.txt

COPY pb pb
COPY python/server python/server

EXPOSE 50051
ENV PYTHONPATH="/app:$PYTHONPATH"

