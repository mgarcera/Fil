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

---

## Phase 3 — Reliability, UX & accessibility hardening

Worked in themed sub-batches (this phase is large; a few items carry decisions). First sub-batch:
reliability + performance + a security quick win — self-contained, no design decisions.

### #16 — transcribe() continuation leak + timeout (audit #16) ✅
- `VoiceRecorderViewModel.transcribe(url:)` now routes through a `TranscriptionResumeGuard` that
  resumes the checked continuation **exactly once** — first of success / error / a 60s safety
  timeout / task cancellation — and cancels the recognition task afterward. Wrapped in
  `withTaskCancellationHandler`.
- Fixes the hang where a recognition that never reported `isFinal` left fil creation stuck in the
  "creating…" state forever. Added `TranscriptionError.timedOut`.
- Guard is `nonisolated`/`@unchecked Sendable` (NSLock-synchronized) so it's callable from the
  nonisolated cancellation handler + speech callback under the target's MainActor-default isolation.
- Verified: diagnostics clean + full BuildProject passed.

### #19 + #17 — graceful container recovery + model prewarm (audit #19, #17) ✅
*(Committed together: both touch `FilApp.swift`; can't split one file's hunks non-interactively.)*
- **#19:** `FilApp.makeModelContainer` no longer `fatalError`s. On a migration/corruption error it
  now (1) **moves the store aside** to a timestamped `.corrupt-<ts>` backup — never silently
  deletes — and retries, then (2) falls back to an **in-memory** container so the app still opens
  instead of crashing. Renamed `deleteStoreFiles` → `moveStoreAside`.
- **#17:** `ArticleGenerationService.prewarm()` (availability-gated, holds the warmed session);
  instructions extracted to a shared constant; called from `RootView.task` after first frame so the
  first fil's title isn't stalled by a cold model start.
- Verified: diagnostics clean + full BuildProject passed.

### #20 (partial) — truncate pinned-snapshot transcript (audit #20) ✅ / file-protection deferred
- `PinnedFilStore` now stores only a ~200-char excerpt in the App Group snapshot instead of the
  full `note.transcript`, keeping the whole note body out of the shared container.
- **Deferred (device-locked testing):** the `.completeFileProtection` half of #20 — the lock-screen
  widget / Live Activity must read `pinnedFilSnapshot.json` while the device is locked, so
  `.complete` would break it. The audio/shared-draft/SwiftData file-protection changes similarly
  need on-device verification. Tracked for a dedicated security-hardening pass.

### #22 (partial) — idle-detector debounce (audit #22) ✅ / sound-decode deferred
- `IdleScreensaverDetector` now resets the idle timer only on `touchesBegan`/`touchesEnded` (not
  every `touchesMoved`), ending the per-movement Timer churn, and detaches the window recognizer
  when idling is disabled.
- **Deferred:** moving SoundscapeManager's 14 AVAudioPlayer decodes off the main thread — clean
  under the target's `@MainActor`-default isolation requires care (AVAudioPlayer is non-Sendable);
  not worth introducing concurrency warnings pre-launch for a minor gain. Tracked with #21.

### #18 — VoiceOver labels + decorative-canvas handling (audit #18) ✅
- **Composer** (`ComposerBar`): labelled add-photos, add-to-do, record (with `.startsMediaSession`),
  send fil, stop recording, remove photo.
- **Header** (`ContentView`): dark/light-mode toggle now announces "switch to light/dark mode".
- **Note cards** (`NoteGridView.DeletableNoteCard`): collapse the decorative blob into one element
  with a composed label (title + fil kind: photo/link/voice/text), a selected value, and a named
  **"select"** action exposing the long-press (which VoiceOver can't otherwise perform).
- **Screensaver overlay** (`ContentView`): collapsed to one element and — importantly — given a
  dismiss `accessibilityAction` so a VoiceOver user isn't trapped (the sighted tap-to-exit isn't
  discoverable); hidden entirely from a11y when idle.
