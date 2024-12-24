#!/usr/bin/with-contenv bashio

declare -a list
declare config1
# declare keep_alive
# declare mtu
declare post_up1
declare post_down1

log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

# Write bootstrap /etc/pluggie.conf
# This config will be overwritten with actual variables later by get_config.py
# lowering log.level temporary due to excessive output from supervisor API
# from which we need to get addon.version
bashio::log.level "info"
addon_version=$(bashio::addon.version)
# setting log.level back
bashio::log.level "${log_level}"

bashio::log.debug "Pluggie Addon version: ${addon_version}"
# Actual write
cat <<EOF > /etc/pluggie.conf
export PLUGGIE_USERAGENT="Pluggie-Client-HA/`echo ${addon_version}`"
export PLUGGIE_APISERVER="api.pluggie.net"
export PLUGGIE_DNS1="1.1.1.1"
EOF

if ! bashio::fs.directory_exists '/ssl/pluggie/wireguard'; then
    mkdir -p /ssl/pluggie/wireguard ||
        bashio::exit.nok "Could not create wireguard storage folder!"
fi

# Local API Status
if ! bashio::fs.directory_exists '/var/lib/wireguard'; then
    mkdir -p /var/lib/wireguard \
        || bashio::exit.nok "Could not create status API storage folder!"
fi

# Connect to API server and get tunnel configuration
if bashio::config.has_value "configuration.access_key"; then
    api_connected=0
    export LOG_LEVEL=$(bashio::config '__BASHIO_LOG_LEVEL' 'info')
    # try connect in loop
    while [ ${api_connected} -eq 0 ]; do
        bashio::log.debug "Connecting to Pluggie API..."
        if /usr/local/bin/get_config.py $(bashio::config 'configuration.access_key'); then
            # Check tunnel state
            if [ -f "/etc/pluggie.state" ] && [ "$(cat /etc/pluggie.state)" = "disabled" ]; then
                bashio::log.warning "Tunnel is disabled. Will check again in 60 seconds..."
                sleep 60
            else
                api_connected=1
                bashio::log.debug "Configuration written successfully."
            fi
        else
            bashio::log.warning "Failed to connect to API, retrying in 30 seconds..."
            sleep 30
        fi
    done
else
    bashio::log.error "Error getting access_key!"
    exit 1
fi
