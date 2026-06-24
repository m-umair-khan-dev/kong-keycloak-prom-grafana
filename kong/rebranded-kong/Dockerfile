# Stage 1: Build UI
FROM node:20 AS ui-builder

WORKDIR /app
COPY . .

RUN npm install -g pnpm --legacy-peer-deps
RUN pnpm install
RUN pnpm build

# Stage 2: Download OIDCIFY
# FROM alpine:3.20 AS oidcify-builder

# ARG OIDCIFY_VERSION=1.3.6

# RUN apk add --no-cache curl tar

# WORKDIR /build

# RUN ARCH=$(uname -m) && \
#     if [ "$ARCH" = "aarch64" ]; then ARCH=arm64; else ARCH=amd64; fi && \
#     curl -L \
#     https://github.com/hanlaur/oidcify/releases/download/v${OIDCIFY_VERSION}/oidcify_${OIDCIFY_VERSION}_linux_${ARCH}.tar.gz \
#     | tar -xz

# # normalize binary location
# RUN find . -type f -name "oidcify" -exec mv {} /build/oidcify \;

# RUN chmod +x /build/oidcify


# Stage 3: Kong Runtime
FROM kong:3.9.1

USER root

# System deps only (no curl/tar needed anymore)
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    luarocks \
    && rm -rf /var/lib/apt/lists/*

# Lua plugin: kong-oidc-v3
RUN luarocks install kong-oidc-v3
RUN luarocks install kong-openid-connect
# RUN luarocks install kong-plugin-jwt-keycloak

# # Copy oidcify binary from builder
# COPY --from=oidcify-builder /build/oidcify /usr/local/bin/oidcify


# Replace Kong GUI
RUN rm -rf /usr/local/kong/gui/*
COPY --from=ui-builder /app/dist/ /usr/local/kong/gui/
RUN chmod -R 755 /usr/local/kong/gui


USER kong