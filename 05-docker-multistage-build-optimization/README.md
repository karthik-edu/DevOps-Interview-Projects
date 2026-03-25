# Project 05 — Optimized Multi-Stage Docker Build Pipeline

Demonstrates the full spectrum of Docker image optimization using two real apps — a Node.js Express server and a Go HTTP server — each with a naive and an optimized Dockerfile side-by-side.

## What You'll See

```
  IMAGE                           SIZE
────────────────────────────────────────────────────────────
  node-app:naive                  ~1100 MB  (node:20 + all deps)
  node-app:optimized              ~  75 MB  (alpine + prod deps only)
────────────────────────────────────────────────────────────
  go-app:naive                    ~ 850 MB  (golang:1.22 + toolchain)
  go-app:optimized                ~   8 MB  (scratch + binary only)
────────────────────────────────────────────────────────────
  Node.js reduction: ~93%   |   Go reduction: ~99%
```

## Quick Start

```bash
chmod +x setup.sh && ./setup.sh
```

## Project Structure

```
05-docker-multistage-build-optimization/
├── setup.sh
└── apps/
    ├── node-app/
    │   ├── Dockerfile          ← optimized: 3-stage + BuildKit cache
    │   ├── Dockerfile.naive    ← single-stage, node:20, root user
    │   ├── src/index.js
    │   └── package.json
    └── go-app/
        ├── Dockerfile          ← optimized: builder → scratch
        ├── Dockerfile.naive    ← single-stage, golang:1.22, root user
        ├── main.go
        └── go.mod
```

## Optimization Techniques

### 1. Multi-Stage Builds
Split the build into stages. Only the final `FROM` contributes to the image — all build tools, compilers, and intermediate files are discarded automatically.

### 2. Minimal Base Images

| Use case | Naive | Optimized |
|----------|-------|-----------|
| Node.js runtime | `node:20` (1.1 GB) | `node:20-alpine` (~70 MB) |
| Go runtime | `golang:1.22` (850 MB) | `scratch` (0 MB base) |

### 3. BuildKit Cache Mounts (`--mount=type=cache`)
```dockerfile
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev
```
The npm/Go module cache persists between builds on the same machine. Changing `index.js` doesn't re-download packages — only changed layers rebuild.

### 4. Layer Order — Dependencies Before Source
```dockerfile
COPY package*.json ./   ← changes rarely → cached
RUN npm ci              ← cached when package.json unchanged
COPY src/ ./            ← changes often  → only this layer rebuilds
```

### 5. Production Dependencies Only
```dockerfile
RUN npm ci --omit=dev   # excludes nodemon, jest, ts-node, etc.
```

### 6. Go Binary Optimisation
```dockerfile
CGO_ENABLED=0 go build -ldflags="-s -w" -o /server .
```
- `CGO_ENABLED=0` — fully static binary, no libc dependency, runs on `scratch`
- `-s` — strip symbol table
- `-w` — strip DWARF debug info
- Result: ~30% smaller binary

### 7. Non-Root User
```dockerfile
# Node: create a user in Alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# Go: use the nobody UID (no user accounts exist in scratch)
USER 65534
```

### 8. No Shell in scratch
The Go optimized image runs from `scratch` — no shell, no package manager, no OS utilities. If the container is compromised there is nothing for an attacker to use.

## Interview Demo Script

```bash
export KUBECONFIG=...   # not needed for this project

# Show the size difference
docker images | grep -E "node-app|go-app"

# Prove non-root
docker exec node-app-demo id
# uid=1000(appuser) gid=1000(appgroup)

# Prove no shell in Go scratch container
docker exec go-app-demo /bin/sh
# Error: no such file or directory

# Show layers (optimized vs naive)
docker history node-app:optimized
docker history node-app:naive

# Rebuild to see cache hits (should be <5 seconds)
docker build -f apps/node-app/Dockerfile -t node-app:optimized apps/node-app
```

## Cleanup

```bash
docker rm -f node-app-demo go-app-demo
docker rmi node-app:naive node-app:optimized go-app:naive go-app:optimized
```
