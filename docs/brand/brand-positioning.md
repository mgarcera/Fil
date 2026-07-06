# Fil — Brand Positioning & Voice

*The source of truth for how Fil presents itself — website, App Store, press, and product copy
should all trace back to this. Written 2026-07-06.*

---

## 1. One line

**Fil — let thoughts be.** A quiet place to speak your mind and let it exist, without turning it
into a project.

## 2. What Fil is

Fil is a voice-first capture app for fleeting thoughts. You tap once, say what's on your mind, and
Fil transcribes it and gives it a short, natural title — all on your device — so you can find it
later. Text, images, and shared links work too. That's the whole app.

Its purpose is **permission, not productivity**: a low-stakes home for the thoughts, moments, and
half-ideas that don't need to become tasks, and shouldn't have to earn their place by being
organized. Capture is effortless; nothing asks anything of you afterward.

## 3. What Fil is NOT

This is load-bearing — it's the brand's spine, straight from the founder's manifesto. Fil is
**not** a productivity app, a second brain, a project manager, or a journal. It deliberately has
no inbox, tags, folders, dashboards, streaks, reminders, graphs, due dates, priority levels,
integrations, mood tracking, or workspaces.

> *Optimization culture makes us believe our thoughts are only valuable if they're organized,
> tagged, linked, and actionable. Some thoughts are just thoughts. Some moments are just moments.
> They just need to exist.*

Fil has zero opinion on how you should organize or scaffold yourself. When we describe Fil,
naming what it refuses to be is as important as naming what it does.

## 4. Who it's for

- People who feel **friction and guilt** in note/task apps — the ones who've abandoned a dozen
  "second brains" because keeping the system fed became the work.
- **Voice-first thinkers** who talk faster than they type and want thoughts out of their head fast.
- **Privacy-conscious** users who don't want an account, a feed, ads, or their words on someone's
  server.
- People who want a **calm, beautiful, low-pressure** digital space — closer to a sketchbook or a
  walk than a dashboard.

Not for: teams, GTD/PKM power users seeking structure, or anyone who wants analytics on their own
mind. That's a feature, not a gap.

## 5. Market fit & differentiation

The capture space is crowded (Apple Notes, Voice Memos, Notion, Obsidian, Day One, Bear, dozens of
"AI notetakers"), but nearly all of them compete on **more**: more structure, more organization,
more features, more optimization. Fil competes on **less** — and on *feeling*.

Its defensible wedge is the intersection of three things few others hold together:
1. **Voice → titled note in one tap**, so capture is genuinely frictionless.
2. **Truly on-device & private** — on-device transcription (where supported) and on-device Apple
   Foundation Models for titling; no account, no cloud, no tracking.
3. **An explicit anti-optimization philosophy** with a warm, human, indie voice — a point of view,
   not just a feature set.

The "AI note" wave is loud but soulless; Fil's counter-position is *calm, private, and
opinionated about restraint.* That's the story press and word-of-mouth can carry — the coined name
has no search pull, so the **brand and the philosophy are the moat**, not SEO.

## 6. Value proposition

**Core promise:** the fastest way from a thought to a note you'll actually find later — with
nothing to manage afterward.

Supporting pillars:
- **Just talk.** One tap, speak, done. Your voice becomes a titled note.
- **Yours, on your device.** No account, no ads, no feed, no tracking.
- **Nothing to keep up with.** No inbox, no streaks, no system to maintain.
- **A place, not a pile.** A calm, considered design that makes notes feel like somewhere to be.

## 7. Brand voice

Fil's voice is the "from mason" voice: **quiet, warm, human, and quietly contrarian.** It sounds
like a thoughtful friend, not a productivity coach or a startup.

**Characteristics**
- **Lowercase.** The app and its writing default to lowercase — it reads casual, unhurried, and
  unpretentious. (Prose *about* Fil, like this doc or press, can use normal case; Fil's own UI and
  first-person copy stay lowercase.)
