---
name: run-fil
description: Build, run, launch, screenshot and drive the Fil iOS app in the simulator, and verify the pinned-folder widget's data. Use when asked to run Fil, start the app, take a screenshot of a screen, check a change in the real app, or verify widget/Live Activity data.
---

# Run Fil

Fil is an iOS app (SwiftUI) plus a widget extension (`FilPinnedWidget`) and a share
extension. It is driven through `xcrun simctl` — there is no headless mode and no web
surface. **The driver is `.claude/skills/run-fil/driver.sh`.**

All paths below are relative to the repo root (`Fil/`, the directory holding `Fil.xcodeproj`).

## Prerequisites

Xcode with an iOS Simulator runtime. Nothing to install — no Homebrew packages are
needed, and note that `timeout(1)` is **not** present on macOS, so don't reach for it.

## Run (agent path)

One command takes you from a cold machine to a running, seeded app:

```bash
.claude/skills/run-fil/driver.sh up
```

That boots a simulator, builds, installs, launches with seeded demo data, and prints the
widget's data contract. Expected tail:

```
launched, settled 6s.
pinned: Yosemite  count=5
gradient: #408CD9 -> #6659CC
blobs: 5  distinct seeds: 5
decodes into PinnedFolderWidgetSnapshot: YES
```

Then drive it:

```bash
.claude/skills/run-fil/driver.sh shot /tmp/fil.png      # screenshot -> prints the path
.claude/skills/run-fil/driver.sh launch "folder:The move"  # jump to a screen
.claude/skills/run-fil/driver.sh snapshot               # widget data contract only
.claude/skills/run-fil/driver.sh statusbar              # 9:41 marketing status bar
.claude/skills/run-fil/driver.sh statusbar clear        # back to the host's real clock
.claude/skills/run-fil/driver.sh logs 30s               # app log lines
.claude/skills/run-fil/driver.sh stop                   # terminate app, leave sim booted
```

**Always open the screenshot and look at it.** A launch that "succeeds" can still put a
blank or empty screen on the display — see the `-FilScreenshotMode` gotcha below.

Screens accepted by `launch`, from `Scripts/capture-screenshots.sh`: `` (home),
`folder:<name>`, `bin`, `compose`, `player`, `canvas`, `pinning`.

Overrides: `FIL_SIM_UDID` (target a specific simulator), `FIL_SIM` (device name,
default `iPhone 17 Pro Max`), `FIL_SETTLE` (post-launch seconds, default 6).

## Marketing screenshots: the clock

`driver.sh statusbar` sets 9:41, full bars, charged, no carrier name.

**It also drives the lock screen's big clock**, which the command's name does not suggest —
and it is the only way to get 9:41 onto a locked screenshot.

**It cannot set the date.** The override forces a `Sat Jan 1` placeholder. The `--help` text
claims *"If the string is a valid ISO date string it will also set the date on relevant
devices"* — **that is false on this runtime.** Every one of these was rejected outright:

```
2026-08-17T09:41:00Z         rejected
2026-08-17T09:41:00+00:00    rejected
2026-08-17 09:41:00          rejected
2026-08-17T09:41             rejected
Mon Aug 17 9:41              rejected
```

`--time` takes a bare clock string and nothing else. Worse, an ISO string doesn't degrade —
it fails the *whole* call with EINVAL, silently taking the battery and signal flags with it,
so you get no overrides at all rather than a partial set.

**For a shot that needs a believable date:** run `statusbar clear` and set the **Mac's** clock
(System Settings → General → Date & Time → turn off "Set automatically"). The simulator has
no clock of its own — it reads the host's, so the lock screen then shows exactly what you set.
Put the Mac's clock back afterwards; while it's wrong, TLS validation and git timestamps are
too.

## Verifying widget work without any UI

`FilPinnedWidget` reads `pinnedFolderSnapshot.json` from the App Group container. The
`snapshot` command finds that per-device container path and checks the JSON decodes into
`PinnedFolderWidgetSnapshot`. That validates the widget's entire data path without adding
a widget to a home or lock screen — do this first, because a widget that renders nothing
is usually a data problem, not a layout one.

