#!/usr/bin/env bash
# shellcheck disable=SC2034
# Minimal implementation of Bashio exit functions for docker-pluggie

# Exit with error message
bashio::exit.nok() {
    local message=${1:-"An error occurred"}

    bashio::log.error "${message}"
    exit 1
}