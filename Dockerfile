ARG DEBIAN_VERSION=trixie
ARG DEBIAN_SNAPSHOT=20251126T082633Z
ARG ASTERISK_DEBIAN_VERSION=22.6.0~dfsg+~cs6.15.60671435-1
ARG PATCH_VERSION=22.6.0
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

# Remove build deps package and debug symbols
RUN rm -f asterisk-build-deps_${ASTERISK_DEBIAN_VERSION}*
RUN rm -f asterisk-*dbgsym_${ASTERISK_DEBIAN_VERSION}*
RUN rm -f asterisk-{tests,dev,dahdi}_${ASTERISK_DEBIAN_VERSION}*

# Stage 2: Runtime
FROM debian:${DEBIAN_VERSION}-slim
ARG ASTERISK_DEBIAN_VERSION

# Copy only the built .deb
WORKDIR /opt
COPY --from=builder /src/*.deb /tmp

# Install the .deb
RUN apt-get -y update && cd /tmp && \
    apt-get install -y ./asterisk_${ASTERISK_DEBIAN_VERSION}_*.deb \
    ./asterisk-config_${ASTERISK_DEBIAN_VERSION}_*.deb \
    ./asterisk-modules_${ASTERISK_DEBIAN_VERSION}_*.deb \
    ./asterisk-mp3_${ASTERISK_DEBIAN_VERSION}_*.deb && \
    apt-get -y install --no-install-recommends dnsutils tcpdump ngrep procps iputils-ping vim mpg123 && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    apt-get clean

RUN mkdir -p /etc/asterisk/pjsip.d /etc/asterisk/sip.d /etc/asterisk/extensions.d /var/run/asterisk /usr/share/asterisk/moh && \
    chown -R asterisk:asterisk /etc/asterisk/pjsip.d /etc/asterisk/sip.d /etc/asterisk/extensions.d /var/run/asterisk /usr/share/asterisk/moh

COPY ./config/*.conf /etc/asterisk/
COPY docker-entrypoint.sh /

CMD ["bash", "-x", "/docker-entrypoint.sh"]

EXPOSE 5060/udp 5060/tcp
