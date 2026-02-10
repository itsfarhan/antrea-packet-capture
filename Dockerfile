FROM golang:1.21 AS builder

WORKDIR /workspace
COPY go.mod go.sum ./
COPY main.go main.go

RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o capture-controller main.go

FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash \
    tcpdump \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /workspace/capture-controller /usr/local/bin/capture-controller

RUN chmod +x /usr/local/bin/capture-controller

ENTRYPOINT ["/usr/local/bin/capture-controller"]
