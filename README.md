# asterisk-usecallmanager Container image

Container image that builds and runs Asterisk with the cisco-usecallmanager patchset applied, plus sane defaults for SIP/PJSIP. 
Designed to let you drop your own Asterisk config in at runtime and have variables expanded automatically.

This image with version 22.6 is not yet intended for production. See https://usecallmanager.nz/ for details regarding `chan_sip` backport.

## Overview
- Base OS: Debian (slim).
- Asterisk packages: built from Debian source and patched with the UseCallManager (UCM) patchset.
- Entry point: a small bootstrap script that
  - remaps the runtime user if requested,
  - auto-detects your public IPv4 address,
  - copies any `*.conf` files from `/config` into `/etc/asterisk`,
  - performs environment variable substitution (`envsubst`) on those files (except dialplan files), and
  - starts Asterisk.

### Relationship to the UseCallManager project
This image consumes the patchset from the UseCallManager project:
- Site: https://usecallmanager.nz/
- Change log: https://usecallmanager.nz/change-log.html

Hints and current state as of Asterisk 22.6 (Nov 2025):
- The UCM patchset continues to evolve for Asterisk 22.x; running patched Asterisk 22.x is generally not recommended for production unless you fully understand the implications and test thoroughly.
- There have been backports and changes affecting `chan_sip` in the UCM patches. Read the change log linked above and validate your configuration.
- `chan_sip` might be suitable for connection to Cisco Phones, pjsip for other SIP endpoints.

Note: This repository’s Dockerfile currently builds against Asterisk Debian source version set by `ARG ASTERISK_DEBIAN_VERSION` (default in this repo points to 22.6.0) on Debian Trixie.

## Requirements
- Docker Engine or compatible runtime.
- For external RTP media, open/forward a UDP range on your host (commonly 10000–10020) and the SIP signaling port(s) you plan to use.
- Outbound DNS to resolve and query Google’s DNS (used to detect public IP) unless you override `EXTERNAL_IP` yourself.


## How configuration works (very important)
At container start, `/docker-entrypoint.sh` performs the following:

1. User/group remap (optional)
   - If `ASTERISK_UID` and `ASTERISK_GID` are provided, the script recreates the `asterisk` user and group with those IDs. This is useful to align file permissions with your host user when bind-mounting volumes.

2. External IP detection
   - The script tries to detect your public IPv4 address:
     ```bash
     dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | sed 's/\"//g'
     ```
   - The result is exported as `EXTERNAL_IP` for later substitution.
   - If it cannot detect an address and you provided a `/config` directory, the script exits with a non‑zero status. If your environment blocks that DNS query, set `EXTERNAL_IP` explicitly.

3. Config ingestion from `/config`
   - If a directory `/config` exists, every `*.conf` file under it is copied into `/etc/asterisk` preserving relative paths. For example:
     - `/config/pjsip.conf` → `/etc/asterisk/pjsip.conf`
     - `/config/pjsip.d/my-peer.conf` → `/etc/asterisk/pjsip.d/my-peer.conf`
   - Variable substitution is applied to all config files via `envsubst`, except dialplan files:
     - Files matching `extensions.conf` or anything under `extensions.d/` are copied verbatim (no substitution) to avoid breaking `${...}` style Asterisk dialplan expressions.
   - All other `.conf` files have shell-style variables expanded using the container’s environment (e.g., `${EXTERNAL_IP}`, `${SIP_BIND_PORT}`, `${WHATEVER}` that you define).

4. Config through volumes files
   - if you do not provider a `/config` directory, you can also mount your own config files at runtime
   - volume mount your config files for SIP, PJSIP and extensions in directories /etc/asterisk/sip.d, /etc/asterisk/pjsip.d and /etc/asterisk/extensions.d. 
   - the main config files for SIP, PJSIP and extensions are /etc/asterisk/sip.conf, /etc/asterisk/pjsip.conf and /etc/asterisk/extensions.conf, which use a tryinclude to the subdirectories.
5. Optional hooks
   - If `/docker-entrypoint.d/` exists, the script runs all executable parts using `run-parts` before starting Asterisk. This is handy for last-mile tweaks.

6. Ownership and start
   - Key Asterisk directories are chowned to the runtime user and Asterisk is launched.

Base configs are bundled under `/etc/asterisk` in the image (copied from this repo’s `config/`). Any files you place in `/config` will override or augment those.


## Config files in Docker Image

All config files are defined with default values except the ones below. 

For basic use cases, simply mount directory volumes to:

  * /etc/asterisk/sip.d
  * /etc/asterisk/pjsip.d
  * /etc/asterisk/extensions.d
  * /etc/asterisk/ari.d

