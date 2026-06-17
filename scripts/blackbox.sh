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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$(cd "$APP_DIR/../fitflex-functions" 2>/dev/null && pwd || true)"

API_BASE="${API_BASE:-http://localhost:3000}"
# Each journey runs in its own Patrol process (fresh app) for isolation.
TARGETS=(
  "integration_test/member_test.dart"
  "integration_test/owner_test.dart"
  "integration_test/trainer_test.dart"
  "integration_test/member_feedback_test.dart"
  "integration_test/owner_feedback_test.dart"
  "integration_test/trainer_feedback_test.dart"
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
  exec patrol develop --target "${TARGETS[0]}" "${DEVICE_ARGS[@]}" "${DEFINES[@]}"
fi

echo "==> Running Patrol blackbox journeys (one process each)…"
FAILED=()
for t in "${TARGETS[@]}"; do
  echo
  echo "────────────────────────────────────────────────────────"
  echo "▶ $t"
  echo "────────────────────────────────────────────────────────"
  if ! patrol test --target "$t" "${DEVICE_ARGS[@]}" "${DEFINES[@]}"; then
    FAILED+=("$t")
  fi
done

echo
echo "════════════════════ SUMMARY ════════════════════"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "✅ All ${#TARGETS[@]} journeys passed."
else
  echo "❌ ${#FAILED[@]}/${#TARGETS[@]} journeys failed:"
  printf '   - %s\n' "${FAILED[@]}"
  exit 1
fi
