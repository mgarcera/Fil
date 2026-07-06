# Fil — Launch Prep Worklog

*Append-only journal of the App Store launch-readiness work. Source of truth for
findings is `LAUNCH_READINESS_AUDIT.md`; this file records what was actually done,
in what order, and how it was verified. Newest entries at the bottom.*

Branch: `launch-prep` (forked from `dynamic-island-share-capture` @ `607779c`).
Working agreement: one commit per audit item (`P<phase>.<n>: … (audit #N)`); build/diagnostics
must pass before an item is checked off in the roadmap; review batched per phase.

---

## Phase 1 — Hard build/submission blockers

**Started.** Items 1–8 from the roadmap. Goal: get the app to a submittable, non-crashing,
iPhone-only state with the required privacy/config metadata.

Verification note: each item is checked with live Xcode diagnostics
(`XcodeRefreshCodeIssuesInFile`); a full `BuildProject` is run at the end of the phase to
validate everything together.

### #1 — Guard FoundationModels availability + fallback (audit #1) ✅
- Added `ArticleGenerationService.generateTitle(from:)` — a non-throwing entry point that gates
  on `SystemLanguageModel.default.isAvailable`, and on unavailability *or* a thrown generation
  error degrades to the existing on-device `shortLabel(keywordFallback(...))`.
- Routed both note-creation paths (`ContentView.saveImageFil`, `saveGeneratedNote`) through it,
  dropping the `try await generateMetadata(...)` that previously threw *before* `modelContext.insert`.
- Result: on Simulator / non–Apple-Intelligence / model-downloading devices the note now always
  saves with a sensible title instead of being silently discarded.
- `generateMetadata` (throwing) is retained for the live path; `refreshMetadataFromTranscript`
  in ArticleView already had its own do/catch and operates on an already-saved note, so left as-is.
- Verified: live diagnostics clean on both files.

### #6 — Force on-device speech recognition (audit #6) ✅
- In `VoiceRecorderViewModel.transcribe(url:)`, set `request.requiresOnDeviceRecognition = true`
  gated on `recognizer.supportsOnDeviceRecognition`, so voice audio stays on the device wherever
  the recognizer supports it. This makes the in-app "processed locally" claim literally true on
  supported hardware.
- Follow-up for Phase 2 (legal): on the rare devices without on-device speech support, transcription
  still falls back to Apple's service — the privacy policy wording must disclose that edge, and no
  absolute "100% on-device" listing claim ships until then. Tracked under audit #6/legal.
- Verified: live diagnostics clean.

### #2 — Trim platforms to iPhone-only (audit #2) ✅
- Via the Xcode build-settings MCP tool (not hand-editing pbxproj), on target `Fil` for both
  Debug + Release: `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`, `TARGETED_DEVICE_FAMILY = 1`,
  `SDKROOT = iphoneos`; deleted `XROS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET`, and
  `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`.
- Removed the 11 Mac idiom entries from `AppIcon.appiconset/Contents.json` (iOS universal only).
- Left in place (harmless): `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]` — the MCP tool can't delete a
  `[sdk=...]`-conditioned key, and it's now completely inert since macOS is no longer a supported
  platform. Can be cleaned by hand later if desired.
- Verified: read back pbxproj — both Debug and Release configs reflect all changes.

### #3 — Unify iOS deployment target (audit #3) ✅
- Set `IPHONEOS_DEPLOYMENT_TARGET = 26.4` on `FilPinnedWidgetExtension` and `FilShareExtension`
  to match the host app (was 26.5 and 27.0 respectively). Chose the app's existing 26.4 as the
  floor for widest device reach rather than raising the app to 27.0.
- The embedded extension (was 27.0 > app 26.4) no longer exceeds the host, which was failing
  upload validation.
- Verified: grep of pbxproj shows all 6 configs (app/widget/extension × Debug/Release) at 26.4.
- Watch at phase-end build: if the widget/extension actually call a 26.5/27.0-only API, the build
  will flag it and we bump the shared floor + note the reach tradeoff.

