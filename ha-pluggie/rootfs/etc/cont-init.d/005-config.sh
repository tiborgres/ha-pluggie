#!/usr/bin/with-contenv bashio

declare -a list
declare config1
declare post_up1
declare post_down1
declare addon_version
declare is_ha_environment

log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"
export LOG_LEVEL=$(bashio::config 'log_level' 'info')

if [ -n "${PLUGGIE_VERSION}" ]; then
    addon_version="${PLUGGIE_VERSION}"
else
    addon_version="Default"
fi

if [[ -n "${SUPERVISOR_TOKEN:-}" ]]; then
    is_ha_environment=true
    PLUGGIE_DIR=/ssl/pluggie
    rm -f /data/pluggie.json
    ln -s ${PLUGGIE_DIR}/pluggie.json /data/pluggie.json
    user_agent="Pluggie-Client-HA/${addon_version}"
    bashio::log.debug "Detected Home Assistant environment"
else
    is_ha_environment=false
    PLUGGIE_DIR=/data
    user_agent="Pluggie-Client-Docker/${addon_version}"
    bashio::log.debug "Detected Docker environment"
fi

if ! bashio::fs.directory_exists '${PLUGGIE_DIR}'; then
    mkdir -p ${PLUGGIE_DIR} ||
        bashio::exit.nok "Could not create ${PLUGGIE_DIR} folder!"
fi

bashio::log.debug "User-Agent: ${user_agent}"

export ERR=0

ADDON_OPTIONS="${PLUGGIE_DIR}/pluggie.json"

if ! bashio::fs.file_exists "${ADDON_OPTIONS}"; then
    bashio::log.debug "Creating new pluggie.json file with default configuration"

    if [ "${is_ha_environment}" = true ]; then
        proxied_host="http://homeassistant.local.hass.io:8123"
    else
        proxied_host="http://localhost:8080"
    fi

    cat <<EOF > "${ADDON_OPTIONS}"
{
  "configuration": {
    "access_key": "XXXXX"
  },
  "log_level": "info",
  "proxied_host": "${proxied_host}",
  "user_agent": "${user_agent}",
  "pluggie_config": {
    "apiserver": "api.pluggie.net",
    "dns": "1.1.1.1",
    "http_port": 54001
  }
}
EOF
chmod 600 "${ADDON_OPTIONS}"

else
    current_user_agent=$(jq -r '.user_agent // ""' "${ADDON_OPTIONS}")

    if [ "${current_user_agent}" != "${user_agent}" ]; then
        bashio::log.debug "Updating User-Agent in pluggie.json"
        temp_file=$(mktemp)

        jq --arg user_agent "${user_agent}" \
           '.user_agent = $user_agent' \
           "${ADDON_OPTIONS}" > "${temp_file}" && mv "${temp_file}" "${ADDON_OPTIONS}"
    fi
fi

if ! bashio::fs.directory_exists '${PLUGGIE_DIR}/wireguard'; then
    mkdir -p ${PLUGGIE_DIR}/wireguard ||
        bashio::exit.nok "Could not create wireguard storage folder!"
fi

# Local API Status
if ! bashio::fs.directory_exists '/var/lib/wireguard'; then
    mkdir -p /var/lib/wireguard \
        || bashio::exit.nok "Could not create status API storage folder!"
fi

access_key=$(bashio::config 'configuration.access_key')
if [ "${access_key}" = "XXXXX" ] || [ -z "${access_key}" ]; then
    bashio::log.warning "Default Access Key is set. Please configure your Access Key in admin interface."
    echo "invalid_key" > "/etc/pluggie.state"
fi

# Create nginx configuration directory
if [ ! -d "/etc/nginx/http.d" ]; then
    mkdir -p "/etc/nginx/http.d"
fi

PLUGGIE_HTTP_PORT=$(bashio::config 'pluggie_config.http_port' '54001')

# /etc/nginx/nginx.conf
cat <<EOF > "/etc/nginx/nginx.conf"
user nginx;
worker_processes auto;
pcre_jit on;
error_log /dev/null;
include /etc/nginx/modules/*.conf;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    server_tokens off;
    client_max_body_size 1m;
    sendfile on;
    tcp_nopush on;
    ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:2m;
    ssl_session_timeout 1h;
    ssl_session_tickets off;
    gzip_vary on;
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' close;
    }
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
            '\$status \$body_bytes_sent "\$http_referer" '
            '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log off;
    include /etc/nginx/http.d/*.conf;
}
EOF

# /etc/nginx/http.d/default.conf
cat <<EOF > "/etc/nginx/http.d/default.conf"
server {
    listen ${PLUGGIE_HTTP_PORT} default_server;

    access_log off;
    error_log /dev/null;

    # Everything is a 404
    location / {
        return 404;
    }

    # You may need this to prevent return 404 recursion.
    location = /404.html {
        internal;
    }
}

# Pluggie Admin Interface
server {
    listen 8099 default_server;
    root /usr/local/www;
    index index.html;

    access_log off;
    error_log /dev/null;

    location /pluggie/api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Check nginx running
if pgrep nginx &>/dev/null; then
    # Reload nginx
    bashio::log.debug "Nginx is running, performing configuration reload"
    nginx -s reload
else
    # Start nginx
    bashio::log.debug "Starting nginx with new configuration"
    nginx -c /etc/nginx/nginx.conf
fi

api_connected=0

bashio::log.debug "api_connected: ${api_connected}"

while [ ${api_connected} -eq 0 ]; do
    bashio::log.debug "Connecting to Pluggie API..."
    if /usr/local/bin/get_config.py "$access_key"; then
        # Check tunnel state
        if [ -f "/etc/pluggie.state" ] && [ "$(cat /etc/pluggie.state)" = "disabled" ]; then
            bashio::log.warning "Tunnel is disabled. Will check again in 60 seconds..."
            sleep 60
        elif [ -f "/etc/pluggie.state" ] && [ "$(cat /etc/pluggie.state)" = "connectivity_issue" ]; then
            # If we have connectivity issues but we also have existing configuration
            # just carry on as there are no issues
            bashio::log.warning "Connectivity issues detected, but continuing with existing configuration."
            api_connected=1
            bashio::log.debug "Using existing configuration due to connectivity issues."
        else
            api_connected=1
            bashio::log.debug "Configuration written successfully."
        fi
    else
        ret=$?
        if [ $ret -eq 1 ]; then
            # Check if access_key is really invalid or there are just connectivity issues
            if [ -f "/etc/pluggie.state" ] && [ "$(cat /etc/pluggie.state)" = "connectivity_issue" ]; then
                # If there are connectivity issues but we have existing configuration
                # just carry on with current configuration
                bashio::log.warning "Connectivity issues detected, continuing with existing configuration."
                api_connected=1
            else
                echo "invalid_key" > "/etc/pluggie.state"

                # Remove obsolete configuration from options.json only in case of truly invalid key
                temp_file=$(mktemp)
                ADDON_OPTIONS="/data/options.json"
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

                api_connected=1
                bashio::log.warning "Invalid Access Key. Please check settings in web interface."

            fi
        fi

        # If there is no connection but script can carry on with existing configuration
        if [ -f "/etc/pluggie.state" ] && [ "$(cat /etc/pluggie.state)" = "connectivity_issue" ]; then
            bashio::log.warning "Continuing with existing configuration due to connectivity issues."
            api_connected=1
        else
            bashio::log.warning "Failed to connect to API, retrying in 30 seconds..."
            sleep 30
        fi
    fi
done
