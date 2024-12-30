#!/usr/bin/with-contenv bashio

# declare pluggie_interface2

log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

# Read environment variables from /etc/pluggie.conf
source /etc/pluggie.conf

# Check created wireguard network interface
PLUGGIE_INTERFACE1_PATH="/sys/class/net/${PLUGGIE_INTERFACE1}"

if [ -d ${PLUGGIE_INTERFACE1_PATH} ]; then
    bashio::log.info "Stopping Pluggie.."

    bashio::log.debug "Stopping NGINX Reverse Proxy."
    if [ -e "/run/nginx/nginx.pid" ]; then
        nginx -s stop
    fi

    bashio::log.debug "Stopping Pluggie Connector."
    if [[ "${__BASHIO_LOG_LEVEL}" -ge "${__BASHIO_LOG_LEVEL_DEBUG}" ]]; then
        # If debug level, show all output
        wg-quick down "${PLUGGIE_INTERFACE1}"
    else
        # Otherwise suppress WireGuard output
        wg-quick down "${PLUGGIE_INTERFACE1}" > /dev/null 2>&1
    fi

    bashio::log.info "Pluggie stopped."
fi
