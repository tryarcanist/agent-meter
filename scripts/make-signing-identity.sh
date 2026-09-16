#!/bin/sh
# Creates a self-signed "agent-meter" code-signing identity in the login
# keychain. build-app.sh signs with it so Keychain's "Always Allow" grants
# survive rebuilds (an unsigned app's identity changes every build).
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 3650 \
    -subj "/CN=agent-meter" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "keyUsage=critical,digitalSignature"
openssl pkcs12 -export -out "$tmp/id.p12" \
    -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -passout pass:agent-meter \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1
security import "$tmp/id.p12" \
    -k ~/Library/Keychains/login.keychain-db -P agent-meter \
    -T /usr/bin/codesign -T /usr/bin/security
echo "Imported signing identity: agent-meter"
