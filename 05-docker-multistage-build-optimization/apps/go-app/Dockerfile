# syntax=docker/dockerfile:1
# =============================================================================
# OPTIMIZED multi-stage Dockerfile — Go 1.22 → scratch
#
# Pattern:
#   builder — full Go toolchain compiles a statically linked binary
#   runtime — scratch (zero-byte base image), just the binary
#
# Key compiler flags:
#   CGO_ENABLED=0  → no C library links, binary is fully static
#   -ldflags="-s -w" → strip debug symbols and DWARF (-s), strip Go symbol
#                      table (-w) — shrinks binary by ~30%
#
# Result: final image is typically 5–15 MB vs 850 MB for the naive image.
# =============================================================================

# ---------- Stage 1: compile ----------
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Copy module files first — Go module downloads are cached separately
# from source changes, so editing main.go doesn't re-download modules.
COPY go.mod ./
# Only copy go.sum if it exists (no external deps in this demo, so no go.sum)
# COPY go.sum ./

# Download modules (cached by BuildKit if go.mod/go.sum unchanged)
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

# Compile: static binary, stripped symbols, no CGO
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /server .

# ---------- Stage 2: minimal runtime (scratch) ----------
# scratch has NO shell, NO package manager, NO OS — just our binary.
# If you need a shell for debugging, use gcr.io/distroless/static:nonroot
FROM scratch AS runtime

# Copy timezone data and CA certificates from builder so HTTPS calls work
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy only the compiled binary
COPY --from=builder /server /server

# scratch has no users — UID 65534 is the conventional "nobody" uid
USER 65534

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/server"]

ENTRYPOINT ["/server"]
