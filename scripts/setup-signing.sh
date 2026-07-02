#!/usr/bin/env bash
# Create a stable self-signed code-signing identity so gab's Accessibility /
# Microphone grants survive rebuilds (ad-hoc signatures change every build and
# reset the grant). Run once. Idempotent.
set -euo pipefail

IDENTITY="gab-dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "Signing identity '$IDENTITY' already present. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P12_PASS="gab-local"   # transient; only used to move the key into the keychain

echo "Generating self-signed code-signing certificate '$IDENTITY'…"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$IDENTITY" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# -legacy: Apple's `security` can't read OpenSSL 3's default PKCS12 algorithms.
# A non-empty password is also required (empty-password p12 fails MAC verify).
openssl pkcs12 -export -legacy -out "$TMP/identity.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -passout "pass:$P12_PASS" >/dev/null 2>&1

# -A: let any app use the key without per-use prompts (fine for a local dev cert).
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -A \
  -T /usr/bin/codesign

echo
echo "Done. The signature is now stable across rebuilds."
echo "Rebuild with: make    (it will sign with '$IDENTITY' automatically)"
