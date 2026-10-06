# asterisk-usecallmanager Container image

[![Docker Build](https://github.com/CygnusNetworks/asterisk-usecallmanager/actions/workflows/docker-build.yml/badge.svg)](https://github.com/CygnusNetworks/asterisk-usecallmanager/actions/workflows/docker-build.yml)
[![Auto-update](https://github.com/CygnusNetworks/asterisk-usecallmanager/actions/workflows/auto-update.yml/badge.svg)](https://github.com/CygnusNetworks/asterisk-usecallmanager/actions/workflows/auto-update.yml)
[![GitHub release](https://img.shields.io/github/v/release/CygnusNetworks/asterisk-usecallmanager)](https://github.com/CygnusNetworks/asterisk-usecallmanager/releases/latest)
[![Docker Pulls](https://img.shields.io/docker/pulls/cygnusnetworks/asterisk-usecallmanager)](https://hub.docker.com/r/cygnusnetworks/asterisk-usecallmanager)
[![Image Size](https://img.shields.io/docker/image-size/cygnusnetworks/asterisk-usecallmanager/latest?arch=amd64)](https://hub.docker.com/r/cygnusnetworks/asterisk-usecallmanager/tags)
[![Platforms](https://img.shields.io/badge/platforms-amd64%20%7C%20arm64-blue)](https://hub.docker.com/r/cygnusnetworks/asterisk-usecallmanager/tags)
[![UseCallManager](https://img.shields.io/badge/patch-usecallmanager.nz-orange)](https://usecallmanager.nz/)
[![License](https://img.shields.io/github/license/CygnusNetworks/asterisk-usecallmanager)](https://github.com/CygnusNetworks/asterisk-usecallmanager/blob/main/LICENSE)

Container image that builds and runs [Asterisk](https://www.asterisk.org/) with the [UseCallManager](https://usecallmanager.nz/) (cisco-usecallmanager) patchset applied, for running Cisco IP phones (SIP firmware) against Asterisk. It ships defaults for SIP/PJSIP that include multiple config files, so you can drop your own Asterisk config in at runtime and have variables expanded automatically.

> **Warning:** The UseCallManager patch for Asterisk 22 is, according to its author, *ready for testing and may not be suitable for production use*. It contains substantial changes to `chan_sip`. Read the [change log](https://usecallmanager.nz/change-log.html) before using this image.

## Overview
- Base OS: Debian Trixie (slim).
- Asterisk packages: built from the Debian source package (fetched from [snapshot.debian.org](https://snapshot.debian.org/)) and patched with the UseCallManager (UCM) patchset.
- Architectures: `linux/amd64` and `linux/arm64`.
- Entry point: a small bootstrap script that
  - remaps the runtime user if requested,
  - auto-detects your public IPv4 address (unless you set it),
  - copies all files from `/config` into `/etc/asterisk`,
  - performs environment variable substitution (`envsubst`) on those copied files (except dialplan files),
  - starts Asterisk (or the command you pass to the container).
- Health check: the container reports `healthy` once `asterisk -rx "core show uptime"` answers (if you run a custom command instead of Asterisk, the container will show up as `unhealthy`).

### Image tags and versioning
Images are published to Docker Hub and the GitHub Container Registry:

| Registry | Image |
|----------|-------|
| Docker Hub | `cygnusnetworks/asterisk-usecallmanager` |
| GHCR | `ghcr.io/cygnusnetworks/asterisk-usecallmanager` |

- `vX.Y.Z` – the UCM patch version, which equals the Asterisk version it is built from (e.g. `v22.10.0` = Asterisk 22.10.0 + `cisco-usecallmanager-22.10.0.patch`).
- `latest` – the most recent build.

The exact Debian package version and snapshot used for a build are the `ARG` defaults in the [`Dockerfile`](https://github.com/CygnusNetworks/asterisk-usecallmanager/blob/main/Dockerfile) of the respective tag.

Updates are automated: a daily workflow checks [usecallmanagernz/patches](https://github.com/usecallmanagernz/patches) for a newer patch of the current Asterisk major version. As soon as Debian also ships the matching Asterisk source package, the Dockerfile is updated, a `vX.Y.Z` tag is pushed, the image is built and a [GitHub release](https://github.com/CygnusNetworks/asterisk-usecallmanager/releases) is created.

### Relationship to the UseCallManager project
This image consumes the patchset from the UseCallManager project:
- Site: https://usecallmanager.nz/
- Change log: https://usecallmanager.nz/change-log.html
- Patches: https://github.com/usecallmanagernz/patches

Hints for Asterisk 22.x:
- There have been backports and changes affecting `chan_sip` in the UCM patches (renamed and removed options). Read the change log linked above and validate your configuration.
- `chan_sip` is suitable for connecting Cisco phones, `pjsip` for other SIP endpoints and trunks.

## Requirements
- Docker Engine or compatible runtime.
- For external RTP media, open/forward a UDP range on your host (by default 10000–10020, see `rtp.conf`) and the SIP signaling port(s) you plan to use.
- **If you need lots of parallel channels, increase the port range in `rtp.conf` and do not use the docker proxy for exposing these ports** (use `network_mode: host` instead).
- Outbound DNS to query Google's DNS (used to detect the public IP) unless you set `EXTERNAL_IP` yourself.

## How configuration works
At container start, `/docker-entrypoint.sh` performs the following:

1. User/group remap (optional)
   - If `ASTERISK_UID` and `ASTERISK_GID` are provided, the script changes the IDs of the `asterisk` user and group (`usermod`/`groupmod`). This is useful to align file permissions with your host user when bind-mounting volumes.

2. External IP detection (only if `/config` exists)
   - If `EXTERNAL_IP` is set, it is used as is.
   - Otherwise the script tries to detect your public IPv4 address:
     ```bash
     dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"'
     ```
   - The result is exported as `EXTERNAL_IP` for later substitution.
   - If no address can be detected, the container exits with a non‑zero status. If your environment blocks that DNS query, set `EXTERNAL_IP` explicitly, or set `IGNORE_EXTERNAL_IP_CHECK=true` if your config does not use `${EXTERNAL_IP}`.

3. Configuration files
   Configuration can be done in two ways (they can also be mixed):

   a) Config ingestion from `/config`
   - If a directory `/config` exists, every file under it is **copied** into `/etc/asterisk` preserving relative paths. For example:
     - `/config/pjsip.conf` → `/etc/asterisk/pjsip.conf`
     - `/config/pjsip.d/my-peer.conf` → `/etc/asterisk/pjsip.d/my-peer.conf`
   - Variable substitution is applied to all config files via `envsubst`, except dialplan files:
     - `extensions.conf` and anything under `extensions.d/` are copied verbatim (no substitution) to avoid breaking `${...}` style Asterisk dialplan expressions.
   - All other files have shell-style variables expanded using the container's environment (e.g., `${EXTERNAL_IP}`, `${SIP_BIND_PORT}`, `${WHATEVER}` that you define).

   b) Config through volume mounts
   - If you do not provide a `/config` directory, you can mount your own config files directly.
   - Mount your config files for SIP, PJSIP, ARI and extensions into `/etc/asterisk/sip.d`, `/etc/asterisk/pjsip.d`, `/etc/asterisk/ari.d` and `/etc/asterisk/extensions.d`.
   - The main config files `sip.conf`, `pjsip.conf`, `ari.conf` and `extensions.conf` in `/etc/asterisk` include the files of these subdirectories.

4. Optional hooks
   - If `/docker-entrypoint.d/` exists, the script runs all executable files in it using `run-parts` before starting Asterisk. This is handy for last-mile tweaks.

5. Ownership and start
   - Key Asterisk directories are chowned to the runtime user (read-only mounts are skipped with a warning).
   - Without arguments Asterisk is launched in the foreground as PID 1. If you pass a command (e.g. `docker run … cygnusnetworks/asterisk-usecallmanager bash`), the steps above run first and then your command is executed instead of Asterisk.

Base configs are bundled under `/etc/asterisk` in the image (copied from this repo's [`config/`](https://github.com/CygnusNetworks/asterisk-usecallmanager/tree/main/config)). Any files you place in `/config` will override or augment those.

## Config files in the Docker image

All config files are Debian default Asterisk config files, except the ones below.

For basic use cases, simply mount directory volumes to:

  * `/etc/asterisk/sip.d`
  * `/etc/asterisk/pjsip.d`
  * `/etc/asterisk/extensions.d`
  * `/etc/asterisk/ari.d`

All `*.conf` files there will be read. If you need more control over configs, do a volume mount to `/config`. Files present there will be copied to `/etc/asterisk` after envsubst parsing.

| File | Content |
|------|---------|
| `ari.conf` | ARI disabled by default, `#tryinclude "ari.d/*.conf"` |
| `sip.conf` | `#tryinclude "sip.d/*.conf"` |
| `pjsip.conf` | `#tryinclude "pjsip.d/*.conf"` |
| `extensions.conf` | `#tryinclude "extensions.d/*.conf"` |
| `asterisk.conf` | `verbose = 5`, `debug = 3`, `autosystemname = yes` |
| `logger.conf` | logs to the console (container stdout) |
| `modules.conf` | disables modules which produce load warnings (including the ARI modules) |
| `rtp.conf` | RTP port range 10000–10020 |

If you need to change the loaded modules (e.g. to enable ARI), override `modules.conf` with your own version.

## Environment variables
Runtime (entrypoint) variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ASTERISK_USER` | `asterisk` | User Asterisk runs as |
| `ASTERISK_GROUP` | same as user | Group Asterisk runs as |
| `ASTERISK_UID` / `ASTERISK_GID` | – | Remap the user/group IDs (both must be set) |
| `EXTERNAL_IP` | auto-detected | Public IPv4 address, available as `${EXTERNAL_IP}` in config files |
| `IGNORE_EXTERNAL_IP_CHECK` | `false` | `true`/`1` skips the IP detection and does not exit if `EXTERNAL_IP` is unset |
| `ENTRYPOINT_DEBUG` | `false` | `true`/`1` traces the entrypoint script (`set -x`) |

Any additional variables you define can be used in your `.conf` files (expanded via `envsubst`), for example `SIP_BIND_ADDR`, `SIP_BIND_PORT`, `LOCAL_NET`.

Build-time variables (Docker build args):

| Argument | Description |
|----------|-------------|
| `DEBIAN_VERSION` | Debian release of the base image (default: `trixie`) |
| `DEBIAN_SNAPSHOT` | snapshot.debian.org timestamp the Asterisk source package is fetched from |
| `ASTERISK_DEBIAN_VERSION` | Debian source version of the `asterisk` package (without epoch) |
| `PATCH_VERSION` | UCM patch version, e.g. `22.10.0` |

## Quick start (docker run)
```bash
# EXTERNAL_IP:          set explicitly if autodetect is blocked
# ASTERISK_UID/GID:     optional UID/GID remap
# /config:              configs to be processed/expanded
# 10000-10020/udp:      RTP media range (adjust together with rtp.conf)
docker run -d \
  --name asterisk \
  -e EXTERNAL_IP=203.0.113.10 \
  -e ASTERISK_UID=$(id -u) -e ASTERISK_GID=$(id -g) \
  -v $(pwd)/my-asterisk-config:/config:ro \
  -p 5060:5060/udp \
  -p 5060:5060/tcp \
  -p 10000-10020:10000-10020/udp \
  cygnusnetworks/asterisk-usecallmanager:latest
```

Use `ghcr.io/cygnusnetworks/asterisk-usecallmanager:latest` to pull from the GitHub Container Registry instead.

Notes:
- If you don't mount `/config`, the image's baked-in configs are used.
- You can mount `/etc/asterisk` directly instead, but `/config` is recommended so you benefit from envsubst.
- Open the Asterisk CLI with `docker exec -it asterisk asterisk -r`.

## docker-compose example
```yaml
services:
  asterisk:
    image: cygnusnetworks/asterisk-usecallmanager:latest
    # image: ghcr.io/cygnusnetworks/asterisk-usecallmanager:latest # alternative image source
    container_name: asterisk
    environment:
      # Provide EXTERNAL_IP if your DNS cannot resolve via Google's o-o.myaddr mechanism
      EXTERNAL_IP: ${EXTERNAL_IP:-}
      # Optional user remap to match host user
      ASTERISK_UID: ${UID:-1000}
      ASTERISK_GID: ${GID:-1000}
      # Any variables you reference inside your *.conf files
      LOCAL_NET: 192.168.1.0/24
      SIP_BIND_ADDR: 0.0.0.0
      SIP_BIND_PORT: "5060"
    volumes:
      - ./my-asterisk-config:/config:ro
    ports:
      - "5060:5060/udp"
      - "5060:5060/tcp"
      - "10000-10020:10000-10020/udp"
    restart: unless-stopped
```

Make sure you understand the implications of your network setup and possible IPv4 NAT scenarios.

## Scripts and hooks
- `/docker-entrypoint.sh` — main launcher (see “How configuration works”).
- `/docker-entrypoint.d/` — optional directory; any executable files placed here will run (via `run-parts`) before Asterisk starts. Use this for last-minute file generation or tweaks.

## Production considerations
- UCM-related features and `chan_sip` changes/backports in Asterisk 22 have caveats. Review: https://usecallmanager.nz/change-log.html
- Prefer `pjsip` for other SIP endpoints or SIP trunks.
- Pin your image to a `vX.Y.Z` tag instead of `latest` and test upgrades in a staging environment.
- The default `asterisk.conf` enables verbose and debug output; lower `verbose`/`debug` for production.

## Troubleshooting
- External IP detection fails: set `EXTERNAL_IP` manually (e.g., with compose or `-e`). Ensure outbound DNS works if you rely on autodetect.
- No audio or one-way audio: confirm the RTP port range is published from host to container and your firewall/NAT rules are correct; ensure your SIP signaling advertises the correct public address (use `${EXTERNAL_IP}` in `pjsip.conf`/`sip.conf`).
- Variable not expanded: remember that `envsubst` runs only on non-dialplan files; dialplan files (`extensions.conf`/`extensions.d/*`) are copied verbatim.

## Building with a different Asterisk source version or patch

Example (adjust the values):

```bash
docker build \
  --build-arg DEBIAN_VERSION=trixie \
  --build-arg DEBIAN_SNAPSHOT=20260615T023212Z \
  --build-arg ASTERISK_DEBIAN_VERSION=22.10.0+dfsg+~cs6.17.60671434-1 \
  --build-arg PATCH_VERSION=22.10.0 \
  -t asterisk-usecallmanager:22.10.0 .
```

- `PATCH_VERSION` must exist as `cisco-usecallmanager-<version>.patch` in [usecallmanagernz/patches](https://github.com/usecallmanagernz/patches/tree/master/asterisk).
- `ASTERISK_DEBIAN_VERSION` must be a Debian source version of `asterisk` (see the [snapshot.debian.org package page](https://snapshot.debian.org/package/asterisk/)) and `DEBIAN_SNAPSHOT` a snapshot timestamp that contains it.
- [`.github/scripts/update-version.sh`](https://github.com/CygnusNetworks/asterisk-usecallmanager/blob/main/.github/scripts/update-version.sh) determines all three values automatically for the newest patch and rewrites the Dockerfile.

## License
The Docker build scripts and configs in this repository are licensed under the [GNU General Public License v2.0](https://github.com/CygnusNetworks/asterisk-usecallmanager/blob/main/LICENSE), like Asterisk itself (several config files are derived from the Asterisk sample configs). Consult the Debian packaging and the UseCallManager project for their respective licenses.

## Credits

Many thanks to the UseCallManager project for providing the patches and the maintainer Gareth Palmer.

See: https://github.com/sponsors/usecallmanagernz for sponsorship of the usecallmanager project.
