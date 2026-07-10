# Blank canvas home — capture-first, retrieve-on-demand

A reframe of Fil's home (2026-07-10). The home stops being a place you *browse* and becomes a
blank canvas you *act on*: tap to capture a thought, ask to surface past thoughts. There is no feed,
no timeline, no theme sections, no scrollable pile. Status: **design** (supersedes the theme-home
direction in `theme-clustering.md`; the clustering *engine* is repurposed, not discarded).

## Vision & brand rationale
Fil is anti-optimization — "let thoughts be." The blank canvas is that taken to its end:
- **Capture-first.** The default state is empty. You come to Fil to put a thought down, not to be
  fed your past. Nothing competes for your attention.
- **Retrieve-on-demand.** Your fils are not gone — they're *at rest*. You reach for them
  deliberately, by asking, the way you'd search your own memory rather than scroll a feed.
- **No pile to manage.** No inbox, no list, no streaks, nothing to "get through." The anti-inbox.

This is a strong stance. It is the whole point — but it has real costs (see Risks). We are choosing
them deliberately.

## The three surfaces

### 1. Blank canvas capture (#1–3) — well-defined, buildable now
- Home opens blank (just background + whatever minimal affordance we decide, see Risks/discoverability).
- **Tap anywhere** → the creation blob (`CreatingFilBlobView`) animates in at center.
- Keyboard rises; the user types (existing `ComposerBar` text path). A fil forms — same creation +
  title generation (`ArticleGenerationService`) pipeline we already have.
- After the fil forms, the canvas returns to blank. The thought is "let be."
- Reuses: `CreatingFilBlobView`, `ComposerBar`, the Note creation + title flow. Mostly a new
  *interaction shell*, not new data plumbing.
- Open: do the four input modes (text / voice / links / photos) all live here, and how are they
  reached from a blank tap? (Text is the sketch; the others need a home.)

### 2. On-demand surfacing (#4) — the novel part (on-device RAG)
Long-press the canvas → a query field. The user types a **domain** ("work", "my company",
"times i felt lost"). Then:
1. **Retrieve** — rank all fils by relevance to the query and take the top ~10–15.
   - Query-vs-fil **embedding cosine** (`NLContextualEmbedding`, mean-centered). Retrieval by topic
     is exactly what cosine is *good* at — unlike the register-clustering we abandoned. This is the
     right tool here.
   - Scales to hundreds of fils cheaply; runs off-main.
2. **Summarize** — feed the top fils to the on-device LLM (`FoundationModels`):
   "summarize what this person has thought about {query}." → a short synthesis.
3. **Surface** — show the summary, with the contributing fils appearing below as blobs the user can
   open.
- On "work" vs "my company": #4 retrieves from the user's *own fils*, not world knowledge, so "my
  company" works **if they've written about it**. It only degrades for domains barely captured.
- Reuses: `FilClusteringService` plumbing (embedding load/cache, LLM session, fallback tiers).

### 3. Fate of browse — RETIRED
Decided: **fils are reachable ONLY through a query.** No browse, no scroll, no all-fils list on the
home. The timeline/grid (`NoteGridView`) and the theme-home prototype are removed from the default
path. (See Risks — we may still need a non-home escape hatch for edge cases like "show everything",
but it is NOT on the canvas.)

## Architecture for #4 (RAG, all on-device)
- **Index:** each fil embedded once on create/edit (`NLContextualEmbedding`), cached by
  `(uuid, textHash)`. Embed the title + a content snippet (as clustering already does).
- **Query:** embed the query string the same way; cosine against the fil index; mean-center to fight
  anisotropy; take top-N above a relevance floor.
- **Synthesize:** pass the top-N fils' text to `FoundationModels` with a summary prompt; guided
  generation for a clean short paragraph (+ maybe 2–3 "threads" it noticed).
- **Tiers / fallback:** LLM summary → (if unavailable) just show the retrieved fils with no summary.
  Retrieval itself degrades to keyword match if embeddings are unavailable.
- **Reuse:** most of this already exists in `FilClusteringService`; refactor it from "cluster all"
  to "retrieve for query + summarize".

## Risks & open questions (chosen deliberately, but real)
- **Discoverability.** A truly blank screen has no affordance — how does a user learn to *tap* to
  create and *long-press* to surface? Needs a first-run hint or a persistent faint cue. This is the
  biggest UX risk.
- **Findability.** You can only retrieve what you can *name*. A fil you can't describe is effectively
  unreachable. Accept, or provide a rare "show all" escape hatch (off-canvas)?
- **Cold start.** Querying with 3 fils returns little. #4 needs a minimum corpus to feel good;
  before that the canvas is capture-only.
- **Trust / loss anxiety.** Blank home can read as "did I lose everything?" The first surfacing needs
  to reassure that nothing is gone.
- **Existing features that assumed browse:** pinned/lock-screen fils, to-dos, screensaver, search.
  Where do they live now? (To-dos especially — a cross-fil surface that isn't a query.)
- **Retrieval quality** on short fils (embedding noise). May need the LLM to re-rank the shortlist.
- **Latency** of #4 (embed query + LLM summary) — needs a loading state; cache recent queries.

## Phased build
1. **Canvas shell (#1–3):** blank home + tap-to-summon-blob + type → fil, behind a prototype flag /
   the temp ▦ entry (reuse it) so it doesn't disturb the current home. Decide the discoverability cue.
2. **Surfacing (#4) v1:** long-press → query field → embedding retrieval → show matching fils (NO
   summary yet). Validate retrieval quality first — this is the make-or-break.
3. **Surfacing v2:** add the `FoundationModels` summary above the retrieved fils.
4. **Reconcile features:** to-dos, pinned fils, the four input modes, first-run onboarding for the
   new gestures.
5. **Promote:** replace `ContentView`'s home with the canvas; retire `NoteGridView`/timeline and the
   theme prototype. (The big surgery — last, once #4 proves out.)

## Sanity check before committing the home
Build #4 retrieval first and confirm that typing a domain surfaces the *right* fils on real data.
If retrieval isn't trustworthy, "only via query" is unsafe (you'd lose access to your thoughts), and
we revisit the escape hatch before stripping browse.
