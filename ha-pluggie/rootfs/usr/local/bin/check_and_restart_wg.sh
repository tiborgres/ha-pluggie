#!/usr/bin/with-contenv bashio

# Function to check DNS records
check_dns() {
    local hostname=$1
    local dns_server=$2

    if [ -z "$hostname" ] || [ "$hostname" = "." ]; then
        bashio::log.debug "Empty hostname provided, skipping DNS check"
        return 0
    fi

    bashio::log.debug "Checking ${hostname} using DNS ${dns_server}.." >&2
    local ip=$(dig +short ${hostname} A @${dns_server} | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "")
    bashio::log.debug "IP for ${hostname} from ${dns_server}: ${ip}" >&2
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
export LOG_LEVEL=$(bashio::config 'log_level' 'info')

access_key=$(bashio::config 'configuration.access_key')
if [ "${access_key}" = "XXXXX" ] || [ -z "${access_key}" ]; then
    bashio::log.warning "No valid Access Key configured. WireGuard check will not run."
    exit 0
fi

# Read configuration from /data/pluggie.json
PLUGGIE_ENDPOINT1_SHORT=$(bashio::config 'pluggie_config.endpoint1_short')
PLUGGIE_ENDPOINT1_IP=$(bashio::config 'pluggie_config.endpoint1_ip')
PLUGGIE_ENDPOINT1_IP_INT=$(bashio::config 'pluggie_config.endpoint1_ip_int')
PLUGGIE_INTERFACE1=$(bashio::config 'pluggie_config.interface1')
PLUGGIE_APISERVER=$(bashio::config 'pluggie_config.apiserver')
PLUGGIE_HOSTNAME=$(bashio::config 'pluggie_config.hostname')
PLUGGIE_DNS=$(bashio::config 'pluggie_config.dns')

# Initialise variables
HOSTNAME_IP=""
CURRENT_ENDPOINT_IP=""
CURRENT_API_IP=""

vpn_restart_needed=false

# Check if we dont have some variables empty
if [ -z "$PLUGGIE_HOSTNAME" ] || [ -z "$PLUGGIE_ENDPOINT1_SHORT" ] || [ -z "$PLUGGIE_ENDPOINT1_IP_INT" ]; then
    bashio::log.debug "Attempting to get configuration from API server..."
    if /usr/local/bin/get_config.py "${access_key}"; then
        # Read configuration from just refreshed /data/pluggie.json
        PLUGGIE_ENDPOINT1_SHORT=$(bashio::config 'pluggie_config.endpoint1_short')
        PLUGGIE_ENDPOINT1_IP=$(bashio::config 'pluggie_config.endpoint1_ip')
        PLUGGIE_ENDPOINT1_IP_INT=$(bashio::config 'pluggie_config.endpoint1_ip_int')
        PLUGGIE_INTERFACE1=$(bashio::config 'pluggie_config.interface1')
        PLUGGIE_APISERVER=$(bashio::config 'pluggie_config.apiserver')
        PLUGGIE_HOSTNAME=$(bashio::config 'pluggie_config.hostname')
        PLUGGIE_DNS=$(bashio::config 'pluggie_config.dns')

        bashio::log.debug "Configuration obtained successfully. Restarting services..."
        cat /dev/null > "/etc/pluggie.state"
        vpn_restart_needed=true
    else
        ret=$?
        # Dont exit if there are connection issues
        if [ -f "/etc/pluggie.state" ] && [ "$(cat /etc/pluggie.state)" = "connectivity_issue" ]; then
            bashio::log.warning "Connectivity issues detected, keeping existing configuration and services running."
            vpn_restart_needed=false
            exit 0
        else
            bashio::log.error "Failed to get configuration from API server."
            exit 1
        fi
    fi
fi

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

bashio::log.debug "HOSTNAME_IP: ${HOSTNAME_IP}" >&2
bashio::log.debug "CURRENT_API_IP: ${CURRENT_API_IP}" >&2
bashio::log.debug "CURRENT_ENDPOINT_IP: ${CURRENT_ENDPOINT_IP}" >&2
bashio::log.debug "PLUGGIE_ENDPOINT1_IP: ${PLUGGIE_ENDPOINT1_IP}" >&2
bashio::log.debug "PLUGGIE_INTERFACE1: ${PLUGGIE_INTERFACE1}" >&2

# Check if hostname or endpoint IP changed
if [ -n "${HOSTNAME_IP}" ] && [ -n "${CURRENT_ENDPOINT_IP}" ] && [ "${HOSTNAME_IP}" != "${CURRENT_ENDPOINT_IP}" ]; then
    bashio::log.error "Hostname IP (${HOSTNAME_IP}) does not match endpoint IP (${CURRENT_ENDPOINT_IP})"
    bashio::log.info "Waiting for DNS propagation. Sleeping for 60 seconds to run loop again"
    vpn_restart_needed=true
    # sleep 60
    exit 1
fi

# Check if endpoint IP changed
if [ -n "${CURRENT_ENDPOINT_IP}" ] && [ -n "${PLUGGIE_ENDPOINT1_IP}" ] && [ "${CURRENT_ENDPOINT_IP}" != "${PLUGGIE_ENDPOINT1_IP}" ]; then
    bashio::log.warning "Pluggie endpoint IP address changed."
    vpn_restart_needed=true

    # Get config from API to check if API server changed
    response=$(curl -s -H "Authorization: Bearer $(bashio::config 'configuration.access_key')" "https://${PLUGGIE_APISERVER}/api/settings")
    NEW_APISERVER=$(echo "${response}" | jq -r '.client_tunnel_settings.apiserver')

    # If API server changed, update it in config
    if [ -n "${NEW_APISERVER}" ] && [ "${NEW_APISERVER}" != "${PLUGGIE_APISERVER}" ]; then
        bashio::log.warning "API server changed from ${PLUGGIE_APISERVER} to ${NEW_APISERVER}"

        # Refresh /data/pluggie.json with jq
        temp_file=$(mktemp)
        jq --arg apiserver "${NEW_APISERVER}" \
           '.pluggie_config.apiserver = $apiserver' /data/pluggie.json > "$temp_file" && mv "$temp_file" /data/pluggie.json
    fi
fi

# Check VPN connectivity
if [ "${vpn_restart_needed}" = "false" ]; then
    if [ -n "${PLUGGIE_ENDPOINT1_IP_INT}" ] && ! ping -q -c 1 -W 3 "${PLUGGIE_ENDPOINT1_IP_INT}" >/dev/null 2>&1; then
        bashio::log.warning "Pluggie endpoint (${PLUGGIE_ENDPOINT1_IP_INT}) is not responding."
        vpn_restart_needed=true
    fi
fi

if [ "${vpn_restart_needed}" = true ]; then
    # Check config file
    if [ ! -f "/etc/wireguard/${PLUGGIE_INTERFACE1}.conf" ]; then
        bashio::log.warning "WireGuard configuration file does not exist. Skipping restart."
        exit 0
    fi

    bashio::log.warning "Refreshing Pluggie configuration from API server.."
    if /usr/local/bin/get_config.py $(bashio::config 'configuration.access_key'); then
        bashio::log.debug "Pluggie configuration refreshed."

        bashio::log.warning "Restarting WireGuard interface ${PLUGGIE_INTERFACE1}.."
        if restart_wireguard; then
            bashio::log.debug "Successfully restarted WireGuard interface ${PLUGGIE_INTERFACE1}."
            if [ -n "${CURRENT_ENDPOINT_IP}" ] && [ -n "${PLUGGIE_ENDPOINT1_IP}" ] && [ "${CURRENT_ENDPOINT_IP}" != "${PLUGGIE_ENDPOINT1_IP}" ]; then
                temp_file=$(mktemp)
                jq --arg ip "${CURRENT_ENDPOINT_IP}" \
                   '.pluggie_config.endpoint1_ip = $ip' /data/pluggie.json > "$temp_file" && mv "$temp_file" /data/pluggie.json
                bashio::log.debug "Updated endpoint1_ip in pluggie.json"
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
        fi
    fi
else
    bashio::log.debug "VPN connection is healthy. No need to restart WireGuard."
fi
