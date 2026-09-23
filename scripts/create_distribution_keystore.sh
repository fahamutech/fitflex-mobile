#!/usr/bin/env bash
# Creates the signing key used ONLY for Firebase App Distribution builds and
# stores it as GitHub Actions secrets on fahamutech/fitflex-mobile.
#
# This is NOT the Play Store upload key (FahamuTech holds that one separately).
# Builds signed with this key cannot be uploaded to the Play listing.
#
# Run from the fitflexmobile/ directory:
#   ./scripts/create_distribution_keystore.sh
#
# The password is random, never printed, and saved to the macOS Keychain as
# service "fitflex-distribution-keystore". Read it back with:
#   security find-generic-password -s fitflex-distribution-keystore -w

set -euo pipefail

REPO="fahamutech/fitflex-mobile"
KEYSTORE_PATH="android/fitflex-distribution.jks"   # git-ignored (**/*.jks)
ALIAS="fitflex-distribution"
KEYCHAIN_SERVICE="fitflex-distribution-keystore"

KEYTOOL="$(command -v keytool || true)"
if ! "$KEYTOOL" -help >/dev/null 2>&1; then
  KEYTOOL="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
fi
[ -x "$KEYTOOL" ] || { echo "keytool not found (install a JDK or Android Studio)."; exit 1; }

if [ -f "$KEYSTORE_PATH" ]; then
  echo "Keystore already exists at $KEYSTORE_PATH — aborting to avoid overwriting it."
  exit 1
fi

# 32 random alphanumeric characters, held only in this process's environment.
KS_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
export KS_PASS

"$KEYTOOL" -genkeypair \
  -keystore "$KEYSTORE_PATH" -storetype PKCS12 \
  -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=FitFlex Af Distribution, O=FitFlex Af, L=Dar es Salaam, C=TZ" \
  -storepass:env KS_PASS -keypass:env KS_PASS

security add-generic-password -U -a "$USER" -s "$KEYCHAIN_SERVICE" \
  -l "FitFlex App Distribution keystore password" -w "$KS_PASS"

base64 -i "$KEYSTORE_PATH" | gh secret set ANDROID_DIST_KEYSTORE_BASE64 -R "$REPO"
printf '%s' "$KS_PASS" | gh secret set ANDROID_DIST_KEYSTORE_PASSWORD -R "$REPO"
printf '%s' "$ALIAS"   | gh secret set ANDROID_DIST_KEY_ALIAS -R "$REPO"

# Google sign-in on Android only works for signing certificates registered on
# the Firebase Android app, so register this key's fingerprints.
FIREBASE_ANDROID_APP_ID="1:318978253903:android:578eecbe0556347d45f63a"
CERT_INFO="$("$KEYTOOL" -list -v -keystore "$KEYSTORE_PATH" -alias "$ALIAS" -storepass:env KS_PASS)"
unset KS_PASS
SHA1="$(printf '%s\n' "$CERT_INFO" | awk '/SHA1:/ {print $2; exit}')"
SHA256="$(printf '%s\n' "$CERT_INFO" | awk '/SHA256:/ {print $2; exit}')"
for SHA in "$SHA1" "$SHA256"; do
  firebase apps:android:sha:create "$FIREBASE_ANDROID_APP_ID" "$SHA" --project fitflex-af-pilot \
    || echo "Could not register $SHA — add it in Firebase console → Project settings → Android app."
done

echo ""
echo "Done."
echo "  Keystore:  $KEYSTORE_PATH  (back this file up; it is git-ignored)"
echo "  Password:  macOS Keychain, service \"$KEYCHAIN_SERVICE\""
echo "  Secrets:   ANDROID_DIST_KEYSTORE_BASE64, ANDROID_DIST_KEYSTORE_PASSWORD, ANDROID_DIST_KEY_ALIAS on $REPO"
echo "  SHA-1:     $SHA1"
echo "  SHA-256:   $SHA256"
