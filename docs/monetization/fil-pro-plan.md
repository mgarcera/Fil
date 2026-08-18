# Fil — Monetization Plan (Support + Cosmetic Shop)

> **⚠️ SUPERSEDED (2026-07-11) by [`blank-canvas-pivot-plan.md`](./blank-canvas-pivot-plan.md).**
> The blank-canvas direction added cloud AI surfacing (a real recurring per-query cost), which breaks
> the two premises this plan rested on — "stays on device" and "no per-use cost." The live money model
> is now a flat freemium **Fil Pro** subscription ($2.99/mo + $24.99/yr, capability-split free tier).
> This file is kept for history only; the cosmetics/tip shop may still return as *optional extra*
> support, but it is no longer the core model.

*Phase 5 strategy. Final model locked with Mason 2026-07-06. Supersedes every earlier framing
(subscription, iCloud-sync-hero, summaries-gate). There is intentionally **no "Pro" tier** and
**nothing essential is ever gated** — monetization is optional support + cosmetics only.*

---

## The model

**À la carte cosmetics + a "Support Fil" bundle unlock + an optional tip.** No tiers. Everything
that makes Fil *Fil* — capture, on-device titles, widgets, Live Activity, share, screensavers you
earn by use — stays **free forever**. Money is something people can choose to give because they
love the app, and get a little delight in return.

Why this fits: it's the generous, anti-treadmill soul of Fil ("fil doesn't ask you to be
consistent"); it sidesteps the loss-anxiety of gating data/features; it needs **no sync, no
migration, no summaries rebuild**; and the price feeling ($2–5 for a delight) matches the value.

### The three purchase types (all via StoreKit IAP)

1. **"Support Fil"** — a **non-consumable** (~$4.99–6.99). Unlocks a **supporter-exclusive set** of
   cosmetics that *can't be bought individually* — e.g. a special app icon, a special screensaver,
   a special sound pack. This is the "thank-you you can only get by supporting."
2. **À la carte shop** — individual **non-consumables** (~$0.99–2.99 each): buy a specific alt app
   icon, a sound pack, or an extra screensaver on its own. "No tiers, pick what you want."
3. **Tip** *(optional)* — a **consumable** (repeatable, e.g. $1.99 / $4.99) that unlocks nothing;
   pure support for people who just want to say thanks. (Consumable because it's repeatable and
   grants nothing permanent.)

> Legal/mechanics: all of this is standard, allowed StoreKit IAP. Non-consumables (Support + à la
> carte) are permanent and **require "Restore Purchases."** The consumable tip grants nothing so it
> needs no restore. "Tip"/"support" is marketing framing on ordinary IAP — just don't call it a
> tax-deductible donation or route payment outside Apple.

## What stays free (never gated)
Everything shipped in Phases 1–4 and all core capture. The only things behind a purchase are
**cosmetics** (icons, sound packs, extra screensavers) and the optional tip. The earn-by-usage
screensavers stay free; purchased screensavers are *additional* variety, not a takeover.

## Surfaces
- **A "shop" tab in Settings.** `SettingsView` already has a tab bar (`SettingsSection`:
  writing / sound / screensaver / about) — add a **shop** (or "support") tab hosting: the Support
  Fil unlock (featured at top), the à la carte grid, the tip options, and **Restore Purchases**.
- Optionally a gentle one-line "support fil" link in About (no nagging, no interruptive paywall).

## Brand / copy — all clean
- **"No subscription" stays true.** **"Notes stay on your device" stays true** (no sync).
- Nothing essential gated → no dark-pattern feel, no loss-anxiety. Framing: "support fil, get a
  little something," never "unlock the app."

---

## Prerequisites & build shape (no data-layer changes anywhere)

### A. StoreKit 2 plumbing
- Add the **In-App Purchase** capability.
- Define products in App Store Connect:
  - `com.smidgecraft.Fil.support` (non-consumable) — the Support bundle.
  - à la carte non-consumables, e.g. `…icon.<name>`, `…sounds.<name>`, `…screensaver.<name>`.
  - optional `…tip.small` / `…tip.large` (consumables).
- A `.storekit` config file for local testing.
- A `StoreManager`: load products, `purchase()`, `restore`, observe `Transaction.currentEntitlements`,
  expose per-product ownership (`owns(_ id:)`) + `hasSupported`.

### B. The shop UI (Settings tab)
- New `SettingsSection.shop`; a calm, on-brand shop view (manifesto voice — "support fil", not
  "GO PRO"). Featured Support unlock, à la carte grid, tip row, Restore link, Terms link.

### C. Cosmetic content + gating
- **Alt app icons** via `setAlternateIconName` (each gated on its product; supporter-set icons gated
  on `hasSupported`).
- **Sound packs** — additional SoundscapeManager sets, selectable once owned.
- **Extra screensavers** — new variants in the screensaver system, unlocked per purchase.
- Gating is pure feature-flags against ownership; **no model/schema changes**.

### D. Legal
- Terms/EULA already drafted; link from the shop. Show price + "one-time" clearly. Restore present.

### E. Analytics (light, first-party)
- Shop views, purchases, restores, tips — enough to see what resonates. No third-party SDKs.

## Suggested build order
1. **StoreKit `StoreManager` + `.storekit` config** (headless; test with local config).
2. **Shop tab in Settings** + Restore.
3. **First cosmetics**: 1–2 alt icons + the Support bundle exclusive icon (smallest satisfying set).
4. Sound packs / extra screensavers as follow-on content.
5. Tip consumable + analytics.

## Open decisions (catalog + pricing)
- **Support Fil price** (~$4.99–6.99) and **what's in the supporter-exclusive set** (which icon /
  screensaver / sound pack are supporter-only).
- **À la carte catalog + prices** — which icons/sounds/screensavers exist, which are individually
  sold vs supporter-only, and each price (~$0.99–2.99).
- **Tip amounts** (and whether to include a tip at all for v1).

## Deferred / separate
- **Onboarding copy fix** — the current onboarding promises the old (removed) summary feature; must
  be corrected before launch regardless of monetization. **Mason is sending an onboarding pattern**
  he prefers; handle then. (Not a monetization item, but tracked so it isn't forgotten.)
- **Summaries** — not part of monetization anymore. If ever re-added, it's a free feature, its own
  decision.
- **iCloud sync** — shelved; scope preserved in `icloud-readiness-scope.md`.
