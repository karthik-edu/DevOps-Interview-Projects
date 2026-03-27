#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-command demo for Project 05: Multi-Stage Docker Build
#
# Usage:
#   chmod +x setup.sh && ./setup.sh
#
# What it does:
#   1. Builds naive (single-stage) images for Node.js and Go
#   2. Builds optimized (multi-stage) images with BuildKit cache mounts
#   3. Prints a side-by-side image size comparison table
#   4. Runs both optimized containers and verifies health endpoints
#   5. Demonstrates non-root execution and no shell in Go scratch image
# =============================================================================

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_DIR="${WORKSPACE_ROOT}/apps/node-app"
GO_DIR="${WORKSPACE_ROOT}/apps/go-app"

# Image tags
NODE_NAIVE="node-app:naive"
NODE_OPT="node-app:optimized"
GO_NAIVE="go-app:naive"
GO_OPT="go-app:optimized"

# Container names (for cleanup and health checks)
NODE_CONTAINER="node-app-demo"
GO_CONTAINER="go-app-demo"

NODE_PORT="3000"
GO_PORT="8080"

log()  { echo "[$(date +%T)] $*"; }
ok()   { echo "[$(date +%T)] ✓ $*"; }
fail() { echo "[$(date +%T)] ✗ $*" >&2; exit 1; }

hr() { printf '%.0s─' {1..60}; echo; }

# --------------------------------------------------------------------------- #
# 1. Prerequisites
# --------------------------------------------------------------------------- #
log "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || fail "Docker is not installed"
docker info >/dev/null 2>&1       || fail "Docker daemon is not running"

DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
ok "Docker ${DOCKER_VER} — BuildKit enabled by default in Docker 23+"

# BuildKit is default in Docker 23+; force it explicitly for older versions
export DOCKER_BUILDKIT=1

# --------------------------------------------------------------------------- #
# 2. Clean up any previous demo containers
# --------------------------------------------------------------------------- #
log "Cleaning up previous demo containers..."
docker rm -f "${NODE_CONTAINER}" "${GO_CONTAINER}" 2>/dev/null || true
ok "Clean"

# --------------------------------------------------------------------------- #
# 3. Build naive images (single-stage, large)
# --------------------------------------------------------------------------- #
log "Building NAIVE Node.js image (single-stage, no cache mounts)..."
docker build \
  -f "${NODE_DIR}/Dockerfile.naive" \
  -t "${NODE_NAIVE}" \
  "${NODE_DIR}" 2>&1 | tail -5
ok "Built ${NODE_NAIVE}"

log "Building NAIVE Go image (single-stage, entire toolchain in final image)..."
docker build \
  -f "${GO_DIR}/Dockerfile.naive" \
  -t "${GO_NAIVE}" \
  "${GO_DIR}" 2>&1 | tail -5
ok "Built ${GO_NAIVE}"

# --------------------------------------------------------------------------- #
# 4. Build optimized images (multi-stage, BuildKit cache mounts)
# --------------------------------------------------------------------------- #
log "Building OPTIMIZED Node.js image (multi-stage + BuildKit cache)..."
docker build \
  --progress=plain \
  -f "${NODE_DIR}/Dockerfile" \
  -t "${NODE_OPT}" \
  "${NODE_DIR}" 2>&1 | grep -E "^#[0-9]|DONE|CACHED|ERROR" | tail -20
ok "Built ${NODE_OPT}"

log "Building OPTIMIZED Go image (multi-stage → scratch)..."
docker build \
  --progress=plain \
  -f "${GO_DIR}/Dockerfile" \
  -t "${GO_OPT}" \
  "${GO_DIR}" 2>&1 | grep -E "^#[0-9]|DONE|CACHED|ERROR" | tail -20
ok "Built ${GO_OPT}"

# --------------------------------------------------------------------------- #
# 5. Image size comparison
# --------------------------------------------------------------------------- #
echo ""
hr
echo "  IMAGE SIZE COMPARISON"
hr
printf "  %-30s  %s\n" "IMAGE" "SIZE"
hr

print_size() {
  local tag=$1
  local size
  size=$(docker image inspect "${tag}" \
    --format '{{.Size}}' 2>/dev/null | awk '{printf "%.1f MB", $1/1024/1024}')
  printf "  %-30s  %s\n" "${tag}" "${size}"
}

print_size "${NODE_NAIVE}"
print_size "${NODE_OPT}"
hr
print_size "${GO_NAIVE}"
print_size "${GO_OPT}"
hr

