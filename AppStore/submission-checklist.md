# Fil — App Store submission checklist

*Corrected 2026-08-13. The Jul 9 version of this file predated the cloud-surfacing
pivot and was wrong in three places (hosting, App Privacy, and the App Store ID).
For the forward view — what's decided, parked, and sequenced — see
`docs/v1-route.md`.*

The remaining **launch-critical, mostly-manual** work. Code side is done; this is
the ASC + capture gate.

## 1. Host the three web pages (rootcause.ltd) — ✅ DONE
All four URLs verified live (HTTP 200) on 2026-08-13:
`rootcause.ltd/fil`, `/fil/privacy`, `/fil/terms`, `/fil/support`.

⚠️ **They will need re-publishing** once the positioning reset lands — the hosted
privacy policy and terms both carry July's privacy-as-positioning language. See
`docs/v1-route.md` → "What the positioning decision blocks."

## 2. App Store Connect — the record — ✅ EXISTS
`FilLinks.appStoreID` is set to a real ID, so the app record was created. Still to
enter or confirm:
- **Name:** `Fil — Let Thoughts Be` · **Subtitle** + **keywords** from
  `AppStore/metadata.md` — but that copy is from Jul 13 and predates folders, the
  full-screen player, and the capture controls. Rewrite before entering.
- **Category**, age rating.
- **Pricing:** free app **with auto-renewable in-app purchases** — *not* "free at
  launch" as the old checklist said.

## 3. App Store Connect — privacy & URLs
- **Privacy Policy URL:** `https://rootcause.ltd/fil/privacy`
- **Support URL:** `https://rootcause.ltd/fil/support`
- **App Privacy nutrition label:** **User Content › Other User Content**, used for
  **App Functionality**, **not linked** to identity, **not** used for tracking.
  Tracking = **No**. Answers in `AppStore/app-privacy.md`.
  ✅ Verified 2026-08-13 to match `Fil/PrivacyInfo.xcprivacy` exactly — the manifest
  and the ASC answers will not contradict each other.
  *(The old "Data Not Collected" answer was pre-pivot and is wrong — surfacing
  transmits user content to a processor.)*
- Encryption: `ITSAppUsesNonExemptEncryption = NO` already set → no export doc.

## 4. App Store Connect — subscriptions ⛔ THE HARD GATE
`Fil/Products.storekit` has both products locally
(`…pro.monthly` $2.99, `…pro.annual` $24.99, `P2W` free intro offer on each).
**ASC needs its own:**
- Subscription **group**.
- Both products created, with localized display names and descriptions.
- **Review screenshot** for each product.
- Price tiers set.
- A **sandbox tester** account.

Until these exist and are approved, the cloud path can't be tested end-to-end —
the App Store Server API can't verify local `.storekit` transactions.

## 5. Screenshots
The 6-shot spec in `AppStore/screenshots.md` is from Jul 5 and describes a UI that
no longer exists. **Rewrite the spec first**, then capture.
- Target 6.9″ (iPhone 17 Pro Max) — simulator captures are accepted.
- Automate: seed launch-argument for curated demo data, `simctl status_bar`
  override for a shipped-looking status bar, `simctl io … screenshot` to the repo.
- Nothing captured yet (`snapshots/` is empty).

## 6. Copy that moves with positioning
Not a placeholder problem any more — an accuracy one. `PaywallView.swift:87`
carries the in-app data-handling sentence, so a positioning change means a copy
change *and a new build*. Settle positioning before archiving.

## 7. Device verification before archiving
- ✅ File protection (#20): backgrounded, locked, unlocked — app resumes, audio
  plays, pinned widget still renders.
- ✅ First-run smoke test: fresh install → first fil → "from mason" seed → tutorial.
- ⬜ **The August surface**, which the old checklist predates and the simulator
  can't honestly cover: the basket Live Activity, the pinned-folder Live Activity,
  both Control Center capture controls, Dynamic Island, full-screen player audio,
  and the sound + haptic layer.

## 8. Build & upload
- Bump the build number; archive (Release); validate; upload via Organizer.
- **Reviewer note** must cover: the on-device model, first-run seeding, and how to
  reach Pro. Surfacing is Pro-gated, so a reviewer needs the sandbox path (item 4)
  to evaluate it — that dependency is why item 4 is the hard gate.
- The proxy must be up and funded during review.

---
*Not blockers, fast-follow after launch: Fil a Folder, the `Note.kind` refactor,
the sourced sound pack, and a ZDR upgrade if pursued. See `docs/v1-route.md`.*
