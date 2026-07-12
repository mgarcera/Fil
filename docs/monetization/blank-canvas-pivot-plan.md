# Fil — the cloud-surfacing pivot (identity, subscription, backend, disclosures)

**Supersedes `fil-pro-plan.md`** (the 2026-07-06 cosmetics-only / no-subscription / stays-on-device
model). The blank-canvas direction added **cloud AI surfacing** (Claude), which breaks two promises
that plan rested on — data leaving the device, and a real recurring per-query cost — so the
monetization and privacy story have to change with it. This doc is the plan for that. Live product
state: `docs/features/blank-canvas-home.md`. **All four headline decisions are now LOCKED
(2026-07-11)** after a research + numbers pass with Mason; see each DECISION block and the "Locked"
summary near the end.

## Why the change
- **Surfacing sends fils to Anthropic's API** → "notes stay on your device" is no longer absolute.
- **Every query costs money** (~$0.01 measured on Haiku 4.5, and it grows with a user's library size
  since the whole corpus is sent) → cosmetics/tips can't reliably cover it; a recurring model can.
- **The dev-key spike is not shippable** — the API key currently lives client-side in AppStorage.

## DECISION 1 — Money model → **Freemium subscription ("Fil Pro"), flat, no credits** *(recommended — now research-grounded)*
Auto-renewing StoreKit 2 subscription unlocks surfacing; **capture stays free forever**. Recurring
revenue matches the recurring API + proxy cost. Skip usage credits for v1 (see findings). The old
cosmetics/tip shop can still exist later as *additional* support, but it's no longer the core model.

