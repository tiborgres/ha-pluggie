#!/usr/bin/with-contenv bashio

log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

# export for python scripts
export LOG_LEVEL=${log_level}

bashio::log.info "Starting Pluggie.."
