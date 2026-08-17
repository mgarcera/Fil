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
.claude/skills/run-fil/driver.sh logs 30s               # app log lines
.claude/skills/run-fil/driver.sh stop                   # terminate app, leave sim booted
```

**Always open the screenshot and look at it.** A launch that "succeeds" can still put a
blank or empty screen on the display — see the `-FilScreenshotMode` gotcha below.

Screens accepted by `launch`, from `Scripts/capture-screenshots.sh`: `` (home),
`folder:<name>`, `bin`, `compose`, `player`, `canvas`, `pinning`.

Overrides: `FIL_SIM_UDID` (target a specific simulator), `FIL_SIM` (device name,
default `iPhone 17 Pro Max`), `FIL_SETTLE` (post-launch seconds, default 6).

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
| `command not found: timeout` | macOS has no `timeout(1)`. Use a background process and `sleep`. |

## Test

```bash
xcodebuild -project Fil.xcodeproj -scheme Fil -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

Builds app, widget extension and share extension. `driver.sh build` wraps this and prints
only the tail.
