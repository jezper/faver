#!/bin/bash
#
# Kör de snabba testerna: reglerna för stunder, burst-set och genomgångsstatus.
#
#   ./scripts/test.sh
#
# Tar sekunder när simulatorn redan är igång, och körs automatiskt före varje
# TestFlight-bygge. Gränssnittstesterna ligger i ./scripts/uitest.sh och tar
# många minuter, så de körs när vi vill, inte varje gång.

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM="${FAVER_SIM:-iPhone 17 Pro}"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

xcodebuild test \
  -project Faver/Faver.xcodeproj \
  -scheme Faver \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$SIM" \
  -only-testing:FaverTests \
  > "$LOG" 2>&1 || true

grep -E "✘|error:" "$LOG" | head -30 || true
grep -E "✔ Test run" "$LOG" || true

if ! grep -q "TEST SUCCEEDED" "$LOG"; then
  echo
  echo "  Testerna föll. Hela loggen:"
  tail -40 "$LOG"
  exit 1
fi