### #4 + #7 — Export-compliance key + usage strings (audit #4, #7) ✅
*(Committed together: both are `INFOPLIST_KEY_*` edits in the same pbxproj file; splitting one
file's hunks into two commits needs interactive `git add -p`, which isn't available here.)*
- #4: added `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` on `Fil` (Debug+Release) so App
  Store Connect builds aren't held for a manual encryption-compliance answer.
- #7: reworded `NSSpeechRecognitionUsageDescription` to describe on-device transcription (it had
  been a verbatim copy of the mic string), and fixed the `NSCameraUsageDescription` (removed the
  trailing space; clearer wording).
- Verified: grep shows all three keys correct in both Debug and Release.

### #5 — Privacy manifests (audit #5) ✅
- Added `PrivacyInfo.xcprivacy` to all three targets: `Fil/`, `FilPinnedWidget/`,
  `FilShareExtension/`. Each declares `NSPrivacyTracking=false`, empty tracking-domains, empty
  collected-data-types, and one `NSPrivacyAccessedAPICategoryUserDefaults` entry with reasons
  `CA92.1` (app-group access) + `1C8F.1` (app-internal access) — the superset that covers both
  the app-group snapshot suite (PinnedFilStore) and @AppStorage/standard UserDefaults use.
- No pbxproj edit needed: the project uses PBXFileSystemSynchronizedRootGroups mapping 1:1 to the
  three target folders (only `Info.plist` is excepted), so each manifest is auto-added to its
  target as a bundled resource. Verified by reading the synchronized-group + exception sections.
- Phase-end build will confirm the manifests copy into each bundle cleanly.

### #8 — Dynamic Type support (audit #8) ✅ (core; inline sites are follow-up)
- `Theme.dmSans`/`dmMono` now anchor to the `.body` text style and use `Font.scaled(by: size/17)`,
  so all text built through the Theme helpers (73 call sites) scales with Dynamic Type. At the
  default setting the result is visually identical to the old fixed `.system(size:)`.
- `SelectableTextView` (UIKit transcript) now builds its fonts with
  `UIFontMetrics(forTextStyle: .body).scaledFont(for:)` and sets `adjustsFontForContentSizeCategory`.
- Added a root clamp on `RootView`: `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` so text
  can grow to accessibility sizes without shattering the fixed-height glass/blob layout.
- **Deliberately left as follow-up** (not silently dropped): the ~43 inline `.font(.system(size:))`
  sites across 12 files still don't scale — converting them is mechanical but broad, and pairs
  naturally with audit P2 #23 (make fixed-height containers flexible). Recommend doing both
  together with on-device verification via the device-interaction skill. The AppKit branch of
  SelectableTextView was left untouched — it no longer compiles now that the app is iPhone-only.
- Chose the SwiftUI-native `.system(.body).scaled(by:)` over raw per-call `UIFontMetrics` because
  it stays reactive to the `dynamicTypeSize` environment. (Confirmed `scaled(by:)` exists in the
  iOS 26 SDK via DocumentationSearch.)

---

## Phase 1 — COMPLETE ✅

All 8 hard blockers addressed. **Full `BuildProject` passed (0 errors)** after the final item,
validating the platform trim, the unified 26.4 deployment target (widget/extension needed nothing
newer — lowering was safe), the privacy-manifest bundling, and every code change together.

