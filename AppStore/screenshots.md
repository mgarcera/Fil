# Fil — Screenshot Spec

*Rewritten 2026-08-18 against the shipped listing copy. The previous version was staged for the
July voice-led positioning — its arc was tap → speak → titled note, one caption argued by negation
("no inbox. no tags. no system."), and one was factually wrong ("titled on your device": titles are
the first line of your own text, not model output). None of that survives here.*

**Required:** at least one **6.9″ iPhone** set (also serves 6.7″), portrait, **1320 × 2868**. The
five existing captures in `screenshots/` are already that size.

**Voice:** sentence case, matching the App Store description as of the rename. Every caption below
is either lifted from the shipped description or is a compression of a line in it — nothing here
claims anything the listing does not.

**Apple OCR-indexes screenshot text**, so captions carry ASO weight as well as comprehension. Put
them in the top or bottom safe zone, and keep the device frame consistent across the set.

## The six

| # | Caption | Frame | Blob |
|---|---------|-------|------|
| 1 | **Pin what you're in the middle of.** | Lock Screen with the pinned folder — the door, and the whole pitch | `blob-1-seed3-coral-indigo` |
| 2 | **Glance, and it's there.** | Dynamic Island expanded, blobs visible | `blob-2-seed11-teal-violet` |
| 3 | **Five places that aren't the app.** | Home Screen widget + Today View, or a composite of the surfaces | `blob-3-seed19-amber-crimson` |
| 4 | **No two thoughts look alike.** | The blob grid — colour, shape, gradient, none repeated | `blob-4-seed23-eucalyptus-sky` |
| 5 | **Open Fil when you want to dig in.** | A thought open: the player, or the folder with its filaments | `blob-5-seed31-orange-magenta` |
| 6 | **Ask in your own words.** | Smart search mid-result — the one Extra feature worth a shot | `blob-6-seed41-emerald-royal` |

Six is the recommendation, not the limit — Apple allows ten. The first two carry the argument; if
only two are ever seen, they should be 1 and 2.

**Ordering logic:** the door first (1–3), then what is behind it (4–5), then what Extra adds (6).
That is the same order the description runs, so a visitor who reads and a visitor who swipes get
the same story.

## Captions deliberately not used

- Anything with "no …" — the site cut its own negation section for the same reason. A caption that
  names what Fil lacks plants the feature in the reader's head.
- "On your device" as a claim about titling. Titles are the first line of your own text.
- "Voice-first" or anything leading with capture. The surfaces are the wedge; capture is table
  stakes and the July positioning that led with it is retired.

## Blobs

Six SVGs in `blobs/`, one per screenshot, generated with the app's own blob algorithm and gradient
palette so they are the real shapes rather than lookalikes. Seed 7 is deliberately absent — that is
the website's blob, and reusing it would make the store and the site look like the same asset
twice.

Open `blobs/_preview.html` to see all six together.

## Still open

- **App Preview video** — optional, and lifts conversion. See `docs/video-brief.md`, which is
  written and unscheduled.
