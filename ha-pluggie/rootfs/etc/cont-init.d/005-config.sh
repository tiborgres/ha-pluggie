#!/usr/bin/with-contenv bashio

declare -a list
declare config1
# temporary off (v0.4.3.2)
# declare config2
declare keep_alive
declare mtu
declare post_up1
# temporary off (v0.4.3.2)
# declare post_up2
declare post_down1
# temporary off (v0.4.3.2)
# declare post_down2

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
    # try connect in loop
    api_connected=0
    export LOG_LEVEL=$(bashio::config '__BASHIO_LOG_LEVEL' 'info')
    while [ ${api_connected} -eq 0 ];
    do
        if /usr/local/bin/get_config.py $(bashio::config 'configuration.access_key'); then
            api_connected=1
            bashio::log.debug "Configuration written successfully."
        else
            bashio::log.warning "Failed to connect to API, retrying in 30 seconds..."
            sleep 30
        fi
    done
else
    bashio::log.error "Error getting access_key!"
    exit 1
fi
