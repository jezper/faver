#!/bin/bash
#
# Visar var byggena ligger just nu.
#
#   ./scripts/status.sh

set -euo pipefail
cd "$(dirname "$0")/.."
APP_ID=6814968962

scripts/asc.sh GET "/v1/builds?filter\[app\]=$APP_ID&sort=-uploadedDate&limit=5" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if 'errors' in d:
    print('Kunde inte fråga Apple:', d['errors'][0].get('detail', ''))
    raise SystemExit(1)
b = d.get('data', [])
if not b:
    print('Inget bygge hos Apple ännu. Ett nyss uppladdat bygge syns efter några minuter.')
    raise SystemExit
lage = {
    'PROCESSING': 'bearbetas av Apple',
    'FAILED':     'avvisat av Apple',
    'INVALID':    'ogiltigt',
    'VALID':      'klart, ligger i TestFlight',
}
for x in b:
    a = x['attributes']
    s = a['processingState']
    print(f\"  bygge {a['version']:>4}  {lage.get(s, s):<28} uppladdat {a['uploadedDate'][:16].replace('T',' ')}\")
"
