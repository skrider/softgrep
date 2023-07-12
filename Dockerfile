FROM python:3.10-slim as base

WORKDIR /app
COPY python/server/requirements.txt .

# RUN --mount=type=cache,target=/root/.cache/pip \
RUN python -m pip install --upgrade pip
RUN python -m pip install --requirement requirements.txt

COPY pb pb
COPY python/server python/server

EXPOSE 50051
ENV PYTHONPATH="/app:$PYTHONPATH"

