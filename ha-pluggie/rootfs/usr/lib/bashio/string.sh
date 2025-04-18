#!/usr/bin/env bash
# shellcheck disable=SC2034
# Minimal implementation of Bashio string functions for docker-pluggie

# Lowercase string
bashio::string.lower() {
    local data=${1}

    echo "${data,,}"
}

# Uppercase string
bashio::string.upper() {
    local data=${1}

    echo "${data^^}"
}