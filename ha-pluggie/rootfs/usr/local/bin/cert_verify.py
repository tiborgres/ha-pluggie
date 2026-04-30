#!/usr/local/bin/python
"""
SSL Certificate Fingerprint Verification Module for Pluggie.

Periodically fetches the remote SSL certificate fingerprint via the public
internet (using DNS-over-HTTPS for secure hostname resolution) and compares
it with the locally stored Let's Encrypt certificate.  The goal is to detect
potential MITM attacks where a relay server might substitute its own
certificate.
"""

import hashlib
import json
import logging
import os
import socket
import ssl
import subprocess
import threading
import time

import requests

from logger import get_logger

OPTIONS_FILE = "/data/pluggie.json"
CERT_VERIFY_FILE = "/tmp/cert_verify.json"
VERIFY_INTERVAL = 3600  # 1 hour
INITIAL_DELAY = 120  # 2 minutes after startup
TRIGGER_FILE = "/tmp/cert_verify_trigger"

_wakeup_event = threading.Event()


def _load_doh_resolvers():
    """
    Load DoH resolver URLs from pluggie.json configuration.

    Falls back to a sensible default list when the config key is absent.

    Returns:
        A list of DoH server URL strings.
    """
    default_resolvers = [
        "https://1.1.1.1/dns-query",
        "https://8.8.8.8/dns-query",
    ]
    try:
        if os.path.isfile(OPTIONS_FILE):
            with open(OPTIONS_FILE, "r") as fh:
                options = json.load(fh)
            resolvers = options.get(
                "pluggie_config", {},
            ).get("doh_resolvers")
            if isinstance(resolvers, list) and resolvers:
                return resolvers
    except Exception as exc:
        logging.debug("Failed to load doh_resolvers from config: %s", exc)
    return default_resolvers


def _resolve_hostname_doh(hostname):
    """
    Resolve a hostname to an IPv4 address using DNS-over-HTTPS (DoH).

    Resolver URLs are read from pluggie_config.doh_resolvers in
    pluggie.json.  Falls back to Cloudflare + Google when the key is
    not present.

    Args:
        hostname: The hostname to resolve.

    Returns:
        The resolved IPv4 address string, or None on failure.
    """
    doh_servers = _load_doh_resolvers()

    for server in doh_servers:
        try:
            resp = requests.get(
                server,
                params={"name": hostname, "type": "A"},
                headers={"Accept": "application/dns-json"},
                timeout=10,
            )
            if resp.status_code != 200:
                continue

            data = resp.json()
            answers = data.get("Answer", [])
            for answer in answers:
                if answer.get("type") == 1:  # A record
                    ip_addr = answer.get("data")
                    if ip_addr:
                        logging.debug(
                            "DoH resolved %s -> %s via %s",
                            hostname, ip_addr, server,
                        )
                        return ip_addr

            # Handle CNAME chain - follow until we get an A record
            for answer in answers:
                if answer.get("type") == 5:  # CNAME
                    cname_target = answer.get("data", "").rstrip(".")
                    if cname_target:
                        return _resolve_hostname_doh(cname_target)

        except Exception as exc:
            logging.debug("DoH resolution failed via %s: %s", server, exc)
            continue

    logging.warning("DoH resolution failed for %s on all servers", hostname)
    return None


def _get_remote_cert_fingerprint(hostname, ip_addr, port=443):
    """
    Connect to *ip_addr* on *port* using TLS with SNI set to *hostname*
    and return the SHA-256 fingerprint of the peer certificate in DER form.

    Args:
        hostname: SNI hostname for the TLS handshake.
        ip_addr:  Resolved IP address to connect to.
        port:     Target port (default 443).

    Returns:
        A colon-separated SHA-256 fingerprint string, or None on error.
    """
    try:
        ctx = ssl.create_default_context()
        # We only want the fingerprint - don't verify the chain here
        # because the addon itself is the legitimate certificate holder.
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        with socket.create_connection((ip_addr, port), timeout=15) as raw:
            with ctx.wrap_socket(raw, server_hostname=hostname) as tls:
                der_cert = tls.getpeercert(binary_form=True)
                if not der_cert:
                    logging.warning(
                        "No certificate received from %s (%s)",
                        hostname, ip_addr,
                    )
                    return None

                sha256 = hashlib.sha256(der_cert).hexdigest().upper()
                fingerprint = ":".join(
                    sha256[i:i + 2] for i in range(0, len(sha256), 2)
                )
                logging.debug(
                    "Remote cert fingerprint for %s: %s",
                    hostname, fingerprint,
                )
                return fingerprint
    except Exception as exc:
        logging.warning(
            "Failed to get remote certificate from %s (%s:%d): %s",
            hostname, ip_addr, port, exc,
        )
        return None


