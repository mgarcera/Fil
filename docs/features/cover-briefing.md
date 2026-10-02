# The cover briefing

The run of messages on a folder's cover. Today it summarises the folder back to you. The decision
on 2026-10-02 is that it should **extend** what you were thinking instead, and that this is the
feature the successor app is worth paying for.

Live code: `Fil/Views/Sandbox/BlockFolderPage.swift` (`CoverSummary`, `Briefing`).

## Why it changed

The on-device model is handed one folder: 24 entries, 400 characters each, and nothing else. With
no source outside that, the only move it has is to ask. A cover that reads "who else is involved
with the STAR Program?" is not making a conversational choice, it is reporting the edge of its own
context. Questions do not go anywhere, and a cover full of them is a cover that costs the reader
work without returning any.

## The four decisions (2026-10-02, Mason)

**1. Source: both, tiered.** Free stays on device and connects your own folders to each other
("you wrote about this in another folder in June"). Paid reaches outward through the worker. This
is the same split `docs/monetization/blank-canvas-pivot-plan.md` already locked, capture free and
cloud paid, so the successor needs no new money model.

**2. The finding is a real link.** One resolved URL with a sentence on why it is next. Not a
free-floating fact: a wrong fact on your own cover is worse than no fact, and a small model
inventing a plausible URL about a city services programme is the failure that would end trust in
the feature on the day it shipped. The safe pattern already exists in `fil-a-folder.md` — the model
proposes search queries, the **worker** runs the search and resolves real URLs, the client builds
link fils from what came back. **The model never emits a URL.**

**3. Output: text that offers.** The bubble carries the finding; a tap adds it to the folder as a
real link fil. The briefing proposes and you accept, so nothing you did not choose lands in your
own notebook. This is the line between a summary and a contributor, and consent is what keeps it
on the right side.

**4. Trigger: on open, hard cached.** It runs when you open a folder whose content changed since
its last briefing, and never otherwise. The signature cache (`CoverSummaryStore`, keyed on version
plus entry count plus newest timestamp) already enforces this; a daily cap backs it up.

## The cost tension, which is new

The locked break-even — about 300 queries a month against $2.99, ~$0.01 per query on Haiku 4.5 plus
~$0.01 per web search — assumes **human-paced** use: someone types a query and reads a result. A
briefing that runs on every cover is **ambient**, and twelve folders touched in a day is twelve
calls nobody asked for. The cache and the daily cap are not polish here, they are what keeps the
tier solvent. Measure a real briefing's cost before the paid tier ships rather than inheriting the
surfacing number, which was measured against the whole corpus rather than one folder.

## What is buildable now

The free tier needs no infrastructure: cross-folder context is assembled on device from data the
app already holds. The paid tier is blocked on the same worker work `fil-a-folder.md` is blocked
on, which is Mason's.

## Voice

Thirteen revisions of the prompt settled the register; the shift from asking to asserting must not
undo it. "Did you know" is the wrong shape, it talks down. "You were reading about X, the thing
next to it is Y" is the right one: it continues the user's own line rather than interrupting it.
