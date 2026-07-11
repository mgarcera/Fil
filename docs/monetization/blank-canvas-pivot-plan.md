# Fil — the cloud-surfacing pivot (identity, subscription, backend, disclosures)

**Supersedes `fil-pro-plan.md`** (the 2026-07-06 cosmetics-only / no-subscription / stays-on-device
model). The blank-canvas direction added **cloud AI surfacing** (Claude), which breaks two promises
that plan rested on — data leaving the device, and a real recurring per-query cost — so the
monetization and privacy story have to change with it. This doc is the plan for that. Live product
state: `docs/features/blank-canvas-home.md`. All four headline choices below are **recommendations
pending Mason's confirm** (marked DECISION).

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
- **Flat auto-renewing "Fil Pro"**, priced in-band (lean **$2.99/mo + a discounted annual ~$24.99**;
  bias people to annual). No credits in v1.
- **Free tier = full-featured surfacing, small monthly cap** (start ~5–10/mo; tune from real cohort
  data — no universal number). Upgrade prompt at ~90% of the cap. Consider a **reverse trial** at
  launch.
- **Guardrails at the proxy** (cheap but not free): a per-user **daily rate limit** to kill scripted
  abuse, plus the payload cap (#10). No literal "unlimited" marketing until usage data backs it —
  though for humans it's effectively unlimited at this cost.

## DECISION 2 — Free/paid line → **capture free + a small surfacing taste, then Pro** *(recommended)*
Everyone captures unlimited fils and on-device titles free, and gets a small monthly surfacing
allowance (e.g. ~5 searches/month) so they feel the magic before paying. Beyond that → Pro.
(Alternatives: surfacing fully Pro, no free taste; or all-free beta to learn first.)

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

## DECISION 4 — Backend → **serverless proxy** *(recommended)*
A lightweight function (Cloudflare Workers / Vercel) that: holds the Anthropic key server-side,
verifies the user's StoreKit subscription (App Store Server API / signed transaction), enforces
per-user rate limits + the free allowance, forwards to Claude, returns the result. Minimal ops,
cheap, fast to stand up. The app never sees the key. (Alternative: a full managed backend for more
caching/abuse control.)

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
1. **Proxy MVP:** stand up the serverless function with the key; port `ClaudeSurfacingService` to
   call it (still ungated) — proves the client→proxy→Claude path end-to-end, key off-device.
2. **StoreKit:** `StoreManager`, an auto-renewing subscription product in App Store Connect, a
   `.storekit` config; `isPro` entitlement.
3. **Subscription verification in the proxy** (App Store Server API) + free-allowance/rate-limit
   accounting.
4. **Paywall + gating:** gate surfacing on `isPro`/allowance; a calm, on-brand upgrade screen (voice
   per `/fil-voice`); Restore.
5. **Disclosures:** privacy policy, nutrition label, in-app note, terms link.
6. **Altitude cleanups** (#9): rename, remove dev-key path, optional `Note.kind`.
7. **Re-home capture modes + onboarding (#5):** voice/photo/link capture and the first-fil seed
   reveal, so the paid home is also a complete capture home.

## Open decisions (beyond the four above)
- **Price** (monthly / annual; e.g. ~$2.99/mo or ~$19.99/yr) and the exact free allowance.
- **Proxy host** (Cloudflare Workers vs Vercel) + how the free allowance is tracked (per Apple
  account? device? anonymous id?).
- **Model tier** for production (Haiku vs Sonnet) and prompt-cache use at scale.
- **Fate of the old cosmetics shop** — drop, or keep as optional extra support alongside Pro.
- **Offline / no-Pro behavior** of the surfacing entry (hide vs show-with-paywall).
- **Zero Data Retention** — pursue a ZDR agreement with Anthropic (lets us say "not stored," a
  stronger privacy claim) vs. ship with the default 30-day-deletion wording.

## Verification / gates before shipping
- Proxy: key never in the client build; subscription verified server-side (can't be spoofed);
  rate-limit + allowance enforced.
- StoreKit: purchase, restore, expiry, and the free→Pro transition all correct (test with the
  `.storekit` config and sandbox).
- Privacy: policy + nutrition label match actual data flow; in-app disclosure present before any
  send.
- App Review: subscription metadata, restore, and privacy answers complete.
