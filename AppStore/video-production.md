# Fil — Video Production Sheet

*Revised 2026-08-18 from the video brief, after a read check and an asset probe.*

Strategy — promise, audience, concept ("The Pattern"), placements, on-screen text — stands as
briefed. This sheet supersedes the brief's **shot lists** and **needs-filming list** only.

Two changes made against the brief:
- **15s:** pinning cut. It is a mechanism shot and it was occupying the payoff slot, showing the
  folder *changing* at the moment the film argues it is *everywhere*. Pinning keeps its home in
  the 30s. The 15s is now four doors and nothing else.
- **30s:** the screensaver reveal cut. Four consecutive interiors read as the feature list the
  brief warns against; three with distinct jobs do not. The reclaimed 2.5s goes to the Turn,
  which is the pivot and had no valid source anyway.

---

## What the asset probe found

| Finding | Detail |
|---|---|
| **The Turn had no source** | The brief asked `lock screen.mp4` for 2.5–4.7s. The file is **3.885s**. Overrun by 0.8s. Recapture. |
| **Everything is variable frame rate** | Average rates run 20.86 → 133.16 fps across the eleven captures. Change-triggered screen recordings, not CFR. Conform before editing. |
| **Two `lock screen` files** | `.mp4` is 1320×2868 H.264 VFR. `.mov` is **1080×1920 HEVC 60fps** — different device, different aspect. Do not mix them up. |
| **The seam is not mp4-vs-mov** | `lock screen.mov` is also Aug 13. The Aug 14 batch is `06-player`, `07-screensaver`, `08-home-canvas`, `09-pinning`, and the 30s crosses that line at 9.5s. |
| **Numbering collides** | The Aug 14 batch reuses the Aug 13 indices — two `06`s, two `07`s, two `08`s. |
| **Two orphan captures** | `06-action button.mp4` and `10-control center.mp4` appear in neither film. If those are real doors they strengthen the pattern. Decide. |
| **`today view.mp4` has no handles** | 4.380s against a requested 2.5–4.4. |

---

## The 15s — hook, demo, payoff · 5 shots

Four doors, one folder, no mechanism. The rhythm is the argument.

| Time | Hold | Beat | Shot | Source |
|---|---|---|---|---|
| 0.0–3.0 | 3.0 | **Hook** | Dynamic Island, expanded, full of coloured blobs. Still for the first 0.4s | recapture |
| 3.0–6.0 | 3.0 | Demo | Lock Screen Live Activity, same folder, blob row along the activity | recapture |
| 6.0–10.0 | 4.0 | Demo | Home Screen widget → swipe right → Today View, **one continuous take** | film |
| 10.0–12.5 | 2.5 | **Payoff** | Lock Screen accessory widget — the permanent surface, no activity required | film |
| 12.5–15.0 | 2.5 | Mark | End card | build |

Every hold clears the ~1.5s a shot needs to register. Five shots reads confident, not cheap.

**Watch the adjacency:** shots 2 and 4 are both the Lock Screen, separated only by shot 3. The
Live Activity's colour band and the accessory widget's small monochrome row should read as
different surfaces — confirm by eye at the edit, and reorder if it reads as a repeat.

**Payoff logic:** the accessory widget is the strongest possible close because it is the only
surface that is *always* there. Nothing was triggered; the folder is simply on the phone.

---

## The 30s — "Great outside. Better inside." · situation, turn, reveal · 10 shots

