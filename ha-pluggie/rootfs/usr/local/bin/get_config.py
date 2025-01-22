#!/usr/local/bin/python

import os
import sys
import argparse
import requests
import socket
import logging

from wireguard_tools import WireguardKey

def setup_logging():
    """Setup logging to work with bashio"""
    bashio_to_python = {
        'all': logging.DEBUG,
        'trace': logging.DEBUG,
        'debug': logging.DEBUG,
        'info': logging.INFO,
        'notice': logging.INFO,
        'warning': logging.WARNING,
        'error': logging.ERROR,
        'fatal': logging.CRITICAL,
        'off': logging.CRITICAL + 10
    }

    # Get log level from environment
    bashio_log_level = os.environ.get('LOG_LEVEL', 'info').lower()
    python_log_level = bashio_to_python.get(bashio_log_level, logging.INFO)

    # Remove any existing handlers
    root = logging.getLogger()
    for handler in root.handlers[:]:
        root.removeHandler(handler)

    # Configure logging with exact bashio format
    logging.basicConfig(
        format='[%(asctime)s] %(levelname)s: %(message)s',
        datefmt='%H:%M:%S',
        level=python_log_level,
        force=True
    )

def load_config_from_file(file_path):
    config = {}
    try:
        with open(file_path, 'r') as conf_file:
            for line in conf_file:
                if line.startswith('export '):
                    key, value = line.strip().split('=', 1)
                    config[key.replace('export ', '').strip()] = value.strip().strip('"')
    except FileNotFoundError:
        logging.debug(f"Error: {file_path} file not found")
        sys.exit(1)
    return config

def resolve_hostname(hostname):
    try:
        return socket.gethostbyname(hostname)
    except socket.error as err:
        logging.debug(f"Error resolving hostname {hostname}: {err}")
        return None

def main():
    setup_logging()
    parser = argparse.ArgumentParser("get_config.py")
    parser.add_argument("access_key", help="Access Key from tunnel profile", type=str)
    args = parser.parse_args()

    config_file = "/etc/pluggie.conf"
    config = load_config_from_file(config_file)
    api_server = config.get('PLUGGIE_APISERVER')
    user_agent = config.get('PLUGGIE_USERAGENT', 'Pluggie-Client-HA/Default')

    logging.debug(f"api_server: {api_server}")

    if not api_server:
        logging.error(f"Error: PLUGGIE_APISERVER not set in {config_file}. Please Rebuild Pluggie Add-on.")
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
        response = requests.post(api_url, headers=headers, json=data, timeout=timeout)

        if response.status_code == 200:
            logging.debug("Public Key upload succeeded")
        elif response.status_code == 400:
            logging.error(f"Invalid data, Error: {response.status_code}")
        elif response.status_code == 401:
            logging.fatal(f"Invalid Access Key. Please check your access key in Pluggie Add-on Configuration.")
            with open("/etc/pluggie.state", "w") as f:
                f.write("invalid_key")
            sys.exit(1)
        elif response.status_code == 403:
            logging.fatal(f"Access denied: Your tunnel is currently disabled. Please contact support or check your subscription status.")
            with open("/etc/pluggie.state", "w") as f:
                f.write("disabled")
            return
        else:
            logging.error(f"Error uploading Public Key to API server, Error: {response.status_code}")
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
                with open(config_file, "w") as f:
                    f.write(f'export PLUGGIE_USERAGENT="{user_agent}"\n')
                    f.write(f'export PLUGGIE_APISERVER="{config["apiserver"]}"\n')
                    f.write(f'export PLUGGIE_DNS="{config.get("dns", "1.1.1.1")}"\n')

                # Get configuration from new API server
                config = load_config_from_file(config_file)
                api_server = config.get('PLUGGIE_APISERVER')
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

            with open(config_file, "w") as f:
                config_lines = [
                    f'PLUGGIE_USERAGENT="{user_agent}"',
                    f'PLUGGIE_INTERFACE1="{config["interface1"]}"',
                    f'PLUGGIE_APISERVER="{config["apiserver"]}"',
                    f'PLUGGIE_HOSTNAME="{config["hostname"]}"',
                    f'PLUGGIE_EMAIL="{config["email"]}"',
                    f'PLUGGIE_KEYFILE="{config["keyfile"]}"',
                    f'PLUGGIE_CERTFILE="{config["certfile"]}"',
                    f'PLUGGIE_HTTP_PORT="{config["http_port"]}"',
                    f'PLUGGIE_HTTPS_PORT="{config["https_port"]}"',
                    f'PLUGGIE_DNS="{config["dns"]}"',
                    f'PLUGGIE_ENDPOINT1_SHORT="{endpoint1_short}"',
                    f'PLUGGIE_ENDPOINT1_IP="{endpoint1_ip}"',
                    f'PLUGGIE_ENDPOINT1_IP_INT="{config["allowed_ips1"].split(",")[0].split("/")[0]}"'
                ]
                f.write('\n'.join(f"export {line}" for line in config_lines))

            ssl_dir = "/ssl/pluggie/wireguard"
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
        logging.error(f"Error communicating with API server {api_server}. Keeping original {config_file}")
        sys.exit(1)

if __name__ == "__main__":
    main()
