#!/usr/bin/with-contenv bashio

log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

bashio::log.info "Stopping Pluggie.."

# Stop NGINX
bashio::log.debug "Stopping NGINX Reverse Proxy."
if pgrep nginx &>/dev/null; then
    nginx -s stop
fi

# Check created wireguard network interface
PLUGGIE_INTERFACE1=$(bashio::config 'pluggie_config.interface1')
if [ -n "${PLUGGIE_INTERFACE1}" ]; then
    PLUGGIE_INTERFACE1_PATH="/sys/class/net/${PLUGGIE_INTERFACE1}"
    if [ -d "${PLUGGIE_INTERFACE1_PATH}" ]; then
        # Stop Wireguard
        bashio::log.debug "Stopping Pluggie Connector."
        if [[ "${__BASHIO_LOG_LEVEL}" -ge "${__BASHIO_LOG_LEVEL_DEBUG}" ]]; then
            # If debug level, show all output
            wg-quick down "${PLUGGIE_INTERFACE1}"
            rm -f /etc/wireguard/${PLUGGIE_INTERFACE1}.conf
        else
            # Otherwise suppress WireGuard output
            wg-quick down "${PLUGGIE_INTERFACE1}" > /dev/null 2>&1
            rm -f /etc/wireguard/${PLUGGIE_INTERFACE1}.conf
        fi
    fi
fi

# Remove obsolete configuration from pluggie.json
temp_file=$(mktemp)

if [[ -n "${SUPERVISOR_TOKEN:-}" ]]; then
    ADDON_OPTIONS="/ssl/pluggie/pluggie.json"
else
    ADDON_OPTIONS="/data/pluggie.json"
fi

jq '.pluggie_config = (.pluggie_config // {}) |
    del(.pluggie_config.interface1) |
    del(.pluggie_config.hostname) |
    del(.pluggie_config.email) |
    del(.pluggie_config.keyfile) |
    del(.pluggie_config.certfile) |
    del(.pluggie_config.http_port) |
    del(.pluggie_config.https_port) |
    del(.pluggie_config.endpoint1_short) |
    del(.pluggie_config.endpoint1_ip) |
    del(.pluggie_config.endpoint1_ip_int)' "${ADDON_OPTIONS}" > "${temp_file}" && mv "${temp_file}" "${ADDON_OPTIONS}"

bashio::log.info "Pluggie stopped."
