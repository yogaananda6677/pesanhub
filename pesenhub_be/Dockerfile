FROM golang:1.26.0-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/pesenhub-api ./cmd/api && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/pesenhub-migrate ./cmd/migrate

FROM alpine:3.24.1 AS runtime
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S -g 10001 pesenhub && \
    adduser -S -D -H -u 10001 -G pesenhub pesenhub
WORKDIR /app
COPY --from=builder --chown=pesenhub:pesenhub /out/pesenhub-api /app/pesenhub-api
COPY --from=builder --chown=pesenhub:pesenhub /out/pesenhub-migrate /app/pesenhub-migrate
COPY --chown=pesenhub:pesenhub migrations /app/migrations
COPY --chown=pesenhub:pesenhub web /app/web
USER pesenhub:pesenhub
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/health/live || exit 1
ENTRYPOINT ["/app/pesenhub-api"]
