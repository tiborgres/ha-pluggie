#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2155
# Minimal implementation of Bashio for docker-pluggie

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

# Bashio version number
readonly BASHIO_VERSION="0.1.0"

# Stores the location of this library
readonly __BASHIO_LIB_DIR=$(dirname "${BASH_SOURCE[0]}")

# Load const.sh
source "${__BASHIO_LIB_DIR}/const.sh"

# Defaults
declare __BASHIO_SUPERVISOR_API=${SUPERVISOR_API:-${__BASHIO_DEFAULT_SUPERVISOR_API}}
declare __BASHIO_SUPERVISOR_TOKEN=${SUPERVISOR_TOKEN:-${__BASHIO_DEFAULT_SUPERVISOR_TOKEN}}
declare __BASHIO_LOG_LEVEL=${LOG_LEVEL:-${__BASHIO_DEFAULT_LOG_LEVEL}}
declare __BASHIO_LOG_FORMAT=${LOG_FORMAT:-${__BASHIO_DEFAULT_LOG_FORMAT}}
declare __BASHIO_LOG_TIMESTAMP=${LOG_TIMESTAMP:-${__BASHIO_DEFAULT_LOG_TIMESTAMP}}
declare __BASHIO_CACHE_DIR=${CACHE_DIR:-${__BASHIO_DEFAULT_CACHE_DIR}}

# Load required modules
source "${__BASHIO_LIB_DIR}/log.sh"
source "${__BASHIO_LIB_DIR}/fs.sh"
source "${__BASHIO_LIB_DIR}/config.sh"
source "${__BASHIO_LIB_DIR}/exit.sh"
source "${__BASHIO_LIB_DIR}/string.sh"
source "${__BASHIO_LIB_DIR}/var.sh"
source "${__BASHIO_LIB_DIR}/addons.sh"