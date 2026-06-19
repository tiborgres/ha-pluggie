#!/usr/local/bin/python

import os
import sys
import argparse
import requests
import socket
import logging
import json

from wireguard_tools import WireguardKey
from logger import setup_logging, get_logger


def load_options():
    """Load configuration from pluggie.json file"""
    try:
        with open('/data/pluggie.json', 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        logging.error("Error: pluggie.json file not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        logging.error(f"Error parsing pluggie.json: {e}")
        sys.exit(1)


def save_options(options, updated_fields):
    try:
        current_options = {}
        with open('/data/pluggie.json', 'r') as f:
            current_options = json.load(f)

        def update_dict_recursively(target, source):
            for key, value in source.items():
                if key in target and isinstance(target[key], dict) and isinstance(value, dict):
                    update_dict_recursively(target[key], value)
                else:
                    target[key] = value

        update_dict_recursively(current_options, updated_fields)

        with open('/data/pluggie.json', 'w') as f:
            json.dump(current_options, f, indent=2, sort_keys=False)

        return current_options
    except Exception as e:
        logging.error(f"Error saving pluggie.json: {e}")
        sys.exit(1)


def resolve_hostname(hostname):
    try:
        return socket.gethostbyname(hostname)
    except socket.error as err:
        logging.debug(f"Error resolving hostname {hostname}: {err}")
        return None


def load_or_generate_keypair(pluggie_dir):
    """Load existing keypair from persistent storage or generate new one."""
    key_file = f"{pluggie_dir}/wireguard/client_key"

    if os.path.exists(key_file):
        try:
            with open(key_file, 'r') as f:
                stored_key = f.read().strip()
            p_key = WireguardKey(stored_key)
            logging.debug("Loaded existing keypair from persistent storage.")
            return str(p_key), str(p_key.public_key())
        except Exception as e:
            logging.warning(f"Failed to load stored keypair: {e}. Generating new one.")

    p_key = WireguardKey.generate()
    private_key, public_key = str(p_key), str(p_key.public_key())

    os.makedirs(f"{pluggie_dir}/wireguard", exist_ok=True)
    with open(key_file, 'w') as f:
        f.write(private_key)
    os.chmod(key_file, 0o600)

    logging.debug("Generated and saved new keypair.")
    return private_key, public_key


DEFAULT_APISERVER = "api.pluggie.net"


def write_state(state):
    with open("/etc/pluggie.state", "w") as f:
        f.write(state)


def try_apiserver(api_server, access_key, public_key, user_agent,
                  interface1, timeout=10):
    api_url = f"https://{api_server}/api/settings"
    headers = {
        "Authorization": f"Bearer {access_key}",
        "User-Agent": user_agent,
    }
    payload = {"access_key": access_key, "public_key": public_key}

    try:
        ping_url = f"https://{api_server}/api/ping"
        ping_response = requests.head(ping_url, headers=headers, timeout=5)
        connectivity_ok = ping_response.status_code < 500
    except requests.exceptions.RequestException:
        connectivity_ok = False
        logging.warning(
            f"Cannot reach API server {api_server} - connectivity issue."
        )

    try:
        response = requests.post(api_url, headers=headers, json=payload,
                                 timeout=timeout)

        if response.status_code == 200:
            logging.debug(f"Public Key upload to {api_server} succeeded")
        elif response.status_code == 400:
            logging.error(f"Invalid data from {api_server}, status 400")
            return "connectivity", None
        elif response.status_code == 401:
            logging.warning(
                f"Access key rejected by {api_server} (401)"
            )
            return "invalid_key", None
        elif response.status_code == 403:
            logging.fatal(
                f"Access denied by {api_server}: tunnel is disabled."
            )
            write_state("disabled")
            return "disabled", None
        elif response.status_code == 503:
            logging.warning(
                f"Temporary server issue at {api_server}. "
                "Using existing configuration."
            )
            write_state("endpoint_unreachable")
        else:
            if not connectivity_ok:
                logging.warning(
                    f"API request to {api_server} failed "
                    f"(status {response.status_code}); connectivity issues."
                )
                if (interface1
                        and os.path.exists(f"/etc/wireguard/{interface1}.conf")):
                    write_state("connectivity_issue")
                else:
                    write_state("no_connection")
                return "connectivity", None
            logging.error(
                f"Error uploading Public Key to {api_server}, "
                f"status {response.status_code}"
            )
            return "connectivity", None

    except requests.exceptions.RequestException as e:
        logging.warning(f"Connection error to {api_server}: {e}")
        if (interface1
                and os.path.exists(f"/etc/wireguard/{interface1}.conf")):
            logging.info(
                "Continuing with existing WireGuard configuration "
                "due to connectivity issues."
            )
            write_state("connectivity_issue")
        else:
            logging.error(
                "No existing configuration and cannot reach API."
            )
            write_state("no_connection")
        return "connectivity", None

    try:
        response = requests.get(api_url, headers=headers, timeout=timeout)
        response.raise_for_status()
        data = response.json()
    except requests.exceptions.RequestException as e:
        logging.error(f"GET {api_url} failed: {e}")
        return "connectivity", None

    return "ok", data


def main():
    logger = setup_logging()

    parser = argparse.ArgumentParser("get_config.py")
    parser.parse_args()

    options = load_options()

    # Read access_key from pluggie.json (single source of truth) with an
    # optional env override for debug. Avoids passing it via argv where it
    # would be visible in ps / /proc/<pid>/cmdline.
    access_key = os.environ.get("PLUGGIE_ACCESS_KEY") \
        or options.get('configuration', {}).get('access_key')

    if not access_key or access_key == "XXXXX":
        logging.fatal("No valid access_key configured in pluggie.json")
        write_state("invalid_key")
        sys.exit(1)

    configured_apiserver = options.get('pluggie_config', {}).get(
        'apiserver', DEFAULT_APISERVER
    )
    user_agent = options.get('user_agent', 'Pluggie-Client-Docker/Default')
    interface1 = options.get('pluggie_config', {}).get('interface1')

    logging.debug(f"configured apiserver: {configured_apiserver}")

    if not configured_apiserver:
        logging.error("Error: apiserver not set in pluggie.json. Please Rebuild Pluggie Add-on.")
        sys.exit(1)

    if os.environ.get("SUPERVISOR_TOKEN"):
        pluggie_dir = "/ssl/pluggie"
    else:
        pluggie_dir = "/data"

    private_key, public_key = load_or_generate_keypair(pluggie_dir)

    outcome, data = try_apiserver(
        configured_apiserver, access_key, public_key,
        user_agent, interface1,
    )
    api_server = configured_apiserver

    if outcome == "invalid_key" and configured_apiserver != DEFAULT_APISERVER:
        logging.info(
            f"Retrying against default apiserver {DEFAULT_APISERVER} "
            f"after 401 from {configured_apiserver}"
        )
        retry_outcome, retry_data = try_apiserver(
            DEFAULT_APISERVER, access_key, public_key,
            user_agent, interface1,
        )
        if retry_outcome == "ok":
            outcome, data = retry_outcome, retry_data
            api_server = DEFAULT_APISERVER
        elif retry_outcome != "invalid_key":
            logging.warning(
                f"Fallback to {DEFAULT_APISERVER} unreachable "
                f"({retry_outcome}); keeping invalid_key verdict from "
                f"{configured_apiserver}"
            )

    if outcome == "invalid_key":
        logging.fatal("Invalid Access Key. Please check your access key in Pluggie Configuration.")
        write_state("invalid_key")
        return 0

    if outcome in ("disabled", "connectivity"):
        sys.exit(1)

    if outcome != "ok" or data is None:
        logging.error("Unexpected outcome from apiserver communication")
        sys.exit(1)

    if data.get("status") != "success":
        logging.error(
            f"Error connecting API server {api_server}: {data.get('message')}"
        )
        sys.exit(2)

    config = data["client_tunnel_settings"]
    write_state("enabled")

    if config.get("apiserver") and config["apiserver"] != api_server:
        logging.info(
            f"API server changed from {api_server} to {config['apiserver']}"
        )
        api_server = config["apiserver"]

    logging.debug("Tunnel configuration:")
    for setting, value in config.items():
        if setting in ["access_key", "preshared_key"]:
            masked_value = value[:3] + "***" if value else "***"
            logging.debug(f"{setting}: {masked_value}")
        else:
            logging.debug(f"{setting}: {value}")

    # endpoint1 settings
    endpoint1_short, _ = config["endpoint1"].split(":")
    endpoint1_ip = resolve_hostname(endpoint1_short)

    tunnel_updates = {
        'user_agent': user_agent,
        'pluggie_config': {
            'interface1': config["interface1"],
            'apiserver': config["apiserver"],
            'hostname': config["hostname"],
            'email': config["email"],
            'keyfile': config["keyfile"],
            'certfile': config["certfile"],
            'http_port': config["http_port"],
            'https_port': config["https_port"],
            'dns': config["dns"],
            'endpoint1_short': endpoint1_short,
            'endpoint1_ip': endpoint1_ip,
            'endpoint1_ip_int': config["allowed_ips1"].split(",")[0].split("/")[0]
        }
    }

    options = save_options(options, tunnel_updates)

    if os.environ.get("SUPERVISOR_TOKEN"):
        PLUGGIE_DIR = "/ssl/pluggie"
    else:
        PLUGGIE_DIR = "/data"

    ssl_dir = f"{PLUGGIE_DIR}/wireguard"
    os.makedirs(ssl_dir, exist_ok=True)

    config1 = f"/etc/wireguard/{config['interface1']}.conf"
    with open(config1, "w") as f:
        wg_config = [
            "[Interface]",
            f"PrivateKey = {private_key}",
            f"Address = {config['address1']}/24",
            f"MTU = {config['mtu']}",
            "",
            "[Peer]",
            f"PublicKey = {config['peer_public_key']}",
            f"PreSharedKey = {config['preshared_key']}",
            f"Endpoint = {config['endpoint1']}",
            f"AllowedIPs = {config['allowed_ips1']}",
            f"PersistentKeepalive = {config['keep_alive']}"
        ]
        f.write('\n'.join(wg_config))

    logging.debug("Configuration files updated successfully.")


if __name__ == "__main__":
    main()
