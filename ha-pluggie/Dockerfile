# Build arguments
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_REF
ARG BUILD_VERSION
ARG BUILD_FROM

FROM ${BUILD_FROM:-x}

## Re-set build arguments after FROM
ARG BUILD_VERSION

# LetsEncrypt
ARG CRYPTOGRAPHY_VERSION
ARG CERTBOT_VERSION
ARG ACME_VERSION

# WireGuard
ARG WIREGUARDTOOLS_VERSION

# Container version
ENV PLUGGIE_VERSION=${BUILD_VERSION}

# Set initial S6 verbosity
ENV S6_VERBOSITY=1 \
    S6_LOGGING_SCRIPT=0 \
    S6_RC_VERBOSITY=0 \
    S6_CMD_RECEIVE_LOGGING=0

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -x \
    && apk add --no-cache \
        wireguard-tools \
        nginx \
        nginx-mod-http-brotli \
        apache2-utils \
        openresolv \
        openssl \
    && pip3 install --no-cache-dir --root-user-action=ignore --find-links \
        "https://wheels.home-assistant.io/alpine-$(cut -d '.' -f 1-2 < /etc/alpine-release)/${BUILD_ARCH}/" \
        cryptography==${CRYPTOGRAPHY_VERSION} \
        certbot==${CERTBOT_VERSION} \
        acme==${ACME_VERSION} \
        wireguard-tools==${WIREGUARDTOOLS_VERSION} \
    && rm -rf /var/cache/apk/* \
    # Custom bashio installation
    && rm -rf /usr/bin/bashio /usr/lib/bashio \
    && ln -s /usr/lib/bashio/bashio /usr/bin/bashio

# Copy root filesystem
COPY rootfs /

# Change permissions
RUN chmod +x /usr/local/bin/* /etc/cont-init.d/* /etc/services.d/*/run

# Docker labels
LABEL \
    io.hass.name="Pluggie" \
    io.hass.description="Make your device visible!" \
    io.hass.type="addon" \
    maintainer="egresh <https://github.com/tiborgres/ha-pluggie>" \
    org.opencontainers.image.title="Pluggie" \
    org.opencontainers.image.description="Make your device visible! (Home Assistant Edition)" \
    org.opencontainers.image.vendor="Pluggie" \
    org.opencontainers.image.authors="egresh <https://github.com/tiborgres/ha-pluggie>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://addons.community" \
    org.opencontainers.image.source="https://github.com/tiborgres/ha-pluggie/ha-pluggie" \
    org.opencontainers.image.documentation="https://github.com/tiborgres/ha-pluggie/README.md"