| Time | Hold | Beat | Shot | Source |
|---|---|---|---|---|
| 0.0–2.0 | 2.0 | Hook | Same Dynamic Island frame as the 15s — one asset, one thumbnail | recapture |
| 2.0–4.0 | 2.0 | Situation | Phone face-up beside a paper trail map and a headlamp; screen lights; the folder is already there | **Kling plate + composite** |
| 4.0–6.5 | 2.5 | Door | Lock Screen | recapture |
| 6.5–9.5 | 3.0 | Door | Home Screen widget → swipe → Today View, one take | film |
| 9.5–13.0 | 3.5 | Door | Pinning; *The move / Yosemite / Reading* | recapture |
| 13.0–17.5 | 4.5 | **Turn** | Tap the Lock Screen activity, land inside the folder. No cut | film |
| 17.5–21.0 | 3.5 | Reveal — *what is in it* | Folder scroll: to-dos, photo, note, links, each with its own blob | film |
| 21.0–24.0 | 3.0 | Reveal — *it does something* | The player: warm blob, transport, scrub bar | recapture |
| 24.0–27.0 | 3.0 | Reveal — *the reward* | The canvas, blobs drifting, none alike | recapture |
| 27.0–30.0 | 3.0 | Mark | End card | build |

The Turn is now the longest hold in the film. Correct — it is the shot the whole second act
is bought with.

The three reveals each answer a different question. Keep them that way; if two start to feel
like the same shot, the second act has drifted back into a tour.

### App Store cut — 9 shots, all screen

Drop shot 2. Apple requires App Preview footage captured from the app on device, and a tabletop
plate breaches that. Redistribute the 2s across the doors:

`2.0–5.0` Lock Screen · `5.0–8.5` widget → Today View · `8.5–12.0` pinning · `12.0–16.5` Turn ·
`16.5–20.0` folder scroll · `20.0–23.5` player · `23.5–27.0` canvas · `27.0–30.0` mark

The version with live action is the social and site cut.

---

## The capture session

One sitting retires five of the brief's seven gaps, plus the seam, plus the Turn overrun, plus
the frame-rate problem. Run it before anything else is edited.

**Set up once, then do not touch:**

- One device or simulator, **1320×2868** throughout, to match the existing library
- `xcrun simctl status_bar <device> override --time "9:41" --cellularBars 4 --wifiBars 3 --batteryState charged --batteryLevel 100`
- **One folder state, frozen.** The brief caught the Island reading *5*, the Lock Screen *6 items*
  and the widget *5 fils* for what is meant to be one folder in one moment. The entire pattern
  argument depends on the count matching everywhere.
- **Capture ~1s of handle either side of every intended in and out.** The missing Turn is exactly
  what happens without this.

**Capture list, in order:**

1. Dynamic Island, expanded — the hook and the poster frame, so shoot it best
2. Lock Screen Live Activity
3. **Lock Screen accessory widget** — permanent surface, never yet filmed, now the 15s payoff
4. **Home Screen widget in use** — `07-home screen.mp4` is 13.6s of the *Add Widget* sheet
5. **Home widget → swipe right → Today View**, one continuous take
6. **The Turn** — tap the Lock Screen activity, land inside the folder, no cut
7. **Folder scroll** — only a still exists today
8. Pinning shelf
9. Player
10. Canvas
11. *Optional:* Action Button and Control Center, if they are real doors

**On export, conform every clip to constant frame rate:**

```
ffmpeg -i "in.mov" -vsync cfr -r 60 -c:v libx264 -crf 16 -pix_fmt yuv420p "out.mp4"
```

Still outstanding after the session: the **tabletop plate** and the **end card**.

---

## The one Kling shot — tabletop plate (30s shot 2, social cut only)

Generate a plate with a **dark screen**, then track the real capture into it. The screen content
must never be generated: it is UI, and generated UI garbles every label in it.

| Spec | Value |
|---|---|
| Size | Medium close-up |
| Angle | High, roughly 45° looking down at a tabletop |
| Movement | Very slow push in, or locked off |
| Lens | ~50mm, shallow depth of field |
| Lighting | Low key. Warm practical from the headlamp, soft window key from one side, rim on the phone edge |
| Duration | Generate 5s for a 2s cut |

**Frame it to dodge all three generation failure modes:** no hands, no logos, and **no legible
text** — a topographic map folded to show contour lines rather than place names, since printed
labels render as gibberish. Keep the phone screen dark in the plate.

Draft on a fast model at 1080p, get a verdict on composition and light, then regenerate the
approved frame at final quality.
