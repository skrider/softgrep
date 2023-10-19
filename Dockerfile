# syntax=docker/dockerfile:1.3

FROM golang:1.19 as builder
ARG TARGETPLATFORM
WORKDIR /src
RUN curl -fsSL https://github.com/daulet/tokenizers/releases/latest/download/libtokenizers.$(echo ${TARGETPLATFORM} | tr / -).tar.gz | tar xvz

COPY go.mod go.sum ./

# Download dependencies
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

RUN --mount=type=cache,target=/go/pkg/mod \
    mv libtokenizers.a /go/pkg/mod/github.com/daulet/tokenizers@v0.5.1/libtokenizers.a

COPY ./pkg ./pkg
COPY ./cmd ./cmd
COPY ./pb ./pb
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/var/cache/go,id=${TARGETPLATFORM} \
    CGO_ENABLED=1 CGO_LDFLAGS="-Wl,--copy-dt-needed-entries" go build ./cmd/softgrep/main.go

