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


def main():
    logger = setup_logging()

    parser = argparse.ArgumentParser("get_config.py")
    parser.add_argument("access_key", help="Access Key from tunnel profile", type=str)
    args = parser.parse_args()

    # Načítame pluggie.json
    options = load_options()

    api_server = options.get('pluggie_config', {}).get('apiserver', 'api.pluggie.net')
    user_agent = options.get('user_agent', 'Pluggie-Client-Docker/Default')

    logging.debug(f"api_server: {api_server}")

    if not api_server:
        logging.error(f"Error: apiserver not set in pluggie.json. Please Rebuild Pluggie Add-on.")
        sys.exit(1)

    p_key = WireguardKey.generate()
    private_key, public_key = str(p_key), str(p_key.public_key())

    try:
        timeout = 10
        api_url = f"https://{api_server}/api/settings"
        headers = {
            "Authorization": f"Bearer {args.access_key}",
            "User-Agent": user_agent
        }
        data = {"access_key": args.access_key, "public_key": public_key}

        try:
            health_check = requests.head(f"https://{api_server}/health", timeout=5)
            connectivity_ok = health_check.status_code == 200
        except requests.exceptions.RequestException:
            connectivity_ok = False
            logging.warning(f"Cannot reach API server {api_server} - connectivity issue.")

        try:
            response = requests.post(api_url, headers=headers, json=data, timeout=timeout)

            if response.status_code == 200:
                logging.debug("Public Key upload succeeded")
            elif response.status_code == 400:
                logging.error(f"Invalid data, Error: {response.status_code}")
            elif response.status_code == 401:
                logging.fatal(f"Invalid Access Key. Please check your access key in Pluggie Configuration.")
                with open("/etc/pluggie.state", "w") as f:
                    f.write("invalid_key")
                return 0
            elif response.status_code == 403:
                logging.fatal(f"Access denied: Your tunnel is currently disabled. Please contact support or check your subscription status.")
                with open("/etc/pluggie.state", "w") as f:
                    f.write("disabled")
                return
            else:
                # Check connectivity issues
                if not connectivity_ok:
                    logging.warning(f"API request failed (status code {response.status_code}), but connectivity issues detected. Continuing with existing configuration.")
                    # Check for existing WireGuard interface in configuration
                    interface1 = options.get('pluggie_config', {}).get('interface1')
                    if interface1 and os.path.exists(f"/etc/wireguard/{interface1}.conf"):
                        # Set connectivity_issue state
                        with open("/etc/pluggie.state", "w") as f:
                            f.write("connectivity_issue")
                        return 0
                logging.error(f"Error uploading Public Key to API server, Error: {response.status_code}")
                sys.exit(1)

        except requests.exceptions.RequestException as e:
            # Catch connection errors
            logging.warning(f"Connection error to API server: {e}")
            # Check existing configuration
            interface1 = options.get('pluggie_config', {}).get('interface1')
            if interface1 and os.path.exists(f"/etc/wireguard/{interface1}.conf"):
                logging.info("Continuing with existing WireGuard configuration due to connectivity issues.")
                # Set connectivity_issue state
                with open("/etc/pluggie.state", "w") as f:
                    f.write("connectivity_issue")
                return 0
            else:
                logging.error("No existing configuration found and cannot connect to API. Exiting.")
                sys.exit(1)

        response = requests.get(api_url, headers=headers, timeout=timeout)
        response.raise_for_status()
        data = response.json()

        if data["status"] == "success":
            config = data["client_tunnel_settings"]
            with open("/etc/pluggie.state", "w") as f:
                f.write("enabled")

            # Update configuration if API changed
            if config["apiserver"] != api_server:
                logging.debug(f"API server changed from {api_server} to {config['apiserver']}")

                update_fields = {
                    'user_agent': user_agent,
                    'pluggie_config': {
                        'apiserver': config["apiserver"],
                        'dns': config.get("dns", "1.1.1.1")
                    }
                }

                options = save_options(options, update_fields)

                # Get configuration from new API server
                api_server = options.get('pluggie_config', {}).get('apiserver')
                api_url = f"https://{api_server}/api/settings"
                response = requests.get(api_url, headers=headers, timeout=timeout)
                response.raise_for_status()
                data = response.json()
                if data["status"] == "success":
                    config = data["client_tunnel_settings"]
                else:
                    logging.error(f"Error getting configuration from new API server: {data.get('message')}")
                    sys.exit(1)

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
        else:
            logging.error(f"Error connecting API server {api_server}: {data['message']}")
            sys.exit(2)

    except requests.exceptions.RequestException as e:
        logging.error(f"Error communicating with API server {api_server}. Keeping original configuration.")
        sys.exit(1)

if __name__ == "__main__":
    main()
