#!/usr/bin/with-contenv bashio

log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

# Read environment variables from /etc/pluggie.conf
source /etc/pluggie.conf

if [[ ! -v PLUGGIE_ENDPOINT1_SHORT ]]; then
    bashio::log.error "Error in reading configuration file /etc/pluggie.conf! Exiting. Please contact Pluggie Support"
    kill -TERM 1
fi

check_dns() {
    local dns_server=$1
    bashio::log.debug "Checking ${dns_server}.."
    local ip=$(dig +short ${PLUGGIE_ENDPOINT1_SHORT} A @${dns_server} | grep -v "\.$")
    bashio::log.debug "Pluggie API IP from ${dns_server}: ${ip}"
    echo "$ip"
}

# Function to restart WireGuard
restart_wireguard() {
    bashio::log.warning "Stopping WireGuard interface.."
    if wg-quick down "${PLUGGIE_INTERFACE1}" 2>/dev/null; then
        bashio::log.warning "WireGuard interface stopped successfully."
    else
        bashio::log.warning "Failed to stop WireGuard interface. It may not have been running. Continuing.."
    fi

    bashio::log.warning "Starting WireGuard interface.."
    if wg-quick up "${PLUGGIE_INTERFACE1}"; then
        bashio::log.warning "WireGuard interface started successfully."
        return 0
    else
        bashio::log.error "Failed to start WireGuard interface."
        return 1
    fi
}

# List of DNS servers to try (Cloudflare, Google, Quad9)
dns_servers=("1.1.1.1" "8.8.8.8" "9.9.9.9")

# Try DNS servers in order
for server in "${dns_servers[@]}"; do
    CURRENT_PLUGGIE_IP=$(check_dns "$server")
    if [ -n "${CURRENT_PLUGGIE_IP}" ]; then
        bashio::log.debug "Valid IP found: ${CURRENT_PLUGGIE_IP}"
        break
    fi
done

# If all DNS checks failed
if [ -z "${CURRENT_PLUGGIE_IP}" ]; then
    bashio::log.error "Error resolving Pluggie endpoint ${PLUGGIE_ENDPOINT1_SHORT}. No valid IP found. Keeping WireGuard up with old Endpoint DNS records."
    exit 1
fi

bashio::log.debug "CURRENT_PLUGGIE_IP: ${CURRENT_PLUGGIE_IP}"
bashio::log.debug "PLUGGIE_ENDPOINT1_IP: ${PLUGGIE_ENDPOINT1_IP}"
bashio::log.debug "PLUGGIE_INTERFACE1: ${PLUGGIE_INTERFACE1}"

vpn_restart_needed=false

if ! ping -q -c 1 -W 3 "${PLUGGIE_ENDPOINT1_IP_INT}" >/dev/null 2>&1; then
    bashio::log.warning "VPN peer (${PLUGGIE_ENDPOINT1_IP_INT}) is not responding."
    vpn_restart_needed=true
fi

if [ "${CURRENT_PLUGGIE_IP}" != "${PLUGGIE_ENDPOINT1_IP}" ]; then
    bashio::log.warning "Pluggie API IP address changed."
    vpn_restart_needed=true
fi

if [ "$vpn_restart_needed" = true ]; then
    bashio::log.warning "Refreshing Pluggie configuration from API server.."
    if /usr/local/bin/get_config.py $(bashio::config 'configuration.access_key'); then
        bashio::log.warning "Pluggie configuration refreshed."

        bashio::log.warning "Restarting WireGuard interface ${PLUGGIE_INTERFACE1}.."
        if restart_wireguard; then
            bashio::log.warning "Successfully restarted WireGuard interface ${PLUGGIE_INTERFACE1}."
            if [ "${CURRENT_PLUGGIE_IP}" != "${PLUGGIE_ENDPOINT1_IP}" ]; then
                sed -i "/^export PLUGGIE_ENDPOINT1_IP/c\export PLUGGIE_ENDPOINT1_IP=\"${CURRENT_PLUGGIE_IP}\"" /etc/pluggie.conf
                bashio::log.warning "Updated PLUGGIE_ENDPOINT1_IP in /etc/pluggie.conf"
            fi

            # Restart nginx and refresh letsencrypt after wireguard
            nginx -s stop
            /etc/services.d/letsencrypt/run
        else
            bashio::log.error "Failed to restart WireGuard interface ${PLUGGIE_INTERFACE1}. Please check your WireGuard configuration."
            exit 1
        fi
    else
        ret=$?
        if [ $ret -eq 10 ]; then
            bashio::log.warning "Tunnel is disabled, skipping WireGuard and nginx operations"
            # Stop WireGuard if it's running
            if wg show "${PLUGGIE_INTERFACE1}" >/dev/null 2>&1; then
                bashio::log.warning "Stopping disabled WireGuard interface.."
                wg-quick down "${PLUGGIE_INTERFACE1}" 2>/dev/null
                bashio::log.warning "WireGuard interface stopped."
            fi
        else
            bashio::log.error "Failed to refresh Pluggie configuration"
            exit 1
        fi
    fi
else
    bashio::log.debug "VPN connection is healthy. No need to restart WireGuard."
fi