### Monetization research (2026) — findings that shaped this
The generic AI-pricing literature screams "flat subscriptions kill AI apps — power users destroy your
margin, use credits/hybrid." **That warning mostly doesn't apply to Fil**, and here's why:
- Those warnings target chat/agent products at **$0.05–$0.30 per conversation** or **$0.50–$5.00 per
  agentic task**; a power user there can cost $90/mo on a $20 plan.
  ([RevenueCat](https://www.revenuecat.com/blog/growth/ai-feature-cost-subscription-app-margins/),
  [digitalapplied](https://www.digitalapplied.com/blog/ai-unit-economics-pricing-margins-services-2026-framework))
- **Fil surfacing is ~$0.01/query** (measured on Haiku, not the ~$0.003 first estimated) and
  **human-paced** (type a query, read a result). Break-even against a $2.99/mo sub is **~300
  queries/month (~10/day)** — most humans won't hit that, but a genuinely heavy daily searcher
  *can*, so it's a real (not theoretical) tail to bound.
- **Cost scales with the user's own library** — the whole fil corpus is sent each query, so a big
  library ⇒ a bigger, pricier payload. This makes the **payload cap / pre-filter (review #10) the #1
  cost lever**, not a minor cleanup (see Finalized model).
- The literature's threshold: **"under $0.10/user/month → bundle it; $1+/user/mo and variable → price
  it explicitly."** ([freemius](https://freemius.com/blog/ai-app-pricing-model/)) A typical Fil user
  (~10–40 surfacings/mo) is **~$0.10–$0.40/user/mo** — just over the bundle line, well under the
  "price-it-explicitly" line. So a **flat freemium sub still fits; credits would add friction for
  little gain — but the free cap + payload cap + a daily rate limit now do real work.**
- **Conversion:** AI apps convert above classic SaaS — good 6–8%, great 15–20% (Claude ~13%); a hard
  paywall earns ~9× the D14 revenue of cheap freemium but forgoes free-user data.
  ([Growth Unhinged](https://www.growthunhinged.com/p/free-to-paid-conversion-report),
  [userpilot](https://userpilot.com/blog/freemium-to-premium/))
- **Free-tier design:** give **full functionality, cap the volume** (≈32% higher conversion than
  crippled features); set the cap **just past the "aha" moment**; fire the upgrade prompt at ~90% of
  the allowance, front-loaded in the first ~2 weeks. A **reverse trial** (full surfacing ~14 days →
  then the free cap) converts well for AI (8–12% "great"). ([PLG Collective via userpilot], freemius)
- **Pricing comps (journal/note apps):** Day One $2.99/mo · $34.99/yr (and its new AI "Gold" tier is
  a direct analog to paid AI reflection); Bear $2.99/mo; Ulysses $5.99/mo · $39.99/yr; Stoic
  $4.99/mo · $39.99/yr. Market band ≈ **$2.99–4.99/mo, ~$20–40/yr**.
  ([Day One plans](https://dayoneapp.com/plans/))

### Finalized model
- **Flat auto-renewing "Fil Pro" — LOCKED at $2.99/mo + $24.99/yr** (2026-07-11; annual ~30% off to
  bias toward commitment). No credits in v1. Rationale: the $1 delta over $1.99 is nearly all margin
  (costs are fixed), ~doubling net profit at every scale while staying in the calm/indie band
  (Day One, Bear). Assumes Apple's 15% Small Business rate.
- **Model tier — LOCKED: Haiku 4.5** (2026-07-11). Testing shows it holds; the ~$0.01/query economics
  depend on it (Sonnet ≈ 3–4× cost, breaks bundling). Sonnet kept as a possible future quality
  toggle / "Pro+", not the default.
- **Backend — LOCKED: Cloudflare Workers** (2026-07-11) for the serverless proxy; Workers KV for
  per-user cost attribution.
- **Free tier = unlimited local keyword search** (find your fils, $0, private) — no volume counter.
  The AI *summary* + semantic/temporal/thematic understanding is the Pro line. **~14-day reverse
  trial** of full AI surfacing at first launch, then it settles to free local search. (See Decision 2
  for the capability split — this supersedes the earlier "small monthly cap" idea.)
- **Guardrails — LOCKED (2026-07-11): no marketed per-user limit; data-first, with invisible
  backstops.** The literature is clear that a *marketed product limit* is off-brand and unnecessary at
  this cost, but shipping with *zero in-path ceiling* is the one genuinely risky choice (billing
  dashboards lag 24–48h, so monitor-and-react can't stop a scripted loop before the bill). So:
  1. **Anthropic account-level spend cap** (their dashboard) — outermost net; total spend can never
     exceed $X/mo regardless of bug/abuse. Set-and-forget.
  2. **Per-user cost attribution in the proxy** — log cost per user ID (proxy is being built anyway).
     This is the "trust the data" instrument: heavy users surface long before they matter.
  3. **Silent circuit-breaker set absurdly high** (~200/day) — not a product limit; an invisible
     runaway guard so a script can't burn all weekend. No human reaches it.
  4. **One-line fair-use clause** in terms: "unlimited" = human-initiated; no bots/scripts/automation.
  Plus the payload cap (#10). Don't advertise the word "unlimited" until ~3 months of data earn it —
  say "surface your thoughts," not "unlimited surfacing."
  *(Each of these four gets expanded when we reach the build phase it belongs to — Mason to co-design.)*

## DECISION 2 — Free/paid line → **split on CAPABILITY: free = local retrieval, Pro = cloud AI understanding** *(LOCKED 2026-07-11)*
The free/paid line is **not** a volume cap on searching your own thoughts (that's extractive and
off-brand, and a good-enough free general search would cannibalize Pro). Instead:
- **Free, unlimited, on-device, $0:** a **local keyword/substring search** over titles + transcripts.
  You can always find your own fils by words you remember. Private, offline, no counter.
- **Pro ($2.99/mo):** **cloud AI surfacing** — the things keyword search structurally *cannot* do:
  semantic / temporal / thematic queries ("what am I forgetting?", "times I felt anxious", "my work
  stuff", "recently"), the warm synthesized **summary**, and type-aware grouping.
- **Reverse trial (~14 days):** full AI surfacing for new users so they feel the magic, then it
  settles to the free local search.

**Why this is the right axis:** keyword search and AI surfacing answer *different needs* — free finds
words you can name; Pro finds thoughts you've forgotten or can't put a keyword to, and hands you the
summary. The "I just want to find a note" user (who was never going to pay) doesn't feel robbed; the
magic + the cost stay behind the wall.

**Free search is deliberately keyword-only** (not on-device embeddings, though the engine exists) — a
clearly weaker literal match sharpens the reason to upgrade, and it's trivial to build.

**Two consequences:**
1. **Fixes a hidden extractive problem:** since the timeline was deleted, fils are currently reachable
   *only* through the paid cloud query — a non-paying user can't reach their own notes at all. The
   free local search is the honest baseline that must exist regardless of monetization.
2. **Free-tier AI cost → ~$0:** free users hit local search, not Claude. So the blended AI-cost column
   in the revenue tables basically collapses to payer-only cost — margins are *better* than projected.

## DECISION 3 — Privacy stance → **keep an on-device-only path; surfacing is opt-in + honestly disclosed** *(recommended)*
Capture, on-device titles, storage, widgets, screensavers stay 100% local. Surfacing is the *only*
thing that sends data out, and only when the user runs a query. Positioning becomes (wording
verified against Anthropic's terms, 2026-07-11):
> "Your thoughts stay on your device. When you ask Fil to surface them, the relevant text is sent
> securely to our AI provider (Anthropic) to answer. It is never used to train models, and is
> deleted within 30 days."
A user who never searches keeps the absolute on-device guarantee.

**Verified facts (Anthropic Commercial/API terms):**
- **Not trained on** — by default Anthropic does NOT train on API inputs/outputs (Commercial Terms).
  ✅ safe to claim.
- **Retention** — the API auto-deletes inputs/outputs within **~30 days** (longer only if content
  is flagged for Usage Policy enforcement). So **"never stored" is FALSE** — say "deleted within 30
  days," not "never stored."
- **Zero Data Retention (ZDR)** — an arrangement (request from Anthropic sales) under which prompts/
  responses aren't stored at rest after the response returns. If we obtain ZDR, we *can* say "not
  stored." Otherwise use the 30-day wording. → tracked in Open decisions.
- The 2025 consumer-terms changes (5-yr retention, opt-in training) apply to Claude.ai consumer
  plans, **NOT** the API/Commercial Terms — doesn't affect us.

## DECISION 4 — Backend → **serverless proxy on Cloudflare Workers** *(LOCKED 2026-07-11)*
A lightweight Cloudflare Worker that: holds the Anthropic key server-side, verifies the user's
StoreKit subscription (App Store Server API / signed transaction) or reverse-trial state, logs
per-user cost to Workers KV (attribution), enforces the silent circuit-breaker, forwards to Claude
(Haiku), returns the result. No free-allowance *metering* is needed — free users never reach the
proxy (they use local keyword search on-device), so the proxy only ever serves Pro + trial users.
Minimal ops, cheap, fast to stand up. The app never sees the key.

## Architecture
```
app (SwiftUI)  ──►  serverless proxy  ──►  Anthropic API
  StoreKit sub        - verify subscription (App Store Server API)
  entitlement         - enforce allowance / rate limit
  no API key          - hold ANTHROPIC_API_KEY (secret)
                      - forward query + fil corpus, return {summary, relevant}
```
- **Client:** replace `ClaudeSurfacingService`'s direct `api.anthropic.com` call + `claudeDevKey`
  with a call to the proxy, authenticated by the StoreKit transaction (JWS) or an app-issued token.
- **Entitlement:** a `StoreManager` (StoreKit 2) exposing `isPro` from `Transaction.currentEntitlements`;
  gate the search button / surfacing on `isPro || withinFreeAllowance`.
- **Payload:** cap/pre-filter the corpus sent per query (ties to review #10) so cost + latency don't
  grow unbounded with library size.

## Disclosures (must ship with the paywall)
- **Privacy policy** update: name Anthropic as a processor, what's sent (fil text for a query), that
  it's **not used to train models** and **deleted within ~30 days** (or "not stored" only if we
  secure ZDR), and that capture stays local. (`docs/legal/privacy-policy.md`, hosted at
  rootcause.ltd/fil/privacy.)
- **App Store privacy nutrition label:** update from "no data collected" — surfacing transmits user
  content to a processor; declare accordingly (likely "User Content" used for App Functionality, not
  linked, not for tracking). Re-answer P2.11's questions for the cloud path.
- **In-app:** a plain-language note at the surfacing entry / first use ("this sends the relevant text
  to our AI"), and the subscription's price/terms/restore per App Store rules.
- **ITSAppUsesNonExemptEncryption / export:** unchanged (standard HTTPS), but re-confirm.

## Identity / altitude cleanups folded in (review #9)
- Rename `BlankCanvasPrototype` → the real home; drop "TEMPORARY prototype / delete when promoted"
  comments and the `showsChrome` scaffolding.
- Remove the dev-key entry sheet + `claudeDevKey` once the proxy is in.
- (Optional) a `Note.kind` enum to replace the ad-hoc `isImageFil`/`hasOpenTodos`/`filKind` ladders
  and centralize the prompt-format contract.

## Phased build
1. ✅ **Proxy MVP (Cloudflare Worker)** — deployed at `fil-surfacing-proxy.mason-2fe.workers.dev`,
   holds `ANTHROPIC_API_KEY`, Haiku; client ported. (2026-07-11/12)
2. ✅ **Local keyword search (the free tier)** — on-device keyword/substring over title + transcript;
   queries branch on `isPro` (Pro → cloud, free → local). Fixes the "fils only reachable via paid
   cloud" gap.
3. ✅ **StoreKit (client)** — `StoreManager` (StoreKit 2, `isPro` + transaction id), local
   `Products.storekit` with monthly $2.99 / annual $24.99 + 2-week free trial. *ASC products +
   sandbox tester still to finish for real testing.*
4. ✅ **Subscription verification in the proxy** — App Store Server API (ES256 auth via the In-App
   Purchase `.p8`, Get All Subscription Statuses, prod→sandbox); shared secret removed. *Per-user KV
   attribution + silent ~200/day circuit-breaker still TODO.*
5. ✅ **Paywall + gating** — native `SubscriptionStoreView` + a bespoke Fil marketing header; free
   users see a calm "found by keyword / fil pro can surface" invite that opens it; success flips
   `isPro`. *(Reverse-trial via StoreKit intro offer; verdict on header copy pending.)*
6. ⬜ **Disclosures:** privacy policy, nutrition label, in-app note, terms link (incl. the fair-use
   clause). Say "surface your thoughts," not "unlimited."
7. ⬜ **Altitude cleanups** (#9): rename `BlankCanvasPrototype` → real home, optional `Note.kind`.
   (Dev-key path already removed in phase 4.)
8. ⬜ **Re-home capture modes + onboarding (#5):** voice/photo/link capture and the first-fil seed
   reveal, so the paid home is also a complete capture home.

**Still TODO (cost controls, deferred):** per-user cost attribution (Workers KV) + the silent
~200/day circuit-breaker in the proxy; the payload cap / pre-filter (review #10).

**Set-and-forget (not a code phase):** set the **Anthropic account-level spend cap** in the console
— the outermost backstop. *(Confirm done.)*

**Testing note:** the App Store Server API can't verify local `.storekit` transactions, so the cloud
path must be tested in **sandbox** (products live in ASC + a sandbox tester + subscribe on device).
Local `.storekit` still exercises the paywall + the `isPro` flip.

## Locked (2026-07-11) — was "open"
- **Price:** $2.99/mo + $24.99/yr. **Model:** Haiku 4.5. **Backend:** Cloudflare Workers.
- **Free/paid line:** capability split — free = unlimited local keyword search; Pro = cloud AI
  surfacing + summary; ~14-day reverse trial. No volume metering on free.
- **Guardrails:** no marketed limit; Anthropic account cap + proxy per-user attribution + silent
  ~200/day circuit-breaker + fair-use clause.
- **Offline / no-Pro behavior:** resolved by the split — the query entry is always present; a free /
  offline user gets local keyword results (never hidden, never a hard paywall wall), with an upgrade
  nudge when the query is one only AI could satisfy.

## Still open
- **Fate of the old cosmetics shop** — drop, or keep as optional extra support alongside Pro.
- **Zero Data Retention** — pursue a ZDR agreement with Anthropic (lets us say "not stored," a
  stronger privacy claim) vs. ship with the default 30-day-deletion wording.
- **Reverse-trial mechanics** — exact length (~14d), how trial state is tracked (StoreKit intro
  offer vs app-side flag), and what the downgrade moment feels like.
- **Circuit-breaker number** — start ~200/day, tune from attribution data.
- **Prompt-cache use at scale** — the corpus prefix is cacheable (Haiku 4096-token min); worth it
  once payloads/library sizes are known (ties to the #10 payload cap).

## Verification / gates before shipping
- Proxy: key never in the client build; subscription verified server-side (can't be spoofed);
  rate-limit + allowance enforced.
- StoreKit: purchase, restore, expiry, and the free→Pro transition all correct (test with the
  `.storekit` config and sandbox).
- Privacy: policy + nutrition label match actual data flow; in-app disclosure present before any
  send.
- App Review: subscription metadata, restore, and privacy answers complete.
