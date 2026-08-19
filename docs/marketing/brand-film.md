# Fil — Brand Film: "Still There"

*Drafted 2026-08-18, ~20s, 9:16 vertical. Direction per `product-video-direction`.*

**Not an App Store asset.** Apple requires App Preview footage captured from the app on device;
an abstract film is ineligible. This is the site hero, Instagram, X, and the launch post. The
screen film in `AppStore/video-production.md` remains the store preview and still needs its
capture session.

## The idea

One cluster of fils, centred, never moving. The world cycles around it — dawn, night, dawn again,
things sweeping past and gone — and the folder is simply always there. The promise is *"the thing
you're in the middle of is already on your screen, so you never open the app to check."* Here the
visual argues it literally: everything changes except the one thing you pinned.

Chosen over "The Cluster" (scattered → gathered is the most-used metaphor in productivity
advertising) and "No Two Alike" (beautiful, but pure brand — it seduces without arguing).

## The material — match the app, not the model's defaults

From `Theme.swift` and `CreatingFilBlobView.swift`, a fil blob is:

- A **gooey, irregular closed bezier outline**, vertices drifting on layered sine waves. Not a
  circle, not a sphere.
- **Two stacked layers** — a solid linear-gradient base, plus a blurred `plus-lighter` additive
  overlay whose gradient direction slowly rotates. Blur radius ~6% of the blob's side.
- **Saturated, jewel-toned**: coral red `#F24D59`, burnt orange `#E67333`, amber `#D9A626`,
  teal `#33BF99`, ocean blue `#408CD9`, indigo `#6659CC`, electric crimson `#E8196A`,
  emerald `#4DB366`.
- **Seeded per fil** — every blob has its own fixed shape. "No two thoughts look alike" is
  literal geometry, not a slogan.

Ask a video model for "blobs" and it returns glassy 3D orbs with specular highlights and chrome
reflections. That is the wrong product. Every prompt below specifies flat, matte, printed-ink
gradient forms with soft luminous edges.

## Production route

The cluster must be *pixel-identical* across the whole film — that identity is the entire
argument. Video models drift, so do not ask one to hold it.

| Layer | Made how | Why |
|---|---|---|
| **The cluster** | Real app render, or a frame from `AppStore/screenshots/08-home-canvas.mov`, composited locked to centre | Authentic seeded geometry, and guaranteed identical in every frame |
| **The world** | **Kling** — light sweeps, day/night wash, passing forms, atmosphere | Exactly what generative video is good at: light, texture, organic motion |
| **The pill resolve** | Motion graphics, or captured from the app | A precise shape morph; generation will not land it |
| **Type** | Motion graphics | Generated text garbles |

If `08-home-canvas.mov` carries any UI chrome, crop to the blob field before using it.

## Shot sheet

| Time | Hold | Beat | Shot | Source |
|---|---|---|---|---|
| 0.0–4.0 | 4.0 | Establish | Cluster centred on a near-black field, blobs breathing in place. Locked off | composite |
| 4.0–8.0 | 4.0 | Cycle 1 | Warm dawn light rakes across the field left to right. Cluster unmoved | **Kling A** |
| 8.0–12.0 | 4.0 | Cycle 2 | Light goes cold and blue; soft forms drift past and away. Cluster unmoved | **Kling B** |
| 12.0–15.0 | 3.0 | Acceleration | Cycles compress — warm, cold, warm — days stacking. Cluster unmoved | **Kling C** |
| 15.0–17.5 | 2.5 | Settle | Everything calms to the opening state. TEXT: *glance and it's there.* | composite |
| 17.5–20.0 | 2.5 | Mark | Cluster contracts into the Dynamic Island pill. TEXT: *Fil: Folders Outside the App* | motion graphics |

Every hold clears the ~1.5s a shot needs to register. Six shots in 20s reads considered, not busy.

**The risk this concept carries:** stillness reads as *static* when the surrounding layer is
under-directed. The world has to be genuinely alive — the light must move with intent, the passing
forms must have weight. If cycles 1–3 come back flat, the film fails, and no amount of type saves it.

## Kling prompts — ready to run

Common settings: `model: kling-video-v3_0`, `aspect_ratio: 9:16`, `duration: 5`,
`enable_audio: false`. Generate 5s for a 4s cut so there are handles.

Each prompt describes **the world only**, on an empty dark field. The cluster is composited in
afterwards, so nothing here should try to render it.

**Kling A — warm dawn rake**
```
Setting: an empty near-black field, deep charcoal, faint soft grain like printed ink.
Action: First the field is completely dark and still, then a wide band of warm amber and
coral light slowly rakes across from left to right, lifting the darkness as it passes, finally
easing back toward darkness and settling.
Camera: locked off, completely static, no movement. Style: flat two-dimensional colour, matte
and soft-edged, luminous gradient light, no reflective surfaces, no lens flare, minimal and
graphic. Duration: 5s.
```

**Kling B — cold night drift**
```
Setting: an empty near-black field washed in cold ocean blue and deep indigo, soft grain.
Action: First the blue light holds steady, then several large soft-edged organic forms drift
slowly across the frame from right to left, blurred and translucent, passing out of frame,
finally leaving the field empty and still again.
Camera: locked off, completely static, no movement. Style: flat two-dimensional colour, matte
gradient forms with soft luminous edges, printed-ink quality, no glass, no metal, no specular
highlights. Duration: 5s.
```

**Kling C — compressed cycles**
```
Setting: an empty dark field, soft grain.
Action: First a warm amber wash floods the frame, then it cools quickly to deep indigo blue,
then warms again to coral, the cycle repeating faster and faster like days passing, finally
slowing and settling back into warm amber.
Camera: locked off, completely static, no movement. Style: flat two-dimensional colour fields,
matte, soft gradient transitions, graphic and minimal, no objects, no reflections.
Duration: 5s.
```

Each prompt ends its action on a settle — the motion-endpoint pattern that keeps a generation
from hanging at 99%.

## Before any of this runs

- **Credits: 0.** Account `101552522`, Free tier. Nothing generates until it is topped up.
- **720p is the ceiling on this tier.** Every model lists `resolution: ['720p']` with no other
  option. For a website hero that is thin — worth weighing a paid tier against upscaling in post.
