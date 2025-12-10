ARG DEBIAN_VERSION=trixie
ARG ASTERISK_VERSION=22.6.0
ARG PATCH_VERSION=22.6.0

# -----------------------------------------------------------------------------
# Stage 1: Builder
# -----------------------------------------------------------------------------
FROM debian:${DEBIAN_VERSION}-slim AS builder
ARG ASTERISK_VERSION
ARG PATCH_VERSION

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /src

# Install minimal tools required to fetch source and run Asterisk's prereq script
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    wget \
    ca-certificates \
    subversion \
    patch \
    pkg-config \
    libsqlite3-dev \
    libxml2-dev \
    libncurses-dev \
    libssl-dev \
    uuid-dev \
    libedit-dev

# Download Asterisk (pipe directly to tar to save space) and the Cisco Patch
RUN wget -qO- https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz \
    | tar -xz --strip-components=1 \
    && wget -q https://github.com/usecallmanagernz/patches/raw/refs/heads/master/asterisk/cisco-usecallmanager-${PATCH_VERSION}.patch \
    && patch -p1 < cisco-usecallmanager-${PATCH_VERSION}.patch

# Install specific build dependencies and MP3 source
RUN ./contrib/scripts/install_prereq install \
    && ./contrib/scripts/get_mp3_source.sh

# Configure and Build
# Bundling pjproject prevents ABI conflicts with system libraries
RUN ./configure \
    --libdir=/usr/lib/x86_64-linux-gnu \
    --with-pjproject-bundled \
    --with-jansson-bundled \
    --with-ssl=ssl \
    --with-srtp \
    && make menuselect.makeopts \
    && menuselect/menuselect --enable format_mp3 menuselect.makeopts \
    && make -j$(nproc) \
    && make install DESTDIR=/tmp/asterisk-install \
    && make samples DESTDIR=/tmp/asterisk-install \
    && make config DESTDIR=/tmp/asterisk-install

# -----------------------------------------------------------------------------
# Stage 2: Runtime
# -----------------------------------------------------------------------------
FROM debian:${DEBIAN_VERSION}-slim

# Install runtime libraries and debug tools
# Note: These libs must match what Asterisk linked against in the builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 \
    libsqlite3-0 \
    libssl3 \
    libncurses6 \
    libuuid1 \
    libedit2 \
    libxslt1.1 \
    liburiparser1 \
    libcurl4 \
    dnsutils \
    tcpdump \
    procps \
    iputils-ping \
    vim \
    mpg123 \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Create Asterisk user
RUN groupadd -r asterisk && useradd -r -g asterisk -G audio,dialout asterisk

# Copy artifacts from builder
COPY --from=builder /tmp/asterisk-install /

# Setup permissions
# Only changing ownership of directories that Asterisk writes to at runtime
RUN mkdir -p /etc/asterisk/pjsip.d \
    && chown -R asterisk:asterisk /etc/asterisk \
                                  /var/lib/asterisk \
                                  /var/run/asterisk \
                                  /var/log/asterisk \
                                  /var/spool/asterisk \
                                  /usr/lib/x86_64-linux-gnu/asterisk

# Copy local config and entrypoint
COPY ./config/*.conf /etc/asterisk/
COPY docker-entrypoint.sh /

RUN chmod +x /docker-entrypoint.sh

WORKDIR /var/lib/asterisk
EXPOSE 5060/udp 5060/tcp

CMD ["/docker-entrypoint.sh"]