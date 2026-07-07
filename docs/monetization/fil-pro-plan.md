# Fil Pro — Monetization Plan

*Phase 5 strategy. Decisions locked with Mason 2026-07-06. Supersedes the audit's default
(subscription + summaries-as-hero) and an interim iCloud-sync-as-hero idea (shelved — see below).*

---

## Model & positioning

- **Model: one-time lifetime unlock** (a StoreKit **non-consumable** IAP). No subscription.
  - **Keeps the brand promise intact** — the App Store copy and website already say *"no
    subscription"*; lifetime honors that and the anti-treadmill ethos. Pay once, own it, no nagging.
  - All AI is on-device (zero marginal cost), so there's no recurring-billing justification anyway.
- **Price: $14.99** one-time to start (Small Business Program → ~$12.74 net). Raise later if wanted.
- **Paid hero: a "Fil Pro" bundle** — the **"zoom out" summaries** + **all screensavers unlocked**
  + **extra ambience** (alt app icons, sound packs, more screensavers). All **local, no CloudKit,
  no migration.**

### Why NOT iCloud sync as the hero (decided after scoping — see `icloud-readiness-scope.md`)
- **Ironically weak for a voice app:** audio recordings are loose files that don't sync via
  SwiftData, so synced voice fils would arrive silent — and fixing that makes the migration heavier.
- **Known tar pit:** a prior attempt cost ~a full day and was reverted with cascading surprises;
  CloudKit's runtime constraints (additive-only production schema, relationship ordering, no unique
  constraints) surface late. Not worth doing under launch pressure.
- **Highest-risk, fully optional** — nothing about launch needs it.
- → **Shelved** as a deliberate, unpressured *maybe-later v2*. Monetization is decoupled from it.

## Free vs Pro

**Free stays genuinely excellent** (crippling it would betray the ethos):
- all capture — voice, text, image, link
- on-device AI titles
- home-screen widget, Live Activity / Dynamic Island, share extension
- the earn-by-usage screensavers (unlock as you create fils)
- outbound share cards, in-app review, everything shipped in Phases 1–4

**Fil Pro (one-time unlock):**
- **"zoom out" summaries** — week / month / year / all-time reflective views (the anchor)
- **all screensavers unlocked instantly** (keep the earn-by-usage path free too)
- **extra ambience** — alternate app icons, sound packs, and/or additional screensavers
- framed as *more calm, more delight* — never *more productivity*

## Brand / copy implications

1. **"No subscription" stays true** — no change.
2. **"Your notes stay on your device" stays 100% true** — because there's no sync, the privacy
   story needs *no* nuancing (a real bonus of this path vs. the sync route).
3. **Summaries must be built** — they're currently hardcoded onboarding preview text
   (`OpenTodoSummaryService.swift` was deleted). This is the gating feature build. Frame as
   reflection, not productivity metrics.

---

## Prerequisites & sequencing

### A. Build the "zoom out" summaries (the gating feature)
- Replace the hardcoded onboarding preview with a real feature: week / month / year / all-time
  views over the user's fils. On-device only. Reflective tone (what surfaced, recurring keywords,
  gentle recap) — not charts/streaks/productivity metrics.
- No schema change required (reads existing `Note` data).

### B. StoreKit 2 (lifetime unlock)
- Add the **In-App Purchase** capability.
- One **non-consumable** product in App Store Connect (e.g. `com.masongarcera.Fil.pro.lifetime`).
- A `.storekit` config file for local testing.
- A small `StoreManager`: load product, `purchase()`, observe `Transaction.currentEntitlements`,
  expose `isPro`.
- **"Restore Purchases" required** for non-consumables (Guideline 3.1.1) — put it on the paywall.

### C. Gate the Pro features on `isPro`
- Summaries, all-screensavers, ambience extras check `isPro`; free users see a gentle upsell.
- Pure feature-flag gating — no data-layer changes.

### D. Paywall
- Calm, on-brand (manifesto voice), one product, one price, restore link, Privacy + Terms links.
- Entry points: a "Fil Pro" row in Settings + a gentle prompt when a Pro feature is tapped.

### E. Legal & analytics
- Terms/EULA already drafted; link from the paywall; show "one-time purchase" + price clearly.
- Lightweight first-party analytics (paywall views, purchases, restores) — no third-party SDKs.

### F. Ambience content
- Design/produce the alt app icons + sound pack(s) / extra screensavers that make the bundle feel
  worth it. Low technical risk; mostly assets.

---

## Suggested build order
1. **Summaries feature** (A) — the anchor; ship-able even before the paywall exists (free at first
   if desired, then gate).
2. **StoreKit lifetime unlock + `isPro`** (B) — headless.
3. **Gate Pro features** (C) + **paywall + Settings entry + Restore** (D).
4. **Ambience content** (F) — parallel asset work.
5. Analytics (E) alongside the paywall.

## Open questions
- **Price:** $14.99 (recommended) vs $19.99.
- **Summaries scope:** which time windows ship first; how "reflective" vs "recap" the tone is.
- **Ambience contents:** how many icons/sounds/screensavers make the bundle feel substantial.
- **Screensavers:** keep the earn-by-usage unlock free AND offer instant-unlock via Pro (recommended
  — free users aren't blocked, Pro is a shortcut + more variety).

## Shelved (future, only if ever revisited)
- **iCloud sync** — full scope preserved in `icloud-readiness-scope.md`. If pursued later: solve
  audio sync first, do the schema migration deliberately (not under launch pressure), test on a
  seeded store. The CloudKit-readiness schema changes are also decent hygiene independent of sync.
