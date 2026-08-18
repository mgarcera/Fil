#!/usr/bin/env bash
#
# driver.sh — build, launch and drive Fil in the iOS Simulator.
#
# Everything an agent needs to get from a clean checkout to a running app with
# seeded data and a screenshot on disk. Run from anywhere; paths resolve to the
# repo root.
#
#   .claude/skills/run-fil/driver.sh up            # boot + build + install + launch
#   .claude/skills/run-fil/driver.sh shot out.png  # screenshot to a file
#   .claude/skills/run-fil/driver.sh snapshot      # the widget's data contract
#
# Why a driver and not a README line: three things here are not guessable.
#   1. Several simulators share the name "iPhone 17 Pro Max" on different
#      runtimes. Selecting by name is a coin flip, and the one you get may not
#      be the one another tool is driving. `boot` resolves and prints a UUID,
#      and every later command reuses it via .sim-udid.
#   2. The app only has content if launched with -FilScreenshotMode, which wipes
#      the store and reseeds from Fil/Resources/DemoLibrary.json. Without it you
#      get a legitimately empty app and may think the launch failed.
#   3. The widget reads a JSON file out of the App Group container, and that
#      container path is a per-device UUID you have to ask simctl for. `snapshot`
#      does that lookup, so widget work can be verified without any UI at all.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
STATE="$ROOT/.claude/skills/run-fil/.sim-udid"

SCHEME="${FIL_SCHEME:-Fil}"
BID="${FIL_BID:-com.smidgecraft.Fil}"
SIM_NAME="${FIL_SIM:-iPhone 17 Pro Max}"
SETTLE="${FIL_SETTLE:-6}"

die() { echo "error: $*" >&2; exit 1; }

# Resolve to a UUID once and remember it. FIL_SIM_UDID overrides everything,
# which is how you point the driver at a simulator another tool already booted.
sim_udid() {
    if [ -n "${FIL_SIM_UDID:-}" ]; then echo "$FIL_SIM_UDID"; return; fi
    [ -f "$STATE" ] && { cat "$STATE"; return; }
    die "no simulator selected — run '$0 boot' first"
}

cmd_boot() {
    local udid
    udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)['devices']
# Prefer an already-booted match: attaching to a running device beats booting a
# second one that then competes for the Simulator window.
cands = [(d['udid'], d.get('state'), rt) for rt, ds in data.items() for d in ds if d['name'] == want]
if not cands:
    sys.exit('no available simulator named ' + want)
for u, st, rt in cands:
    if st == 'Booted':
        print(u); break
else:
    print(cands[0][0])
" "$SIM_NAME") || die "could not resolve a simulator named '$SIM_NAME'"

    echo "$udid" > "$STATE"
    echo "simulator: $SIM_NAME ($udid)"
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    open -a Simulator
    # Dark is the app's design context; the simulator launches light, which makes
    # every screenshot wrong in a way that looks like a styling bug.
    xcrun simctl ui "$udid" appearance dark >/dev/null 2>&1 || true
    echo "booted."
}

cmd_build() {
    # Braces are load-bearing: a bare $SCHEME followed by a multi-byte character
    # gets the character absorbed into the variable name under set -u.
    echo "building ${SCHEME}..."
    xcodebuild -project "$ROOT/Fil.xcodeproj" -scheme "$SCHEME" \
        -destination 'generic/platform=iOS Simulator' \
        -configuration Debug build 2>&1 | tail -3
}

app_path() {
    find ~/Library/Developer/Xcode/DerivedData/Fil-*/Build/Products/Debug-iphonesimulator \
        -maxdepth 1 -name "Fil.app" 2>/dev/null | head -1
}

cmd_install() {
    local udid app
    udid=$(sim_udid)
    app=$(app_path)
    [ -n "$app" ] || die "no built Fil.app found — run '$0 build' first"
    xcrun simctl install "$udid" "$app"
    echo "installed: $app"
}

# screen: "" (home) | folder:Yosemite | bin | compose | player | canvas | pinning
cmd_launch() {
    local udid screen args
    udid=$(sim_udid)
    screen="${1:-}"
    args=(-FilScreenshotMode)
    [ -n "$screen" ] && args+=(-FilScreenshotScreen "$screen")
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BID" "${args[@]}"
    sleep "$SETTLE"
    echo "launched${screen:+ on $screen}, settled ${SETTLE}s."
}