def _get_local_cert_fingerprint(hostname):
    """
    Read the local Let's Encrypt certificate and return its SHA-256
    fingerprint.

    The certificate path is derived from the standard certbot directory
    layout under the Pluggie SSL directory.

    Args:
        hostname: The hostname whose certificate to read.

    Returns:
        A colon-separated SHA-256 fingerprint string, or None on error.
    """
    # Determine Pluggie SSL directory
    if os.environ.get("SUPERVISOR_TOKEN"):
        pluggie_dir = "/ssl/pluggie"
    else:
        pluggie_dir = "/data"

    cert_path = os.path.join(
        pluggie_dir, "letsencrypt", "live", hostname, "cert.pem",
    )

    if not os.path.isfile(cert_path):
        # Certbot may use a numbered directory when certs are expanded
        live_dir = os.path.join(pluggie_dir, "letsencrypt", "live")
        if os.path.isdir(live_dir):
            for entry in sorted(os.listdir(live_dir), reverse=True):
                if entry.startswith(hostname):
                    candidate = os.path.join(live_dir, entry, "cert.pem")
                    if os.path.isfile(candidate):
                        cert_path = candidate
                        break

    if not os.path.isfile(cert_path):
        logging.warning("Local certificate not found at %s", cert_path)
        return None

    try:
        # Convert PEM to DER for fingerprinting
        result = subprocess.run(
            ["openssl", "x509", "-in", cert_path, "-outform", "DER"],
            capture_output=True,
            timeout=10,
        )
        if result.returncode != 0:
            logging.warning(
                "openssl x509 failed: %s",
                result.stderr.decode(errors="replace"),
            )
            return None

        der_bytes = result.stdout
        sha256 = hashlib.sha256(der_bytes).hexdigest().upper()
        fingerprint = ":".join(
            sha256[i:i + 2] for i in range(0, len(sha256), 2)
        )
        logging.debug(
            "Local cert fingerprint for %s: %s", hostname, fingerprint,
        )
        return fingerprint
    except Exception as exc:
        logging.warning("Failed to read local certificate: %s", exc)
        return None


def _save_result(result):
    """Persist verification result to a JSON file for the API to read."""
    try:
        with open(CERT_VERIFY_FILE, "w") as fh:
            json.dump(result, fh, indent=2)
    except Exception as exc:
        logging.error("Failed to save cert verification result: %s", exc)


def run_verification():
    """
    Execute a single certificate fingerprint verification cycle.

    Returns:
        A dict with the verification result.
    """
    result = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "status": "unknown",
        "local_fingerprint": None,
        "remote_fingerprint": None,
        "match": None,
        "hostname": None,
        "error": None,
        "cert_dir": None,
        "cert_hint": None,
    }

    try:
        # Read hostname from pluggie.json
        if not os.path.isfile(OPTIONS_FILE):
            result["status"] = "error"
            result["error"] = "Options file not found"
            return result

        with open(OPTIONS_FILE, "r") as fh:
            options = json.load(fh)

        hostname = options.get("pluggie_config", {}).get("hostname")
        if not hostname:
            result["status"] = "error"
            result["error"] = "Hostname not configured"
            return result

        result["hostname"] = hostname

        # Check that addon is in a working state
        state_file = "/etc/pluggie.state"
        if os.path.isfile(state_file):
            with open(state_file, "r") as fh:
                state = fh.read().strip()
            if state not in ("enabled",):
                result["status"] = "skipped"
                result["error"] = (
                    f"Addon state is '{state}', skipping verification"
                )
                return result

        # Step 1: resolve hostname via DoH
        ip_addr = _resolve_hostname_doh(hostname)
        if not ip_addr:
            result["status"] = "error"
            result["error"] = "Failed to resolve hostname via DoH"
            return result

        # Step 2: get remote certificate fingerprint
        # Always use port 443 - the public-facing HTTPS port on the
        # relay server.  pluggie_config.https_port is the *internal*
        # port behind WireGuard, not the public one.
        remote_fp = _get_remote_cert_fingerprint(hostname, ip_addr, 443)
        result["remote_fingerprint"] = remote_fp

        if not remote_fp:
            result["status"] = "error"
            result["error"] = "Failed to retrieve remote certificate"
            return result

        # Step 3: get local certificate fingerprint
        local_fp = _get_local_cert_fingerprint(hostname)
        result["local_fingerprint"] = local_fp

        # Store cert location hint for UI
        live_path = f"letsencrypt/live/{hostname}/"
        if os.environ.get("SUPERVISOR_TOKEN"):
            result["cert_dir"] = f"/ssl/pluggie/{live_path}"
            result["cert_hint"] = ""
        else:
            result["cert_dir"] = live_path
            result["cert_hint"] = "inside the volume mounted to /data in your container"

        if not local_fp:
            result["status"] = "error"
            result["error"] = "Failed to read local certificate"
            return result

        # Step 4: compare
        result["match"] = (local_fp == remote_fp)
        result["status"] = "verified" if result["match"] else "mismatch"

        if result["match"]:
            logging.debug(
                "Certificate verification OK for %s - fingerprints match",
                hostname,
            )
        else:
            logging.warning(
                "Certificate MISMATCH for %s! "
                "Local: %s  Remote: %s - possible MITM!",
                hostname, local_fp, remote_fp,
            )

    except Exception as exc:
        result["status"] = "error"
        result["error"] = str(exc)
        logging.error("Certificate verification error: %s", exc)

    # Report result to API server
    if result["status"] in ("verified", "mismatch"):
        _report_to_apiserver(result)

    return result


