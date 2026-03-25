# syntax=docker/dockerfile:1
# =============================================================================
# OPTIMIZED multi-stage Dockerfile — Node.js 20 + Alpine
#
# Pattern:
#   deps    — install only production dependencies (npm ci --omit=dev)
#   builder — install all deps (including dev) for any build steps
#   runtime — minimal Alpine image, non-root user, only what's needed to run
#
# BuildKit cache mounts keep npm's cache between builds so re-installs
# only download changed packages — dramatically faster on repeat builds.
# =============================================================================

# ---------- Stage 1: production dependencies only ----------
FROM node:20-alpine AS deps
WORKDIR /app

COPY package*.json ./
# --mount=type=cache persists npm's cache across builds (BuildKit feature)
# --omit=dev skips devDependencies so node_modules stays minimal
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev

# ---------- Stage 2: build (install all deps, run any compile/bundle step) ----------
FROM node:20-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Copy source after deps so source changes don't bust the npm cache layer
COPY src/ ./src/

# If using TypeScript, esbuild, etc. run the build here:
# RUN npm run build

# ---------- Stage 3: minimal runtime image ----------
FROM node:20-alpine AS runtime

# Create a dedicated non-root user — principle of least privilege
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy ONLY production node_modules from deps stage (no devDependencies)
COPY --from=deps   /app/node_modules ./node_modules
# Copy source from builder stage (swap for compiled output if using TS/esbuild)
COPY --from=builder /app/src          ./src
COPY package.json .

# Drop to non-root before the process starts
USER appuser

EXPOSE 3000

# Use the numeric UID in HEALTHCHECK so it works in restricted environments
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "src/index.js"]
