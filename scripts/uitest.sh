#!/bin/bash
#
# Kör gränssnittstesterna mot ett riktigt fotobibliotek i simulatorn.
#
#   ./scripts/uitest.sh
#
# Tar många minuter. Körs när vi rört något i flödena, inte vid varje bygge.
#
# Ordningen spelar roll. Appen måste vara installerad innan den kan få
# fotobehörighet, annars installerar testkörningen över behörigheten och appen
# möts av välkomstskärmen i stället för ett bibliotek. Därför byggs och installeras
# den först, får behörighet sedan, och testerna körs utan att bygga om.

set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM="${FAVER_SIM:-iPhone 17 Pro}"
BUNDLE=com.jezper.Faver
DERIVED="${TMPDIR:-/tmp}/faver-uitest-derived"

log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$1"; }
die() { log "MISSLYCKADES: $1"; exit 1; }

SEED=$(mktemp -d)
trap 'rm -rf "$SEED"' EXIT

log "startar simulatorn $SIM"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b > /dev/null

log "bygger appen och testerna"
xcodebuild build-for-testing \
  -project Faver/Faver.xcodeproj \
  -scheme Faver \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DERIVED" \
  > /dev/null 2>&1 || die "bygget"

APP=$(find "$DERIVED/Build/Products" -maxdepth 2 -name "Faver.app" | head -1)
[ -n "$APP" ] || die "hittar inte den byggda appen"

log "bygger bilderna"
xcrun swift scripts/seed-photos.swift "$SEED" > /dev/null || die "bildbygget"

log "fyller simulatorns fotobibliotek"
# Ett bibliotek som växer för varje körning ger olika svar varje gång, så appen
# nollställs först. Bilderna ligger kvar mellan körningar, vilket är avsiktligt:
# de är identiska varje gång och att lägga in dem tar tid.
xcrun simctl uninstall "$SIM" "$BUNDLE" 2>/dev/null || true
for f in "$SEED"/*.jpg; do xcrun simctl addmedia "$SIM" "$f"; done

log "installerar appen och ger den fotobehörighet"
xcrun simctl install "$SIM" "$APP"

# simctl privacy grant skriver en rad i behörighetsdatabasen, men med värdet 0,
# vilket betyder nekad. Appen möts då av välkomstskärmen och varje test väntar ut
# sin tid på ett kort som aldrig kan dyka upp. Värdet sätts därför direkt.
# Simulatorn måste stå still medan databasen skrivs.
UDID=$(xcrun simctl list devices -j | python3 -c "
import json, sys
name = sys.argv[1]
for runtime in json.load(sys.stdin)['devices'].values():
    for device in runtime:
        if device['name'] == name and device['isAvailable']:
            print(device['udid']); raise SystemExit
" "$SIM")
[ -n "$UDID" ] || die "hittar inte simulatorn $SIM"

TCC="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"
xcrun simctl privacy "$SIM" grant photos "$BUNDLE" 2>/dev/null || true
xcrun simctl shutdown "$UDID" 2>/dev/null || true
sqlite3 "$TCC" "update access set auth_value = 2 where client = '$BUNDLE' and service = 'kTCCServicePhotos';" \
  || die "kunde inte sätta fotobehörigheten"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null

log "kör testerna"
xcodebuild test-without-building \
  -project Faver/Faver.xcodeproj \
  -scheme Faver \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$DERIVED" \
  -only-testing:FaverUITests \
  2>&1 | grep -E "Test Case .* (passed|failed)|error:|TEST SUCCEEDED|TEST FAILED" || true
