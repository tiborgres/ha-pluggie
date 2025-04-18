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


### One-Time Setup

1. Edit your Home Assistant's `configuration.yaml` file and add/update:
   ```yaml
   http:
      use_x_forwarded_for: true
      trusted_proxies:
        - 172.30.32.0/23  # Pluggie Add-On
   ```
2. Enable Sidebar for Configuration page
3. Start the Add-On
4. Restart Home Assistant to apply `configuration.yaml` changes and to enable Sidebar view
5. After Home Assistant Restart - Set the "Access Key" and other settings on Pluggie Sidebar page
6. Check the Add-On status in Log output
7. Test the connection by opening your browser and navigating to your chosen generated domain name:
   ```
   https://generated-domain-name.pluggie.net
   ```
   or your custom domain if configured in the admin interface (https://my.pluggie.net/)


## Configuration

### Required Configuration

```
Access Key: YOUR_ACCESS_KEY          # Access key from https://my.pluggie.net
```


### Advanced Configuration

```
Log Level: info                        # Optional: debug, info, warning, error; Default: info
Proxied Host: ""                       # Optional: Full URL of proxied host; Default: http://homeassistant.local.hass.io:8123

# Basic Auth
Basic Authentication Username: ""      # Optional: Username for Basic Auth protection
Basic Authentication Password: ""      # Optional: Password for Basic Auth protection

# Let's Encrypt Configuration
ACME Root CA Certificate: ""           # Optional: Custom root CA certificate
ACME Server: ""                        # Optional: Custom ACME server URL
Key Type: ecdsa                        # Optional: Certificate key type (ecdsa, rsa)
Elliptic Curve: secp256r1              # Optional: Curve for ECDSA keys (secp256r1, secp384r1); Default: secp256r1
```

### Configuration Options Explained

**Basic**
- `Access Key`: Your unique access key that identifies and authorizes your Home Assistant instance with Pluggie services.

**Logging**
- `Log Level`: Controls the detail level of logging. Use 'debug' for troubleshooting, 'info' for normal operation.

**Network**
- `Proxied Host`: URL of your Home Assistant (default) or web enabled device to connect to (e.g. https://myrouter.internal:8080)

**Security**
- `Basic Authentication Username`: Optional username for Basic Auth protection. If set along with password, will enable Basic Auth.
- `Basic Authentication Password`: Optional password for Basic Auth protection. Must be set together with username.


**SSL/TLS Certificate**
- `ACME Root CA Certificate`: Custom certificate authority. Only needed if you use your own CA.
- `ACME Server`: Alternative ACME server URL. Use this if you want to use a different certificate provider.
- `Key Type`: Choose between ECDSA (faster, modern) or RSA (wider compatibility) certificates.
- `Elliptic Curve`: Security level for ECDSA certificates. secp256r1 is recommended for most users.


## Support

- Got questions? Visit our website at [https://pluggie.net](https://pluggie.net)
- Need help? Contact our support team through support@pluggie.net