# Calculate reduction percentage
node_naive_bytes=$(docker image inspect "${NODE_NAIVE}" --format '{{.Size}}' 2>/dev/null)
node_opt_bytes=$(docker image inspect "${NODE_OPT}"   --format '{{.Size}}' 2>/dev/null)
go_naive_bytes=$(docker image inspect "${GO_NAIVE}"   --format '{{.Size}}' 2>/dev/null)
go_opt_bytes=$(docker image inspect "${GO_OPT}"       --format '{{.Size}}' 2>/dev/null)

node_reduction=$(awk "BEGIN {printf \"%.0f\", (1 - ${node_opt_bytes}/${node_naive_bytes}) * 100}")
go_reduction=$(awk   "BEGIN {printf \"%.0f\", (1 - ${go_opt_bytes}/${go_naive_bytes}) * 100}")

echo "  Node.js size reduction : ${node_reduction}%"
echo "  Go      size reduction : ${go_reduction}%"
hr
echo ""

# --------------------------------------------------------------------------- #
# 6. Run optimized containers
# --------------------------------------------------------------------------- #
log "Starting optimized Node.js container..."
docker run -d \
  --name "${NODE_CONTAINER}" \
  -p "${NODE_PORT}:3000" \
  "${NODE_OPT}"

log "Starting optimized Go container..."
docker run -d \
  --name "${GO_CONTAINER}" \
  -p "${GO_PORT}:8080" \
  "${GO_OPT}"

# --------------------------------------------------------------------------- #
# 7. Health checks
# --------------------------------------------------------------------------- #
wait_healthy() {
  local name=$1 url=$2
  log "Waiting for ${name} to be ready..."
  for i in $(seq 1 15); do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
    if [ "${HTTP}" = "200" ]; then
      ok "${name} is healthy (HTTP 200)"
      return 0
    fi
    echo "  ... waiting (${i}/15, HTTP ${HTTP})"
    sleep 2
  done
  fail "${name} did not become healthy"
}

wait_healthy "Node.js app" "http://localhost:${NODE_PORT}/health"
wait_healthy "Go app"      "http://localhost:${GO_PORT}/health"

echo ""
log "Node.js response:"
curl -s "http://localhost:${NODE_PORT}/" | python3 -m json.tool 2>/dev/null || \
  curl -s "http://localhost:${NODE_PORT}/"

echo ""
log "Go response:"
curl -s "http://localhost:${GO_PORT}/" | python3 -m json.tool 2>/dev/null || \
  curl -s "http://localhost:${GO_PORT}/"
echo ""

# --------------------------------------------------------------------------- #
# 8. Security checks
# --------------------------------------------------------------------------- #
hr
echo "  SECURITY VERIFICATION"
hr

# Node: verify non-root user
NODE_UID=$(docker exec "${NODE_CONTAINER}" id -u 2>/dev/null || echo "unknown")
if [ "${NODE_UID}" != "0" ]; then
  ok "Node.js container running as non-root (uid=${NODE_UID})"
else
  echo "  ✗ WARNING: Node.js container running as root"
fi

# Go: scratch has no shell — exec must fail (that's a GOOD thing)
if docker exec "${GO_CONTAINER}" /bin/sh -c "echo test" >/dev/null 2>&1; then
  echo "  ✗ WARNING: Go scratch container has a shell (unexpected)"
else
  ok "Go scratch container has NO shell — zero attack surface"
fi

hr
echo ""

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
echo "============================================================"
echo " Project 05 — Multi-Stage Docker Build Optimization"
echo "============================================================"
echo "  Node.js app : http://localhost:${NODE_PORT}/"
echo "  Go app      : http://localhost:${GO_PORT}/"
echo ""
echo "  Size reduction: Node.js ${node_reduction}%  |  Go ${go_reduction}%"
echo ""
echo "  To rebuild and see BuildKit cache in action (2nd build is faster):"
echo "    docker build -f apps/node-app/Dockerfile -t node-app:optimized apps/node-app"
echo "    docker build -f apps/go-app/Dockerfile   -t go-app:optimized   apps/go-app"
echo ""
echo "  To inspect image layers:"
echo "    docker history ${NODE_OPT}"
echo "    docker history ${GO_OPT}"
echo ""
echo "  To clean up:"
echo "    docker rm -f ${NODE_CONTAINER} ${GO_CONTAINER}"
echo "    docker rmi ${NODE_NAIVE} ${NODE_OPT} ${GO_NAIVE} ${GO_OPT}"
echo "============================================================"
