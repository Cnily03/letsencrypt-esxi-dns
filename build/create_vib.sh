#!/bin/bash
#
# Copyright (c) Johannes Feichtner <johannes@web-wack.at>
#
# Script to build letsencrypt-esxi-dns VIB using VIB Author

LOCALDIR=$(dirname "$(readlink -f "$0")")
TEMP_DIR=/tmp/letsencrypt-esxi-dns-$$

# Ensure prerequisites are installed
git version > /dev/null 2>&1
if [ $? -eq 1 ]; then
  echo "git not installed, exiting..."
  exit 1
fi

vibauthor --version > /dev/null 2>&1
if [ $? -eq 1 ]; then
  echo "vibauthor not installed, exiting .."
  exit 1
fi

# Define VIB metadata
cd "${LOCALDIR}" || exit

VIB_DATE=$(date --date="$(git log -n1 --format="%cd" --date="iso")" '+%Y-%m-%dT%H:%I:%S')
VIB_TAG=$(git describe --tags --abbrev=0 --match '[0-9]*.[0-9]*.[0-9]*' 2> /dev/null || echo 0.0.1)

# Setting up VIB spec confs
VIB_DESC_FILE=${TEMP_DIR}/descriptor.xml
VIB_PAYLOAD_DIR=${TEMP_DIR}/payloads/payload1

# Create letsencrypt-esxi-dns temp dir
mkdir -p ${TEMP_DIR}
# Create VIB spec payload directory
mkdir -p ${VIB_PAYLOAD_DIR}

# Create target directory
BIN_DIR=${VIB_PAYLOAD_DIR}/opt/letsencrypt-dns
INIT_DIR=${VIB_PAYLOAD_DIR}/etc/init.d
mkdir -p ${BIN_DIR} ${INIT_DIR}

# Copy files to the corresponding locations
cp ../* ${BIN_DIR} 2>/dev/null
cp ../letsencrypt-dns ${INIT_DIR}

# Ensure that shell scripts are executable
chmod +x ${INIT_DIR}/letsencrypt-dns ${BIN_DIR}/renew.sh

# Create tgz with payload
tar czf ${TEMP_DIR}/payload1 -C ${VIB_PAYLOAD_DIR} etc opt

# Create letsencrypt-esxi-dns VIB descriptor.xml
PAYLOAD_FILES=$(tar tf ${TEMP_DIR}/payload1 | grep -v -E '/$' | sed -e 's/^/    <file>/' -e 's/$/<\/file>/')
PAYLOAD_SIZE=$(stat -c %s ${TEMP_DIR}/payload1)
PAYLOAD_SHA256=$(sha256sum ${TEMP_DIR}/payload1 | awk '{print $1}')
PAYLOAD_SHA256_ZCAT=$(zcat ${TEMP_DIR}/payload1 | sha256sum | awk '{print $1}')
PAYLOAD_SHA1_ZCAT=$(zcat ${TEMP_DIR}/payload1 | sha1sum | awk '{print $1}')

cat > ${VIB_DESC_FILE} << EOF
<vib version="5.0">
  <type>bootbank</type>
  <name>letsencrypt-esxi-dns</name>
  <version>${VIB_TAG}-0.0.0</version>
  <vendor>Cnily03</vendor>
  <summary>Let's Encrypt DNS for ESXi</summary>
  <description>Let's Encrypt DNS-01 certificate renewal for ESXi</description>
  <release-date>${VIB_DATE}</release-date>
  <urls>
    <url key="letsencrypt-esxi-dns">https://github.com/Cnily03/letsencrypt-esxi-dns</url>
  </urls>
  <relationships>
    <depends/>
    <conflicts/>
    <replaces/>
    <provides/>
    <compatibleWith/>
  </relationships>
  <software-tags/>
  <system-requires>
    <maintenance-mode>false</maintenance-mode>
  </system-requires>
  <file-list>
${PAYLOAD_FILES}
  </file-list>
  <acceptance-level>community</acceptance-level>
  <live-install-allowed>true</live-install-allowed>
  <live-remove-allowed>true</live-remove-allowed>
  <cimom-restart>false</cimom-restart>
  <stateless-ready>true</stateless-ready>
  <overlay>false</overlay>
  <payloads>
    <payload name="payload1" type="tgz" size="${PAYLOAD_SIZE}">
        <checksum checksum-type="sha-256">${PAYLOAD_SHA256}</checksum>
        <checksum checksum-type="sha-256" verify-process="gunzip">${PAYLOAD_SHA256_ZCAT}</checksum>
        <checksum checksum-type="sha-1" verify-process="gunzip">${PAYLOAD_SHA1_ZCAT}</checksum>
    </payload>
  </payloads>
</vib>
EOF

# Create letsencrypt-esxi-dns VIB
touch ${TEMP_DIR}/sig.pkcs7
ar r letsencrypt-esxi-dns.vib ${TEMP_DIR}/descriptor.xml ${TEMP_DIR}/sig.pkcs7 ${TEMP_DIR}/payload1

# Create the offline bundle
PYTHONPATH=/opt/vmware/vibtools-6.0.0-847598/bin python -c "import vibauthorImpl; vibauthorImpl.CreateOfflineBundle('letsencrypt-esxi-dns.vib', 'letsencrypt-esxi-dns-offline-bundle.zip', True)"

# Show some details about what we have just created
vibauthor -i -v letsencrypt-esxi-dns.vib

# Remove letsencrypt-esxi-dns temp dir
rm -rf ${TEMP_DIR}
