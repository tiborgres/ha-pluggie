#!/usr/bin/with-contenv bashio

log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

bashio::log.debug "Applying new configuration."

if [ -f "/tmp/restart_reason" ]; then
    bashio::log.debug "Container scripts are restarting, skipping apply_config.sh"
    exit 0
fi

# Reload wireguard if needed
if wg show &>/dev/null; then
    bashio::log.debug "Check if we need wireguard restart"
    /usr/local/bin/check_and_restart_wg.sh
fi

# Update nginx configuration
/usr/local/bin/update_nginx_config.sh

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

bashio::log.debug "Configuration applied successfully"

# Reload admin_api.py
admin_pid=$(pgrep -f "/usr/local/bin/admin_api.py")
if [ -n "$admin_pid" ]; then
    bashio::log.debug "Sending SIGUSR1 to admin_api.py (PID: $admin_pid)"
    kill -SIGUSR1 $admin_pid
else
    bashio::log.warning "admin_api.py process not found, cannot send reload signal"
fi
