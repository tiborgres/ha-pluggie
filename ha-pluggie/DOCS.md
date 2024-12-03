# Home Assistant Add-on: Pluggie

## Installation

1. Add the Pluggie repository to your Home Assistant instance:
   ```
   https://github.com/tiborgres/pluggie
   ```
2. Click on the "Pluggie" add-on in the add-on store
3. Click on the "INSTALL" button

## Configuration

### Required Configuration

```
configuration:
  access_key: YOUR_ACCESS_KEY   # Access key from https://api.pluggie.net
```

### Advanced Configuration

```
log_level: info                 # Optional: debug, info, warning, error
mtu: 1420                       # Optional: MTU value for the WireGuard interface
keep_alive: 25                  # Optional: WireGuard keepalive interval in seconds

# Let's Encrypt Configuration
acme_root_ca_cert: ""           # Optional: Custom root CA certificate
acme_server: ""                 # Optional: Custom ACME server URL
key_type: ecdsa                 # Optional: Certificate key type (ecdsa, rsa)
elliptic_curve: secp256r1       # Optional: Curve for ECDSA keys (secp256r1, secp384r1)
```

### Configuration Options Explained

**Basic**
- `access_key`: Your unique access key that identifies and authorizes your Home Assistant instance with Pluggie services.

**Logging**
- `log_level`: Controls the detail level of logging. Use 'debug' for troubleshooting, 'info' for normal operation.

**Network**
- `mtu`: Maximum Transmission Unit size. Default is suitable for most connections. Lower it if you experience connectivity issues.
- `keep_alive`: How often the connection checks if it's still active. Increase this value if you have unstable internet.

**SSL/TLS Certificate**
- `acme_root_ca_cert`: Custom certificate authority. Only needed if you use your own CA.
- `acme_server`: Alternative ACME server URL. Use this if you want to use a different certificate provider.
- `key_type`: Choose between ECDSA (faster, modern) or RSA (wider compatibility) certificates.
- `elliptic_curve`: Security level for ECDSA certificates. secp256r1 is recommended for most users.

## Usage

1. Edit your Home Assistant's `configuration.yaml` file and add/update:
   ```yaml
   http:
      use_x_forwarded_for: true
      trusted_proxies:
        - 172.30.32.0/23  # pluggie add-on
   ```
2. Restart Home Assistant to apply `configuration.yaml` changes
3. Configure the add-on with your access key
4. Start the add-on
5. Check the add-on status in log output
6. Test the connection by opening your browser and navigating to your chosen domain name:
   ```
   https://your-domain-name.pluggie.net
   ```
   or your custom domain if configured in the admin interface.

## Support

- Got questions? Visit our website at [https://pluggie.net](https://pluggie.net)
- Need help? Contact our support team through your [Pluggie Admin Interface](https://api.pluggie.net/support)