- Verified: full BuildProject passed (the live-diagnostics tool errored transiently; build is
  authoritative).

### #15 — permission priming + Settings-redirect on denial (audit #15) ✅
- Added `VoiceRecorderViewModel.permissionStatus` (reads combined mic + speech state *without*
  prompting).
- New `MicPrimingSheet` — a benefit-framed, manifesto-voice screen ("talk to fil… you can always
  just type instead") with **enable** / **not now**.
- `ContentView.startRecording()` now branches on status: authorized → record; notDetermined → show
  priming (enable → system prompt; not now → focus the text field); denied → an alert offering
  **open settings** (`UIApplication.openSettingsURLString`) / not now — instead of the old
  dead-end "OK" alert.
- Verified: full BuildProject passed. (New UI for Mason to eyeball on device.)

### #21 (safe subset) — force-unwraps + save logging (audit #21) ✅ / full Swift 6 flip deferred
- New `Fil/FilLog.swift`: an `OSLog` `Logger` + `ModelContext.saveOrLog()` that logs save failures
  instead of swallowing them. Converted all 12 `try? modelContext.save()` sites (ContentView,
  OnboardingView, ArticleView ×6, KeywordAttachmentSheet ×2) to `saveOrLog()`.
- Removed the four force-unwraps: `AquariumView` (3× `randomElement()!` → `?? default` / `guard`)
  and `SelectableTextView` (`URL(string:)!` → `if let`, mirroring the AppKit branch).
- **Deferred (per decision):** the full `SWIFT_VERSION = 6` / `strict-concurrency = complete`
  migration — its own post-launch effort on this `@MainActor`-heavy codebase. Bundled with the
  off-main SoundscapeManager decode (#22).
- Verified: full BuildProject passed.

---

## Phase 4 — Growth infrastructure

### #24 (started) — brand foundation
- `docs/brand/brand-positioning.md`: the source-of-truth brand doc — one-line positioning, what
  Fil is / is NOT (from the "from mason" manifesto), audience, market fit & differentiation, value
  prop, **voice** (with do/don't), the `-fil-` lexicon, visual identity, and ready-to-use lines.
  First input for the website; everything downstream (press kit, ASO, copy) checks against it.
- Expanded the brand doc's **visual identity** section with real values from `Theme.swift`: the
  three fil gradient palettes (hex + names), utility/anchor colors (default gradient, record red,
  accent gradient), DM Sans/DM Mono typography (with the honest note that the app currently renders
  via the system font), the blob/capsule/circle/rounded-rect shape language + corner radii, the
  16-stop gradient system, and motion/feel.
- **Website copy** drafted → `docs/website/website-copy.md`: SEO meta, hero, how-it-works, the
  "what fil isn't" turn, features, privacy, "from mason", footer — plus build notes and the
  on-device privacy-claim guardrail.
- Press kit: **deferred** by decision — only needed for active press outreach; cheap to assemble
  later from the brand doc + metadata.

### #26 — review prompt after an "aha" moment (audit #26) ✅
- `ContentView`: `@Environment(\.requestReview)` + `@AppStorage("didRequestReview")`. After a fil is
  successfully created (`createFil`), `maybeRequestReview()` fires once, gated to `notes.count >= 3`
  and a 1.5s delay so the ask lands on a happy beat. StoreKit further throttles actual display.
- Verified: full BuildProject passed.

---

## Phase 5 — Monetization (Fil Pro)

- **Strategy** decided + documented in `docs/monetization/fil-pro-plan.md`: one-time **lifetime
  unlock** (keeps the "no subscription" promise), **iCloud sync as the paid hero**, summaries move
  to free.
- **iCloud-readiness scope** (the gating technical work) fully scoped in
  `docs/monetization/icloud-readiness-scope.md` — verified against Apple's SwiftData sync docs.
  Per-file model changes (remove `.unique`, default non-optionals across Note/NoteImage/
  KeywordAttachment/UserProfile), container `cloudKitDatabase` gating, entitlements + Background
  Modes, VersionedSchema migration, and a test plan. **Two important findings surfaced:**
  (a) attachment binaries are stored inline in a Codable blob → can exceed CloudKit record limits;
  (b) **audio files live as loose files** (`audioFilePath`) and won't sync via SwiftData — a synced
  voice fil would arrive without playable audio unless remodeled. Both are open decisions in the doc.
- No app code changed yet — scoping only.

---

## Onboarding redesign (action-first + "from mason" seed fil)

Design in `docs/onboarding/onboarding-design.md` (research in `onboarding-research.md`). Building on
`launch-prep`, per-item commits.

### O1 — strip stale onboarding (submittable checkpoint) ✅
- `RootView` now renders `ContentView()` directly; new users no longer see the stale
  summary-preview onboarding that promised the removed summaries feature (accuracy / App Review
  risk removed). The lowercase toggle already lives in Settings; `UserProfile` was only the
  onboarding gate, so nothing user-facing is lost. `OnboardingView`/`SummaryScope` now dead code
  (removed in O5). Verified: full BuildProject passed.

### O2 — first-launch nudge ✅ (already satisfied)
- The existing empty-state tip (`ContentView.emptyStateTip`, in Mason's voice) already invites
  "to get started, create a fil… highlight text, click fil'ament…". No new nudge needed.

### O3 + O4 + O5 — action-first flow + seed fil + cleanup ✅
- **Flow (`ContentView`):** after the user's **own** first fil completes in `createFil`, a quiet
  congratulation overlay ("that's a fil. it's yours.") shows for ~2s, then the **"from mason" seed
  fil animates in through the same `createFil`/creation-blob path** (the reveal demonstrates the
  creation animation + discoverability). Guarded once by `@AppStorage("didSeedWelcomeFil")`.
- **Seed excluded from activation:** it runs through `createFil` too, so an `isSeedingWelcomeFil`
  flag skips user-fil stamping + re-trigger.
- **Seed content (`WelcomeFil.swift`):** fixed title/transcript/gradient (no AI → always renders) +
  two sample filaments (`filament`, `landfil`) that highlight in the transcript. Deletable like any
  fil. Copy is Mason-editable in one file.
- **Instrumentation:** first-party `firstLaunchAt` / `firstUserFilAt` (epoch seconds, seed excluded).
- **Cleanup:** moved `RootView` into `FilApp.swift`; **deleted `OnboardingView.swift`**.
- Verified: diagnostics clean + full BuildProject passed.
- **Open (Mason):** edit seed copy / congrat line / gradient; device-test the first-run sequence.

---

### (Phase 5 monetization pivot, for reference)
- **Pivot (2026-07-06):** after scoping, **iCloud sync SHELVED as the Pro hero** — audio files
  (loose files) don't sync via SwiftData (voice fils would arrive silent) and a prior migration
  attempt cost ~a day + was reverted. New Pro hero = **summaries + all-screensavers + ambience
  bundle** (local, no CloudKit, no migration). `fil-pro-plan.md` rewritten; scope doc marked
  shelved. Bonus: "notes stay on your device" copy stays 100% true. Gating build is now the
  **summaries feature**, not a migration.

### #25 — outbound share cards (audit #25) ✅
- New `Fil/Views/FilShareCard.swift`: `FilShareCard` (a branded 1080² card — the fil's gradient
  blob + title + excerpt + "fil · let thoughts be" wordmark on a fixed dark canvas) and
  `FilShareCardData`, a `nonisolated` `Transferable` value that renders to PNG **on demand at share
  time** via `@MainActor ImageRenderer` (not eagerly).
- `ArticleView`: a `ShareLink` in the toolbar trailing group (labelled "share fil") backed by a
  cheap `filShareCard` computed value. Every shared card is a free, on-brand impression — the
  organic-acquisition loop the audit flagged as missing.
- Verified: full BuildProject passed. (Worth an on-device look at the rendered card + share sheet.)




