# Fil — App Store submission checklist

The remaining **launch-critical, mostly-manual** work. Code side is done; this is the ASC + hosting
gate. Order is roughly sequential. Drafts referenced live in this repo.

## 1. Host the three web pages (rootcause.ltd)
Publish the drafts to the URLs already wired in `Fil/FilLinks.swift`:
- **Privacy Policy** → `https://rootcause.ltd/fil/privacy` — source: `docs/legal/privacy-policy.md`
- **Terms of Service** → `https://rootcause.ltd/fil/terms` — source: `docs/legal/` (terms draft)
- **Support** → `https://rootcause.ltd/fil/support` — source: `docs/support/`
- Verify each loads over HTTPS and the in-app Settings → About rows open them.
- Confirm the Privacy Policy's **speech wording matches the code**: transcription is fully on-device
  (`requiresOnDeviceRecognition = true`), so the policy must say so.

## 2. App Store Connect — create the record
- New app; set the bundle identifier to the app's (matches the Xcode target).
- **Name:** `Fil — Let Thoughts Be` · **Subtitle** + **keywords**: from `AppStore/metadata.md`
  (keywords deduped against name/subtitle).
- **Category**, age rating, and pricing (free at launch).

## 3. App Store Connect — privacy & URLs
- **Privacy Policy URL:** `https://rootcause.ltd/fil/privacy`
- **Support URL:** `https://rootcause.ltd/fil/support`
- **App Privacy nutrition label:** "Data Not Collected", Tracking = **No** — answers in
  `AppStore/app-privacy.md`. Must stay consistent with `PrivacyInfo.xcprivacy`.
- Encryption: `ITSAppUsesNonExemptEncryption = NO` is already set → no export-compliance doc needed.

## 4. Screenshots (+ optional preview)
- Capture the 6-shot set at 6.9″ and 6.7″ per `AppStore/screenshots.md`; upload.

## 5. Code loose end
- After the app record exists, set `FilLinks.appStoreID` (currently placeholder `"0000000000"`) so
  the in-app "rate fil" deep link works. One-line change → new build.

## 6. Device verification before archiving
- **#20 file protection:** on a physical device, background the app, **lock** it, then confirm on
  unlock the app resumes cleanly, audio/video still play, and the **pinned lock-screen widget still
  renders** (the App Group snapshot is intentionally left readable while locked).
- Smoke-test first-run: fresh install → make first fil → "from mason" seed appears → tap **here** →
  the tutorial video plays.

## 7. Build & upload
- Bump the build number; archive (Release); validate; upload via Xcode Organizer / Transporter.
- Submit for review with a reviewer note if the on-device model / first-run seeding needs context.

---
*Not blockers, fast-follow after launch: Phase 4 growth (website/press/promo, TestFlight beta,
launch), Phase 5 monetization (summaries + paywall). See `LAUNCH_READINESS_AUDIT.md` roadmap.*
