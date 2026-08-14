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
# Produces both stills (PNG) and clips (MOV, via `simctl io recordVideo`). The clips feed the
# website's frame rows, where a still sits dead next to four moving ones.
#
# NOT captured here: the lock screen, Dynamic Island, Today view, and Control Center. Those are
# recorded by hand today. An earlier version of this comment claimed simulators can't show a lock
# screen and that a device was required — that is wrong (Simulator ⌘L locks), so the boundary is
# "not automated yet", not "impossible". See docs/v1-route.md.

set -euo pipefail

SIM="${FIL_SIM:-iPhone 17 Pro Max}"
SCHEME="Fil"
BID="com.masongarcera.Fil"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/AppStore/screenshots"
SETTLE="${FIL_SETTLE:-7}"   # seconds to let the launch animation and reveals finish

# Stills. name|screen argument ("" = home)
SHOTS=(
  "01-home|"
  "02-folder-yosemite|folder:Yosemite"
  "03-folder-move|folder:The move"
  "04-bin|bin"
  "05-compose|compose"
)

# Clips for the website's frame rows, where a still would sit dead. name|screen|seconds.
# `player` opens the first seeded fil that has audio and starts it playing; `canvas` raises
# the screensaver named in DemoLibrary.json without waiting out the 60s idle timer.
#
# ONLY MOVING SCREENS CAN BE RECORDED. `simctl io recordVideo` emits frames on display change,
# so a screen that holds still yields a ~0.06s file rather than a static clip of the right
# length. Measured over 5s: player 5.8s, screensaver 7.8s, compose 4.8s, home 4.8s — and a
# folder interior 0.06s, because nothing in it moves. A folder therefore has to be a still.
CLIPS=(
  "06-player|player|6"
  "07-screensaver|canvas|8"
  "08-home-canvas||5"
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

for entry in "${CLIPS[@]}"; do
  name="${entry%%|*}"; rest="${entry#*|}"
  screen="${rest%%|*}"; secs="${rest##*|}"
  xcrun simctl terminate "$SIM" "$BID" 2>/dev/null || true
  xcrun simctl launch "$SIM" "$BID" --args -FilScreenshotMode -FilScreenshotScreen "$screen" > /dev/null
  sleep "$SETTLE"
  # recordVideo runs until interrupted, so it goes to the background and takes a SIGINT.
  # --force overwrites a previous take rather than failing the run.
  xcrun simctl io "$SIM" recordVideo --codec h264 --force "$OUT/$name.mov" > /dev/null 2>&1 &
  rec=$!
  sleep "$secs"
  kill -INT "$rec" 2>/dev/null || true
  wait "$rec" 2>/dev/null || true
  # recordVideo finalizes the container after the signal. Starting the next take immediately
  # produced a 0.06s file, so give the encoder a beat to let go before the next launch.
  sleep 2
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$name.mov" 2>/dev/null | cut -c1-4)
  echo "  ✓ $name.mov (${dur}s)"
  # A clip far shorter than asked for means the recorder never really started — worth failing
  # loudly, because the file still exists and looks like a successful capture.
  awk -v d="${dur:-0}" -v w="$secs" 'BEGIN { if (d < w * 0.5) exit 1 }' \
    || echo "    ⚠ expected ~${secs}s — recorder likely did not start"
done

echo "▸ $(ls -1 "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ') stills, $(ls -1 "$OUT"/0[6-8]-*.mov 2>/dev/null | wc -l | tr -d ' ') clips in AppStore/screenshots/"
sips -g pixelWidth -g pixelHeight "$OUT/01-home.png" 2>/dev/null | tail -2
