#!/usr/bin/with-contenv bashio

log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

bashio::log.debug "Updating nginx configuration."

# Read configuration from /data/pluggie.json
PLUGGIE_HTTP_PORT=$(bashio::config 'pluggie_config.http_port' '54001')
PLUGGIE_HTTPS_PORT=$(bashio::config 'pluggie_config.https_port' '54002')
PLUGGIE_HOSTNAME=$(bashio::config 'pluggie_config.hostname' 'localhost')
PLUGGIE_USERAGENT=$(bashio::config 'user_agent')
DOMAIN=${PLUGGIE_HOSTNAME:-"localhost"}

if [[ "${PLUGGIE_USERAGENT}" == *"Pluggie-Client-Docker"* ]]; then
    PLATFORM="docker-pluggie"
    PLUGGIE_DIR=/data
elif [[ "${PLUGGIE_USERAGENT}" == *"Pluggie-Client-HA"* ]]; then
    PLATFORM="ha-pluggie"
    PLUGGIE_DIR=/ssl/pluggie
else
    PLATFORM="unknown"
    PLUGGIE_DIR=/data
fi

CERT_DIR="${PLUGGIE_DIR}/letsencrypt/live/${PLUGGIE_HOSTNAME}"
NGINX_CONF="/etc/nginx/http.d/default.conf"
PLUGGIE_CONF="/etc/nginx/http.d/pluggie.conf"
WEBSOCKETMAPS_CONF="/etc/nginx/http.d/websocket-map.conf"

cat <<EOF > ${WEBSOCKETMAPS_CONF}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}
EOF

cat <<EOF > ${NGINX_CONF}
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

# admin interface
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

PROXIED_HOST=$(bashio::config 'proxied_host' 'http://localhost:8080')
if [ -z "$PROXIED_HOST" ]; then
    if [ "$PLATFORM" = "ha-pluggie" ]; then
        bashio::log.debug "Home Assistant Pluggie detected, using default proxied_host"
        PROXIED_HOST="http://homeassistant.local.hass.io:8123"
    else
        bashio::log.debug "Empty proxied_host, skipping HTTPS configuration"

        if [ -f "${PLUGGIE_CONF}" ]; then
            rm -f "${PLUGGIE_CONF}"
            bashio::log.debug "Removed existing ${PLUGGIE_CONF}"
        fi
    fi
fi

# No basic_auth allowed if proxied_host = HA URL
IS_HOMEASSISTANT=0
if [[ "${PROXIED_HOST}" == *"homeassistant"* || "${PROXIED_HOST}" == *"hass"* ]]; then
    IS_HOMEASSISTANT=1
    bashio::log.debug "Home Assistant URL detected: ${PROXIED_HOST}"

    if bashio::config.has_value "basic_auth_username" && bashio::config.has_value "basic_auth_password"; then
        bashio::log.warning "Basic authentication cannot be used with Home Assistant URLs. Your basic_auth settings will be ignored."
    fi
fi

PROXIED_PROTOCOL=$(echo "${PROXIED_HOST}" | sed -E 's#^(https?)://.*$#\1#')
PROXIED_HOSTNAME=$(echo "${PROXIED_HOST}" | sed -E 's#^https?://([^:/]+).*$#\1#')

if [ -f "${CERT_DIR}/fullchain.pem" ] && [ -f "${CERT_DIR}/privkey.pem" ]; then
    cat <<EOF > ${PLUGGIE_CONF}
server {
    listen                        ${PLUGGIE_HTTPS_PORT} ssl;
    server_name                   ${DOMAIN};
    ssl_certificate               ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key           ${CERT_DIR}/privkey.pem;

    access_log off;
    error_log /dev/null;

    # Basic location block
    location / {
EOF

    if [ ${IS_HOMEASSISTANT} -eq 0 ] && bashio::config.has_value "basic_auth_username" && bashio::config.has_value "basic_auth_password"; then
        mkdir -p /etc/nginx/auth

        echo "$(bashio::config 'basic_auth_username'):$(openssl passwd -apr1 "$(bashio::config 'basic_auth_password')")" > /etc/nginx/auth/.htpasswd
        chown -R nginx:nginx /etc/nginx/auth
        chmod 600 /etc/nginx/auth/.htpasswd

        cat <<EOF >> ${PLUGGIE_CONF}
        # Basic authentication
        auth_basic "Restricted Access";
        auth_basic_user_file /etc/nginx/auth/.htpasswd;

EOF
    fi

    cat <<EOF >> ${PLUGGIE_CONF}
        proxy_pass                ${PROXIED_HOST};
        proxy_redirect            ${PROXIED_PROTOCOL}://${PROXIED_HOSTNAME}/ \$scheme://\$server_name/;
        proxy_http_version        1.1;
        proxy_set_header          Host ${PROXIED_HOSTNAME};
        proxy_set_header          X-Real-IP \$remote_addr;
        proxy_set_header          X-Forwarded-Host ${PROXIED_HOSTNAME};
        proxy_set_header          X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header          X-Forwarded-Proto \$scheme;
        proxy_set_header          Upgrade \$http_upgrade;
        proxy_set_header          Connection \$connection_upgrade;
        proxy_set_header          Accept-Encoding "";
        proxy_read_timeout        3600s;
        proxy_send_timeout        3600s;
EOF

    if [ ${IS_HOMEASSISTANT} -eq 1 ]; then
        bashio::log.debug "Preserving Authorization header for Home Assistant URL"
    else
        cat <<EOF >> ${PLUGGIE_CONF}
        proxy_set_header          Authorization "";
EOF
    fi

    cat <<EOF >> ${PLUGGIE_CONF}
        proxy_buffering           off;
        proxy_request_buffering   off;

        # SSL
        proxy_ssl_server_name     on;
    }
}
EOF

    bashio::log.debug "HTTPS configuration created successfully"
else
    bashio::log.warning "SSL certificates not found. Skipping HTTPS configuration"
fi

bashio::log.debug "NGINX configuration updated successfully"
