# ==============================================================================
# Encryptor — container image
#
#   docker build -t encryptor .
#
#   # Run as YOUR user, so files written to the mounted directory belong to you
#   # (the tool creates everything with mode 0600):
#   docker run --rm -it --user "$(id -u):$(id -g)" -v "$PWD:/data" encryptor
#   docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/data" encryptor \
#       encrypt --pass-file /data/pass.txt secret.txt
#
# Certificates, keys and the log live in $ENCRYPTOR_CONFIG_DIR (default
# /home/encryptor/.config/encryptor, which only uid 1000 can write). To keep
# them between runs, mount a directory and point the variable at it:
#   -v "$HOME/.config/encryptor:/state" -e ENCRYPTOR_CONFIG_DIR=/state
#
# The base image tag is updated by Dependabot (.github/dependabot.yml); rebuild
# regularly to pick up OpenSSL security fixes.
# ==============================================================================
FROM alpine:3.24

LABEL org.opencontainers.image.title="Encryptor" \
      org.opencontainers.image.description="Authenticated file encryption and X.509 toolkit built on OpenSSL" \
      org.opencontainers.image.source="https://github.com/mpgamer75/encryptor" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="3.0.0"

RUN apk add --no-cache bash openssl coreutils less ncurses-terminfo-base \
    && addgroup -g 1000 encryptor \
    && adduser -D -u 1000 -G encryptor encryptor

COPY encryptor.sh /usr/local/bin/encryptor
COPY lib/ /usr/local/lib/encryptor/
COPY man/encryptor.1 /usr/local/share/man/man1/encryptor.1

RUN chmod 755 /usr/local/bin/encryptor \
    && chmod 644 /usr/local/lib/encryptor/*.sh

USER encryptor
ENV LANG=C.UTF-8
WORKDIR /data

# Fail the build if the engine does not work with this image's OpenSSL.
RUN encryptor selftest

ENTRYPOINT ["/usr/local/bin/encryptor"]
CMD ["help"]
