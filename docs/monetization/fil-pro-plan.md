# Fil Pro — Monetization Plan

*Phase 5 strategy. Decisions locked with Mason 2026-07-06. Supersedes the audit's default
(subscription + summaries-as-hero) where they differ.*

---

## Model & positioning

- **Model: one-time lifetime unlock** (a StoreKit **non-consumable** IAP). No subscription.
  - **This keeps the brand promise intact** — the App Store copy and website already say *"no
    subscription."* Lifetime honors that *and* the anti-treadmill ethos ("fil doesn't ask you to be
    consistent"). Pay once, own it, no nagging.
  - Since all AI is on-device (zero marginal cost per user), there's no "cover our server bills"
    story to justify recurring billing — one-time is the honest fit.
- **Price: $14.99–19.99** one-time. Lean **$14.99** to start (easy yes for a coined-name indie app;
  can raise later). Enroll in the **Small Business Program** (15% commission → ~$12.74 net at
  $14.99).
- **Paid hero: iCloud sync** (your notes on all your devices, later Mac/iPad). This is the value
  people will happily pay once for.

## Free vs Pro

**Free stays genuinely excellent** (crippling it would betray the ethos):
- all capture — voice, text, image, link
- on-device AI titles
- home-screen widget, Live Activity / Dynamic Island, share extension
- the **"zoom out" summaries** (week / month / year / all-time) — **moved to free**
- the earn-by-usage screensavers

**Fil Pro (one-time):**
- **iCloud sync** across devices (the hero)
- **all screensavers unlocked instantly** (keep the earn-by-usage path free too)
- future: **Mac / iPad** apps, and any later power niceties
- framed as *more calm, more continuity* — never *more productivity*

## Brand / copy implications

1. **"No subscription" stays true** — no copy change needed there. 
2. **Privacy wording needs a careful nuance for sync.** Today: *"your notes stay on your phone / never leave your device."* With Pro sync, a user's notes go to **their own private iCloud** (CloudKit private database) — Apple-hosted, end-to-end within their account, **never our servers**. Update the privacy policy + any "stays on your device" copy to: *"on your device by default; with iCloud sync on, through your own private iCloud — never our servers."* Keep the free-tier default as fully on-device.
3. Onboarding currently markets summaries as if they exist — since they're now **free**, they still must be **built** to not be misleading (see prerequisites).

---

## Prerequisites & sequencing

### A. CloudKit model prep — the real gating work (do first, carefully)
Enabling SwiftData + CloudKit imposes schema rules the `Note` model currently violates:

1. **Remove `@Attribute(.unique)` from `Note.uuid`** — CloudKit forbids unique constraints. Replace
   with **app-level dedup** (we already handle `ZNOTE.ZUUID` collisions in `FilApp`; fold that into
   a dedup-on-insert/merge instead of relying on the DB constraint).
2. **Give every non-optional attribute a default** (or make it optional): `title`, `transcript`,
   `audioFilePath`, `timestamp`, `duration`, `todos`, `completedTodos`, `calibrationNotes`,
   `threadedBacklinks` (others like `keyword`, gradients already have defaults).
3. **Make relationship inverses optional** — `KeywordAttachment.note`, `NoteImage.note` (verify +
   adjust the `NoteImage` / `KeywordAttachment` models).
4. **Keep `.externalStorage`** (favicon/image data) — supported with CloudKit (becomes CKAsset).
5. **Migration:** these are schema changes on existing v1 stores. Add defaults = lightweight;
   removing the unique constraint needs a tested migration. Ship + test on a seeded store before
   release. **Risk: losing the DB-level uniqueness guarantee** — the app must not create dup uuids.

> Recommendation: do this schema prep as its own isolated, well-tested change even though sync
> ships later — it's foundational and migration-sensitive, and it's cleaner to land before the
> user base grows.

### B. StoreKit 2 (lifetime unlock)
- Add the **In-App Purchase** capability (entitlement).
- Create **one non-consumable** product in App Store Connect (e.g. `com.masongarcera.Fil.pro.lifetime`).
- Add a `.storekit` **configuration file** for local testing.
- Implement a small `StoreManager`: load product, `purchase()`, observe `Transaction.currentEntitlements`, expose `isPro`.
- **"Restore Purchases" is required** for non-consumables (Guideline 3.1.1) — put it on the paywall.

### C. Paywall
- On-brand, calm paywall (manifesto voice — not a hard-sell). One product, one price, restore link,
  links to Privacy + Terms.
- Entry points: a "Fil Pro" row in Settings, and a gentle prompt when a Pro-gated action is tapped
  (turn on sync / unlock all screensavers).

### D. Legal
- Terms/EULA already drafted; link them from the paywall. Apple's Standard EULA covers a
  non-consumable, but the paywall must show price + "one-time purchase" clearly.
- Update the **privacy policy** for the iCloud-sync nuance (see brand implications #2).

### E. Analytics
- Lightweight, first-party (no third-party SDKs): paywall impressions, purchases, restores — enough
  to see conversion and validate the price.

### F. The "zoom out" summaries (free feature, still must be built)
- Currently hardcoded onboarding preview text (`OpenTodoSummaryService.swift` was deleted). Build
  the real week/month/year/all-time reflective summaries. Can ship as a **free v1.x update**
  independent of Pro. Frame as reflection, not productivity metrics.

---

## Suggested build order
1. **CloudKit model prep + migration** (A) — foundational, test hard.
2. **StoreKit lifetime unlock + `isPro`** (B) — behind the scenes, no UI yet.
3. **Paywall + Settings "Fil Pro" entry + Restore** (C, D).
4. **Wire iCloud sync to `isPro`** (turn the CloudKit container on for Pro users).
5. **Summaries** (F) — parallel free-tier work; can ship earlier.
6. Analytics (E) alongside the paywall.

## Open questions / risks
- **Exact price:** $14.99 vs $19.99 (recommend $14.99 to start).
- **Sync toggle model:** is sync auto-on once Pro, or a Settings toggle? (Recommend a toggle,
  default on, so privacy-minded users can keep it local.)
- **CloudKit migration risk** is the main technical unknown — needs real device testing with an
  existing store.
- Free users who later go Pro: their existing local fils must sync up cleanly on first enable.