def _report_to_apiserver(result):
    """
    Report certificate verification result to the Pluggie API server.

    The API server stores the result and sends email notification
    to the user if a mismatch is detected.

    Args:
        result: Verification result dict.
    """
    try:
        if not os.path.isfile(OPTIONS_FILE):
            return

        with open(OPTIONS_FILE, "r") as fh:
            options = json.load(fh)

        access_key = options.get("configuration", {}).get("access_key")
        if not access_key or access_key == "XXXXX":
            return

        api_server = options.get(
            "pluggie_config", {},
        ).get("apiserver", "api.pluggie.net")
        user_agent = options.get("user_agent", "Pluggie-Client")

        api_url = f"https://{api_server}/api/cert-verify"
        headers = {
            "Authorization": f"Bearer {access_key}",
            "User-Agent": user_agent,
            "Content-Type": "application/json",
        }

        payload = {
            "status": result.get("status"),
            "local_fingerprint": result.get("local_fingerprint"),
            "remote_fingerprint": result.get("remote_fingerprint"),
            "match": result.get("match"),
            "timestamp": result.get("timestamp"),
        }

        resp = requests.post(
            api_url, headers=headers, json=payload, timeout=10,
        )
        logging.debug(
            "Cert verify reported to apiserver: %d", resp.status_code,
        )
    except Exception as exc:
        logging.debug("Failed to report cert verify to apiserver: %s", exc)


def trigger_verification():
    """
    Signal the verification loop to run immediately.

    Called after a successful reconnect to skip the remaining sleep
    interval and run a fresh certificate check right away.
    """
    _wakeup_event.set()


def verification_loop():
    """
    Background loop that runs verification periodically.

    Wakes up immediately when _wakeup_event is set or TRIGGER_FILE
    appears on disk (written by shell scripts after a reconnect).
    Intended to be started as a daemon thread from admin_api.py.
    """
    get_logger("cert_verify")
    logging.debug(
        "Certificate verification thread started (interval: %ds)",
        VERIFY_INTERVAL,
    )

    # Initial delay to let services fully start; honour early triggers.
    if not os.path.exists(TRIGGER_FILE):
        _wakeup_event.wait(timeout=INITIAL_DELAY)
    _wakeup_event.clear()

    while True:
        # Remove trigger file before running so a touch arriving
        # during the check is not silently dropped.
        try:
            if os.path.exists(TRIGGER_FILE):
                os.remove(TRIGGER_FILE)
        except OSError:
            pass

        try:
            result = run_verification()
            _save_result(result)
        except Exception as exc:
            logging.error(
                "Unexpected error in verification loop: %s", exc,
            )

        # Wait for next scheduled run, but wake early on event or
        # trigger file appearing on disk (checked every 10 s).
        deadline = time.monotonic() + VERIFY_INTERVAL
        while time.monotonic() < deadline:
            remaining = deadline - time.monotonic()
            woken = _wakeup_event.wait(timeout=min(remaining, 10))
            if woken:
                _wakeup_event.clear()
                break
            if os.path.exists(TRIGGER_FILE):
                break


def start_verification_thread():
    """Start the background verification thread (daemon)."""
    thread = threading.Thread(target=verification_loop, daemon=True)
    thread.name = "cert-verify"
    thread.start()
    return thread


def get_last_result():
    """
    Read and return the last verification result from disk.

    Returns:
        A dict with the last result, or a default 'pending' result.
    """
    if os.path.isfile(CERT_VERIFY_FILE):
        try:
            with open(CERT_VERIFY_FILE, "r") as fh:
                return json.load(fh)
        except Exception:
            pass

    return {
        "status": "pending",
        "local_fingerprint": None,
        "remote_fingerprint": None,
        "match": None,
        "hostname": None,
        "error": "Verification has not run yet",
    }
