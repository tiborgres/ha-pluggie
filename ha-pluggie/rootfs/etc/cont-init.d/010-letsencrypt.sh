#!/usr/bin/with-contenv bashio
# ==============================================================================
# Init folder & structures
# ==============================================================================

PLUGGIEDIR=/ssl/pluggie
mkdir -p ${PLUGGIEDIR}/workdir
mkdir -p ${PLUGGIEDIR}/letsencrypt
mkdir -p /var/log/letsencrypt
