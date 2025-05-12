# Pluggie


## About

Pluggie (https://pluggie.net/) provides secure Internet access to devices behind NAT, such as Home Assistant, while offering filtering by continents, countries (Geo IP), or IP ranges. It functions as a connector, utilizing Pluggie servers as intermediaries to establish the connection.


## Features

- Zero knowledge about your traffic which is fully encrypted between your Home Assistant or web-enabled device and you (or your clients). Pluggie servers just pass traffic.
- NO traffic decryption/encryption on Pluggie servers at all; only necessary info such as SNI is required to route traffic.
- SSL/TLS certificate issuing via Let's Encrypt is done on your Home Assistant or device.
- Assign your own domain name for your Home Assistant / device (no domain transfer required) or just use _some_hostname_.pluggie.net.
- Filtering out traffic based on continents, countries (Geo IP), or IP addresses/ranges.

With Pluggie, you don't need to configure router, firewall, IPv6 or VPS in datacenter.
Just install, provide the Access Key, run, and enjoy access to your Home Assistant / device.


## Used Technologies

- [WireGuard][wg]
- [NGINX][nginx]
- [Let's Encrypt][letsencrypt]


## Authors

Tibor Gres

Project inspired by:
- [Home Assistant Cloud][hacloud]
- [WireGuard Add-on][wg_addon]
- [Nginx Proxy Manager][nginxproxymanager]
- [Tailscale][tailscale]
- [Cloudflare Tunnel][tailscale]

For a full list of all authors and contributors of Wireguard add-on,
check [the contributor's page][wg_addon_contributors].


## License

MIT License

Copyright (c) 2024 Tibor Gres

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


[project]: https://pluggie.net
[hacloud]: https://www.home-assistant.io/cloud
[wg_addon]: https://github.com/hassio-addons/addon-wireguard
[wg_addon_contributors]: https://github.com/bigmoby/addon-wireguard-client/graphs/contributors
[wg]: https://www.wireguard.com
[nginx]: https://nginx.org
[nginxproxymanager]: https://nginxproxymanager.com
[letsencrypt]: https://letsencrypt.org
[tailscale]: https://tailscale.com
[cloudflare]: https://www.cloudflare.com/en-gb/products/tunnel
