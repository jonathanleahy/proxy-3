FROM golang:1.23-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o mock-server cmd/main.go
RUN go build -o capture-proxy cmd/capture/main.go

FROM alpine:latest

RUN apk update && apk add --no-cache ca-certificates 2>/dev/null || true

WORKDIR /app

COPY --from=builder /app/mock-server /app/mock-server
COPY --from=builder /app/capture-proxy /app/capture-proxy

RUN mkdir -p /app/configs /app/captured

VOLUME ["/app/configs", "/app/captured"]

EXPOSE 8090 8091

ENV PORT=8090
ENV CONFIG_PATH=/app/configs

CMD ["/app/mock-server"]