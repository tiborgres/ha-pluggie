#!/usr/bin/env bash
# shellcheck disable=SC2034
# Minimal implementation of Bashio logging for docker-pluggie

# Source constants if not already loaded
if [ -z "${__BASHIO_COLORS_RESET:-}" ] && [ -f "/usr/lib/bashio/const.sh" ]; then
    # shellcheck disable=SC1091
    source /usr/lib/bashio/const.sh
fi

# Mapping for log levels to numbers
declare -A __BASHIO_LOG_LEVELS=(
    [ALL]=${__BASHIO_LOG_LEVEL_ALL}
    [TRACE]=${__BASHIO_LOG_LEVEL_TRACE}
    [DEBUG]=${__BASHIO_LOG_LEVEL_DEBUG}
    [INFO]=${__BASHIO_LOG_LEVEL_INFO}
    [NOTICE]=${__BASHIO_LOG_LEVEL_NOTICE}
    [WARNING]=${__BASHIO_LOG_LEVEL_WARNING}
    [ERROR]=${__BASHIO_LOG_LEVEL_ERROR}
    [FATAL]=${__BASHIO_LOG_LEVEL_FATAL}
    [CRITICAL]=${__BASHIO_LOG_LEVEL_CRITICAL}
    [OFF]=${__BASHIO_LOG_LEVEL_OFF}
)

# Set log level from environment variable
bashio::log.level() {
    local level=${1:-}
    level="${level^^}"

    # Check if numeric
    if [[ "${level}" =~ ^[0-9]+$ ]]; then
        if [[ "${level}" -lt "${__BASHIO_LOG_LEVEL_OFF}" || "${level}" -gt "${__BASHIO_LOG_LEVEL_ALL}" ]]; then
            bashio::log.warning "Invalid log level number: ${level}"
            return
        fi
        __BASHIO_LOG_LEVEL="${level}"
        return
    fi

    # Check if valid level name
    if [[ -n "${level}" && -n "${__BASHIO_LOG_LEVELS[${level}]:-}" ]]; then
        __BASHIO_LOG_LEVEL="${__BASHIO_LOG_LEVELS[${level}]}"
        return
    fi

    bashio::log.warning "Unknown log level: ${level}"
}

# Internal log function - simplified version without adding colors
bashio::_log() {
    local level=${1}
    local message=${2}
    local timestamp

    if [[ "${__BASHIO_LOG_LEVEL}" -ge "${level}" ]]; then
        timestamp=$(date +"${__BASHIO_LOG_TIMESTAMP}")
        message=$(printf "${__BASHIO_LOG_FORMAT}" "${message}")

        # Determine log level name
        local log_level=""
        if [[ "${level}" -eq "${__BASHIO_LOG_LEVEL_DEBUG}" ]]; then
            log_level="DEBUG"
        elif [[ "${level}" -eq "${__BASHIO_LOG_LEVEL_INFO}" ]]; then
            log_level="INFO"
        elif [[ "${level}" -eq "${__BASHIO_LOG_LEVEL_NOTICE}" ]]; then
            log_level="NOTICE"
        elif [[ "${level}" -eq "${__BASHIO_LOG_LEVEL_WARNING}" ]]; then
            log_level="WARNING"
        elif [[ "${level}" -eq "${__BASHIO_LOG_LEVEL_ERROR}" ]]; then
            log_level="ERROR"
        elif [[ "${level}" -eq "${__BASHIO_LOG_LEVEL_FATAL}" ]]; then
            log_level="FATAL"
        elif [[ "${level}" -eq "${__BASHIO_LOG_LEVEL_CRITICAL}" ]]; then
            log_level="CRITICAL"
        else
            log_level="UNKNOWN"
        fi

        echo -e "[${timestamp}] ${log_level}: ${message}" >&2
    fi
}

# Log functions for each level with colors
bashio::log.trace() { bashio::_log "${__BASHIO_LOG_LEVEL_TRACE}" "${*}"; }
bashio::log.debug() { bashio::_log "${__BASHIO_LOG_LEVEL_DEBUG}" "${__BASHIO_COLORS_BLUE}${*}${__BASHIO_COLORS_RESET}"; }
bashio::log.info() { bashio::_log "${__BASHIO_LOG_LEVEL_INFO}" "${__BASHIO_COLORS_GREEN}${*}${__BASHIO_COLORS_RESET}"; }
bashio::log.notice() { bashio::_log "${__BASHIO_LOG_LEVEL_NOTICE}" "${__BASHIO_COLORS_CYAN}${*}${__BASHIO_COLORS_RESET}"; }
bashio::log.warning() { bashio::_log "${__BASHIO_LOG_LEVEL_WARNING}" "${__BASHIO_COLORS_YELLOW}${*}${__BASHIO_COLORS_RESET}"; }
bashio::log.error() { bashio::_log "${__BASHIO_LOG_LEVEL_ERROR}" "${__BASHIO_COLORS_RED}${*}${__BASHIO_COLORS_RESET}"; }
bashio::log.fatal() { bashio::_log "${__BASHIO_LOG_LEVEL_FATAL}" "${__BASHIO_COLORS_RED}${*}${__BASHIO_COLORS_RESET}"; }
bashio::log.critical() { bashio::_log "${__BASHIO_LOG_LEVEL_CRITICAL}" "${__BASHIO_COLORS_RED}${*}${__BASHIO_COLORS_RESET}"; }
