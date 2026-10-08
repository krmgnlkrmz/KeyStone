#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator on the newest iOS runtime (prefers "iPhone 16").
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, sys, re
data = json.load(sys.stdin)["devices"]
def ver(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
best = None
for rt, devs in data.items():
    if "iOS" not in rt: continue
    for d in devs:
        if not d["name"].startswith("iPhone"): continue
        score = (ver(rt), d["name"] == "iPhone 16", "Pro" not in d["name"])
        if best is None or score > best[0]: best = (score, d["udid"], d["name"], rt)
if not best: sys.exit("no iPhone simulator")
print(f"Using {best[2]} on {best[3]}", file=sys.stderr)
print(best[1])
'
