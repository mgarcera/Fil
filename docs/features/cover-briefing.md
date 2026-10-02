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

**1. Source: outward only.** Revised the same day, after the cards: there is **no inward tier and
no cross-folder connection**. The free half is exactly the on-device briefing that exists now,
summarising the folder you are in, and Mason's read is that it is already enough. The paid half
reaches outward through the worker. The split still matches what
`docs/monetization/blank-canvas-pivot-plan.md` locked, capture free and cloud paid, so the
successor needs no new money model.

A cross-folder briefing was offered and declined. Keeping the free half inside one folder also
keeps the two halves legible: free tells you what is in the folder, paid tells you what is not.

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

The free half already ships. The paid half is blocked on the same worker work `fil-a-folder.md`
has been blocked on since 2026-08-13, which is Mason's, so the design is written first and the
endpoint is built against it.

## Voice

Thirteen revisions of the prompt settled the register; the shift from asking to asserting must not
undo it. "Did you know" is the wrong shape, it talks down. "You were reading about X, the thing
next to it is Y" is the right one: it continues the user's own line rather than interrupting it.

---

# The paid half: design (2026-10-02)

Written before the worker exists, so the endpoint is built against a contract rather than the
other way round. Four more decisions settled the shape.

**What leaves the device: the folder's entries.** Not topics, not the on-device briefing. The
model needs the user's actual words to find the thread worth following, the same material
surfacing already sends. This is the expensive choice and it is paired with the one below.

**One finding per briefing.** The single best thread, one web search, a predictable cent. Two or
three findings triples the cost and the chance that one of them is thin.

**It lands after the on-device bubbles, before the sign-off.** The free run says what is in the
folder, the finding extends it, the signature closes. A cover with no finding is exactly the cover
that ships free, with nothing missing from it.

**Per-folder opt-in, off by default.** Subscribing is consent to be billed, not consent for a
particular folder to be sent anywhere. A folder reaches outward only once it is switched on, in
the menu that already holds the cover controls.

The last two decisions are load-bearing together: full entries leave, but only from folders the
user has deliberately opened up. Neither is safe without the other.

## The contract

`POST /briefing` on the existing Cloudflare Worker, the same shared-secret gate the surfacing
endpoint uses.

```jsonc
// request
{
  "folderName": "Learning Materials",
  "entries": ["…", "…"],        // newest first, same 24 × 400 window the device uses
  "locale": "en-US"
}
// response
{
  "message": "You were reading about affordance and signifier. Don Norman's own",
                                  // one or two sentences, the finding in the app's voice
  "link": {
    "url": "https://…",           // RESOLVED BY THE WORKER, never written by the model
    "title": "…",
    "host": "…"
  }
}
// or
{ "message": null, "link": null }   // nothing worth following: a real answer, not a failure
```

## The flow

1. Client checks, in this order and stopping at the first no: the folder is opted in, the
   subscription is active, the content signature has changed since the last finding, the daily cap
   has room. Nothing is sent until all four pass.
2. Worker asks Haiku 4.5 for **one search query plus the sentence that will introduce it**. The
   model returns the query, not a URL.
3. Worker runs the web search on that query and resolves the top result to a real URL and title.
4. Worker returns the message and the resolved link. If the search returns nothing usable, it
   returns nulls rather than a link the model imagined.
5. Client renders the finding as the last message before the sign-off, and caches it under the
   same signature as the on-device run.

Step 2 and 3 being separate is the whole safety argument, and it is not new: `fil-a-folder.md`
specifies the same split. **The model proposes queries; the worker resolves URLs.**

The reason is sharper than "models make links up", which measurement on 2026-10-02 showed is not
quite the problem. Asked for citations, Apple's on-device model returned a mix: `arxiv.org`
resolved 200, `www.icml.org` did not resolve at all, and a documentation URL came back 404 because
it carried one underscore the real page does not have. So a local model does emit real URLs, and
it has no way to tell you which of its URLs are real. **Nothing a model outputs is a citation
until something resolves it.** That is why resolution belongs on the worker in every tier.

Measured with the Foundation Models framework on macOS 26.6.2 with Apple Intelligence enabled,
and every URL checked with `curl -L`. No iOS 27 device was exercised.

## The client

- `ClaudeSurfacingService.briefing(folderName:entries:) async throws -> Finding?`
- `struct Finding: Sendable { let message: String; let url: URL; let title: String; let host: String }`
- Opt-in lives on the folder, defaulting false, so it survives alongside the cover image already
  stored per folder.
- Cache: extend `CoverSummaryStore` so a finding is stored with the same version-plus-count-plus-
  newest signature the summary uses. A changed folder re-runs both or neither.
- Failure is silent. No finding is the free cover, which is a complete product.

## The bubble

Same `PaperBubble` as every other message, so it reads as the thread continuing rather than as an
advertisement. The link inside it uses the nest's existing link treatment. A tap on the bubble
files it into the folder as a real link fil via `LinkFil.fetchDescription`, which is the
proposes-and-you-accept rule from the decisions above: nothing lands in the notebook unchosen.

## The sign-off problem

The run currently signs "On-device AI", and that sentence stops being true for any run containing
a cloud finding. Either the finding carries its own attribution and the sign-off narrows to the
messages above it, or the sign-off changes when a finding is present. This is a copy decision and
it is Mason's; what cannot happen is the current string sitting under a message that came from a
web search.

## Cost

Measure before the tier ships. The ~$0.01 per query in `blank-canvas-pivot-plan.md` was measured
sending the **whole corpus**; a briefing sends one folder, so tokens are lower, and a web search at
roughly $0.01 is on top. The number to put in a spreadsheet is a measured briefing on a real
folder, not an inherited one.

The cap matters more than the unit price. A briefing is ambient rather than human-paced, so a
daily per-user ceiling and the signature cache are what keep the subscription solvent.

## The free half has a coverage gap, and it is bigger than "old phones"

`SystemLanguageModel` has three distinct unavailable reasons, not one: `deviceNotEligible`,
`appleIntelligenceNotEnabled`, `modelNotReady`. Apple Intelligence needs an A17 Pro or newer with
8 GB of RAM, **7 GB of free storage** for the downloaded assets, and the user to have switched it
on. A current phone with a full disk, or one belonging to someone who never turned the feature on,
gets the same nothing an iPhone 13 does.

`CoverSummary.load()` today has no branch for this. The availability check fails, `result` stays
empty, `split("")` returns nothing, and the cover renders its title with blank space under it. For
the successor, whose cover IS the product, a silent blank is the wrong answer to a condition this
common. Whatever v1 does here, it needs a deliberate one.

## Out of v1

Facts without a link, corrections to the user's notes, more than one finding, anything that files
itself, and any cross-folder reading. Each was considered and declined on 2026-10-02.
