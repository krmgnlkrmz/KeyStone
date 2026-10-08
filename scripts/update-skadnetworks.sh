#!/usr/bin/env bash
# Fetches Google's published SKAdNetwork identifiers and rewrites the SKAdNetworkItems block in App/Info.plist.
#   --print   only print the list
set -euo pipefail
cd "$(dirname "$0")/.."
URL="https://developers.google.com/admob/ios/3p-skadnetworks"
IDS=$(curl -fsSL "$URL" | grep -oE "[a-z0-9]{10}\.skadnetwork" | awk '!seen[$0]++')
COUNT=$(echo "$IDS" | grep -c . || true)
[ "$COUNT" -gt 10 ] || { echo "Could not read the list from $URL (got $COUNT ids)"; exit 1; }
if [ "${1:-}" = "--print" ]; then echo "$COUNT identifiers:"; echo "$IDS"; exit 0; fi
python3 - "$IDS" <<'PY'
import re, sys
ids = sys.argv[1].split()
items = "\n".join(f"\t\t<dict>\n\t\t\t<key>SKAdNetworkIdentifier</key>\n\t\t\t<string>{i}</string>\n\t\t</dict>" for i in ids)
p = "App/Info.plist"
s = open(p, encoding="utf-8").read()
s = re.sub(r"(<key>SKAdNetworkItems</key>\s*<array>).*?(\s*</array>)", lambda m: m.group(1) + "\n" + items + m.group(2), s, flags=re.S)
open(p, "w", encoding="utf-8").write(s)
print(f"Wrote {len(ids)} SKAdNetwork identifiers to {p}")
PY
