#!/usr/bin/with-contenv bashio

# Function to check DNS records
check_dns() {
    local hostname=$1
    local dns_server=$2
    bashio::log.debug "Checking ${hostname} using DNS ${dns_server}.."
    local ip=$(dig +short ${hostname} A @${dns_server} | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "")
    bashio::log.debug "IP for ${hostname} from ${dns_server}: ${ip}"
    echo "$ip"
}

# Function to restart WireGuard
restart_wireguard() {
    bashio::log.debug "Stopping WireGuard interface.."
    # Capture output from wg-quick down
    if wg-quick down "${PLUGGIE_INTERFACE1}" 2>&1 | while IFS= read -r line; do
        if [[ $line == \[#\]* ]]; then
            command="${line#*\] }"
            bashio::log.debug "WireGuard command: ${command}"
        else
            bashio::log.debug "WireGuard: ${line}"
        fi
    done; then
        bashio::log.debug "WireGuard interface stopped successfully."
    else
        bashio::log.warning "Failed to stop WireGuard interface. It may not have been running. Continuing.."
    fi

    bashio::log.debug "Starting WireGuard interface.."
    # Capture output from wg-quick up
    if wg-quick up "${PLUGGIE_INTERFACE1}" 2>&1 | while IFS= read -r line; do
        if [[ $line == \[#\]* ]]; then
            command="${line#*\] }"
            bashio::log.debug "WireGuard command: ${command}"
        else
            bashio::log.debug "WireGuard: ${line}"
        fi
    done; then
        bashio::log.debug "WireGuard interface started successfully."
        return 0
    else
        bashio::log.error "Failed to start WireGuard interface."
        return 1
    fi
}


log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

# Read environment variables from /etc/pluggie.conf
source /etc/pluggie.conf

if [[ ! -v PLUGGIE_ENDPOINT1_SHORT ]]; then
    bashio::log.fatal "Error in reading configuration file /etc/pluggie.conf! Exiting. Please contact Pluggie Support"
    kill -TERM 1
fi

vpn_restart_needed=false

# List of DNS servers to try (Cloudflare, Google, Quad9)
dns_servers=("1.1.1.1" "8.8.8.8" "9.9.9.9")

# Try DNS servers in order
for server in "${dns_servers[@]}"; do
    # Check hostname IP
    HOSTNAME_IP=$(check_dns "${PLUGGIE_HOSTNAME}" "$server")
    if [ -n "${HOSTNAME_IP}" ]; then
        bashio::log.debug "Valid hostname IP found: ${HOSTNAME_IP}"

        # Check endpoint IP
        CURRENT_ENDPOINT_IP=$(check_dns "${PLUGGIE_ENDPOINT1_SHORT}" "$server")
        if [ -n "${CURRENT_ENDPOINT_IP}" ]; then
            bashio::log.debug "Valid Pluggie endpoint IP found: ${CURRENT_ENDPOINT_IP}"

            # Check API server using the same check_dns function
            CURRENT_API_IP=$(check_dns "${PLUGGIE_APISERVER}" "$server")
            if [ -n "${CURRENT_API_IP}" ]; then
                bashio::log.debug "Valid API server IP found: ${CURRENT_API_IP}"
                break
            fi
        fi
    fi
done

# If all DNS checks failed
if [ -z "${HOSTNAME_IP}" ]; then
    bashio::log.error "Error resolving hostname ${PLUGGIE_HOSTNAME}. No valid IPs found."
    # 'sleep 60' instead of 'exit 1' to keep running for case the DNS records will become valid again
    bashio::log.info "Sleeping for 60 seconds to run loop again"
    sleep 60
    # exit 1
fi

if [ -z "${CURRENT_ENDPOINT_IP}" ]; then
    bashio::log.error "Error resolving Pluggie endpoints. No valid IPs found. Keeping WireGuard up with old DNS records."
    # 'sleep 60' instead of 'exit 1' to keep running for case the DNS records will become valid again
    bashio::log.info "Sleeping for 60 seconds to run loop again"
    sleep 60
    # exit 1
fi

if [ -z "${CURRENT_API_IP}" ]; then
    bashio::log.error "Error resolving Pluggie API server. No valid IPs found. Keeping WireGuard up with old DNS records."
    # 'sleep 60' instead of 'exit 1' to keep running for case the DNS records will become valid again
    bashio::log.info "Sleeping for 60 seconds to run loop again"
    sleep 60
    # exit 1
fi

bashio::log.debug "HOSTNAME_IP: ${HOSTNAME_IP}"
bashio::log.debug "CURRENT_API_IP: ${CURRENT_API_IP}"
bashio::log.debug "CURRENT_ENDPOINT_IP: ${CURRENT_ENDPOINT_IP}"
bashio::log.debug "PLUGGIE_ENDPOINT1_IP: ${PLUGGIE_ENDPOINT1_IP}"
bashio::log.debug "PLUGGIE_INTERFACE1: ${PLUGGIE_INTERFACE1}"

# Check if hostname or endpoint IP changed
if [ "${HOSTNAME_IP}" != "${CURRENT_ENDPOINT_IP}" ]; then
    bashio::log.error "Hostname IP (${HOSTNAME_IP}) does not match endpoint IP (${CURRENT_ENDPOINT_IP})"
    bashio::log.info "Waiting for DNS propagation. Sleeping for 60 seconds to run loop again"
    vpn_restart_needed=true
    # sleep 60
    exit 1
fi

# Check if endpoint IP changed
if [ "${CURRENT_ENDPOINT_IP}" != "${PLUGGIE_ENDPOINT1_IP}" ]; then
    bashio::log.warning "Pluggie endpoint IP address changed."
    vpn_restart_needed=true

    # Get config from API to check if API server changed
    response=$(curl -s -H "Authorization: Bearer $(bashio::config 'configuration.access_key')" "https://${PLUGGIE_APISERVER}/api/settings")
    NEW_APISERVER=$(echo "${response}" | jq -r '.client_tunnel_settings.apiserver')

    # If API server changed, update it in config
    if [ -n "${NEW_APISERVER}" ] && [ "${NEW_APISERVER}" != "${PLUGGIE_APISERVER}" ]; then
        bashio::log.warning "API server changed from ${PLUGGIE_APISERVER} to ${NEW_APISERVER}"
        sed -i "/^export PLUGGIE_APISERVER/c\export PLUGGIE_APISERVER=\"${NEW_APISERVER}\"" /etc/pluggie.conf
    fi
fi

# Check VPN connectivity
if ! ping -q -c 1 -W 3 "${PLUGGIE_ENDPOINT1_IP_INT}" >/dev/null 2>&1; then
    bashio::log.warning "Pluggie endpoint (${PLUGGIE_ENDPOINT1_IP_INT}) is not responding."
    vpn_restart_needed=true
fi

if [ "${vpn_restart_needed}" = true ]; then
    bashio::log.warning "Refreshing Pluggie configuration from API server.."
    if /usr/local/bin/get_config.py $(bashio::config 'configuration.access_key'); then
        bashio::log.debug "Pluggie configuration refreshed."

        bashio::log.warning "Restarting WireGuard interface ${PLUGGIE_INTERFACE1}.."
        if restart_wireguard; then
            bashio::log.debug "Successfully restarted WireGuard interface ${PLUGGIE_INTERFACE1}."
            if [ "${CURRENT_ENDPOINT_IP}" != "${PLUGGIE_ENDPOINT1_IP}" ]; then
                sed -i "/^export PLUGGIE_ENDPOINT1_IP/c\export PLUGGIE_ENDPOINT1_IP=\"${CURRENT_ENDPOINT_IP}\"" /etc/pluggie.conf
                bashio::log.debug "Updated PLUGGIE_ENDPOINT1_IP in /etc/pluggie.conf"
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
                bashio::log.debug "WireGuard interface stopped."
            fi
        else
            bashio::log.error "Failed to refresh Pluggie configuration"
            exit 1
        fi
    fi
else
    bashio::log.debug "VPN connection is healthy. No need to restart WireGuard."
fi
