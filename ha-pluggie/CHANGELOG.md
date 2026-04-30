## v0.5.3

- cert verification triggered immediately after reconnect

- bump versions:
  - cryptography 46.0.7 --> 47.0.0


## v0.5.2

- improved self-recovery during API server or Pluggie endpoint outages:
  - added proper error states (no_connection, endpoint_unreachable) to prevent misclassifying network issues as invalid access key
  - fixed configuration cleanup targeting pluggie.json instead of HA-managed options.json


## v0.5.1

- bump versions:
  - certbot 5.4.0 --> 5.5.0
  - cryptography 46.0.6 --> 46.0.7


## v0.5.0

- removed armhf, armv7 and i386, support for these platforms ended in v0.4.6

- bump versions:
  - alpinelinux 3.22 --> 3.23
  - python 3.13 --> 3.14
  - cryptography 46.0.5 --> 46.0.6


## v0.4.6

- lower S6_VERBOSITY log level 1 --> 0

- bump versions:
  - certbot 5.3.1 --> 5.4.0

- DEPRECATION NOTICE:
  - platforms armhf, armv7 and i386 are not supported in HomeAssistant anymore and will be removed in release 0.5.0. This does not affect the Docker Edition of Pluggie.
  - !!! THIS IS THE LAST v0.4.x VERSION !!!
  - !!! NEXT RELEASE WILL BE v0.5.0 !!!


## v0.4.5

- feature:
  - Added SSL certificate fingerprint verification with MITM detection, API reporting, and email alerts on mismatch

- DEPRECATION NOTICE:
  - platforms armhf, armv7 and i386 are not supported in HomeAssistant anymore and will be removed in release 0.5.0. This does not affect the Docker Edition of Pluggie.


## v0.4.4

- bump versions:
  - wireguard-tools 0.5.3 --> 0.6.0

- DEPRECATION NOTICE:
  - platforms armhf, armv7 and i386 are not supported in HomeAssistant anymore and will be removed in next release (0.5.0). This does not affect the Docker Edition of Pluggie.


## v0.4.3

- bump versions:
  - cryptography 46.0.3 --> 46.0.5
  - certbot 5.2.2 --> 5.3.1
- fix warning class not being removed on validation success (Pluggie sidebar)

- DEPRECATION NOTICE:
  - platforms armhf, armv7 and i386 are not supported in HomeAssistant anymore and will be removed in next release (0.5.0). This does not affect the Docker Edition of Pluggie.


## v0.4.2

- fix day/night view of Pluggie sidebar
- bump versions:
  - certbot 5.1.0 --> 5.2.2


## v0.4.1

- show helpful error pages in cases of incomplete Pluggie setup


## v0.4.0

- replace gzip by brotli (lower traffic consumption)
- remove TLSv1.1


## v0.3.9.1

- bump versions:
  - fixed from v0.3.9: cryptography 46.0.2 --> 46.0.3


## v0.3.9

- Dark Mode! :)
- bump versions:
  - cryptography 46.0.2 --> 46.0.3


## v0.3.8

- fix for viewing consumed traffic information in Pluggie sidebar index.html


## v0.3.7

- bump versions:
  - cryptography 46.0.1 --> 46.0.2
  - certbot 5.0.0 --> 5.1.0


## v0.3.6

- bump versions:
  - wireguard-tools 0.5.2 --> 0.5.3


## v0.3.5

- bump versions:
  - cryptography 45.0.7 --> 46.0.1


## v0.3.4

- fix:
  - traffic info view on mobiles in sidebar


## v0.3.3

- feature:
  - add consumed traffic info into Pluggie sidebar page so there is no need to go check it via https://my.pluggie.net interface


## v0.3.2

- bump versions:
  - cryptography 45.0.4 --> 45.0.7
  - certbot 4.1.1 --> 5.0.0


## v0.3.1

- v0.3.1


## v0.3.0.4

- bumped versions:
  - alpinelinux 3.21 --> 3.22
  - cryptography 44.0.2 --> 45.0.4
  - certbot 4.0.0 --> 4.1.1
- no fixes needed :)


## v0.3.0.3

- fixes:
  - missing logo :)


## v0.3.0.2

- fixes:
  - replace custom regex by more standardised way
  - admin_api URL --> /pluggie/api
  - minor permissions fix for default pluggie.json when created


## v0.3.0.1

bumped versions:
  - cryptography 44.0.0 --> 44.0.2
  - certbot 3.0.1 --> 4.0.0
  - wireguard-tools 0.5.0 --> 0.5.2


## v0.3.0.0

- initial version
