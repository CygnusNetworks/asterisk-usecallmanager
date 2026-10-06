#!/usr/bin/env bash
# Look for a newer UCM patch for the tracked Asterisk major version and the
# matching packaged Debian asterisk source. If both exist, rewrite the version
# ARGs in the Dockerfile. Prints "key=value" lines (for $GITHUB_OUTPUT).
#   changed=true|false  patch_version=X.Y.Z  [waiting_for_debian=true]
set -euo pipefail

DOCKERFILE="${DOCKERFILE:-Dockerfile}"
PATCH_REPO_API="https://api.github.com/repos/usecallmanagernz/patches/contents/asterisk"
SNAPSHOT_API="https://snapshot.debian.org/mr/package/asterisk"

curl_json() {
  local auth=()
  [[ "$1" == https://api.github.com/* && -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  curl -fsSL --retry 3 "${auth[@]}" "$1"
}

current=$(sed -n 's/^ARG PATCH_VERSION=//p' "$DOCKERFILE")
major=${current%%.*}

latest=$(curl_json "$PATCH_REPO_API" \
  | jq -r '.[].name' \
  | sed -n "s/^cisco-usecallmanager-\(${major}\.[0-9.]*[0-9]\)\.patch$/\1/p" \
  | sort -V | tail -n1)
[[ -n "$latest" ]] || { echo "no ${major}.x patch found" >&2; exit 1; }

if [[ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)" == "$current" ]]; then
  echo "Dockerfile already at $current (latest patch: $latest)" >&2
  echo "changed=false"
  exit 0
fi

# Final releases only: "22.11.0+dfsg+~cs..." matches, "22.11.0-rc2+dfsg..." does not.
debian=$(curl_json "$SNAPSHOT_API/" \
  | jq -r '.result[].version' \
  | grep -E "^1:${latest//./\\.}[+~]dfsg" | sort -V | tail -n1 || true)
if [[ -z "$debian" ]]; then
  echo "patch $latest exists, but Debian has no packaged asterisk $latest yet - waiting" >&2
  echo "changed=false"
  echo "waiting_for_debian=true"
  exit 0
fi
debian_noepoch=${debian#1:}

# The snapshot must contain every source file of this version. The fileinfo
# also lists files of other versions, so only look at this version's files.
snapshot=$(curl_json "$SNAPSHOT_API/$debian/srcfiles?fileinfo=1" \
  | jq -r --arg p "asterisk_${debian_noepoch%-*}" \
      '[.fileinfo[][] | select(.archive_name=="debian" and (.name|startswith($p))) | .first_seen] | max')
[[ -n "$snapshot" && "$snapshot" != null ]] || { echo "no snapshot for $debian" >&2; exit 1; }
curl -fsSI "https://snapshot.debian.org/archive/debian/$snapshot/pool/main/a/asterisk/asterisk_${debian_noepoch}.dsc" >/dev/null \
  || { echo ".dsc not reachable in snapshot $snapshot" >&2; exit 1; }

sed -i.bak \
  -e "s|^ARG DEBIAN_SNAPSHOT=.*|ARG DEBIAN_SNAPSHOT=$snapshot|" \
  -e "s|^ARG ASTERISK_DEBIAN_VERSION=.*|ARG ASTERISK_DEBIAN_VERSION=$debian_noepoch|" \
  -e "s|^ARG PATCH_VERSION=.*|ARG PATCH_VERSION=$latest|" "$DOCKERFILE"
rm -f "$DOCKERFILE.bak"

echo "updated $current -> $latest (debian $debian_noepoch, snapshot $snapshot)" >&2
echo "changed=true"
echo "patch_version=$latest"
