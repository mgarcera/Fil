# Where the pinned folder goes on a paged home — 2026-09-28

The home's folder list becomes pages, one folder per page, modelled on the full-screen fil player.
Settled before the study: a page is the hero plus its contents, the Bin lives in the dock, and
reorder and delete move to a long-press edit mode. The one open question was the pinned folder,
which already had a hero on the old home and was already kept out of the list below it.

Three variants, each making a different claim. Built in
`Fil/Views/Sandbox/PagedHomeStudy.swift`, judged on device against Mason's real folders.

## A — the dock only (lost)

The pinned folder sits beside the Bin on the dock, present on every page, and has **no page of its
own**. `pages` excluded it; `dockPinned` was it.

The claim: the pinned folder is REACHABLE, never arrived at. Constant access over ceremony.

Why it lost: it shrinks the one folder you chose to feature down to a dock slot the same size as
the Bin's. The hero — the 3D folder whose lid hinges open and whose fils spill out — is the reason
the pinned folder feels chosen, and A is the only variant that never shows it.

## C — both (lost)

Full hero on page one AND a slot in the dock, with a small "In the dock" mark on the page so the
two read as one thing rather than two.

The claim: reachable and arrived at; redundancy buys reach.

Why it lost: it is the same note that got the pinned folder pulled out of the old home's list on
2026-09-25 — the hero above and a row below said one thing twice and read as redundancy. C is that
arrangement again with a dock instead of a list.

## B — page one (won)

Page one is the pinned folder at full hero size. The dock holds the Bin alone. Every other folder
is one swipe from it.

"Page one is the best."

## Not captured as images

The three differ in two computed properties, `pages` and `dockPinned`, and the study was judged on
device where a screenshot is not something this setup takes. The rule each variant applied is
recorded above instead, which is the part a diff would never show. Recover the variants from this
commit's parent if one is ever wanted back.

## What came out of the verdict, as new work rather than variants

- The page-one dot becomes a **pin glyph** rather than a circle, so the dock's absence is not the
  only thing saying which page is the pinned one.
- A page **scrolls**, the way the full-screen player does: the hero fills the first screen and the
  folder's own fils are under it, in the sections the folder screen already uses. "Basically what
  the user sees when they open a folder now, just at this top level."
- The dot row **scrubs**: press and drag across it to move between pages, which is what the iOS
  home screen does and what "press and hold to scrub" was describing.

---

# Direction bake-off — structure vs weight vs world, 2026-09-28

Three directions, one axis each, rendered in HTML on the app's own `DemoLibrary.json` (Yosemite,
The move, Reading — the three folders and ten fils the App Store screenshots are cut from).

The keep-list going in was nearly empty by Mason's own call: the five faces, the folder-as-object,
the five containers and **blob-as-identity** were all opened, on the reasoning that Fil is
underperforming in the App Store against Weeklite and Sphere and that the blob works against
gestalt — people prefer clear, regular shape.

## D2 — the ledger (lost)

