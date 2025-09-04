FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY main.go ./
RUN go build -o example-app main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /app

COPY --from=builder /app/example-app .

EXPOSE 8080
CMD ["./example-app"]