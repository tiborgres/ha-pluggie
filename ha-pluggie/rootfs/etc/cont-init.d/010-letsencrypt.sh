#!/usr/bin/with-contenv bashio
# ==============================================================================
# Init folder & structures
# ==============================================================================

if [[ -n "${SUPERVISOR_TOKEN:-}" ]]; then
    PLUGGIE_DIR=/ssl/pluggie
else
    PLUGGIE_DIR=/data
fi

mkdir -p ${PLUGGIE_DIR}/workdir
mkdir -p ${PLUGGIE_DIR}/letsencrypt
mkdir -p /var/log/letsencrypt
