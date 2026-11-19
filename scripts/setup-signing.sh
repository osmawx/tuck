#!/bin/bash
# Creates Tuck’s persistent local signing identity without changing certificate trust settings.
# Keep the original certificate name for existing installations.
set -euo pipefail
SIGNING_NAME="Hider Local Development"
if security find-certificate -c "$SIGNING_NAME" >/dev/null 2>&1; then
    echo "Signing certificate already exists; keeping the existing identity."
    exit 0
fi

umask 077
SIGNING_PASSWORD=$(/usr/bin/openssl rand -hex 24)
export SIGNING_PASSWORD
SIGNING_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$SIGNING_DIRECTORY"' EXIT
cat > "$SIGNING_DIRECTORY/certificate.conf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = Hider Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG

/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 \
    -config "$SIGNING_DIRECTORY/certificate.conf" \
    -keyout "$SIGNING_DIRECTORY/key.pem" -out "$SIGNING_DIRECTORY/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -name "$SIGNING_NAME" \
    -inkey "$SIGNING_DIRECTORY/key.pem" -in "$SIGNING_DIRECTORY/cert.pem" \
    -out "$SIGNING_DIRECTORY/identity.p12" -passout env:SIGNING_PASSWORD
SIGNING_KEYCHAIN=$(security default-keychain -d user | tr -d '"' | xargs)
security import "$SIGNING_DIRECTORY/identity.p12" -k "$SIGNING_KEYCHAIN" -P "$SIGNING_PASSWORD" -T /usr/bin/codesign
echo "Persistent local signing identity installed."