- **Plain and spare.** Short sentences. Real words. No jargon, no hype, no exclamation marks.
- **Declarative and calm.** States things simply ("some thoughts are just thoughts") rather than
  selling.
- **Gently contrarian.** Comfortable saying what Fil *won't* do. Confident in its smallness.
- **Warm, first-person, and honest.** Mason is a real person (data specialist + social worker) who
  built this; the voice can be personal and admit the app is small on purpose.
- **Playful with the name.** The `-fil-` wordplay is part of the charm (see §8) — used sparingly,
  never forced.

**Tone dial by context:** most playful in-app and in "from mason"; warm-and-plain on the website;
plain-and-credible in press and legal.

**Do**
- "some thoughts are just thoughts."
- "talk, and your words become a note you can find later."
- "no account. no ads. your notes stay on your phone."
- "fil doesn't ask you to be consistent."

**Don't**
- "Supercharge your productivity with AI!" (hype, optimization)
- "Your second brain, organized." (the exact thing Fil rejects)
- "Unlock powerful insights and trends." (surveillance of the self)
- ALL CAPS, exclamation points, growth-hack urgency, feature-listing for its own sake.

## 8. The name & lexicon

**Fil** — evokes *fill* (filling in a thought), *fulfillment* (**ful·fil·ment**), and, ironically,
*file* — a nod the brand leans into precisely *because* Fil refuses to make you file anything.

