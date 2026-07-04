#!/usr/bin/env bash
# Generates the Play Store upload keystore for com.fitflexafrica.mobile.
#
# Run from the fitflexmobile/ directory:
#   ./scripts/generate_release_keystore.sh
#
# You will be prompted interactively for a keystore password, key password,
# and identity details. Choose a strong password and store it in a password
# manager — losing it means you can never update the app under the same
# Play Store listing again.
#
# After running, copy android/key.properties.example to android/key.properties
# and fill in the passwords/alias you just chose.

set -euo pipefail

KEYSTORE_PATH="android/fitflexaf-upload-keystore.jks"
ALIAS="fitflexaf-upload"

if [ -f "$KEYSTORE_PATH" ]; then
  echo "Keystore already exists at $KEYSTORE_PATH — aborting to avoid overwriting it."
  exit 1
fi

keytool -genkey -v \
  -keystore "$KEYSTORE_PATH" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000

echo ""
echo "Keystore created at $KEYSTORE_PATH"
echo "Next: cp android/key.properties.example android/key.properties"
echo "Then fill in storePassword / keyPassword with what you just entered."
