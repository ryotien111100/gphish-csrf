# Multi-stage build for Gophish using Debian (better SQLite compatibility)
FROM golang:1.21-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    gcc \
    g++ \
    libsqlite3-dev \
    patch \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Clone Gophish repository
RUN git clone https://github.com/gophish/gophish.git .

# CSRF Protection Fix for Reverse Proxy - Config Fix Only
# We fixed generate-config.sh to correctly place trusted_origins (without scheme).
# r.URL.Scheme is already handled by handlers.ProxyHeaders (X-Forwarded-Proto).
# No Dockerfile code injection needed, just proper config generation.


# Set CGO for SQLite
ENV CGO_ENABLED=1

# Download dependencies
RUN go mod download

# Build Gophish  
RUN go build -ldflags="-s -w" -o gophish .

# Final stage - use Debian slim for better compatibility
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libsqlite3-0 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create gophish user
RUN groupadd -g 1000 gophish && \
    useradd -u 1000 -g gophish -s /bin/bash -m gophish

# Set working directory
WORKDIR /app

# Copy built binary and assets from builder
COPY --from=builder --chown=gophish:gophish /build/gophish /app/gophish
COPY --from=builder --chown=gophish:gophish /build/static /app/static
COPY --from=builder --chown=gophish:gophish /build/templates /app/templates
COPY --from=builder --chown=gophish:gophish /build/db /app/db
COPY --from=builder --chown=gophish:gophish /build/VERSION /app/VERSION

# Copy config generation script
COPY --chown=gophish:gophish generate-config.sh /app/generate-config.sh

# Create directory for database if not exists
RUN mkdir -p /app && chown -R gophish:gophish /app && chmod +x /app/generate-config.sh

# Make binary executable
RUN chmod +x /app/gophish

# Switch to gophish user
USER gophish

# Expose ports
EXPOSE 3333 80

# Health check - check admin server only (phish server root returns 404)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3333/login || exit 1

# Run Gophish with absolute path
# Run config generation script and then start gophish from data directory
CMD ["/bin/sh", "-c", "/app/generate-config.sh && cd /app/data && /app/gophish"]