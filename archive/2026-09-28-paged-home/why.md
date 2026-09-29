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
