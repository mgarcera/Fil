#!/usr/bin/env bash
#
# Captures the marketing / App Store screenshot set from the simulator.
#
#   Scripts/capture-screenshots.sh            # build, then shoot everything
#   Scripts/capture-screenshots.sh --no-build # reshoot without rebuilding
#
# What it does, and why each step is there:
#   • forces dark appearance — the sim launches light, which is wrong for every shot
#   • overrides the status bar to 9:41 / full bars / charged, the marketing convention
#   • launches with -FilScreenshotMode, which wipes the store and reseeds it from
#     Fil/Resources/DemoLibrary.json so every run is identical
#   • picks the screen with -FilScreenshotScreen rather than `simctl openurl`, because
#     opening a fil:// URL from outside the app makes iOS show an "Open in Fil?" prompt
#     that can't be dismissed unattended and lands in the middle of the frame
#
# Edit the content of the shots in Fil/Resources/DemoLibrary.json — not here, and not in
# the UI. Edit which shots get taken in the SHOTS array below.
#
# NOT captured here: the lock screen, Dynamic Island, Today view, and Control Center.
# Simulators can't lock, so those surfaces have to come from a real device.

set -euo pipefail

SIM="${FIL_SIM:-iPhone 17 Pro Max}"
SCHEME="Fil"
BID="com.masongarcera.Fil"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/AppStore/screenshots"
SETTLE="${FIL_SETTLE:-7}"   # seconds to let the launch animation and reveals finish

# name|screen argument ("" = home)
SHOTS=(
  "01-home|"
  "02-folder-yosemite|folder:Yosemite"
  "03-folder-move|folder:The move"
  "04-bin|bin"
  "05-compose|compose"
)

cd "$ROOT"
mkdir -p "$OUT"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "▸ building for $SIM"
  xcodebuild -project Fil.xcodeproj -scheme "$SCHEME" -configuration Debug \
    -destination "platform=iOS Simulator,name=$SIM" build > /tmp/fil-capture-build.log 2>&1 \
    || { echo "build failed — see /tmp/fil-capture-build.log"; exit 1; }
fi

# Ask the build system for the product path rather than guessing DerivedData.
eval "$(xcodebuild -project Fil.xcodeproj -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$SIM" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ TARGET_BUILD_DIR =/{print "DIR=\""$2"\""} / FULL_PRODUCT_NAME =/{print "NAME=\""$2"\""}')"
APP="$DIR/$NAME"
[[ -d "$APP" ]] || { echo "no built app at $APP — run without --no-build"; exit 1; }

echo "▸ preparing $SIM"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b > /dev/null
xcrun simctl ui "$SIM" appearance dark > /dev/null
xcrun simctl status_bar "$SIM" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3
xcrun simctl uninstall "$SIM" "$BID" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"

for entry in "${SHOTS[@]}"; do
  name="${entry%%|*}"
  screen="${entry#*|}"
  xcrun simctl terminate "$SIM" "$BID" 2>/dev/null || true
  if [[ -n "$screen" ]]; then
    xcrun simctl launch "$SIM" "$BID" --args -FilScreenshotMode -FilScreenshotScreen "$screen" > /dev/null
  else
    xcrun simctl launch "$SIM" "$BID" --args -FilScreenshotMode > /dev/null
  fi
  sleep "$SETTLE"
  xcrun simctl io "$SIM" screenshot "$OUT/$name.png" > /dev/null 2>&1
  echo "  ✓ $name.png"
done

echo "▸ $(ls -1 "$OUT"/*.png | wc -l | tr -d ' ') shots in AppStore/screenshots/"
sips -g pixelWidth -g pixelHeight "$OUT/01-home.png" 2>/dev/null | tail -2
