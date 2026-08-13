# Fil a Folder

An agent that *fills* a brand-new folder with generated content. The user names a theme, optionally
answers 1–3 clarifying questions (the Remindown copilot pattern), picks **how many notes / links /
to-dos**, and Fil generates them: notes written, links found (real URLs via web search), to-dos
created. Pro-only (Claude + web search cost). Replaces the old smart-organize/clustering grouping.

Status: **POST-V1 — design only, deprioritized (decided 2026-08-13).** Model tier: **Haiku 4.5**
(locked; see docs/monetization/blank-canvas-pivot-plan.md).

> **Consequence of the post-v1 call:** smart-organize **stays in v1**. Its removal was only ever
> premised on Fil a Folder replacing it, so punch-list items 4 and 8 — and the "remove `organize`"
> half of item 5 — are **void, not deferred**. Smart-organize is live, Pro-gated, and was improved
> as recently as 2026-08-12 (folder captions). v1's Pro story is surfacing **plus** smart-organize.

## Punch list
| # | Item | Status |
|---|------|--------|
| 1 | Price-test Fil a Folder on Haiku 4.5 (prompts + cost worksheet below; measure a real run) | ▫️ in progress |
| 2 | Lock the design forks (to-dos shape, links-in-v1, Q&A step, review step, caps) | ▫️ open |
| 3 | Cloudflare worker: add `fil-a-folder` endpoint (notes/links/todos; web search for links) | ▫️ blocked on infra (Mason) |
| 4 | ~~Cloudflare worker: REMOVE the `organize` endpoint~~ | ❌ VOID — organize stays in v1 |
| 5 | Client: `ClaudeSurfacingService.filAFolder(...)` (~~remove `organize` + `OrganizedFolder`~~ — void) | ▫️ not started |
| 6 | Client: `FilAFolderView` copilot sheet (name → Q&A → steppers → generate → review → create) | ▫️ not started |
| 7 | Client: build folder + fils from result (notes; link fils via LinkFil; to-dos fil) | ▫️ not started |
| 8 | ~~Remove old smart-organize UI: `organizeRequest`, `organize()`, `apply()`, organizing/error, ✨ control~~ | ❌ VOID — smart-organize stays in v1 |
| 9 | Pro gate + per-type caps + daily rate limit (reuse circuit-breaker) | ▫️ not started |
| ✓ | Delete dead on-device `FilClusteringService` (kept `FilClusterInput`) | ✅ done 2026-08-11 |

## Open forks (decide before building the client)
1. **To-dos**: one fil holding N items, or N separate to-do fils?
2. **Links in v1**: ship real web-search links now, or start notes+to-dos and add links when the worker's search is ready?
3. **Q&A step**: keep clarifying questions before the steppers, or steppers-only?
4. **Review step**: review/edit/deselect before create (recommended), or auto-create?
5. **Caps** per type (proposed: notes ≤ 8, links ≤ 5, to-dos ≤ 12).

## Flow
name it → (optional) clarify Q&A → steppers (Notes / Links / To-dos) → agent runs (gooey "filling"
animation) → review generated set → create folder + fils, drop in. Success haptic.

## Price test — Haiku 4.5 (fill in the measured columns)

### Prompt A — clarify (JSON out, ~120 max tokens)
> The user is creating a folder themed: "{theme}". Ask 1–3 short questions to understand what they
> want in it (angle, scope, tone). Respond as a JSON array of strings.

### Prompt B — generate (JSON out)
> Create content for a folder themed "{theme}".
> User clarifications:
> {qa}
> Generate exactly:
> - {N} notes — each {title, body ~80–120 words}
> - {L} link search queries — short topics to web-search for real URLs (do NOT invent URLs)
> - {T} to-do items
> Return JSON: {"notes":[{"title","body"}], "linkQueries":[...], "todos":[...]}

The worker then runs web search on `linkQueries` (per-query OR one aggregated), resolves real URLs,
and the client builds link fils via `LinkFil.fetchDescription`.

### Cost worksheet (assumptions — replace with measured)
Rates (CONFIRM against current pricing): Haiku 4.5 ≈ $1.00/MTok in, $5.00/MTok out; web search ≈
$10 / 1,000 searches ($0.01/search).

| Piece | in tok (est) | out tok (est) | est cost | MEASURED |
|---|---|---|---|---|
| Clarify | ~200 | ~100 | ~$0.0007 | |
| Generate (8 notes + 12 todos + 5 link queries) | ~500 | ~1,600 | ~$0.008 | |
| Links — one aggregated search | +search results ~8k in | — | ~$0.01 search + ~$0.008 tok | |
| Links — per-search (×5) | +results ~5×5k in | — | ~$0.05 search + ~$0.025 tok | |

**Est totals:** notes+to-dos only ≈ **$0.01** (≈ one surfacing query); + aggregated-search links ≈
**$0.025–0.03**; + per-search links ≈ **$0.06+**. → **Bound links: cap ≤5 and use ONE aggregated
search.** Break-even vs $2.99/mo (Apple SB 15%): with links ~$0.03/run, ~85 runs/mo; measure to confirm.

### To measure (Mason)
Run Prompt A + B on Haiku 4.5 (Anthropic console/worker) for a representative theme; record real
input/output tokens + search count for both link strategies; plug into the MEASURED column.
