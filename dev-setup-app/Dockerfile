# ============================================================
# Dockerfile — Build the Dev Setup Linux app in a clean
# Ubuntu 22.04 container (avoids the Ubuntu 24.04 webkit
# compatibility issues). Requires Docker Desktop for Windows.
#
# Usage from WSL:
#   docker build -t dev-setup-builder .
#   docker run --rm -v $(pwd):/app dev-setup-builder
#   # Output: src-tauri/target/release/bundle/
# ============================================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WEBKIT_DISABLE_DMABUF_RENDERER=1

# ── System dependencies ──────────────────────────────────────
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    wget \
    file \
    git \
    pkg-config \
    libssl-dev \
    libgtk-3-dev \
    libwebkit2gtk-4.0-dev \
    libjavascriptcoregtk-4.0-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev \
    patchelf \
    squashfs-tools \
    libxdo-dev \
    libxcb1-dev \
    libxrandr-dev \
    libdbus-1-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 ───────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Rust ─────────────────────────────────────────────────────
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --default-toolchain stable && \
    rustup show

# ── Tauri CLI ────────────────────────────────────────────────
RUN cargo install tauri-cli --version "^1.5" --locked

# ── Build step ───────────────────────────────────────────────
WORKDIR /app

# Cache npm dependencies as a separate layer
COPY package.json package-lock.json ./
RUN npm ci

# Copy rest of the project and build
COPY . .
RUN cargo tauri build

# The output bundles are left in target/release/bundle/
# Mount your host directory to /app so the outputs are accessible