All `*.conf` files there will be read. If you need more control over configs, do a volume mount to `/config`. Files present there will be copied to `/etc/asterisk` after envsubst parsing.

- `ari.conf` - defines tryingclude ari.d/*.conf - ari disabled by default
- `sip.conf` - defines tryingclude sip.d/*.conf
- `pjsip.conf` - defines tryingclude pjsip.d/*.conf
- `extensions.conf` - defines tryingclude extensions.d/*.conf
- `asterisk.conf` - defines verbose = 5, debug = 3, autosystemname = yes
- `logger.conf` - sets logging to stdout
- `modules.conf` - disables modules which produce load warnings

## Environment variables
Runtime (entrypoint) variables:
- `ASTERISK_USER` (default: `asterisk`)
- `ASTERISK_GROUP` (default: same as user)
- `ASTERISK_UID` / `ASTERISK_GID` (optional remap)
- `EXTERNAL_IP` (optional; auto-detected if not set and `/config` exists)
- Any additional variables you define for use in your `.conf` files (expanded via `envsubst`). For example: `SIP_BIND_ADDR`, `SIP_BIND_PORT`, `LOCAL_NET`, etc.

Build-time (Docker build args):
- `DEBIAN_VERSION` (default: `trixie`)
- `ASTERISK_DEBIAN_VERSION` (Debian source version string)
- `PATCH_VERSION` (UCM patch version, e.g., `22.6.0`)


## Quick start (docker run)
```bash

docker run \
  --name asterisk \
  -e EXTERNAL_IP=203.0.113.10 \  # set explicitly if autodetect is blocked
  -e ASTERISK_UID=$(id -u) -e ASTERISK_GID=$(id -g) \  # optional UID/GID remap
  -v $(pwd)/my-asterisk-config:/config:ro \            # configs to be processed/expanded
  -p 5060:5060/udp \ # SIP signaling udp
  -p 5060:5060/tcp \ # SIP signaling
  -p 10000-20000:10000-20000/udp \                     # RTP media range (adjust as needed)
  cygnusbn/asterisk-usecallmanager:latest
```

Notes:
- If you don’t mount `/config`, the image’s baked-in configs are used.
- You can mount `/etc/asterisk` directly instead, but `/config` is recommended so you benefit from envsubst.


## docker-compose example
```yaml
services:
  asterisk:
    image: asterisk-usecallmanager:local  # or your registry image
    container_name: asterisk
    environment:
      # Provide EXTERNAL_IP if your DNS cannot resolve via Google’s o-o.myaddr mechanism
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
      # Optional: drop-in scripts executed before Asterisk starts
      # - ./entrypoint.d:/docker-entrypoint.d:ro
    ports:
      - "5060:5060/udp"
      - "5060:5060/tcp"
      - "10000-10020:10000-10020/udp"
    restart: unless-stopped
```


## Scripts and hooks
- `/docker-entrypoint.sh` — main launcher (see “How configuration works”).
- `/docker-entrypoint.d/` — optional directory; any executable files placed here will run (via `run-parts`) before Asterisk starts. Use this for last-minute file generation or tweaks.


## Production considerations
- The UseCallManager patches are powerful but invasive. Validate carefully before deploying to production.
- As of Asterisk 22.5, UCM-related features and `chan_sip` changes/backports have caveats. Review: https://usecallmanager.nz/change-log.html
- Prefer `pjsip` for new deployments unless you have a specific reason to use `chan_sip`.
- Pin your image and config versions; test upgrades in a staging environment.


## Troubleshooting
- External IP detection fails: set `EXTERNAL_IP` manually (e.g., with compose or `-e`). Ensure outbound DNS works if you rely on autodetect.
- No audio or one-way audio: confirm RTP port range is published from host to container and your firewall/NAT rules are correct; ensure your SIP signaling advertises the correct public address (use `${EXTERNAL_IP}` in `pjsip.conf`/`sip.conf`).
- Variable not expanded: remember that `envsubst` runs only on non-dialplan `.conf` files; dialplan files (`extensions.conf`/`extensions.d/*`) are copied verbatim.


## Building with a different Asterisk source version or patch
```bash
docker build \
  --build-arg DEBIAN_VERSION=trixie \
  --build-arg ASTERISK_DEBIAN_VERSION=22.6.0~dfsg+~cs6.15.60671435-1 \
  --build-arg PATCH_VERSION=22.6.0 \
  -t asterisk-usecallmanager:22.6-ucm .
```

Adjust the args to match versions provided by Debian and the UCM patchset you want to consume.


## License
This repository contains Docker build scripts and example configs. Asterisk itself is licensed under GPLv2; consult Debian packaging and the UseCallManager project for their respective licenses.
