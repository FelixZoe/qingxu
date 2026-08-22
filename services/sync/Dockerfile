# syntax=docker/dockerfile:1

FROM golang:1.27.0-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN go test ./... && go vet ./...
RUN CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build ./...
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/qingxu-sync ./cmd/sync-server \
    && mkdir -p /out/data \
    && chmod 0700 /out/data

FROM scratch
LABEL org.opencontainers.image.title="Qingxu Sync" \
      org.opencontainers.image.description="Single-user self-hosted sync service for Qingxu" \
      org.opencontainers.image.source="https://github.com/FelixZoe/qingxu" \
      io.qingxu.component="sync"
COPY --from=build --chown=65532:65532 /out/data /data
COPY --from=build --chown=65532:65532 /out/qingxu-sync /qingxu-sync
ENV SYNC_ADDR=:8080 \
    SYNC_DATA_FILE=/data/store.json
EXPOSE 8080
VOLUME ["/data"]
USER 65532:65532
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/qingxu-sync", "healthcheck"]
ENTRYPOINT ["/qingxu-sync"]