A single note is **a fil**. In-product wordplay (use naturally, don't over-explain):
- **landfil** — delete / discard a fil
- **fil'ament** — a keyword attachment that threads fils together
- ambient screensavers: **filosophy**, **filharmonic**, **filanthropy**, **chlorofil**, and the
  koi pond, **fillet**
- **ful·fil·ment** — the feeling Fil hopes to give ("i hope you'll find as much ful*fil*ment and
  fun as i do")

## 9. Visual identity

*Values below are pulled from the app's `Theme.swift`. Semantic tokens are adaptive (light + dark)
color sets defined in `Assets.xcassets`, so they have no single fixed hex — use the app as the
reference, or sample both appearances. The gradient palettes and utility colors are fixed hex.*

### 9a. Color

**Semantic / adaptive tokens** (roles, not fixed hex — light + dark variants live in the asset
catalog): `Background`, `PrimaryText`, `SecondaryText`, `TertiaryText`, `Divider`,
`CardBackground`, and the tab colors (`ActiveTabText`, `ActiveTabBackground`, `InactiveTabText`,
`InactiveTabBackground`). Default appearance is **dark**. For the website, treat these as: near-black
canvas in dark mode / warm-white in light mode, high-contrast primary text, muted secondary text.

**Fil gradient palettes** — the heart of the identity. Every fil (blob, card, widget) uses a
two-color linear gradient. Colors are drawn from *all three* palettes below, and cross-palette pairs
are allowed (bright ↔ earthy ↔ cool), which is what gives the grid its variety.

*Palette 1 — bright*

| Hex | Name |
|---|---|
| `#F24D59` | coral red |
| `#E67333` | burnt orange |
| `#D9A626` | amber |
| `#33BF99` | teal |
| `#408CD9` | ocean blue |
| `#6659CC` | indigo |
| `#E8196A` | electric crimson |
| `#4DB366` | emerald |

*Palette 2 — earthy*

| Hex | Name |
|---|---|
| `#5C2318` | mahogany |
| `#355E3B` | deep leaf |
| `#B85C38` | burnt sienna |
| `#1E5265` | deep teal |
| `#A3B18A` | soft moss |
| `#4F7C72` | eucalyptus |
| `#D99A5B` | warm amber |
| `#E0C27A` | faded gold |
| `#EAD5A3` | pollen |

*Palette 3 — vivid & cool*

| Hex | Name |
|---|---|
| `#E85B9C` | rose |
| `#B5379E` | fuchsia |
| `#8A4FD9` | violet |
| `#33B5D9` | sky |
| `#A8CC33` | chartreuse |
| `#6E4B6E` | plum |
| `#2E4FB3` | royal blue |
| `#B9A5E6` | lavender |
| `#26C2C2` | teal-cyan |
| `#9E2B6E` | deep magenta |

**Utility & anchor colors**

| Hex | Role |
|---|---|
| `#408CD9` → `#6659CC` | default fil gradient (ocean blue → indigo) — the safe "hero" pair |
| `#E63333` | record red (recording state) |
| accent gradient | `#33BF99` → green → blue → pink → orange → indigo (used for the send/stop border-beam) |

*Web guidance:* lead with one warm, high-craft blob gradient as the hero accent (e.g. coral→indigo
or teal→violet). Let the gradients be the color; keep surrounding UI near-monochrome (canvas +
text) so the blobs pop.

### 9b. Typography

- **Brand typefaces:** **DM Sans** (primary) and **DM Mono** (mono accent, used for metadata —
  word counts, durations, timestamps, "version"). Both are free on Google Fonts — **use these on
  the website** to match brand intent.
- *Implementation note:* in-app, `Theme.dmSans` / `Theme.dmMono` currently render via the **system
  font stack** (SF) at the corresponding sizes/weights; DM Sans/DM Mono are the brand faces and the
  intended direction. The website should use the real DM Sans/DM Mono.
- **Casing:** lowercase for Fil's own voice (headings, UI, product copy). Sentence case is fine for
  long-form web body if readability needs it.
- **Weights in use:** regular, medium, semibold, bold. Sizes range ~9–22pt in-app (badges small,
  section titles ~18–22).

### 9c. Shape language

- **The blob** — the signature shape. An organic, procedurally-generated closed curve (5–9 points,
  sinusoidal wave offsets, a per-fil rotation and slight asymmetry seeded from the note's id), so no
  two fils are shaped alike. This is *the* brand mark alongside the wordmark — favor it over generic
  circles/rounded-rects in marketing.
- **Capsules** — badges (the keyword/title chip) and primary buttons ("enable", tabs).
- **Circles** — icon buttons (mic, send, photo).
- **Rounded rectangles** — cards and glass panels. Corner radii in use: **22** (cards), **26**
  (composer bar), **28** (settings/glass card).

### 9d. Gradient & surface system

- **Gradient:** two-color `LinearGradient`, direction set by a per-fil angle (seeded), rendered with
  **16 smooth stops using smoothstep easing** so the edge colors hold and the midpoint doesn't turn
  muddy. Reproduce this on web with a multi-stop CSS gradient rather than a hard 2-stop.
- **Glass & light:** frosted-glass surfaces (`.ultraThinMaterial`), soft blurred ambient gradient
  backdrops, subtle mesh gradients. Airy, layered, luminous.

### 9e. Motion & feel

- **Calm, spacious, unhurried.** Lots of room; nothing shouts.
- **Organic springs**, not snappy pop. Text reveals via a gentle blur→sharp gradient wipe; blobs
  morph rather than cut. Never gamified, never urgent.
- On web: prefer slow fades and soft parallax over aggressive scroll-jacking or bouncy animations.

## 10. Ready-to-use lines

- **Tagline:** *let thoughts be.*
- **One-liner:** *fil is a quiet place to speak your mind — talk, and your words become a titled
  note you can find later, right on your device.*
- **Boilerplate (≈50 words):** *Fil is a voice-first app for capturing fleeting thoughts without
  turning them into projects. Tap once and talk; Fil transcribes and titles your note on your
  device — no account, no ads, no system to keep up with. Not a productivity app. Just a calm place
  for thoughts to exist.*
- **Website hero:** *speak your mind. let it be.*

---

*Everything downstream — website copy, press kit, App Store description, screenshots, future
features — should be checkable against this doc: does it sound like Fil, and does it honor "let
thoughts be"?*