Commits on `launch-prep` (one per audit item, plus a combined #4+#7):
`P1.1`(93d1746) · `P1.6`(effc325) · `P1.2`(76ddb5a) · `P1.3`(0578322) · `P1.4+P1.7`(3a24760) ·
`P1.5`(fc652ed) · `P1.8`(next).

Carried into later phases (noted inline above): on-device-speech privacy-policy wording for
no-support devices (→ Phase 2 #9); inline `.system(size:)` conversion + fixed-height flexibility
(→ P2 #23); the inert `[sdk=macosx*]` runpath (cosmetic). Nothing here blocks submission.

### #8 follow-up — blob badge padding + growth at large text (device finding)
- Mason device-tested Dynamic Type: works great, but at larger sizes the keyword badge on blob
  cards looked cramped (fixed 6/3 padding) and grew enough to cover the centered word-count ("X
  words") on some blobs.
- Fix in `NoteCardView`: moved the badge chrome into `KeywordBadgeLabel`, made its internal padding
  `@ScaledMetric(relativeTo: .body)` so it breathes proportionally, and capped the badge subtree at
  `.dynamicTypeSize(...DynamicTypeSize.xLarge)` — a notch below the app-wide accessibility1 clamp —
  so the compact chip stops swallowing the blob's word-count/waveform content. Body/content text
  still scales to accessibility1.
- Verified: diagnostics clean + full BuildProject passed. (This is a concrete instance of P2 #23.)

---

## Phase 2 — Submission metadata & App Store Connect

Positioning locked (after a brainstorm grounded in the "from mason" manifesto — Fil is
explicitly anti-optimization, *not* a productivity/second-brain/journal app):
- **Name:** `Fil — Let Thoughts Be`   **Subtitle:** `Speak your mind. Let it be.`
- **Category:** Lifestyle (primary) / Utilities (secondary).
- ASO strategy: visible name/subtitle carry the soul; the hidden 100-char keyword field + the
  description carry search terms. "Voice notes" intentionally dropped from the visible name.
- Legal docs: Privacy Policy **+** Terms of Service. Hosting: placeholder URL constant, one place.

### #12 — In-app Settings links (audit #12) ✅
- New `Fil/FilLinks.swift` — single source of truth for external URLs (Privacy, Terms, Support,
  contact mailto, App Store write-review). Three web URLs + the numeric App Store ID are clearly
  marked `TODO(launch)` placeholders; changing them later is a one-line-each edit.
- `SettingsView` About now shows tappable rows: from mason · privacy policy · terms of service ·
  contact & feedback · rate fil, via a shared `aboutRow` helper (reuses the existing row styling;
  labelled Text so VoiceOver reads them). Opens via `@Environment(\.openURL)`.
- Verified: diagnostics clean + full BuildProject passed. Links 404/no-op until the pages are
  hosted and the App Store ID is set (expected; placeholder phase).

### #9, #10, #13, #14, #11 — Phase 2 documents authored ✅ (drafted; you host/enter/capture)
Committed as one set (interdependent reference content, not independently-revertible code):
- **#9 Privacy Policy** — `docs/legal/privacy-policy.md`. Local-first; names mic/speech/camera;
  honestly discloses the on-device-vs-Apple-speech-service nuance and the LinkPresentation fetch.
- **Terms of Service** — `docs/legal/terms-of-service.md`. Short; defers to Apple's Standard EULA.
- **#10 Support page** — `docs/support/index.md`. Contact + FAQ (offline, storage, permissions,
  voice privacy, delete, screensaver unlocks).
- **#11 App Privacy answers** — `AppStore/app-privacy.md`. "Data Not Collected" + Tracking No,
  with the rationale (Apple's speech service ≠ developer collection) and an ASC checklist.
- **#13 Listing metadata** — `AppStore/metadata.md`. Final `Fil — Let Thoughts Be` /
  `Speak your mind. Let it be.`; ~96-char keyword string; promo text; description + What's New in
  the manifesto voice; Lifestyle/Utilities categories.
- **#14 Screenshot spec** — `AppStore/screenshots.md`. 6-shot 6.9″ shot-list with lowercase
  captions; flags the "don't claim 100% on-device transcription" caveat.

Docs live under `docs/` and `AppStore/` at the repo root — **outside the app targets**, so they're
never bundled into the app.

---

## Phase 2 — COMPLETE ✅ (my part)

All 6 items addressed. The **code** item (#12 in-app links) builds clean; the **content** items
(#9/#10/#11/#13/#14) are drafted and ready.

**Handoff — these need you (accounts/hosting/capture I can't do):**
1. Host `docs/legal/privacy-policy.md`, `docs/legal/terms-of-service.md`, and `docs/support/` at
   real URLs, then update the three placeholders in `Fil/FilLinks.swift` (one line each).
2. In App Store Connect: enter the Privacy Policy URL + Support URL; complete App Privacy per
   `AppStore/app-privacy.md`; set name/subtitle/keywords/description per `AppStore/metadata.md`.
3. Capture + upload the 6.9″ screenshots per `AppStore/screenshots.md`.
4. After the app record exists, set the numeric `appStoreID` in `FilLinks.swift` so "rate fil" works.



