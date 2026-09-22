#!/bin/bash
#
# Pratar med Apples App Store Connect-API.
#
#   scripts/asc.sh GET /v1/builds
#   scripts/asc.sh POST /v1/betaGroups '{"data":...}'
#
# Nyckeln ligger i ~/.appstore-api och ~/.appstore-key.p8, utanför repot.
# Den är privat och ger tillgång till hela Apple-kontot.
#
# Apple vill ha ett signerat pass (JWT) i varje anrop. Maskinen saknar
# python-bibliotek för det, så passet signeras med openssl och signaturen
# räknas om från DER till det råformat Apple kräver.

set -euo pipefail

CONF="$HOME/.appstore-api"
[ -f "$CONF" ] || { echo "saknar $CONF"; exit 1; }
# shellcheck disable=SC1090
set -a; . "$CONF"; set +a
[ -f "$ASC_KEY_PATH" ] || { echo "saknar nyckelfilen $ASC_KEY_PATH"; exit 1; }

NOW=$(date +%s); EXP=$((NOW+600))
b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
HDR=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | b64)
PL=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$ASC_ISSUER_ID" "$NOW" "$EXP" | b64)
SIGNIN="$HDR.$PL"
DER=$(printf '%s' "$SIGNIN" | openssl dgst -sha256 -sign "$ASC_KEY_PATH" | xxd -p | tr -d '\n')
RS=$(python3 - "$DER" <<'PY'
import sys
d = bytes.fromhex(sys.argv[1]); i = 2
if d[1] & 0x80: i = 2 + (d[1] & 0x7f)
def rd(b, i):
    l = b[i+1]; v = b[i+2:i+2+l]
    return v.lstrip(b'\x00').rjust(32, b'\x00'), i+2+l
r, i = rd(d, i); s, _ = rd(d, i)
print((r+s).hex())
PY
)
SIG=$(printf '%s' "$RS" | xxd -r -p | b64)
TOKEN="$SIGNIN.$SIG"

M=${1:-GET}; P=$2; B=${3:-}
if [ -n "$B" ]; then
  curl -s -X "$M" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$B" "https://api.appstoreconnect.apple.com$P"
else
  curl -s -X "$M" -H "Authorization: Bearer $TOKEN" "https://api.appstoreconnect.apple.com$P"
fi
