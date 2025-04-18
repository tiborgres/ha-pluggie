#!/usr/bin/env bash
# shellcheck disable=SC2034
# Minimal implementation of Bashio configuration for docker-pluggie

# Configuration directory
declare __BASHIO_CONFIG_CACHE_DIR="${__BASHIO_CACHE_DIR}/config"

# Configuration JSON data
declare __BASHIO_CONFIG_DATA=""

# Load configuration data from config.yaml or pluggie.json
bashio::_config_load() {
    if [[ -z "${__BASHIO_CONFIG_DATA:-}" ]]; then
        mkdir -p "${__BASHIO_CONFIG_CACHE_DIR}"

        # Default empty config
        __BASHIO_CONFIG_DATA="{}"

        # Determine which config file to use based on environment
        local config_file=""
        if [[ -n "${SUPERVISOR_TOKEN:-}" ]]; then
            # Home Assistant environment
            config_file="/ssl/pluggie/pluggie.json"
        else
            # Pure Docker environment
            config_file="/data/pluggie.json"
        fi

        # Read from the determined config file
        if [[ -f "${config_file}" ]]; then
            __BASHIO_CONFIG_DATA=$(<"${config_file}")
            return
        fi

        # Write our final configuration to debug log
    fi
}

# Get config value function
bashio::config() {
    local key=${1}
    local default=${2:-}
    local value=""

    bashio::_config_load

    # Handle nested keys (like configuration.access_key)
    if [[ "${key}" == *"."* ]]; then
        local parts=(${key//./ })
        local query=".${parts[0]}"

        for ((i=1; i<${#parts[@]}; i++)); do
            query="${query}.${parts[i]}"
        done

        value=$(echo "${__BASHIO_CONFIG_DATA}" | jq -r "${query} // empty" 2>/dev/null)
    else
        value=$(echo "${__BASHIO_CONFIG_DATA}" | jq -r ".${key} // empty" 2>/dev/null)
    fi

    if [[ -z "${value}" || "${value}" == "null" ]]; then
        echo "${default}"
    else
        echo "${value}"
    fi
}

# Check if config has value
bashio::config.has_value() {
    local key=${1}
    local value=""

    value=$(bashio::config "${key}")

    if [[ -z "${value}" || "${value}" == "null" ]]; then
        # Special case for access_key
        if [[ "${key}" == "configuration.access_key" ]] && [[ -n "${PLUGGIE_ACCESS_KEY:-}" ]]; then
            return 0
        fi
        return 1
    fi
    return 0
}

# Check if config exists
bashio::config.exists() {
    bashio::config.has_value "${1}"
}