`distinct seeds` in its output matters: the blob silhouettes are only distinguishable
from each other if their seeds differ.

## Run (human path)

Open `Fil.xcodeproj` and hit Run. Useful for the SwiftUI preview canvas; useless for
anything scripted.

## Gotchas

- **Without `-FilScreenshotMode` the app launches genuinely empty** and looks like a
  failed launch. The flag wipes the store and reseeds from
  `Fil/Resources/DemoLibrary.json`, so every run is identical. The driver always passes
  it. Edit demo content in that JSON, never in the UI.
- **Several simulators share the name "iPhone 17 Pro Max"** across runtimes, so selecting
  by name is nondeterministic and you can end up driving a different device than another
  tool is watching. `driver.sh boot` resolves to a UUID, prefers an already-booted match,
  and caches it in `.claude/skills/run-fil/.sim-udid`.
- **There is no `simctl lock`.** The simulator locks with ⌘L in the Simulator app, and
  driving that through `osascript`/System Events **hangs** without macOS Accessibility
  permission — it blocks until killed rather than erroring. Don't script the lock screen;
  lock it by hand.
- **The headless preview renderer cannot render accessory (lock-screen) widget families.**
  `RenderPreview` on `#Preview(as: .accessoryRectangular)` returns a correctly-sized
  canvas containing **zero non-transparent pixels** — and so does `.accessoryCircular`,
  including Apple's own `AccessoryWidgetBackground()`. `systemSmall` renders fine through
  the same code, so this is a renderer limitation, not a bug in the widget. Verify
  `systemSmall` via preview; verify accessory families by hand on a locked simulator.
- **Xcode's MCP device-interaction tools are not usable here.** They accept only devices
  from their own runtime list (which may exclude the one you booted), they require a
  subagent, and their command vocabulary lives in a `device-interaction` skill that is not
  installed on this machine.
- **`simctl openurl` with a `fil://` URL raises an undismissable "Open in Fil?" prompt**
  that lands mid-frame. This is why screen selection uses the `-FilScreenshotScreen`
  launch argument instead. (Documented in `Scripts/capture-screenshots.sh`; not
  re-verified here.)
- **Only moving screens can be recorded.** `simctl io recordVideo` emits frames on display
  change, so a static screen yields a ~0.06s file rather than a still clip of the right
  length. A folder interior has to be a still. (Also from the capture script.)

## Troubleshooting

| Symptom | Fix |
|---|---|
| `no simulator selected — run './driver.sh boot' first` | Run `driver.sh boot`, or set `FIL_SIM_UDID`. |
| `no built Fil.app found` | Run `driver.sh build`. The driver looks in `~/Library/Developer/Xcode/DerivedData/Fil-*/Build/Products/Debug-iphonesimulator`. |
| `no pinnedFolderSnapshot.json yet` | Nothing is pinned. Launch with `-FilScreenshotMode` (the driver does) — the seed pins Yosemite. |
| `unbound variable` from the driver after an edit | A `$VAR` was followed by a multi-byte character (e.g. `…`), which gets absorbed into the variable name under `set -u`. Brace it: `${VAR}`. |
| Screenshot is blank / all black | The app didn't finish launching. Raise `FIL_SETTLE`. |
| `status_bar override` fails with `Invalid argument` / EINVAL | An ISO date string was passed to `--time`. Use a bare clock string (`"9:41"`). The whole call fails, so no overrides get set at all. |
| Lock screen date reads `Sat Jan 1` | A status bar override is active. `driver.sh statusbar clear`, then set the Mac's clock if you need a specific date. |
| `command not found: timeout` | macOS has no `timeout(1)`. Use a background process and `sleep`. |

## Test

```bash
xcodebuild -project Fil.xcodeproj -scheme Fil -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

Builds app, widget extension and share extension. `driver.sh build` wraps this and prints
only the tail.