cmd_shot() {
    local udid out
    udid=$(sim_udid)
    out="${1:-$ROOT/.claude/skills/run-fil/shot.png}"
    xcrun simctl io "$udid" screenshot "$out" 2>/dev/null
    echo "$out"
}

# The pinned-folder JSON in the App Group container is what FilPinnedWidget
# decodes. Checking it verifies the widget's whole data path without adding a
# single widget to a home or lock screen.
cmd_snapshot() {
    local udid grp dir
    udid=$(sim_udid)
    grp=$(xcrun simctl get_app_container "$udid" "$BID" groups 2>/dev/null | head -1)
    [ -n "$grp" ] || die "no App Group container — has the app been installed and launched?"
    dir=$(echo "$grp" | awk '{print $NF}')
    python3 - "$dir/pinnedFolderSnapshot.json" <<'PY'
import json, sys, os
p = sys.argv[1]
if not os.path.exists(p):
    sys.exit("no pinnedFolderSnapshot.json yet — launch the app first (nothing pinned writes no file)")
d = json.load(open(p))
need = {"id", "name", "count", "blobs", "gradientStartHex", "gradientEndHex", "updatedAt"}
missing = need - set(d)
print(f"pinned: {d.get('name')}  count={d.get('count')}")
print(f"gradient: {d.get('gradientStartHex')} -> {d.get('gradientEndHex')}")
seeds = [b.get("seed") for b in d.get("blobs", [])]
print(f"blobs: {len(seeds)}  distinct seeds: {len(set(seeds))}")
print("decodes into PinnedFolderWidgetSnapshot:", "YES" if not missing else f"NO, missing {missing}")
if missing:
    sys.exit(1)
PY
}

# Marketing status bar: 9:41, full bars, charged, no carrier name.
#
# This drives the LOCK SCREEN's big clock too, not just the status bar strip — which is
# not what the command's name suggests, and is the only way to get 9:41 onto a locked
# screenshot. What it will NOT do is set the date: it forces a "Sat Jan 1" placeholder,
# and every ISO form the --help text promises is rejected outright (see SKILL.md). For a
# shot needing a believable date, clear this and set the Mac's clock instead — the
# simulator has no clock of its own.
cmd_statusbar() {
    local udid
    udid=$(sim_udid)
    if [ "${1:-on}" = "clear" ]; then
        xcrun simctl status_bar "$udid" clear
        echo "status bar overrides cleared — lock screen shows the host's real date and time"
        return
    fi
    # These exact flags are known-good together. Passing an ISO string to --time makes the
    # whole call fail with EINVAL, taking the battery and signal flags down with it.
    xcrun simctl status_bar "$udid" override \
        --time "9:41" --batteryState charged --batteryLevel 100 \
        --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 \
        --operatorName ""
    echo "status bar: 9:41, full bars, charged, no carrier (date will read 'Sat Jan 1')"
}

cmd_logs() {
    local udid
    udid=$(sim_udid)
    xcrun simctl spawn "$udid" log show --last "${1:-1m}" --style compact \
        --predicate "process == \"Fil\"" 2>/dev/null | tail -40
}

cmd_stop() {
    local udid
    udid=$(sim_udid)
    xcrun simctl terminate "$udid" "$BID" >/dev/null 2>&1 || true
    echo "app terminated (simulator left booted — shutting it down costs a slow re-boot next run)"
}

cmd_up() {
    cmd_boot
    cmd_build
    cmd_install
    cmd_launch "${1:-}"
    cmd_snapshot || true
}

case "${1:-up}" in
    boot)      cmd_boot ;;
    build)     cmd_build ;;
    install)   cmd_install ;;
    launch)    cmd_launch "${2:-}" ;;
    shot)      cmd_shot "${2:-}" ;;
    snapshot)  cmd_snapshot ;;
    statusbar) cmd_statusbar "${2:-on}" ;;
    logs)      cmd_logs "${2:-1m}" ;;
    stop)      cmd_stop ;;
    up)        cmd_up "${2:-}" ;;
    *)         die "unknown command '$1' (boot|build|install|launch|shot|snapshot|statusbar|logs|stop|up)" ;;
esac
