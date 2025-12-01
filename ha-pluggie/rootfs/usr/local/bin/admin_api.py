#!/usr/local/bin/python

import os
import json
import logging
import sys
import threading
import time
import signal
import requests
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse
from logger import setup_logging, reload_options_log_level

OPTIONS_FILE = "/data/pluggie.json"


def validate_url(url):
    """
    Validate if the provided string is a valid URL with http or https scheme.

    Args:
        url (str): URL to validate

    Returns:
        tuple: (is_valid, error_message)
    """

    if not url or url.strip() == "":
        return True, None  # Empty URL is allowed

    url = url.strip()

    # Use urllib.parse for validation
    try:
        result = urllib.parse.urlparse(url)

        # Check scheme
        if result.scheme not in ["http", "https"]:
            return False, "URL must start with http:// or https://"

        # Check netloc (host)
        if not result.netloc:
            return False, "URL must contain a valid hostname"

        # Check for invalid port format (colon with no digits after)
        if ':' in result.netloc and not result.netloc.split(':')[1].isdigit():
            return False, "Invalid URL format: hostname followed by colon must include a port number"

        # Check for double protocol
        if '//' in result.netloc or '://' in result.path:
            return False, "URL contains multiple protocol prefixes (http:// or https://)"

        return True, None

    except Exception as e:
        return False, f"Invalid URL: {str(e)}"


# Signal handler for reloading config
def signal_handler(sig, frame):
    logging.info("Received signal to reload config")
    reload_options_log_level(OPTIONS_FILE)


# Setup logging
logger = setup_logging()
reload_options_log_level(OPTIONS_FILE)

# Register signal handler
signal.signal(signal.SIGUSR1, signal_handler)


class AdminAPIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        current_level = logging.getLogger().getEffectiveLevel()

        if current_level <= logging.DEBUG:
            sys.stderr.write("%s - - [%s] %s\n" %
                             (self.address_string(),
                              self.log_date_time_string(),
                              format % args))


    def _set_headers(self, content_type='application/json'):
        self.send_response(200)
        self.send_header('Content-type', content_type)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()


    def do_OPTIONS(self):
        self._set_headers()


    def do_GET(self):
        try:
            if self.path == '/pluggie/api/options':
                try:
                    with open(OPTIONS_FILE, 'r') as f:
                        options = json.load(f)
                    self._set_headers()
                    self.wfile.write(json.dumps(options).encode())
                except BrokenPipeError:
                    logging.warning("Broken pipe error when returning options")
                    return
                except Exception as e:
                    logging.error(f"Error reading options: {e}")
                    try:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": str(e)}).encode())
                    except BrokenPipeError:
                        logging.warning("Broken pipe error while sending error response")
                        return

            elif self.path == '/pluggie/api/edition':
                try:
                    edition = "unknown"
                    try:
                        with open(OPTIONS_FILE, 'r') as f:
                            options = json.load(f)
                            user_agent = options.get('user_agent', '')
                            if "Docker" in user_agent:
                                edition = "docker"
                            elif "HA" in user_agent:
                                edition = "ha"
                    except Exception as conf_error:
                        logging.debug(f"Error determining edition from pluggie.json: {conf_error}")

                    self._set_headers()
                    self.wfile.write(json.dumps({"edition": edition}).encode())
                except BrokenPipeError:
                    logging.warning("Broken pipe error when returning edition")
                    return
                except Exception as e:
                    logging.error(f"Error determining edition: {e}")
                    try:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": str(e)}).encode())
                    except BrokenPipeError:
                        logging.warning("Broken pipe error while sending error response")
                        return

            elif self.path == '/pluggie/api/status':
                try:
                    status = 'unknown'
                    connectivity_issue = False

                    if os.path.exists('/etc/pluggie.state'):
                        with open('/etc/pluggie.state', 'r') as f:
                            status = f.read().strip()

                        # Set flag if "connectivity_issue"
                        if status == "connectivity_issue":
                            connectivity_issue = True

                        # Check connectivity issue if "invalid_key"
                        if status == 'invalid_key':
                            access_key = None
                            with open(OPTIONS_FILE, 'r') as f:
                                options = json.load(f)
                                access_key = options.get('configuration', {}).get('access_key')

                            if access_key == "XXXXX" or not access_key:
                                connectivity_issue = False
                                status = 'invalid_key'
                            elif access_key and len(access_key) > 10:
                                connectivity_issue = False
                            else:
                                try:
                                    api_server = options.get('pluggie_config', {}).get('apiserver', 'api.pluggie.net')
                                    test_url = f"https://{api_server}/health"
                                    response = requests.head(test_url, timeout=3)

                                    if response.status_code != 200:
                                        connectivity_issue = True
                                        logging.debug(f"API connectivity check failed: Status code {response.status_code}")
                                except Exception as e:
                                    if access_key != "XXXXX" and access_key:
                                        connectivity_issue = True
                                        with open('/etc/pluggie.state', 'w') as f:
                                            f.write('connectivity_issue')
                                        status = 'connectivity_issue'
                                    logging.debug(f"API connectivity check failed: {e}")

                    self._set_headers()
                    self.wfile.write(json.dumps({
                        "status": status,
                        "connectivity_issue": connectivity_issue
                    }).encode())
                except BrokenPipeError:
                    logging.warning("Broken pipe error when returning status")
                    return
                except Exception as e:
                    logging.error(f"Error reading Pluggie status: {e}")
                    try:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": str(e)}).encode())
                    except BrokenPipeError:
                        logging.warning("Broken pipe error while sending error response")
                        return

            elif self.path == '/pluggie/api/health':
                try:
                    self._set_headers()
                    self.wfile.write(json.dumps({"status": "ok"}).encode())
                except BrokenPipeError:
                    logging.warning("Broken pipe error when returning health status")
                    return
                except Exception as e:
                    logging.error(f"Error in health check: {e}")
                    try:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": str(e)}).encode())
                    except BrokenPipeError:
                        logging.warning("Broken pipe error while sending error response")
                        return

            elif self.path == '/pluggie/api/traffic':
                try:
                    with open(OPTIONS_FILE, 'r') as f:
                        options = json.load(f)

                    access_key = options.get('configuration', {}).get('access_key')
                    if not access_key or access_key == 'XXXXX':
                        self._set_headers()
                        self.wfile.write(json.dumps({
                            "status": "error",
                            "message": "No valid access key configured"
                        }).encode())
                        return

                    api_server = options.get('pluggie_config', {}).get('apiserver', 'api.pluggie.net')
                    api_url = f"https://{api_server}/api/traffic"
                    headers = {
                        'Authorization': f'Bearer {access_key}',
                        'User-Agent': options.get('user_agent', 'Pluggie-HA-Addon')
                    }

                    response = requests.get(api_url, headers=headers, timeout=10)

                    if response.status_code == 200:
                        traffic_data = response.json()
                        self._set_headers()
                        self.wfile.write(json.dumps(traffic_data).encode())
                    else:
                        self._set_headers()
                        self.wfile.write(json.dumps({
                            "status": "error",
                            "message": "Traffic data unavailable"
                        }).encode())

                except requests.exceptions.RequestException as e:
                    logging.debug(f"API connectivity error: {e}")
                    self._set_headers()
                    self.wfile.write(json.dumps({
                        "status": "error",
                        "message": "N/A at the moment"
                    }).encode())
                except Exception as e:
                    logging.error(f"Error retrieving traffic data: {e}")
                    try:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": str(e)}).encode())
                    except BrokenPipeError:
                        logging.warning("Broken pipe error while sending error response")
                        return

            elif self.path == '/pluggie/api/proxy-check':
                try:
                    with open(OPTIONS_FILE, 'r') as f:
                        options = json.load(f)

                    proxied_host = options.get('proxied_host', '')
                    user_agent = options.get('user_agent', '')

                    # Determine platform
                    is_ha_addon = "HA" in user_agent

                    # If no proxied_host configured, use default for HA addon
                    if not proxied_host or proxied_host.strip() == '':
                        if is_ha_addon:
                            proxied_host = "http://homeassistant.local.hass.io:8123"
                        else:
                            # Docker without proxied_host - nothing to check
                            self._set_headers()
                            self.wfile.write(json.dumps({
                                "status": "ok",
                                "message": "No proxied host configured",
                                "check_performed": False
                            }).encode())
                            return

                    # Perform the check
                    try:
                        response = requests.get(
                            proxied_host,
                            timeout=5,
                            allow_redirects=False,
                            headers={
                                'X-Forwarded-For': '127.0.0.1',
                                'X-Forwarded-Proto': 'https'
                            }
                        )

                        if response.status_code == 400:
                            # 400 Bad Request - likely missing trusted_proxies
                            self._set_headers()
                            self.wfile.write(json.dumps({
                                "status": "config_required",
                                "message": "Proxied host returned 400 Bad Request. Configuration may be required.",
                                "http_status": 400,
                                "is_ha_addon": is_ha_addon,
                                "check_performed": True
                            }).encode())
                        else:
                            # Any other response means the connection works
                            self._set_headers()
                            self.wfile.write(json.dumps({
                                "status": "ok",
                                "message": "Proxied host is reachable",
                                "http_status": response.status_code,
                                "check_performed": True
                            }).encode())

                    except requests.exceptions.ConnectionError as e:
                        # Connection refused or host unreachable
                        logging.debug(f"Proxy check connection error: {e}")
                        self._set_headers()
                        self.wfile.write(json.dumps({
                            "status": "connection_error",
                            "message": "Cannot connect to proxied host",
                            "check_performed": True
                        }).encode())

                    except requests.exceptions.Timeout:
                        logging.debug("Proxy check timeout")
                        self._set_headers()
                        self.wfile.write(json.dumps({
                            "status": "timeout",
                            "message": "Connection to proxied host timed out",
                            "check_performed": True
                        }).encode())

                except BrokenPipeError:
                    logging.warning("Broken pipe error when checking proxy")
                    return
                except Exception as e:
                    logging.error(f"Error checking proxy: {e}")
                    try:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": str(e)}).encode())
                    except BrokenPipeError:
                        logging.warning("Broken pipe error while sending error response")
                        return

            else:
                try:
                    self.send_response(404)
                    self.end_headers()
                except BrokenPipeError:
                    logging.warning("Broken pipe error while sending 404 response")
                    return
        except BrokenPipeError:
            logging.warning("Broken pipe error in do_GET")
            return
        except Exception as e:
            logging.error(f"Unexpected error in do_GET: {e}")
            return


    def do_POST(self):
        try:
            if self.path == '/pluggie/api/options':
                try:
                    content_length = int(self.headers['Content-Length'])
                    post_data = self.rfile.read(content_length)
                    options = json.loads(post_data.decode('utf-8'))

                    # Validate proxied_host if present
                    if 'proxied_host' in options and options['proxied_host']:
                        is_valid, error_message = validate_url(options['proxied_host'])
                        if not is_valid:
                            self._set_headers()
                            self.wfile.write(json.dumps({
                                "status": "error",
                                "message": error_message,
                                "field": "proxied_host"
                            }).encode())
                            return

                    delay_apply = options.pop('delay_apply', False) if isinstance(options, dict) else False

                    # Read the existing file to ensure we keep the structure
                    with open(OPTIONS_FILE, 'r') as f:
                        current_options = json.load(f)

                    # Check if access_key is changing
                    access_key_changed = False
                    if 'configuration' in options and 'access_key' in options['configuration']:
                        new_access_key = options['configuration']['access_key']
                        current_access_key = current_options.get('configuration', {}).get('access_key')
                        if current_access_key != new_access_key and new_access_key != "XXXXX":
                            access_key_changed = True
                            logging.debug("Access key has changed, will restart container")
                        else:
                            access_key_changed = False
                            logging.debug("Access key unchanged or set to default, no restart needed")

                    # Update with new values
                    for key in options:
                        if key in current_options:
                            if isinstance(current_options[key], dict) and isinstance(options[key], dict):
                                current_options[key].update(options[key])
                            else:
                                current_options[key] = options[key]
                        else:
                            current_options[key] = options[key]

                    # Write back the updated options
                    with open(OPTIONS_FILE, 'w') as f:
                        json.dump(current_options, f, indent=2)

                    self._set_headers()
                    response = {"status": "success"}

                    if access_key_changed:
                        response["message"] = "Access key updated, container will restart. Please wait."

                    self.wfile.write(json.dumps(response).encode())

                    if not delay_apply and not access_key_changed:
                        import threading

                        def apply_config_process():
                            try:
                                result = os.system("/usr/local/bin/apply_config.sh")
                            except Exception as e:
                                logging.error(f"Error applying configuration: {e}")

                        thread = threading.Thread(target=apply_config_process)
                        thread.daemon = True
                        thread.start()
                    elif access_key_changed:
                        import threading

                        def restart_process():
                            time.sleep(0.5)

                            try:
                                logging.info("Starting service restart process")
                                with open("/tmp/restart_reason", "w") as f:
                                    f.write("access_key_changed")

                                scripts = [
                                    "/etc/cont-finish.d/001-stop.sh",
                                    "/etc/cont-init.d/001-start.sh",
                                    "/etc/cont-init.d/005-config.sh",
                                    "/etc/cont-init.d/010-letsencrypt.sh",
                                    "/etc/services.d/connector1/run",
                                    "/etc/services.d/letsencrypt/run",
                                    "s6-svc -r /var/run/s6/legacy-services/status"
                                ]

                                for script in scripts:
                                    logging.debug(f"Executing script: {script}")
                                    return_code = os.system(script)

                                    if return_code != 0:
                                        logging.error(f"Script {script} failed with return code {return_code}")
                                    else:
                                        logging.debug(f"Script {script} completed successfully")
                            except Exception as e:
                                logging.error(f"Error during restart: {e}")

                        thread = threading.Thread(target=restart_process)
                        thread.daemon = True
                        thread.start()

                except BrokenPipeError as e:
                    logging.warning(f"Broken pipe error (expected during restarts): {e}")
                    return
                except Exception as e:
                    logging.error(f"Error updating options: {e}")
                    try:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(json.dumps({"error": str(e)}).encode())
                    except BrokenPipeError:
                        logging.warning("Broken pipe error while sending error response")
                        return

            else:
                try:
                    self.send_response(404)
                    self.end_headers()
                except BrokenPipeError:
                    logging.warning("Broken pipe error while sending 404 response")
                    return
        except BrokenPipeError:
            logging.warning("Broken pipe error in do_POST")
            return
        except Exception as e:
            logging.error(f"Unexpected error in do_POST: {e}")
            return


    def do_HEAD(self):
        try:
            if self.path == '/pluggie/api/health':
                self._set_headers()
            else:
                self.send_response(404)
                self.end_headers()
        except BrokenPipeError:
            logging.warning("Broken pipe error in do_HEAD")
            return
        except Exception as e:
            logging.error(f"Unexpected error in do_HEAD: {e}")
            return


def run(server_class=HTTPServer, handler_class=AdminAPIHandler, port=8000):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    logging.debug(f'Starting admin server on port {port}...')
    httpd.serve_forever()


if __name__ == '__main__':
    run()
