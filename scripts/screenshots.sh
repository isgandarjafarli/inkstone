#!/bin/bash
# Takes a screenshot of every screen in the simulator, in light and dark mode.
# Usage: scripts/screenshots.sh <simulator-udid> <path/to/Inkstone.app> <output-dir>
set -euo pipefail
UDID="$1"; APP="$2"; OUT="$3"
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
mkdir -p "$OUT"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiBars 3 || true

SCREENS="onboarding-0 onboarding-1 onboarding-3 today review words progress word word-long char settings
session-learn session-meaning session-word session-listening session-tones session-recall session-writing
widgets-lock widgets-home widgets-large"
DARK="onboarding-0 today word char session-learn session-meaning widgets-home widgets-large progress"

shoot() {
  local mode="$1" name="$2"
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screenshot "$name" >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$mode-$name.png" >/dev/null 2>&1
  echo "shot $mode-$name"
}

xcrun simctl ui "$UDID" appearance light
for s in $SCREENS; do shoot light "$s"; done
xcrun simctl ui "$UDID" appearance dark
for s in $DARK; do shoot dark "$s"; done
xcrun simctl terminate "$UDID" "$BUNDLE" || true
