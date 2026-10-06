#!/bin/bash
set -e # Fail immediately if any command fails
[[ "${ENTRYPOINT_DEBUG}" == "true" || "${ENTRYPOINT_DEBUG}" == "1" ]] && set -x

echo "Starting Asterisk Entrypoint"

# --- Configuration ---
ASTERISK_USER=${ASTERISK_USER:-asterisk}
ASTERISK_GROUP=${ASTERISK_GROUP:-${ASTERISK_USER}}
CONFIG_SRC="/config"
CONFIG_DEST="/etc/asterisk"

# Set IGNORE_EXTERNAL_IP_CHECK to true or 1 to skip the IP detection and exit check
IGNORE_EXTERNAL_IP_CHECK=${IGNORE_EXTERNAL_IP_CHECK:-false}

# --- UID/GID Mapping ---
if [ -n "${ASTERISK_UID}" ] && [ -n "${ASTERISK_GID}" ]; then
    echo "Updating asterisk user to UID:${ASTERISK_UID} GID:${ASTERISK_GID}"
    
    # Modify group and user IDs allowing non-unique IDs (-o) just in case
    groupmod -o -g "${ASTERISK_GID}" "${ASTERISK_GROUP}"
    usermod -o -u "${ASTERISK_UID}" -g "${ASTERISK_GID}" "${ASTERISK_USER}"
    
    # Fix home directory ownership if it changed
    chown "${ASTERISK_UID}:${ASTERISK_GID}" "/var/lib/asterisk"
fi

# --- Configuration Processing ---
if [ -d "$CONFIG_SRC" ]; then
    echo "Processing configuration files from $CONFIG_SRC..."
    
    # 1. Detect External IP Address
    if [ -n "${EXTERNAL_IP}" ]; then
        echo "External ip set via environment variable."
    elif [[ "${IGNORE_EXTERNAL_IP_CHECK}" == "true" || "${IGNORE_EXTERNAL_IP_CHECK}" == "1" ]]; then
        echo "EXTERNAL_IP not set, detection skipped (IGNORE_EXTERNAL_IP_CHECK=${IGNORE_EXTERNAL_IP_CHECK})."
    else
        # If EXTERNAL_IP is NOT provided, attempt detection
        echo "EXTERNAL_IP not set. Detecting address..."
        EXTERNAL_IP=$(dig -4 TXT +short +time=3 +tries=2 o-o.myaddr.l.google.com @ns1.google.com | tr -d '"' || true)

        if [ -z "$EXTERNAL_IP" ]; then
            echo "Error: Unable to detect external ip address. Exiting."
            echo "To fix this, provide it as an environment variable: -e EXTERNAL_IP=1.2.3.4"
            echo "or set -e IGNORE_EXTERNAL_IP_CHECK=true if your config does not use \${EXTERNAL_IP}."
            exit 1
        fi
    fi
    export EXTERNAL_IP

    echo "External ip is ${EXTERNAL_IP:-<unset>}"
    
    # 2. Process Files
    find "$CONFIG_SRC" -type f | while read -r file; do
        rel_path="${file#$CONFIG_SRC/}"
        dest_file="$CONFIG_DEST/$rel_path"
        dest_dir="$(dirname "$dest_file")"

        mkdir -p "$dest_dir"

        # Apply variable substitution
        # Check if file is extensions.conf or inside extensions.d directory
        if [[ "$rel_path" == "extensions.conf" ]] || [[ "$rel_path" == extensions.d/* ]]; then
            echo "  - Not performing envsubst: $rel_path"
            # Dialplan files use ${...} themselves, copy them verbatim
            cp "$file" "$dest_file"
        else
            echo "  - Full envsubst: $rel_path"
            # Substitute all environment variables in other config files
            envsubst < "$file" > "$dest_file"
        fi
    done
fi

# --- Custom Entrypoint Scripts ---
DIR="/docker-entrypoint.d"
if [ -d "$DIR" ]; then
    echo "Running custom scripts in $DIR"
    /bin/run-parts --verbose "$DIR"
fi

# --- Permissions Fix ---
echo "Fixing permissions..."
mkdir -p /var/run/asterisk
chown -R "${ASTERISK_USER}:${ASTERISK_GROUP}" \
    /var/log/asterisk \
    /etc/asterisk \
    /var/lib/asterisk \
    /var/run/asterisk \
    /var/spool/asterisk \
    || echo "Warning: could not change ownership of some files (read-only mounts?), continuing."

# --- Execution ---
echo "Starting Asterisk..."
if [ "$#" -eq 0 ]; then
    # Default behavior: Run Asterisk
    exec /usr/sbin/asterisk -T -W -U "${ASTERISK_USER}" -p -vvvdddf
else
    # Run custom command passed to docker run
    exec "$@"
fi