#!/bin/bash
# Generates a reusable, self-signed release identity and prints its certificate fingerprint.
set -euo pipefail

identity_file="${1:?Usage: create-release-identity.sh <new PKCS#12 file>}"
: "${TUCK_SIGNING_P12_PASSWORD:?Set a strong export password in TUCK_SIGNING_P12_PASSWORD}"
if [[ -e "$identity_file" || -L "$identity_file" ]]; then
    echo "Refusing to replace an existing signing identity." >&2
    exit 1
fi
umask 077
signing_directory="$(mktemp -d)"
trap 'rm -rf "$signing_directory"' EXIT

cat > "$signing_directory/certificate.conf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = Tuck Release Signing
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG

/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 \
    -config "$signing_directory/certificate.conf" \
    -keyout "$signing_directory/key.pem" -out "$signing_directory/certificate.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
    -name "Tuck Release Signing" -inkey "$signing_directory/key.pem" -in "$signing_directory/certificate.pem" \
    -out "$identity_file" -passout env:TUCK_SIGNING_P12_PASSWORD
/usr/bin/openssl x509 -in "$signing_directory/certificate.pem" -noout -fingerprint -sha1 |
    awk -F= '{gsub(/:/, "", $2); print toupper($2)}'
