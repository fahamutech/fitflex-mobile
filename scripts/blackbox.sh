#!/usr/bin/env bash
#
# FitFlex blackbox journey runner (Patrol-based).
# Drives the installed app on a connected device/emulator using widget-key and
# text finders (no screen-size coordinate taps), against the LOCAL backend via
# the dev mock-login (member / gym owner / trainer).
#
# Usage:
#   ./scripts/blackbox.sh                 # run all journeys
#   ./scripts/blackbox.sh --develop       # interactive (patrol develop) for one target
#   API_BASE=http://10.0.2.2:3000 ./scripts/blackbox.sh   # override backend (emulator)
#
# Requirements:
#   - patrol_cli:  dart pub global activate patrol_cli
#   - A device/emulator connected (adb devices)
#   - Backend running on :3000  (cd ../fitflex-functions && npm run dev:fs)
#
set -euo pipefail

# Patrol's CLI update check is unrelated to the test and can fail on an
# otherwise healthy offline/local run. CI mode disables only that check.
export CI="${CI:-true}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$(cd "$APP_DIR/../fitflex-functions" 2>/dev/null && pwd || true)"

API_BASE="${API_BASE:-http://localhost:3000}"
# Each journey runs in its own Patrol process (fresh app) for isolation.
TARGETS=(
  # Registration & login flows (create real accounts, sign in, cleanup)
  "integration_test/sign_in_flow_test.dart"
  "integration_test/register_login_test.dart"
  "integration_test/register_trainer_login_test.dart"
  # Core role journeys (dev-login smoke tests)
  "integration_test/member_test.dart"
  "integration_test/owner_test.dart"
  "integration_test/trainer_test.dart"
  "integration_test/role_choice_test.dart"
  "integration_test/direct_membership_test.dart"
  # Full UAT feedback matrices (physical-device regression)
  "integration_test/member_feedback_test.dart"
  "integration_test/owner_feedback_test.dart"
  "integration_test/trainer_feedback_test.dart"
  # Cross-role interaction flows
  "integration_test/member_booking_test.dart"
  "integration_test/member_booking_conflict_test.dart"
  "integration_test/member_trainer_enquiry_test.dart"
  "integration_test/trainer_booked_session_test.dart"
  # Marketplace flows
  "integration_test/vendor_marketplace_test.dart"
  "integration_test/marketplace_buyer_test.dart"
)

cd "$APP_DIR"

echo "==> Checking device…"
if ! adb get-state >/dev/null 2>&1; then
  echo "ERROR: no device. Connect a phone (USB debugging) or start an emulator." >&2
  exit 1
fi
adb devices -l | sed -n '2,$p'

echo "==> Checking local backend at $API_BASE …"
HEALTH_URL="${API_BASE/localhost/127.0.0.1}/health"
if ! curl -sf -m 5 "$HEALTH_URL" >/dev/null 2>&1; then
  echo "ERROR: backend not reachable at $HEALTH_URL" >&2
  if [ -n "$BACKEND_DIR" ]; then
    echo "       Start it with:  (cd \"$BACKEND_DIR\" && npm run dev:fs)" >&2
  fi
  exit 1
fi
echo "    backend OK"

# Bridge the phone's localhost:3000 to this machine (no-op for 10.0.2.2 emulator hosts).
if [[ "$API_BASE" == *localhost* || "$API_BASE" == *127.0.0.1* ]]; then
  echo "==> adb reverse tcp:3000 tcp:3000"
  adb reverse tcp:3000 tcp:3000 >/dev/null
fi

if ! command -v patrol >/dev/null 2>&1; then
  echo "ERROR: patrol_cli not found. Install:  dart pub global activate patrol_cli" >&2
  exit 1
fi

DEFINES=(--dart-define=API_BASE="$API_BASE" --dart-define=MOCK_AUTH=true)

# Optional device pin: ./scripts/blackbox.sh -d <id>  (or DEVICE env var)
DEVICE_ARGS=()
if [[ "${1:-}" == "-d" && -n "${2:-}" ]]; then
  DEVICE_ARGS=(-d "$2"); shift 2
elif [[ -n "${DEVICE:-}" ]]; then
  DEVICE_ARGS=(-d "$DEVICE")
fi

if [[ "${1:-}" == "--develop" ]]; then
  echo "==> patrol develop (interactive) — target: ${TARGETS[0]}"
  exec patrol develop --target "${TARGETS[0]}" ${DEVICE_ARGS[@]+"${DEVICE_ARGS[@]}"} "${DEFINES[@]}"
fi

# Pre-suite cleanup: remove leftover E2E test data from previous runs.
echo "==> Pre-suite cleanup of E2E test data…"
curl -sf -m 5 -X POST "${API_BASE/localhost/127.0.0.1}/auth/dev/cleanup" \
  -H 'content-type: application/json' \
  -d '{"emailPattern":"@e2e-test.fitflex.test"}' 2>/dev/null || echo "    (cleanup endpoint not available — continuing)"

echo "==> Running Patrol blackbox journeys (one process each)…"
FAILED=()
for t in "${TARGETS[@]}"; do
  echo
  echo "────────────────────────────────────────────────────────"
  echo "▶ $t"
  echo "────────────────────────────────────────────────────────"
  # USB reconnects clear reverse mappings. Re-apply immediately before every
  # target so a long multi-target run never silently loses the local backend.
  if [[ "$API_BASE" == *localhost* || "$API_BASE" == *127.0.0.1* ]]; then
    adb reverse tcp:3000 tcp:3000 >/dev/null
  fi
  if ! patrol test --target "$t" ${DEVICE_ARGS[@]+"${DEVICE_ARGS[@]}"} "${DEFINES[@]}"; then
    FAILED+=("$t")
  fi
done

# Post-suite cleanup: remove E2E test data created during this run.
echo
echo "==> Post-suite cleanup of E2E test data…"
curl -sf -m 5 -X POST "${API_BASE/localhost/127.0.0.1}/auth/dev/cleanup" \
  -H 'content-type: application/json' \
  -d '{"emailPattern":"@e2e-test.fitflex.test"}' 2>/dev/null || echo "    (cleanup endpoint not available)"

echo
echo "════════════════════ SUMMARY ════════════════════"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "✅ All ${#TARGETS[@]} journeys passed."
else
  echo "❌ ${#FAILED[@]}/${#TARGETS[@]} journeys failed:"
  printf '   - %s\n' "${FAILED[@]}"
  exit 1
fi
