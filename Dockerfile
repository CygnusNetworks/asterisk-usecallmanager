# syntax=docker/dockerfile:1
ARG DEBIAN_VERSION=trixie
ARG DEBIAN_SNAPSHOT=20260615T023212Z
ARG ASTERISK_DEBIAN_VERSION=22.10.0+dfsg+~cs6.17.60671434-1
ARG PATCH_VERSION=22.10.0
FROM debian:$DEBIAN_VERSION-slim AS builder
ARG DEBIAN_SNAPSHOT
ARG ASTERISK_DEBIAN_VERSION
ARG PATCH_VERSION

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    devscripts \
    debhelper \
    fakeroot \
    dh-make \
    dpkg-dev \
    quilt \
    git \
    wget

# Copy source code
WORKDIR /src

RUN dget https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/pool/main/a/asterisk/asterisk_$ASTERISK_DEBIAN_VERSION.dsc
RUN wget https://github.com/usecallmanagernz/patches/raw/refs/heads/master/asterisk/cisco-usecallmanager-$PATCH_VERSION.patch

RUN DEBIAN_FRONTEND=noninteractive mk-build-deps -i asterisk_${ASTERISK_DEBIAN_VERSION}.dsc --tool "apt-get -y"
RUN UNPACK_DIR=$(ls -d */) && cd $UNPACK_DIR && quilt pop -a && quilt import -P cisco-usecallmanager ../cisco-usecallmanager-${PATCH_VERSION}.patch && quilt push -a && dpkg-buildpackage -us -uc -b

# Stage 2: Runtime
FROM debian:${DEBIAN_VERSION}-slim
ARG ASTERISK_DEBIAN_VERSION
ARG PATCH_VERSION

LABEL org.opencontainers.image.title="asterisk-usecallmanager" \
      org.opencontainers.image.description="Asterisk with usecallmanager.nz patch for Cisco IP Phones" \
      org.opencontainers.image.source="https://github.com/CygnusNetworks/asterisk-usecallmanager" \
      org.opencontainers.image.vendor="Cygnus Networks" \
      org.opencontainers.image.version="${PATCH_VERSION}"

WORKDIR /opt

# Install the built .debs straight from the builder stage (bind mount, so the
# packages do not end up in an image layer)
RUN --mount=type=bind,from=builder,source=/src,target=/debs \
    apt-get -y update && cd /debs && \
    apt-get install -y ./asterisk_${ASTERISK_DEBIAN_VERSION}_*.deb \
    ./asterisk-config_${ASTERISK_DEBIAN_VERSION}_*.deb \
    ./asterisk-modules_${ASTERISK_DEBIAN_VERSION}_*.deb \
    ./asterisk-mp3_${ASTERISK_DEBIAN_VERSION}_*.deb && \
    apt-get -y install --no-install-recommends dnsutils tcpdump ngrep procps iputils-ping vim mpg123 gettext-base && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    apt-get clean

RUN mkdir -p /etc/asterisk/pjsip.d /etc/asterisk/sip.d /etc/asterisk/extensions.d /etc/asterisk/ari.d /var/run/asterisk /usr/share/asterisk/moh && \
    chown -R asterisk:asterisk /etc/asterisk/pjsip.d /etc/asterisk/sip.d /etc/asterisk/extensions.d /etc/asterisk/ari.d /var/run/asterisk /usr/share/asterisk/moh

COPY ./config/*.conf /etc/asterisk/
COPY --chmod=755 docker-entrypoint.sh /

# Without arguments the entrypoint starts Asterisk, otherwise it runs the given
# command after the config processing
ENTRYPOINT ["/docker-entrypoint.sh"]

# SIP signaling and the RTP range configured in config/rtp.conf
EXPOSE 5060/udp 5060/tcp 10000-10020/udp

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD asterisk -rx "core show uptime" | grep -q "System uptime" || exit 1
