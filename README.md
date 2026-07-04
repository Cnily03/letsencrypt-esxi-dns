# Let's Encrypt for VMware ESXi

`letsencrypt-esxi-dns` is a lightweight open-source solution to automatically obtain and renew Let's Encrypt certificates on standalone VMware ESXi servers. Packaged as a _VIB archive_ or _Offline Bundle_, install/upgrade/removal is possible directly via the web UI or, alternatively, with just a few SSH commands.

Features:

- **Fully-automated**: Requesting and renewing certificates without user interaction
- **Auto-renewal**: A cronjob runs once a week to check if a certificate is due for renewal
- **Persistent**: The certificate, private key and all settings are preserved over ESXi upgrades
- **Configurable**: Customizable parameters for renewal interval, Let's Encrypt (ACME) backend, etc
- **DNS validation**: Uses Cloudflare DNS-01 challenges, so ESXi does not need to expose HTTP to the Internet

_Successfully tested with ESXi 6.5, 6.7, 7.0, 8.0._

## Why?

Many ESXi servers are accessible over the Internet and use self-signed X.509 certificates for TLS connections. This situation not only leads to annoying warnings in the browser when calling the Web UI, but can also be the reason for serious security problems. Despite the enormous popularity of [Let's Encrypt](https://letsencrypt.org), there is no convenient way to automatically request, renew or remove certificates in ESXi.

## Prerequisites

Before installing `letsencrypt-esxi-dns`, ensure the following preconditions are met:

- The certificate domain is a _Fully Qualified Domain Name (FQDN)_ in a public Cloudflare DNS zone
- ESXi can make outbound HTTPS requests to Let's Encrypt and Cloudflare
- A Cloudflare API token with Zone Read and DNS Edit permissions is available
- `~/.acme.env` exists for the ESXi root user before the renewal script runs:

```bash
export ACME_EMAIL="user@example.com"
export CF_Account_ID="account_id"
export CF_Token="secret_key"
export ESXI_DOMAIN="example.com"
```

**Note:** As soon as you install this software, any existing, non Let's Encrypt certificate gets replaced!

## Install

`letsencrypt-esxi-dns` can be installed via SSH or the Web UI (= Embedded Host Client).

### SSH on ESXi

```bash
$ wget -O /tmp/letsencrypt-esxi-dns.vib https://github.com/Cnily03/letsencrypt-esxi-dns/releases/latest/download/letsencrypt-esxi-dns.vib

$ esxcli software vib install -v /tmp/letsencrypt-esxi-dns.vib -f
Installation Result
   Message: Operation finished successfully.
   Reboot Required: false
   VIBs Installed: web-wack-creations_bootbank_letsencrypt-esxi-dns_1.0.0-0.0.0
   VIBs Removed:
   VIBs Skipped:

$ esxcli software vib list | grep letsencrypt-dns
letsencrypt-esxi-dns  1.0.0-0.0.0  web-wack-creations  CommunitySupported  2022-05-29

$ cat /var/log/syslog.log | grep letsencrypt-dns
2022-05-29T20:01:46Z /etc/init.d/letsencrypt-dns: Running 'start' action
2022-05-29T20:01:46Z /opt/letsencrypt-dns/renew.sh: Starting certificate renewal.
2022-05-29T20:01:46Z /opt/letsencrypt-dns/renew.sh: Existing cert for example.com not issued by Let's Encrypt. Requesting a new one!
2022-05-29T20:02:02Z /opt/letsencrypt-dns/renew.sh: Success: Obtained and installed a certificate from Let's Encrypt.
```

### Web UI (= Embedded Host Client)

1. _Storage -> Datastores:_ Use the Datastore browser to upload the [VIB file](https://github.com/Cnily03/letsencrypt-esxi-dns/releases/latest/download/letsencrypt-esxi-dns.vib) to a datastore path of your choice.
2. _Manage -> Security & users:_ Set the acceptance level of your host to _Community_.
3. _Manage -> Packages:_ Switch to the list of installed packages, click on _Install update_ and enter the absolute path on the datastore where your just uploaded VIB file resides.
4. While the VIB is installed, ESXi requests a certificate from Let's Encrypt. If you reload the Web UI afterwards, the newly requested certificate should already be active. If not, see the [Wiki](https://github.com/Cnily03/letsencrypt-esxi-dns/wiki) for troubleshooting.

### Optional Configuration

If you want to try out the script before putting it into production, you may want to test against the [staging environment](https://letsencrypt.org/docs/staging-environment/) of Let's Encrypt. Probably, you also do not wish to renew certificates once in 30 days but in longer or shorter intervals. Most variables of `renew.sh` can be adjusted by creating a `renew.cfg` file with your overwritten values.

`vi /opt/letsencrypt-dns/renew.cfg`

```bash
# Request a certificate from the staging environment
DIRECTORY_URL="https://acme-staging-v02.api.letsencrypt.org/directory"
# Set the renewal interval to 15 days
RENEW_DAYS=15
# Wait longer for Cloudflare TXT record propagation
DNS_PROPAGATION_SECONDS=180
```

To apply your modifications, run `/etc/init.d/letsencrypt-dns start`

## Uninstall

Remove the installed `letsencrypt-esxi-dns` package via SSH:

```bash
$ esxcli software vib remove -n letsencrypt-esxi-dns
Removal Result
   Message: Operation finished successfully.
   Reboot Required: false
   VIBs Installed:
   VIBs Removed: web-wack-creations_bootbank_letsencrypt-esxi-dns_1.0.0-0.0.0
   VIBs Skipped:
```

This action will purge `letsencrypt-esxi-dns`, undo the cronjob and remove any legacy HTTP challenge proxy route before calling `/sbin/generate-certificates` to generate and install a new, self-signed certificate.

## Usage

Usually, fully-automated. No interaction required.

### Hostname Change

If you change the hostname on our ESXi instance, the domain the certificate is issued for will mismatch. In that case, either re-install `letsencrypt-esxi-dns` or simply run `/etc/init.d/letsencrypt-dns start`, e.g.:

```bash
$ esxcfg-advcfg -s new-example.com /Misc/hostname
Value of HostName is new-example.com

$ /etc/init.d/letsencrypt-dns start
Running 'start' action
Starting certificate renewal.
Existing cert issued for example.com but current domain name is new-example.com. Requesting a new one!
Generating RSA private key, 4096 bit long modulus
...
```

### Force Renewal

You already have a valid certificate from Let's Encrypt but nonetheless want to renew it now:
```bash
rm /etc/vmware/ssl/rui.crt
/etc/init.d/letsencrypt-dns start
```

## How does it work?

* Checks if the current certificate is issued by Let's Encrypt and due for renewal (_default:_ 30d in advance)
* Reads `~/.acme.env` for the ACME email address, Cloudflare credentials and target ESXi domain
* Generates a 4096-bit RSA keypair and CSR
* Creates a Cloudflare `_acme-challenge` TXT record for DNS-01 validation
* Configures ESXi firewall to allow outgoing HTTP/HTTPS client connections
* Uses [acme-tiny](https://github.com/diafygi/acme-tiny) for all interactions with Let's Encrypt
* Removes the Cloudflare TXT challenge record after validation
* Installs the retrieved certificate and restarts all services relying on it
* Adds a cronjob to check periodically if the certificate is due for renewal (_default:_ weekly on Sunday, 00:00)

## Demo

Here is a sample output when invoking the script manually via SSH:

```bash
$ /etc/init.d/letsencrypt-dns start

Running 'start' action
Starting certificate renewal.
Existing cert for example.com not issued by Let's Encrypt. Requesting a new one!
Generating RSA private key, 4096 bit long modulus
***************************************************************************++++
e is 65537 (0x10001)
Serving HTTP on 0.0.0.0 port 8120 ...
Parsing account key...
Parsing CSR...
Found domains: example.com
Getting directory...
Directory found!
Registering account...
Already registered!
Creating new order...
Order created!
Verifying example.com...
Creating Cloudflare TXT record _acme-challenge.example.com in zone example.com...
Waiting 120s for DNS propagation...
Deleting Cloudflare TXT record _acme-challenge.example.com...
example.com verified!
Signing certificate...
Certificate signed!
Success: Obtained and installed a certificate from Let's Encrypt.
hostd signalled.
rabbitmqproxy is not running
VMware HTTP reverse proxy signalled.
sfcbd-init: Getting Exclusive access, please wait...
sfcbd-init: Exclusive access granted.
vpxa signalled.
vsanperfsvc is not running.
/etc/init.d/vvold ssl_reset, PID 2129283
vvold is not running.
```

## Troubleshooting

See the [Wiki](https://github.com/Cnily03/letsencrypt-esxi-dns/wiki) for possible pitfalls and solutions.

## License

    letsencrypt-esxi-dns is free software;
    you can redistribute it and/or modify it under the terms of the
    GNU General Public License as published by the Free Software Foundation,
    either version 3 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
