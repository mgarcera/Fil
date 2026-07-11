# Fil — the cloud-surfacing pivot (identity, subscription, backend, disclosures)

**Supersedes `fil-pro-plan.md`** (the 2026-07-06 cosmetics-only / no-subscription / stays-on-device
model). The blank-canvas direction added **cloud AI surfacing** (Claude), which breaks two promises
that plan rested on — data leaving the device, and a real recurring per-query cost — so the
monetization and privacy story have to change with it. This doc is the plan for that. Live product
state: `docs/features/blank-canvas-home.md`. All four headline choices below are **recommendations
pending Mason's confirm** (marked DECISION).

## Why the change
- **Surfacing sends fils to Anthropic's API** → "notes stay on your device" is no longer absolute.
- **Every query costs money** (~$0.003 on Haiku 4.5, non-zero, scales with use) → cosmetics/tips
  can't reliably cover it; a recurring model can.
- **The dev-key spike is not shippable** — the API key currently lives client-side in AppStorage.

## DECISION 1 — Money model → **Freemium subscription ("Fil Pro")** *(recommended)*
Auto-renewing StoreKit 2 subscription unlocks surfacing; **capture stays free forever**. Recurring
revenue matches the recurring API + proxy cost. (Alternatives: usage-credit IAP packs; or
cosmetics-only + free surfacing — financially risky. The old cosmetics/tip shop can still exist
later as *additional* support, but it's no longer the core model.)

## DECISION 2 — Free/paid line → **capture free + a small surfacing taste, then Pro** *(recommended)*
Everyone captures unlimited fils and on-device titles free, and gets a small monthly surfacing
allowance (e.g. ~5 searches/month) so they feel the magic before paying. Beyond that → Pro.
(Alternatives: surfacing fully Pro, no free taste; or all-free beta to learn first.)

## DECISION 3 — Privacy stance → **keep an on-device-only path; surfacing is opt-in + honestly disclosed** *(recommended)*
Capture, on-device titles, storage, widgets, screensavers stay 100% local. Surfacing is the *only*
thing that sends data out, and only when the user runs a query. Positioning becomes:
> "Your thoughts stay on your device. When you ask Fil to surface them, the relevant text is sent
> securely to our AI to answer — never stored, never used for training."
A user who never searches keeps the absolute on-device guarantee. (Anthropic's API does not train on
submitted data by default — the backbone of this claim; verify current terms at build time.)

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
  it's transient / not trained on / not stored, and that capture stays local. (`docs/legal/privacy-policy.md`,
  hosted at rootcause.ltd/fil/privacy.)
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

## Verification / gates before shipping
- Proxy: key never in the client build; subscription verified server-side (can't be spoofed);
  rate-limit + allowance enforced.
- StoreKit: purchase, restore, expiry, and the free→Pro transition all correct (test with the
  `.storekit` config and sandbox).
- Privacy: policy + nutrition label match actual data flow; in-app disclosure present before any
  send.
- App Review: subscription metadata, restore, and privacy answers complete.
