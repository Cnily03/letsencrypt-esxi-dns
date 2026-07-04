#!/bin/sh
#
# Copyright (c) Johannes Feichtner <johannes@web-wack.at>
# Released under the GNU GPLv3 License.

LOCALDIR=$(dirname "$(readlink -f "$0")")
LOCALSCRIPT=$(basename "$0")

DIRECTORY_URL="https://acme-v02.api.letsencrypt.org/directory"
SSL_CERT_FILE="$LOCALDIR/ca-certificates.crt"
RENEW_DAYS=30
DNS_PROPAGATION_SECONDS=120
ACME_ENV_FILE="${ACME_ENV_FILE:-}"

ACCOUNTKEY="esxi_account.key"
KEY="esxi.key"
CSR="esxi.csr"
CRT="esxi.crt"
VMWARE_CRT="/etc/vmware/ssl/rui.crt"
VMWARE_KEY="/etc/vmware/ssl/rui.key"

if [ -z "$ACME_ENV_FILE" ]; then
  if [ -n "$HOME" ]; then
    ACME_ENV_FILE="$HOME/.acme.env"
  else
    ACME_ENV_FILE="/root/.acme.env"
  fi
fi

if [ ! -r "$ACME_ENV_FILE" ] && [ -r "/.acme.env" ]; then
  ACME_ENV_FILE="/.acme.env"
fi

if [ -r "$ACME_ENV_FILE" ]; then
  . "$ACME_ENV_FILE"
fi

DOMAIN="${ESXI_DOMAIN:-$(hostname -f)}"

if [ -r "$LOCALDIR/renew.cfg" ]; then
  . "$LOCALDIR/renew.cfg"
fi

CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-$CF_Account_ID}"

log() {
   echo "$@"
   logger -p daemon.info -t "$0" "$@"
}

log "Starting certificate renewal.";

# Preparation steps
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "${DOMAIN/.}" ]; then
  log "Error: Hostname ${DOMAIN} is no FQDN."
  exit
fi

if [ -z "$ACME_EMAIL" ]; then
  log "Error: ACME_EMAIL is not set. Put it in ${ACME_ENV_FILE}."
  exit
fi

if [ -z "$CF_ACCOUNT_ID" ]; then
  log "Error: CF_Account_ID is not set. Put it in ${ACME_ENV_FILE}."
  exit
fi

if [ -z "$CF_Token" ]; then
  log "Error: CF_Token is not set. Put it in ${ACME_ENV_FILE}."
  exit
fi

# Add a cronjob for auto renewal. The script is run once a week on Sunday at 00:00
if ! grep -q "$LOCALDIR/$LOCALSCRIPT" /var/spool/cron/crontabs/root; then
  kill -sighup "$(pidof crond)" 2>/dev/null
  echo "0    0    *   *   0   /bin/sh $LOCALDIR/$LOCALSCRIPT" >> /var/spool/cron/crontabs/root
  crond
fi

# Check issuer and expiration date of existing cert
if [ -e "$VMWARE_CRT" ]; then
  # If the cert is issued for a different hostname, request a new one
  SAN=$(openssl x509 -in "$VMWARE_CRT" -text -noout | grep DNS: | sed 's/DNS://g' | xargs)
  if [ "$SAN" != "$DOMAIN" ] ; then
    log "Existing cert issued for ${SAN} but current domain name is ${DOMAIN}. Requesting a new one!"
  # If the cert is issued by Let's Encrypt, check its expiration date, otherwise request a new one
  elif openssl x509 -in "$VMWARE_CRT" -issuer -noout | grep -q "O=Let's Encrypt"; then
    CERT_VALID=$(openssl x509 -enddate -noout -in "$VMWARE_CRT" | cut -d= -f2-)
    log "Existing Let's Encrypt cert valid until: ${CERT_VALID}"
    if openssl x509 -checkend $((RENEW_DAYS * 86400)) -noout -in "$VMWARE_CRT"; then
      log "=> Longer than ${RENEW_DAYS} days. Aborting."
      exit
    else
      log "=> Less than ${RENEW_DAYS} days. Renewing!"
    fi
  else
    log "Existing cert for ${DOMAIN} not issued by Let's Encrypt. Requesting a new one!"
  fi
fi

cd "$LOCALDIR" || exit

# Cert Request
[ ! -r "$ACCOUNTKEY" ] && openssl genrsa 4096 > "$ACCOUNTKEY"

openssl genrsa -out "$KEY" 4096
openssl req -new -sha256 -key "$KEY" -subj "/CN=$DOMAIN" -config "./openssl.cnf" > "$CSR"
chmod 0400 "$ACCOUNTKEY" "$KEY"

# Allow outbound ACME and Cloudflare API requests.
esxcli network firewall ruleset set -e true -r httpClient

# Retrieve the certificate
export SSL_CERT_FILE
ACME_CERT_OUTPUT="/tmp/letsencrypt-dns-cert.$$"
ACME_ERROR_OUTPUT="/tmp/letsencrypt-dns-acme-error.$$"

python ./acme_tiny.py \
  --account-key "$ACCOUNTKEY" \
  --csr "$CSR" \
  --directory-url "$DIRECTORY_URL" \
  --contact "mailto:$ACME_EMAIL" \
  --cloudflare-account-id "$CF_ACCOUNT_ID" \
  --cloudflare-token "$CF_Token" \
  --dns-propagation-seconds "$DNS_PROPAGATION_SECONDS" \
  > "$ACME_CERT_OUTPUT" 2> "$ACME_ERROR_OUTPUT"
ACME_STATUS=$?

if [ -s "$ACME_ERROR_OUTPUT" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && log "acme_tiny: $line"
  done < "$ACME_ERROR_OUTPUT"
fi

CERT=$(cat "$ACME_CERT_OUTPUT")
rm -f "$ACME_CERT_OUTPUT" "$ACME_ERROR_OUTPUT"

if [ "$ACME_STATUS" -ne 0 ]; then
  log "Error: ACME client exited with status ${ACME_STATUS}."
fi

# If an error occurred during certificate issuance, $CERT will be empty
if [ -n "$CERT" ] ; then
  echo "$CERT" > "$CRT"
  # Provide the certificate to ESXi
  cp -p "$LOCALDIR/$KEY" "$VMWARE_KEY"
  cp -p "$LOCALDIR/$CRT" "$VMWARE_CRT"
  log "Success: Obtained and installed a certificate from Let's Encrypt."
elif openssl x509 -checkend 86400 -noout -in "$VMWARE_CRT"; then
  log "Warning: No cert obtained from Let's Encrypt. Keeping the existing one as it is still valid."
else
  log "Error: No cert obtained from Let's Encrypt. Generating a self-signed certificate."
  /sbin/generate-certificates
fi

for s in /etc/init.d/*; do if $s | grep ssl_reset > /dev/null; then $s ssl_reset; fi; done
