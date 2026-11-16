#!/bin/bash
# Takes screenshots of the Apple Watch app in a watch simulator.
# Usage: scripts/watch-screenshots.sh <path/to/InkstoneWatch.app> <output-dir>
set -euo pipefail
APP="$1"; OUT="$2"
mkdir -p "$OUT"
if [ ! -d "$APP" ]; then echo "no watch app at $APP"; exit 1; fi
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")

# Newest watchOS runtime, preferring a large current watch.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
d = json.load(sys.stdin)["devices"]
runtimes = sorted((k for k in d if "watchOS" in k), key=lambda k: [int(x) for x in re.findall(r"\d+", k)])
for rt in reversed(runtimes):
    watches = [x for x in d[rt] if x["name"].startswith("Apple Watch")]
    def score(x):
        n = x["name"]
        return (("46mm" in n) or ("45mm" in n), "Series" in n, "Ultra" not in n)
    watches.sort(key=score, reverse=True)
    if watches:
        print(watches[0]["udid"]); break
')
if [ -z "$UDID" ]; then
  RT=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
r = [x for x in json.load(sys.stdin)["runtimes"] if x.get("platform") == "watchOS" and x.get("isAvailable")]
print(r[-1]["identifier"] if r else "")')
  DT=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
t = [x["identifier"] for x in json.load(sys.stdin)["devicetypes"] if "Apple Watch" in x["name"] and ("46mm" in x["name"] or "45mm" in x["name"])]
print(t[-1] if t else "")')
  if [ -z "$RT" ] || [ -z "$DT" ]; then echo "no watchOS simulator runtime on this machine"; exit 1; fi
  UDID=$(xcrun simctl create "Inkstone Watch" "$DT" "$RT")
fi
xcrun simctl list devices | grep "$UDID" || true

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

for name in watch-home watch-carousel watch-review watch-write watch-face watch-settings; do
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screenshot "$name" >/dev/null
  sleep 8
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 && echo "shot $name"
done
xcrun simctl terminate "$UDID" "$BUNDLE" || true
