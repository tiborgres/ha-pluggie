#!/usr/bin/env bash
# shellcheck disable=SC2034
# Minimal implementation of Bashio variable functions for docker-pluggie

# Check if variable is empty
bashio::var.is_empty() {
    local var=${1}

    [[ -z "${var}" ]]
}

# Check if variable is a number
bashio::var.is_number() {
    local var=${1}

    [[ "${var}" =~ ^[0-9]+$ ]]
}