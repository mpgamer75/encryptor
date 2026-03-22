# ==============================================================================
# Encryptor — Docker Image
# Multi-stage build: minimal runtime image based on Alpine Linux
# ==============================================================================
# Usage:
#   docker build -t encryptor .
#   docker run --rm -it -v "$PWD:/data" -w /data encryptor
#   docker run --rm -v "$PWD:/data" -w /data encryptor \
#       --encrypt secret.txt --algo aes-256-gcm --pass-file /data/pass.txt
# ==============================================================================

FROM alpine:3.19 AS runtime

LABEL org.opencontainers.image.title="Encryptor"
LABEL org.opencontainers.image.description="Advanced CLI encryption tool"
LABEL org.opencontainers.image.url="https://github.com/mpgamer75/encryptor"
LABEL org.opencontainers.image.source="https://github.com/mpgamer75/encryptor"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="2.1.0"

# Install runtime dependencies (Alpine uses bash from a separate package)
RUN apk add --no-cache \
    bash \
    openssl \
    coreutils \
    less \
    util-linux \
    && rm -rf /var/cache/apk/*

# Create non-root user for running encryptor
RUN addgroup -g 1000 encryptor && \
    adduser -D -u 1000 -G encryptor encryptor

# Copy application files
COPY --chown=encryptor:encryptor encryptor.sh /usr/local/bin/encryptor
COPY --chown=encryptor:encryptor lib/ /usr/local/lib/encryptor/
COPY --chown=root:root docs/ /usr/local/share/doc/encryptor/

RUN chmod 755 /usr/local/bin/encryptor && \
    chmod 755 /usr/local/lib/encryptor/ && \
    chmod 644 /usr/local/lib/encryptor/*.sh

# Patch the LIB_DIR path to the installed location
RUN sed -i 's|LIB_DIR="$SCRIPT_DIR/lib"|LIB_DIR="/usr/local/lib/encryptor"|' \
    /usr/local/bin/encryptor

# Create config directory for the encryptor user
RUN mkdir -p /home/encryptor/.config/encryptor/certs \
             /home/encryptor/.config/encryptor/tools && \
    chmod 700 /home/encryptor/.config/encryptor \
              /home/encryptor/.config/encryptor/certs && \
    chown -R encryptor:encryptor /home/encryptor/.config

USER encryptor
WORKDIR /data

ENTRYPOINT ["/usr/local/bin/encryptor"]
CMD ["--help"]