Fil's black kept, pages dropped. Density and typographic weight doing the work instead of colour:
folder name at 25px Gabarito bold, count at 30px DM Mono in near-black (#ffffff2e), colour reduced
to a 4px gradient bar down the row's left edge, the blob demoted to an 11px rounded square. Three
thoughts previewed per folder, then a count.

Why it lost: it is the most information per screen of the three and it stops being Fil. With the
blob at 11px the gradients no longer read as identity, so the one thing that ties a thought to its
card, its player, its widget and its screensaver is gone — and nothing replaces it.

## D3 — the deck (lost)

A different world. Warm light ground (#efe9dd) with a radial lift, folders as physical cards with
a clear rounded-rectangle shape, a real shadow and the folder's gradient as a colour field across
the card's head. Instrument Serif carrying the names at 25px. **No blobs anywhere** — every shape
regular, which is the gestalt argument rendered rather than argued.

Why it lost: this was the direction built to test whether the blob should go, and seeing it
answered the question the other way. On a light ground the gradients stop glowing and become
flat colour fields, which is exactly what black was load-bearing for.

## D1 — the paged home (won)

Black, blob, one folder per page, hero filling the first screen with its thoughts under it, pin on
page one's dot, the dot row scrubbing under a drag, Bin in the dock.

"D1. strip the others and let's keep working on D1 as a base."

**The blob stays**, decided by the bake-off rather than in the abstract: D3 removed it and the
removal is what made the case for keeping it.

---

# Below the hero: feed vs screens, 2026-09-28

## Screens (lost)

One thought per screen, snapping vertically. No rail, no marker, no gutter, no card — the
reasoning being that at that scale a thought does not need introducing. A note was Instrument
Serif at 23–42 depending on its character count, a photograph filled the width with an italic
caption, voice was the waveform at 2.6× so the length of the recording was visible rather than
read, a link was its own title at 34 with the domain, a to-do was a checklist at 17. Each carried
its date at the bottom in mono.

**Where it came from.** An accident. Direction B's hero promoted a folder's newest thought as a
pull quote when the folder had no summary, and on a folder holding only the welcome note that put
the whole note on the arrival screen. It read better than anything the feed was doing, and the
idea was that accident generalised.

**Why it lost:** "feed is still better, it was worth a try." One thought per screen buys
presentation and spends the thing the feed is for — seeing what a folder holds without moving.

## Direction B's hero (lost, one build)

Name at 46, the folder's caption as an editorial lede in Instrument Serif italic at 27, a 46×2
rule in the folder's tint, the count in mono at 10, no folder mark. Chosen from the hero bake-off
in `https://claude.ai/artifact/89iwB4v7b1EHvBR3NjomAX` as the only direction that degraded
*upward* on the hard case.

Its fallback is what produced screens, so its real contribution was the idea it caused rather than
the layout it proposed. What survives of it: type only, no folder mark. What went: the lede, the
rule, the count, and everything on the arrival screen the user had not written.

**Settled:** the hero is the folder's name, upper left, and nothing else.

---

# The nest, and what it replaced — 2026-09-28

## NotesPage (deleted)

A folder's plain notes consolidated into one Apple Books–style reading page: the folder name as a
running header greyed and clipped, Newsreader at 19, and — the two details that carried most of the
resemblance — **first-line indents on continuation paragraphs and hyphenation at 0.9**. Neither is
reachable from SwiftUI's `Text`; both are `NSParagraphStyle`, so it was a `UITextView`.

Notes opened a new section flush left with space above; continuations indented 20. That is the book
convention for a break, and it meant two thoughts read as two without a rule between them.

**Why it went:** the block model replaced it within the hour. Every thought became a block in one
scrolling document, so consolidating *only* the prose into a separate page stopped having a job —
the whole page was already one document.

**Worth keeping if a reading surface ever comes back:** hyphenation at 0.9, not 1.0. At full
strength almost every line breaks, the ragged edge disappears, and it reads as justified text that
was never justified.

## Type, settled

Newsreader across the page — notes, to-dos, link titles, captions, the running header. Helvetica
survives only in the composer and the chrome. A note is one size, 16, with weight the only thing
separating its title from its body.

**16, not the 14.5 the body used to be.** Newsreader sets smaller than Helvetica at the same point
size, so matching the number would have been a step down from what the page read at. The ask was
"the size of the body text", and that is a size you see rather than a number.

## The axes, settled

Down moves between folders while you are on a cover. One step across takes you into the nest.
Inside the nest, down belongs to the content and folder paging is switched off.

The axis changes meaning by **depth**, not by scroll position. An earlier model switched horizontal
from "folders" to "thoughts" depending on how far you had scrolled, which is a change you cannot
see coming; this one you swiped to reach, the way the rules change inside an app on the home screen.

## The bar, settled

Input, not navigation. It was the transport — chevrons and a position — which said what the axes
already said, and needed a counter to justify itself. It is now the composer, which is the app's
premise, and it reports where a thought will land when an insertion point is chosen.

## 2026-09-29 — the nest became a screen

The horizontal step from cover to nest was a `TabView(.page)` per folder, inside the vertical
pager. That put a `UIPageViewController` between two SwiftUI scroll views: the page controller
turned pages whether or not the `card` binding accepted the write, `folderIndex` drifted when a
lazy neighbour's `onAppear` fired, and the composer's safe area and keyboard had to survive
three container boundaries. Five composer fixes went out that night, each adjusting a number on
a relationship the inner scroll view could not see, before a console stream from the device
showed the scroll view *growing* by the keyboard's height instead of translating.

Mason named it: "the composer and the vertical scroll view are layered too differently." The
nest is now pushed in a `NavigationStack` from the cover — the same horizontal slide, owned by
the framework — and gets one plain container, the way the shipped home's composer has. The
`card` axis, the guards, the write-back, the offset and the keyboard notification all went with
it. A glass back control replaces the edge swipe, which a hidden navigation bar takes away.

The composer itself is the shipped `ComposerBar` in `CanvasHome`'s glass dock; the grouped
Add | Ask row it beat is in `archive/2026-09-29-nest-composer/`.

Two materials on purpose: the nest's back control is glass because it is navigation; the
cover's image control is line art because it is an image choice. Neither verdicted as of
2026-09-30, nor is Glass vs Hairline on the bubbles — sandbox axis A still carries both.


## 2026-09-30 — three cover setups; Editorial with Plate's face

Three that differed in kind, on each folder's real ground with its real name, count and month
span, flipped on sandbox axis B from a picker moved to the bottom edge for the purpose.

- **Editorial** — Newsreader masthead at 58, a tracked Archivo Narrow deck above it
  (`SEP – OCT 2026   ·   14 THOUGHTS`), a hairline below. The structure that won.
- **Poster** — Anton all-caps as large as the name allows (four lines, scaling to 0.4), a 3pt
  rule, the count as a 96pt numeral beside its label. The newsstand register. Lost.
- **Plate** — Fraunces Black centred in a hairline frame, rules above and below, mono folios in
  SF Mono. The literary-masthead register, drawn rather than set. Lost as a layout; **its face
  won**: "editorial with plates font."

Six faces were added for the round and stay registered: Anton, Archivo Narrow 400/600,
Fraunces 400/700/900. Only Fraunces Black and Archivo Narrow SemiBold are used by the cover
now; the rest are parked for the next type study, and the reason is this line.

2026-10-01: the summary's face is Lexend at 16 (Fraunces stays on the name) — Medium on the count-and-months lead, Light on the prose, after a first pass in Regular. Light read thin on the prose and Regular came back the same day; Lexend Light stays in the bundle, parked, and the reason is this line.

## 2026-10-01 — the black edge, and the language it names

A 2pt black outline on the cover name's glyphs — asked for as a legibility fix over bright cover
photographs — read to Mason as "a totally different design language that I think I was going for
in the first place: 2D, flat, paper." Not glass, not depth, not blur: ink on a sheet, with an edge.

Recorded as a direction, not a decision. He has ideas and has not laid them out yet. What is
settled by it so far: the name keeps its edge; the two materials rule from 09-29 (glass for
navigation, line art for choices) may be the seam this pulls at, since glass is the opposite of
paper. Open: what else on the cover and in the nest takes the edge — the rule, the deck, the
bubbles — and whether the glass dock survives a paper world.

Also settled the same day, by verdict: bubbles are glass, not hairline (axis A stripped).

Filaments on bubbles, verdict 2026-10-01: **lit words** (FilCard's treatment carried into the bubble) over chips. Chips not yet stripped — they are the only form that reaches a photo or voice fil, and the paper direction's ideas are pending; the strip waits on those.

### The paper pass, 2026-10-01

Mason's ideas, laid out and built the same day: message bubbles are white with a 2pt black border
and black ink; the cover's summary sits in the same bubble, leading (the folder answering you),
with no hairline above it; the months and count become a stamp set exactly like the nest's day
separators (`MAY – AUG 2026  ·  4`). On trial on the two axes: how a lit filament word reads on
white (the fil's colour / black underlined / a pale band), and whether the dock and back control
go paper, stay glass, or become line art.

Open, noted for testing: bubble text is SwiftUI `Text`, not the shipped `SelectableTextView`, so
select → Filament is not reachable from the nest and new filaments cannot be made there yet.

Summary voice, verdict 2026-10-01: **casual** lowercase texting, with greetings cut ("hey", "yeah") — over the warm normal-case friend. Two to four one-line messages springing in 120ms apart. Lit words: yellow band. Chrome: glass. White: 0.86.

### The summary, reframed — 2026-10-01, late

Four prompt rounds in a row chased a *mirror* ("what you keep returning to") and the on-device
model answered each with a different failure: quoted topic words, "they" for the writer, a greeting,
and finally my own example sentence copied back as the first line. Stepping back, the question
never asked was what the summary is for. Settled by cards:

- **A briefing** — what's in this folder, fast — over a mirror or a nudge.
- **Restate, then one observation last.** Every bubble but the last says one particular thing the
  entries say; the last is the one place a reading is allowed, so a wrong one is contained by
  position.
- **On-device only** for now. The shipped Claude path exists and is Fil Extra-gated, and this phone
  is not on Fil Extra; Private Cloud Compute waits on Apple's entitlement.
- Voice stays casual lowercase, no greetings; two to four bubbles springing in; no example
  sentences in the prompt, ever — the shape is described, never shown.

## 2026-10-01 — the arc's end is a different app

Mason, late on the first of October: Fil comes off the App Store; what this sandbox became ships as a
new app, under a new name, free, in the notes or utilities category, "keeping thoughts in a familiar
but unique format." Fil stays as archival content. The port the arc was heading toward is not into
Fil's codebase; it is out of it. Everything above is the record of how the successor was found.
