#!/bin/bash
#
# Bygger Faver och skickar den till TestFlight.
#
#   ./scripts/testflight.sh              bygg och skicka
#   ./scripts/testflight.sh --bara-bygg  bygg och kontrollera, skicka inte
#
# Till skillnad från Ullared, som byggs i Expos moln, byggs Faver här på
# maskinen. Det är ett vanligt Xcode-projekt, så vägen går rakt till Apple.
#
# Signeringen ligger i nyckelknippan faver-signing, utanför repot. Skapades en
# gång; certifikatet går ut 2027-09-22 och måste förnyas då.
#
# Byggnumret hämtas från Apple och räknas upp. Apple vägrar ta emot ett
# byggnummer som redan finns, och att hålla siffran i projektfilen betyder att
# den glöms bort. Versionen (MARKETING_VERSION) styrs däremot i Xcode.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID=6814968962
BUNDLE=com.jezper.Faver
TEAM=SUPDJZHQDA
PROFILE="Faver App Store"
IDENTITY="Apple Distribution: Lorne Holding AB ($TEAM)"
KC="$HOME/Library/Keychains/faver-signing.keychain-db"
PASS_FILE="$HOME/.apple-signing/keychain-pass"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

CONF="$HOME/.appstore-api"
[ -f "$CONF" ] || { echo "saknar $CONF"; exit 1; }
# shellcheck disable=SC1090
set -a; . "$CONF"; set +a

SUBMIT=yes
[ "${1:-}" = "--bara-bygg" ] && SUBMIT=no

log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$1"; }
die() { log "MISSLYCKADES: $1"; exit 1; }

[ -f "$PASS_FILE" ] || die "saknar $PASS_FILE, signeringen är inte uppsatt"
[ -d /Applications/Xcode.app ] || die "Xcode saknas"

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

echo
log "kör de snabba testerna"
scripts/test.sh || die "testerna"

log "låser upp nyckelknippan"
security unlock-keychain -p "$(cat "$PASS_FILE")" "$KC" || die "nyckelknippan"

log "frågar Apple vilket byggnummer som är taget"
LATEST=$(scripts/asc.sh GET "/v1/builds?filter\[app\]=$APP_ID&sort=-version&limit=1" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['data'][0]['attributes']['version'] if d.get('data') else 0)
")
BUILD=$((LATEST + 1))
VERSION=$(grep -m1 'MARKETING_VERSION = ' Faver/Faver.xcodeproj/project.pbxproj | sed 's/.*= //;s/;//')
log "bygger version $VERSION, byggnummer $BUILD"

xcodebuild -project Faver/Faver.xcodeproj -scheme Faver -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Faver.xcarchive" archive \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KC" \
  > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; die "bygget"; }

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$IDENTITY</string>
  <key>provisioningProfiles</key>
  <dict><key>$BUNDLE</key><string>$PROFILE</string></dict>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

log "paketerar"
xcodebuild -exportArchive -archivePath "$OUT/Faver.xcarchive" \
  -exportPath "$OUT/export" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  > "$OUT/export.log" 2>&1 || { tail -40 "$OUT/export.log"; die "paketeringen"; }

IPA="$OUT/export/Faver.ipa"
SIZE=$(du -h "$IPA" | cut -f1)
log "klart, $SIZE"

# Valideringen fångar det Apple annars avvisar efter uppladdningen, och tar
# under en minut. Uppladdningen tar lika lång tid, så det kostar inget att
# alltid göra båda.
log "validerar hos Apple"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
  > "$OUT/validate.log" 2>&1 || { tail -20 "$OUT/validate.log"; die "valideringen"; }
log "inga fel"

if [ "$SUBMIT" = no ]; then
  cp "$IPA" ./Faver.ipa
  log "skickade inte. Bygget ligger i ./Faver.ipa"
  exit 0
fi

log "laddar upp"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
  > "$OUT/upload.log" 2>&1 || { tail -20 "$OUT/upload.log"; die "uppladdningen"; }

echo
log "uppe hos Apple. Version $VERSION, byggnummer $BUILD."
echo
echo "  Apple bearbetar bygget, ungefär en kvart. Sedan dyker det upp i"
echo "  TestFlight på telefonen av sig självt, gruppen Team får alla byggen."
echo "  Följ det med: scripts/status.sh"
