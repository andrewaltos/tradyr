#!/bin/bash
# One-time setup: create a self-signed code-signing identity named "Tradyr Local".
#
# Why bother: macOS ties the microphone, speech recognition and system-audio (TCC) grants to
# the app's code signature. Ad-hoc signing changes identity on every build, so every rebuild
# re-prompts for permission and litters System Settings with stale entries. A stable
# certificate makes the grants persist.
#
# Expect two authorisation prompts: one to add the key to your login keychain,
# one to mark the certificate as trusted for code signing.
set -euo pipefail

NAME="Tradyr Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "==> identity '$NAME' already exists"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> generating certificate"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Apple's SecKeychainItemImport cannot read OpenSSL 3's default PKCS#12
# encryption (AES-256-CBC with a SHA-256 MAC) and reports it as "MAC verification
# failed ... (wrong password?)". Pin the older algorithms it does understand.
# The passphrase is a throwaway: this file lives in $WORK for one command.
# LibreSSL (Apple's /usr/bin/openssl) already defaults to these and rejects -macalg.
PASSPHRASE="tradyr"
PBE_FLAGS=()
if openssl version | grep -q '^OpenSSL'; then
  PBE_FLAGS=(-certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1)
fi

openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" \
  "${PBE_FLAGS[@]}" -passout "pass:$PASSPHRASE"

echo "==> importing into login keychain"
# -A lets codesign use the key without prompting on every build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSPHRASE" -A -T /usr/bin/codesign

echo "==> trusting for code signing"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
security find-identity -v -p codesigning | grep "$NAME" || {
  echo "!!! identity not visible to codesign; builds will fall back to ad-hoc" >&2
  exit 1
}
echo "==> done"
