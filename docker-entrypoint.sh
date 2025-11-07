#!/bin/bash

echo starting entrypoint

# run as user asterisk by default
ASTERISK_USER=${ASTERISK_USER:-asterisk}
ASTERISK_GROUP=${ASTERISK_GROUP:-${ASTERISK_USER}}

if [ "$1" = "" ]; then
  COMMAND="/usr/sbin/asterisk -T -W -U ${ASTERISK_USER} -p -vvvdddf"
else
  COMMAND="$@"
fi

if [ "${ASTERISK_UID}" != "" ] && [ "${ASTERISK_GID}" != "" ]; then
  # recreate user and group for asterisk
  # if they've sent as env variables (i.e. to match with host user to fix permissions for mounted folders

  deluser asterisk && \
  addgroup -g ${ASTERISK_GID} ${ASTERISK_GROUP} && \
  adduser -D -H -u ${ASTERISK_UID} -G ${ASTERISK_GROUP} ${ASTERISK_USER} \
  || exit
fi

if test -d "/config"; then
  echo "Detecting external ip address"
  export EXTERNAL_IP=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | sed 's/\"//g')
  if test -z "$EXTERNAL_IP"; then
    echo "Unable to detect external ip address"
    exit 1
  fi
  echo "External ip is ${EXTERNAL_IP}"
  FILES=$(find /config -name \*.conf)
  for file in $FILES; do
    echo "Copying Asterisk configfile from ${file} to /etc/asterisk/${file#/config/}"
    dir=$(dirname ${file#/config/})
    if test "${dir}" != "."; then
      echo "creating config dir /etc/asterisk/${dir}"
      mkdir -p /etc/asterisk/${dir}
    fi
    if [[ "${file#/config/}" =~ ^extensions\.d\/.* ]] || [[ "${file#/config/}" =~ ^extensions.conf ]]; then
      echo no variable substitution in dialplan file ${file#/config/}
      cp $file /etc/asterisk/${file#/config/}
    else
      cat $file | envsubst > /etc/asterisk/${file#/config/}
    fi
  done
fi

DIR=/docker-entrypoint.d
if test -d "$DIR"; then
  /bin/run-parts --verbose "$DIR"
fi

chown -R ${ASTERISK_USER}: /var/log/asterisk \
                           /etc/asterisk \
                           /var/lib/asterisk \
                           /var/run/asterisk \
                           /var/spool/asterisk; \

echo Starting Asterisk
exec ${COMMAND}
