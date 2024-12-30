# Home Assistant Add-On: Pluggie


## Installation

1. Click on button to add Pluggie repository to your Home Assistant Add-On Store:

   [![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Ftiborgres%2Fha-pluggie)

   ..or add the Pluggie repository manually (Settings -> Add-ons -> Add-on Store -> Repositories):
   ```
   https://github.com/tiborgres/ha-pluggie
   ```
2. Check for updates and go into the Add-On Store
3. Choose Pluggie Add-On
4. Click on the INSTALL button


## Configuration

### Required Configuration

```
configuration:
  access_key: YOUR_ACCESS_KEY   # Access key from https://admin.pluggie.net
```


### Advanced Configuration

```
log_level: info                 # Optional: debug, info, warning, error; Default: info
proxied_host: ""                # Optional: Full URL of proxied host; Default: http://homeassistant.local.hass.io:8123

# Basic Auth
basic_auth_username: ""         # Optional: Username for Basic Auth protection
basic_auth_password: ""         # Optional: Password for Basic Auth protection

# Let's Encrypt Configuration
acme_root_ca_cert: ""           # Optional: Custom root CA certificate
acme_server: ""                 # Optional: Custom ACME server URL
key_type: ecdsa                 # Optional: Certificate key type (ecdsa, rsa)
elliptic_curve: secp256r1       # Optional: Curve for ECDSA keys (secp256r1, secp384r1); Default: secp256r1
```

<!-- Removed from upper table as obsolete:
mtu: 1420                       # Optional: MTU value for the WireGuard interface; Default: 1420
keep_alive: 25                  # Optional: WireGuard keepalive interval in seconds; Default: 25
 -->


### Configuration Options Explained

**Basic**
- `access_key`: Your unique access key that identifies and authorizes your Home Assistant instance with Pluggie services.

**Logging**
- `log_level`: Controls the detail level of logging. Use 'debug' for troubleshooting, 'info' for normal operation.

**Network**
- `proxied_host`: URL of your Home Assistant (default) or web enabled device to connect to (e.g. https://myrouter.internal:8080)

**Security**
- `basic_auth_username`: Optional username for Basic Auth protection. If set along with password, will enable Basic Auth.
- `basic_auth_password`: Optional password for Basic Auth protection. Must be set together with username.

<!-- - `mtu`: Maximum Transmission Unit size. Default is suitable for most connections. Set it lower if you experience connectivity issues.
- `keep_alive`: How often the connection checks if it's still active. Set it lower if you have unstable internet.
 -->

**SSL/TLS Certificate**
- `acme_root_ca_cert`: Custom certificate authority. Only needed if you use your own CA.
- `acme_server`: Alternative ACME server URL. Use this if you want to use a different certificate provider.
- `key_type`: Choose between ECDSA (faster, modern) or RSA (wider compatibility) certificates.
- `elliptic_curve`: Security level for ECDSA certificates. secp256r1 is recommended for most users.


### One-Time Setup

1. Edit your Home Assistant's `configuration.yaml` file and add/update:
   ```yaml
   http:
      use_x_forwarded_for: true
      trusted_proxies:
        - 172.30.32.0/23  # Pluggie Add-On
   ```
2. Restart Home Assistant to apply `configuration.yaml` changes
3. Set the "access_key" on Pluggie Add-On Configuration page
4. Start the Add-On
5. Check the Add-On status in Log output
6. Test the connection by opening your browser and navigating to your chosen generated domain name:
   ```
   https://generated-domain-name.pluggie.net
   ```
   or your custom domain if configured in the admin interface.


## Support

- Got questions? Visit our website at [https://pluggie.net](https://pluggie.net)
- Need help? Contact our support team through your [Pluggie Admin Interface](https://admin.pluggie.net/support)
