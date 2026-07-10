# Theme clustering — reorganizing the home by content, not time

A design for grouping fils into **automatic, emergent themes** as the primary home, replacing the
day-based timeline. All on-device. Status: **design** (a UI prototype exists; the engine is not built).

## Vision & brand guardrails
Fil is anti-optimization — "no inbox, no tags, no streaks." Themes must read as **tracing** thoughts,
not **filing** them. Non-negotiables:
- **Zero user effort.** No user-created labels, folders, or confirmations. The app notices; the user
  does nothing.
- **Ephemeral.** Clusters are recomputed, never persisted as folders. You can't "clear" or "manage"
  a theme.
- **Discovery, not management.** No counts-as-scores, no "you should organize" nudges.

Decided: **theme is the home** (primary), time demotes to newest-first *within* a theme.

## Current prototype (feel locked)
`Fil/Fil/Views/ThemeHomePrototype.swift` (temporary, reached via a grid button in the home header):
a vertical scroll of named theme sections, each an always-open list of **blob + title rows** (à la
`TodoSheet`), so you can tell fils apart. Clusters are **mock** (stable UUID hash into fixed buckets).
The real engine's job is to replace that mock grouping — the UI stays.

## Architecture — three on-device stages

### 1. Embed each fil → a vector
Meaning, not keywords.
- **v1: `NLEmbedding.sentenceEmbedding(for:)`** — one call → one vector per fil, no setup; Apple
  recommends it for semantic-similarity tasks. Per-language; returns `nil` for unsupported languages
  → fall through to the deterministic tier.
- **v2 upgrade: `NLContextualEmbedding`** — deeper BERT-style vectors, but returns *subword* vectors
  to mean-pool and needs an asset download (`requestAssets` / `hasAvailableAssets`).
- **Cache** each vector keyed by `(note.uuid, textHash)`; only (re)embed on create/edit. Store as a
  side cache (e.g. a small `@Model FilEmbedding { uuid, vector: [Float], textHash }` or a persisted
  dictionary) — not inline on `Note`.
- Fil text to embed: `transcript` (fallback `title`/`keyword`), trimmed.

### 2. Cluster the vectors → groups
- Similarity = **cosine**. Count is unknown, so **not** fixed-k. Use **greedy / agglomerative
  threshold clustering**: merge fils above a similarity threshold; cluster count emerges.
- Bound to ~3–8 sections; route loners into an **"everything else"** catch-all.
- O(n²) similarity is trivial at phone scale (dozens–hundreds); run **off-main**.
- **Ephemeral** — recomputed, never saved as folders.

### 3. Name each cluster → a label
- **v2: `FoundationModels`** (same on-device LLM as titles): a `@Generable` short label from the
  cluster's fil titles. Availability-gated + slower.
- **v1 / fallback: dominant filament keyword** in the cluster, or the most-central fil's title.
  Deterministic, instant, universal. Names are ephemeral, never user-confirmed.

## Service shape
`FilClusteringService` — an `actor` for the heavy work, surfacing an `@Observable` result:
- Embeds incrementally (one fil on create/edit, off-main).
- Clusters + names on a **debounced cadence**: on theme-view appear, or when fils change past a
  threshold. Caches the result until fils change.
- Output: `[ThemeCluster { name: String, fils: [Note] }]` — which the theme home renders exactly like
  the prototype (name header + blob-title rows). UI change = swap mock `themes`/`fils(in:)` for this.

## Robustness & gates
- **Tiered fallback:** contextual → sentence embedding → **filament/keyword grouping** (deterministic,
  no ML). The home always renders something sensible.
- **Cold start:** gate the theme view behind ~10 fils (like the koi pond); the reveal becomes a moment.
- **Stability:** re-cluster gently (animate re-settling); never reshuffle on every keystroke.
- **Battery/perf:** embed one fil at a time; cluster off-main; cache aggressively.
- **Privacy:** 100% on-device — consistent with the "stays on your device" claim.

## Open decisions
- Similarity **threshold** + min/max cluster sizes (tune empirically once the engine logs real
  clusters).
- Whether a fil can appear in **more than one** theme (soft) — start **hard** (nearest cluster wins).
- Time's remaining presence: is the day grid still reachable as a secondary lens, or fully retired?
- Where cached embeddings live (side `@Model` vs. persisted dict).

## Phased build
1. **v1 engine:** `FilClusteringService` = `NLEmbedding.sentenceEmbedding` + greedy-threshold
   clustering + keyword naming + cache; deterministic keyword fallback. No asset download, no gated
   LLM → ships to every device.
2. **Wire to the theme home:** replace the prototype's mock grouping with the service output; keep the
   blob-title-row UI. Add the 10-fil gate + gentle re-settle.
3. **v2 quality:** `NLContextualEmbedding` embeddings + `FoundationModels` cluster naming, behind
   availability checks with the v1 path as fallback.
4. **Decide time's fate** and (if kept) the day↔theme lens toggle.

## Sanity check before shipping
Build the service first and **log the clusters it produces on real fils** — validate that groupings
feel meaningful before committing the home to them.
