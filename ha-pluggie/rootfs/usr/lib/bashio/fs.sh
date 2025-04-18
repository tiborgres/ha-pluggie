#!/usr/bin/env bash
# shellcheck disable=SC2034
# Minimal implementation of Bashio filesystem functions for docker-pluggie

# Check if directory exists
bashio::fs.directory_exists() {
    local directory=${1}

    if [[ -d "${directory}" ]]; then
        return 0
    fi
    return 1
}

# Check if file exists
bashio::fs.file_exists() {
    local file=${1}

    if [[ -f "${file}" ]]; then
        return 0
    fi
    return 1
}