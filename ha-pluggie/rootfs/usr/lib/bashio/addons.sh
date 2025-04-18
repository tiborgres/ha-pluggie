#!/usr/bin/env bash
# shellcheck disable=SC2034
# Minimal implementation of Bashio add-on functions for docker-pluggie

# Get add-on info from API
bashio::_addon.api() {
    local endpoint=${1:-}
    local response=""
    local cache_file="${__BASHIO_CACHE_DIR}/addons"

    # Try to get from supervisor API first
    if [[ -n "${__BASHIO_SUPERVISOR_TOKEN}" ]]; then
        if response=$(curl -sSL -H "Authorization: Bearer ${__BASHIO_SUPERVISOR_TOKEN}" \
            "${__BASHIO_SUPERVISOR_API}/addons/self/info" 2>/dev/null); then
            mkdir -p "${__BASHIO_CACHE_DIR}"
            echo "${response}" > "${cache_file}"
            echo "${response}"
            return 0
        fi
    fi

    # If we can't get it from API, check config file
    if [[ -f "/data/pluggie.json" ]]; then
        response="{\"version\":\"$(grep "version" /data/pluggie.json | sed 's/.*: "\(.*\)".*/\1/' 2>/dev/null)\"}"
        echo "${response}"
        return 0
    fi

    # Last fallback - use a default version
    echo "{\"version\":\"Default\"}"
    return 0
}

# Get add-on version
bashio::addon.version() {
    local response
    response=$(bashio::_addon.api)

    echo "$(echo "${response}" | jq -r '.version // "Default"')"
}