# Fil — Launch-Readiness Audit

*Produced by a multi-agent launch-readiness audit (12 domain agents; false positives removed and severities reconciled by a lead synthesizer). File:line references are relative to the repository root.*

## Executive Summary

**Read: NO-GO as currently configured — but the gap to submittable is small and mostly mechanical.** Fil is a well-architected, genuinely local-first voice-to-note app with a clean privacy story, no third-party SDKs, no network telemetry, and high-craft SwiftUI. However, it cannot be submitted today: the core note-creation flow silently fails when Apple Intelligence is unavailable (which includes many App Review devices), the project still advertises iPad/Mac/visionOS despite an iPhone-only v1, the required privacy manifest is missing, mandatory App Store Connect metadata (privacy policy, support URL, export compliance) does not exist, and marketed privacy claims conflict with actual server-capable speech transcription.

**Counts:** P0: 14 · P1: 26 · P2: 23 · Future: 8

**Top headline risks**

1. **Core feature data-loss on non–Apple-Intelligence devices.** `generateMetadata` calls FoundationModels with no availability guard/fallback, and the throw happens *before* the note is inserted — so voice/image notes are silently discarded on Simulator and non-eligible/AI-off devices. A reviewer will hit this.
2. **Platform-scope mismatch.** `TARGETED_DEVICE_FAMILY = "1,2,7"` and `SUPPORTED_PLATFORMS` include `macosx xros xrsimulator` for an iPhone-only, portrait-locked v1 — inviting Guideline 2.1/4.0 rejection and an unintended availability footprint.
3. **Privacy claims vs. reality.** In-app copy ("everything is processed locally") and the natural ASO story assert on-device processing, but `SFSpeechRecognizer` is not forced on-device, so audio can be sent to Apple's servers — a 5.1.1 misleading-metadata and inaccurate-nutrition-label risk.
4. **Submission-gating metadata absent.** No `PrivacyInfo.xcprivacy` (while UserDefaults, a required-reason API, is used), no Privacy Policy URL, no Support URL, and no `ITSAppUsesNonExemptEncryption` key — each independently blocks or stalls submission.
5. **Deployment-target mismatch across the app group.** Share extension min-OS (27.0) exceeds the host app (26.4), which fails validation and can make the extension unavailable.

---

## P0 — Launch Blockers

**Core note creation breaks when Apple Intelligence is unavailable (no FoundationModels availability guard/fallback)**
Evidence: `Fil/Services/ArticleGenerationService.swift:13-31` builds `LanguageModelSession` and calls `session.respond(...)` with no `SystemLanguageModel.default.availability` check and no do/catch; callers `saveImageFil` (`Fil/ContentView.swift:1150`) and `saveGeneratedNote` (`Fil/ContentView.swift:1182`) compute the title *before* `modelContext.insert` (lines 1165/1197), and `createFil`'s catch (`Fil/ContentView.swift:838-840`) only sets `recorder.errorMessage` — so the note is never saved. The safe pattern already exists in `ArticleView.swift:798-809` (title regeneration wraps in do/catch), proving it is simply absent on the create paths.
Recommendation: Check `SystemLanguageModel.default.availability` before creating a session; when unavailable, route the title through the existing `keywordFallback()` (`ArticleGenerationService.swift:135`) so the note always saves, and wrap the `respond` call so a thrown error degrades to the same fallback.
Skill: `apple-skills:apple-intelligence`

**App declares iPad / Mac / visionOS support despite an iPhone-only v1**
Evidence: `Fil.xcodeproj/project.pbxproj:526,575` set `TARGETED_DEVICE_FAMILY = "1,2,7"` and `:520,569` set `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`; `XROS_DEPLOYMENT_TARGET`/`MACOSX_DEPLOYMENT_TARGET = 26.4` (`:527/576`, `:513/562`) and a macOS `LD_RUNPATH_SEARCH_PATHS` override (`:512/561`) are present. `INFOPLIST_KEY_UISupportedInterfaceOrientations` is portrait (`:508`) while the iPad orientation key (`:509`) declares full landscape; `AppIcon.appiconset/Contents.json` carries Mac idiom variants. The UI is portrait iPhone-only (32 `.fraction` detent/glass sites across 8 view files), never laid out for iPad/Vision/Mac. `SDKROOT = auto` (`:518/567`) can silently re-resolve to other platforms.
Recommendation: Set `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`, `TARGETED_DEVICE_FAMILY = "1"`, and `SDKROOT = iphoneos` on Debug and Release; delete `XROS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET`, and the `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]` override; drop the iPad landscape orientation key and the Mac AppIcon idiom entries. In App Store Connect, uncheck iPad and Mac availability. Clear DerivedData and confirm only iPhone run destinations remain. *(Merged from Release, iOS code-quality, and Platform-scope domains.)*
Skill: `apple-skills:ios`

**Deployment target mismatched across the app group (share extension 27.0 > app 26.4)**
Evidence: `Fil.xcodeproj/project.pbxproj` — main app `IPHONEOS_DEPLOYMENT_TARGET = 26.4` (`:510/559`), `FilPinnedWidget = 26.5` (`:593/627`), `FilShareExtension = 27.0` (`:660/692`). All three share `group.com.masongarcera.Fil`. An embedded extension must not require a higher minimum OS than its host; this fails upload validation and makes the extension unavailable on 26.x devices.
Recommendation: Pick one realistic minimum iOS (the lowest that supports the FoundationModels + Liquid Glass APIs actually called) and apply it uniformly to app, widget, and share extension. *(P1 in Release domain, P0 in iOS code-quality; the cross-target mismatch — especially extension > app — is the load-bearing, submission-blocking defect, so treated as a blocker.)*
Skill: `apple-skills:ios`

**Missing export-compliance key (`ITSAppUsesNonExemptEncryption`) stalls every App Store Connect build**
Evidence: Zero matches repo-wide; absent from `Fil/Info.plist` (only `CFBundleURLTypes` + `NSSupportsLiveActivities`) and from all `INFOPLIST_KEY_*` entries in `project.pbxproj`. Without it, every uploaded build is held pending a manual encryption-compliance answer.
Recommendation: Add `ITSAppUsesNonExemptEncryption = NO` (the app uses only standard OS crypto) to `Fil/Info.plist` or as `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in the pbxproj, so it is set for every build.
Skill: `apple-skills:release-review`

**Required privacy manifest `PrivacyInfo.xcprivacy` is absent while a required-reason API (UserDefaults) is used**
Evidence: No `*.xcprivacy` file exists anywhere (Glob + pbxproj both empty). UserDefaults is used in `Fil/ContentView.swift:50`, `Fil/Services/PinnedFilStore.swift:103` (app-group suite), plus `SoundscapeManager.swift` and `TemporaryFilDraftStore.swift`. Apple's automated review rejects binaries using required-reason APIs without a declaring manifest.
Recommendation: Add `Fil/PrivacyInfo.xcprivacy` (and matching manifests to widget + share extension, which also touch shared UserDefaults) with `NSPrivacyTracking=false`, empty `NSPrivacyTrackingDomains`, empty `NSPrivacyCollectedDataTypes`, and `NSPrivacyAccessedAPITypes` = one `NSPrivacyAccessedAPICategoryUserDefaults` entry with reasons `["CA92.1"]` (app-group) — add `1C8F.1` if app-internal reads/writes also occur. Add the file to Copy Bundle Resources. *(Merged across Privacy-manifest, Legal, ASO, and Security domains.)*
Skill: `apple-skills:legal`

**No publicly accessible Privacy Policy URL exists (Apple requires one even for no-collection apps)**
Evidence: Glob for privacy/terms/eula/legal returns nothing; `SettingsView.swift:156-179` (About) shows only a "from mason" button and a version string — no in-app legal link. The app requests microphone, speech recognition, and camera (`project.pbxproj:497-499,546-548`), so Guideline 5.1.1 makes a Privacy Policy URL a non-waivable App Store Connect field.
Recommendation: Publish a short local-first privacy policy (draft provided in the Legal section below), host it at a public URL (e.g. GitHub Pages / garcera.us), enter it in App Store Connect, and add an in-app "Privacy Policy" link in `SettingsView` About. *(Merged from Release, Privacy-manifest, Legal, and ASO domains.)*
Skill: `apple-skills:legal`

**Speech transcription is not forced on-device, contradicting the app's on-device privacy claim**
Evidence: `Fil/ViewModels/VoiceRecorderViewModel.swift:54-74` creates `SFSpeechRecognizer()` + `SFSpeechURLRecognitionRequest` and runs `recognitionTask` without ever setting `requiresOnDeviceRecognition = true` (zero repo-wide matches). Without it, audio can be sent to Apple's servers. Meanwhile `ContentView.swift:636` ships user-facing copy: "everything is processed locally and nothing is stored in the cloud." — factually false for the speech step as coded.
Recommendation (preferred): set `request.requiresOnDeviceRecognition = true`, gated on `recognizer.supportsOnDeviceRecognition` with a fallback, so the on-device claim is literally true. Otherwise, reconcile the in-app copy, ASO listing, and privacy policy to disclose that voice audio may be processed by Apple's speech recognition service. The in-app copy and the policy must agree before launch, and no absolute "100% on-device / nothing leaves your phone" listing claims may ship until the flag is set. *(Merged from Legal and ASO domains.)*
Skill: `apple-skills:apple-intelligence` + `apple-skills:legal`

**App Privacy "nutrition label" answers must reflect speech-to-server behavior**
Evidence: No privacy manifest exists and `SFSpeechRecognizer` is not forced on-device (`VoiceRecorderViewModel.swift:54-74`). A blanket "Data Not Collected" answer would be inaccurate while audio can leave the device for transcription. The App Privacy questionnaire is a hard submission gate.
Recommendation: Complete App Privacy honestly. If `requiresOnDeviceRecognition = true` is set (above), voice/transcripts/notes/AI all stay on device and the answer becomes a clean "Data Not Collected" / Tracking = No that matches the empty `NSPrivacyCollectedDataTypes`. Keep the nutrition label, manifest, and description wording consistent.
Skill: `apple-skills:release-review` + `apple-skills:legal`

**All app text uses fixed-size fonts — Dynamic Type does not work anywhere**
Evidence: `Fil/Theme.swift:41-47` — `dmSans`/`dmMono` return `.system(size:)` with fixed point sizes and no `relativeTo:` anchor. These back real content text (73 call sites across 11 files) plus 43 inline `.font(.system(size:))` sites across 12 files; repo has zero `@ScaledMetric`/`UIFontMetrics`/`.dynamicTypeSize` usage. `SelectableTextView.swift:41,57,67` hard-codes `UIFont.systemFont(ofSize: 16)`. A text-centric app shipping a claimed-but-broken Dynamic Type nutrition label is a launch-blocking accessibility/compliance issue.
Recommendation: Make the two Theme helpers Dynamic-Type-aware in one place (map to a text style, or scale via `UIFontMetrics`/`@ScaledMetric`), use `UIFontMetrics` for the UIKit `SelectableTextView`, then convert remaining inline text sites; clamp with `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` where the glass composer can't grow. Verify in Accessibility Inspector. *(Merged from Accessibility and iOS code-quality domains.)*
Skill: `xcode-integration:accessibility-dynamic-type-specialist`

*(The remaining P0 items are the per-domain restatements folded into the merged blockers above: the duplicate FoundationModels-availability findings from the Onboarding/Performance/iOS-quality domains, the duplicate privacy-manifest / privacy-policy / speech-on-device / device-family / deployment-target findings across Release, Legal, ASO, Security, and Platform-scope, all consolidated here to a single actionable blocker each.)*

---

## P1 — Strongly Recommended Before Launch

**Speech Recognition permission string incorrectly describes microphone use**
Evidence: `project.pbxproj:499,548` set `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` to a verbatim copy of the microphone string ("Fil needs access to your microphone to record voice notes."), while the permission is actively triggered (`VoiceRecorderViewModel.swift:94`). Guideline 5.1.1 flags usage strings that don't describe actual data use.
Recommendation: Reword to describe transcription, e.g. "Fil transcribes your voice recordings into text on your device so it can title and save your notes." Also trim the trailing space in the camera string (`:497/546`). *(Also raised as P2 in ASO/Legal; kept at P1.)*
Skill: `apple-skills:release-review`

**No in-app link to the Privacy Policy / Support / Rate in Settings**
Evidence: `SettingsView.swift:156-179` (About) contains only a "from mason" button and a version string; `FromMasonFilCard.swift` is a static manifesto with no links. Repo-wide there is no mailto, support, feedback, privacy, or review link anywhere.
Recommendation: Add an About/Settings section with: Privacy Policy (hosted URL), Contact/Feedback (`mailto:mason@garcera.us`), and Rate Fil (StoreKit). This satisfies Apple's in-app-policy expectation, gives journalists a contact, and funnels reviews. *(Merged from Legal, Growth, and Monetization domains.)*
Skill: `apple-skills:generators` + `apple-skills:legal`

**No Support URL / support surface for the App Store listing**
Evidence: App Store Connect requires a Support URL; a bare mailto is not accepted. The only contact is the user's email; `SettingsView` About has no support/website link.
Recommendation: Stand up a simple support page (e.g. `garcera.us/fil/support`) with a mailto and short FAQ, and set it as the Support URL.
Skill: `apple-skills:growth`

**Share Extension deployment target already covered as a P0 blocker (cross-target mismatch)** — see P0. *(Original Release-domain P1; escalated on merge with iOS code-quality's P0.)*

**Do not paywall v1 — ship free; the marketed premium feature isn't built yet**
Evidence: Onboarding markets "zoom out across your thoughts" and four summary scopes (`OnboardingView.swift:112,366-434`), but every summary is hardcoded preview text (`previewRewrite:396-407`); `OpenTodoSummaryService.swift` was deleted (git status). Shipped AI is only on-device title generation (`ArticleGenerationService.swift:16`); no StoreKit exists anywhere.
Recommendation: Launch v1.0 fully free with no StoreKit. Build the actual zoom-out/summary feature before charging — gating an unbuilt hero feature risks Guideline 3.1.2 rejection and user trust.
Skill: `apple-skills:monetization`

**Subscription cannot lean on "covering AI/API costs" — all AI is on-device and free to run**
Evidence: `ArticleGenerationService.swift:2,16` runs a `LanguageModelSession` entirely on-device; there is no network AI call and no per-note cost.
Recommendation: When Pro ships, frame it around convenience/power (cross-time summaries, todo roll-ups, all screensavers, later iCloud sync + Mac/Vision), not "covering AI costs" — App Review must see genuine ongoing value.
Skill: `apple-skills:monetization`

**No StoreKit/IAP scaffolding exists (fine for free v1, required before Pro)**
Evidence: Repo-wide search finds no StoreKit imports, no `Product.purchase`/`Transaction.currentEntitlements`, no `.storekit` config, and no In-App Purchase capability in `Fil.entitlements` (only the app group).
Recommendation: For Pro (v1.1+), add the In-App Purchase capability, create an auto-renewable subscription group (Monthly + Annual) in App Store Connect, implement StoreKit 2, and use a StoreKit Configuration file for local testing.
Skill: `apple-skills:generators`

**Missing legal docs required before any subscription can be submitted**
Evidence: No privacy policy, terms/EULA, or in-app links; `SettingsView.swift:156-179` has no legal links. Auto-renewable subscriptions require these under Guideline 3.1.2 and Schedule 2.
Recommendation: Before enabling Pro, publish a privacy policy and terms/EULA (Apple's Standard EULA is acceptable), link both from the paywall and Settings, and add the required auto-renewing disclosure text (price, period, auto-renew, cancel-in-Settings).
Skill: `apple-skills:legal`

**App Store name/subtitle keyword real estate is unused (on-device display name is bare "Fil")**
Evidence: No `INFOPLIST_KEY_CFBundleDisplayName` for the main app target (set only for the widget `:591,625` and share extension `:658,690`), so the name defaults to "Fil" — a coined word with near-zero search volume. Name (30 chars, highest ASO weight) and subtitle (30 chars) carry no category terms.
Recommendation: Set the App Store name to "Fil - Voice Notes & Ideas" and subtitle to "Speak, transcribe, remember" (ASC metadata fields, independent of the on-device icon name), then dedupe the keyword field against them. *(Also raised as P2 brand-discoverability in Growth; kept at P1.)*
Skill: `apple-skills:app-store`

**No App Store screenshots or asset pipeline exist yet**
Evidence: No `fastlane/`, `metadata/`, or screenshots directory. At least one 6.9″ iPhone set is mandatory for submission; the app is highly visual (gradients, grid, Dynamic Island, widget).
Recommendation: Produce the 6-shot set (see Listing Kit) at 6.9″/6.7″ from an iPhone 16/15 Pro Max, with caption keywords in top/bottom safe areas (Apple OCR indexes them). Consider a 15s "tap → speak → titled note" preview.
Skill: `apple-skills:app-store` + `apple-skills:generators`

**Mic and Speech permissions cold-prompted with no priming**
Evidence: `startRecording` (`ContentView.swift:938-948`) calls `requestPermissions` on the first record tap, firing raw iOS mic + Speech dialogs (`VoiceRecorderViewModel.swift:76-100`); `OnboardingView` has no permission UI. Cold double-prompts risk permanent denial of the core feature.
Recommendation: Show a benefit-framed priming screen with a "Not now" (continue text-only) before `requestPermissions` runs; call it only after "Enable."
Skill: `apple-skills:generators` (permission-priming)

**Permission-denied alert dead-ends with no route to Settings**
Evidence: `ContentView.swift:149-153` shows "Permissions Required" with only OK; iOS never re-shows the dialog after denial and there is no re-prompt path (no `openSettingsURLString` anywhere), so a declining user can never record.
Recommendation: Add "Open Settings" via `UIApplication.openSettingsURLString` plus "Not now", detect the denied state so copy adapts, and keep the app usable text-only.
Skill: `apple-skills:generators` (permission-priming)

**No Apple Intelligence availability gate surfaces a raw error on unsupported devices**
Evidence: `ArticleGenerationService.swift:16` creates `LanguageModelSession` unconditionally; on failure `createFil` sets `recorder.errorMessage = error.localizedDescription` (`ContentView.swift:838-839`) shown verbatim (`:162-168`). *(This is the UX face of the P0 data-loss blocker; fixed by the same availability guard/fallback.)*
Recommendation: Gate on `SystemLanguageModel.default.availability` at first-run; when unavailable, show a clear message and use the text-only title fallback, and note the Apple Intelligence requirement in the App Store description.
Skill: `apple-skills:apple-intelligence`

**FoundationModels session created per call with no prewarm or reuse**
Evidence: `ArticleGenerationService.swift:13-43` builds a new session every call with no `prewarm()`; the first generation stalls (`ContentView.swift:1182`).
Recommendation: Warm/reuse the session and call `prewarm()`, gate on availability, and fall back to `keywordFallback()` (`:135`) — this addresses both the cold-start latency and the unavailability failure.
Skill: `apple-skills:apple-intelligence`

**`transcribe()` continuation can leak, hanging fil creation forever**
Evidence: `VoiceRecorderViewModel.swift:63-73` resumes the checked continuation only on error or `result.isFinal`. If the task terminates abnormally (cancel/stall/non-final with no later final), it never resumes; the awaiting `createFil` (`ContentView.swift:836`) leaves the "creating fil…" state and placeholder blob stuck permanently.
Recommendation: Guarantee exactly one resume (a `hasResumed` flag, resume+return on error, resume on `isFinal`, plus a timeout/cancellation path). Setting `requiresOnDeviceRecognition = true` also reduces network-dependent stalls.
Skill: `apple-skills:swift`

**Full note transcript copied in plaintext into an unprotected App Group file, persisting until unpin**
Evidence: `PinnedFilStore.swift:51,57` copies the entire `note.transcript` into `previewText`, written to `pinnedFilSnapshot.json` in the app-group container (`:83`, migration `:109`) with only `.atomic` (no file protection), removed only on `unpin()` (`:66-72`). The widget renders only ~4 lines (`FilPinnedWidget.swift:102-106`), so the full body is never needed. App-group files default to `completeUntilFirstUserAuthentication` (readable while locked).
Recommendation: Truncate `previewText` to the small excerpt the widget renders (~200 chars) and write with `[.atomic, .completeFileProtection]` at `:83` and `:109`.
Skill: `apple-skills:security`

**No outbound share / social-export path — the core viral loop is missing**
Evidence: The share extension is inbound-only (`ShareViewController.swift:28` → `SharedDraftInbox`; drained at `ContentView.swift:894-901`); repo-wide there is no `ShareLink`/`UIActivityViewController` outbound share. The share-worthy "zoom out" summaries cannot leave the app, though `ImageRenderer` plumbing already exists (`ArticleView.swift:959`).
Recommendation: Add an outbound `ShareLink`/`ImageRenderer` "summary card" (and note-share). Every shared card is a free branded impression — the highest-leverage organic acquisition mechanism for a free, ad-budget-less app. Ship pre-launch if possible, else as the first fast-follow.
Skill: `apple-skills:generators` (share cards)

**No rating/review prompt anywhere — forfeiting the social-proof flywheel**
Evidence: Repo-wide search for `requestReview`/`SKStoreReviewController`/StoreKit review paths returns nothing; no code ever asks a happy user to rate.
Recommendation: Add an `SKStoreReviewController` prompt after a genuine "aha" moment (e.g. first AI title/summary in `ArticleView`), gated to ~1–2 asks/year.
Skill: `apple-skills:generators` (review prompt)

**No website, press kit, README, or marketing assets exist in the repo**
Evidence: Repo root has no README, `fastlane/metadata`, `press/`, `marketing/`, or screenshot assets; the only brand asset is the app icon. Press outreach requires a downloadable press kit and a web App Store link.
Recommendation: Before pitching press, create a one-page website (App Store link + `/press`), a press kit (1024 icon, 6–8 framed+raw screenshots, short/medium/long copy, fact sheet, "from mason" founder bio/photo), and a 20–30s promo video — the gating dependency for all outreach.
Skill: `apple-skills:app-store` + `apple-skills:growth`

**No Dynamic Type support** — folded into the P0 "all text uses fixed-size fonts" blocker above (iOS code-quality domain restatement of the Accessibility P0).

**Light/dark mode toggle button has no VoiceOver label**
Evidence: `ContentView.swift:297-307` renders only `Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")` with no `.accessibilityLabel`, unlike the labeled Settings/Search/Screensaver siblings (`:244,264,295`).
Recommendation: Add `.accessibilityLabel(isDarkMode ? "Switch to light mode" : "Switch to dark mode")`.
Skill: `xcode-integration:accessibility-voiceover-specialist`

**Composer icon-only buttons (photos, checklist, mic, send, remove image) are unlabeled**
Evidence: `ComposerBar.swift` — PhotosPicker (`:91-97`), add-todo (`:100-106`), mic/send/stop via `filledCircle`/`beamedCircle` (`:231-247,276-299`), and remove-image (`:322-334`) contain only SF Symbols and no `.accessibilityLabel` (zero accessibility modifiers in the file).
Recommendation: Add labels — "Add photos", "Add to-do", "Record", "Send fil", "Stop recording", "Remove photo"; consider `.accessibilityAddTraits(.startsMediaSession)` on the record button.
Skill: `xcode-integration:accessibility-voiceover-specialist`

**Home note cards announce only the tiny badge, not the fil's type or a usable selection action**
Evidence: `NoteGridView.swift:521-555` (DeletableNoteCard) wraps `NoteCardView` in a Button with a long-press-to-select gesture (`:548-551`) and no accessibility modifiers anywhere in `NoteGridView`/`NoteCardView`. VoiceOver announces the auto-combined Text with no fil-type context (voice/text/image/link) and no VoiceOver equivalent for long-press selection.
Recommendation: Give each card a composed label (`.accessibilityElement(children: .combine)` + `.accessibilityLabel("\(note.title), \(type)")`) and expose selection via `.accessibilityAction(named: "Select") { onLongPress() }`.
Skill: `xcode-integration:accessibility-voiceover-specialist`

---

## P2 — Polish / Fast-Follow

**SwiftData container load failure calls `fatalError` (crash on launch)** — `Fil/FilApp.swift:39,46`; a migration/disk error crashes instead of degrading. Recommendation: fall back to an in-memory container or a recovery screen offering to reset local data. Skill: `apple-skills:swiftdata`

**Aggressive automatic SwiftData store deletion on load failure** — `FilApp.swift:38-48`/`shouldResetStore:57-87` can silently wipe all notes when a load error string merely `contains("migration"|"schema"|"model"|"store")`, e.g. a transient locked-file error under file protection. Recommendation: tighten to specific NSError codes, move the old store aside instead of deleting, and surface a recoverable path. Skill: `apple-skills:swiftdata`

**SwiftData store uses default file protection, not Complete** — `FilApp.swift:30-33,51-55`; no protection class on the store or its `-wal`/`-shm` sidecars. Recommendation: apply `FileProtectionType.complete` (or `.completeUnlessOpen`) via the store URL / app-wide default. Skill: `apple-skills:security`

**Shared-draft inbox writes note text and images with no file protection** — `SharedDraftInbox.swift:34,48,107`; shared content rests at default protection until the next foreground drain. Recommendation: write with `[.atomic, .completeFileProtection]`, set `.protectionKey = .complete` on the directory, and bound decoded image sizes on drain. Skill: `apple-skills:security`

**Audio recordings stored in Documents with default protection** — `VoiceRecorderViewModel.swift:23-24`, `KeywordAttachmentSheet.swift:874-875`; `.m4a` files inherit `completeUntilFirstUserAuthentication`. Recommendation: apply `FileProtectionType.complete` after `stopRecording()` or set the app-wide default. Skill: `apple-skills:security`

**No privacy screen / snapshot blur when app backgrounds** — no resign-active blur; the app-switcher snapshot captures whatever note is open. Recommendation: add a full-screen cover/blur on `scenePhase == .inactive`/`.background`. Skill: `apple-skills:security`

**Camera and Speech usage strings are generic / slightly misleading** — `project.pbxproj:497-499,546-548`; camera string is vague with a trailing space and the speech string duplicates the mic text. Recommendation: tighten both and mirror them in the privacy policy's Permissions section. Skill: `apple-skills:release-review`

**`SUPPORTED_PLATFORMS` / device-family cleanup consistency** — listing-consistency restatement of the P0 platform-scope fix; ensure the store's device-compatibility line and marketing all say iPhone-only. Skill: `apple-skills:release-review`

**AppIcon asset catalog carries a macOS ('mac') idiom variant** — `Fil/Assets.xcassets/AppIcon.appiconset/Contents.json`; dead weight once macOS is dropped. Recommendation: remove mac-idiom entries and macOS PNGs. Skill: `apple-skills:ios`

**Swift 5 language mode — no strict concurrency checking** — `project.pbxproj:525,574,609,643,676,708` (`SWIFT_VERSION = 5.0`) on a heavily async/`@MainActor`/SwiftData codebase (e.g. FaviconLoader callback at `ContentView.swift:1129-1138`). Recommendation: adopt Swift 6 mode (or `SWIFT_STRICT_CONCURRENCY = complete`) and resolve warnings. Skill: `apple-skills:swift`

**Minor force-unwraps in decorative/link code** — `AquariumView.swift:130,166,274` (`randomElement()!`), `SelectableTextView.swift:59` (`URL(string:)!`). Recommendation: safe unwraps with defaults; skip `.link` if URL init returns nil. Skill: `apple-skills:ios`

**Save errors swallowed; creation failures shown generically** — `try? modelContext.save()` at `ContentView.swift:1137`, `OnboardingView.swift:334` (~40+ `try?` occurrences); creation failure surfaces as raw `error.localizedDescription`. Recommendation: wrap meaningful saves in do/catch with `os.Logger`, and give a friendlier action-oriented failure alert. Skill: `apple-skills:ios`

**15 (actually 14) AVAudioPlayers decoded on the main thread at first sound** — `SoundscapeManager.swift:22-39,140-155`; the first sound-triggering interaction pays the full synchronous decode cost. Recommendation: build asynchronously off-main after the first frame and `prepareToPlay()`. Skill: `apple-skills:performance`

**Idle detector churns a Timer per touch and never detaches the recognizer** — `IdleScreensaverDetector:41-52,65-87`. Recommendation: debounce to `touchesBegan/Ended` and detach when inactive. Skill: `apple-skills:performance`

**No PrivacyInfo.xcprivacy privacy manifest (Security-domain restatement)** — folded into the P0 privacy-manifest blocker; when added, also declare file-timestamp reason `C617.1` if any file-date APIs are triggered. Skill: `apple-skills:security`

**Confirm no additional required-reason API categories are triggered by file/atomic writes** — `PinnedFilStore.swift:83,109` use `data.write(..., options:.atomic)`; no file-timestamp/disk-space/uptime APIs found. Recommendation: after adding the manifest, verify via Xcode's privacy report that UserDefaults is the only flagged category (verification step, no code change). Skill: `apple-skills:legal`

**Confirm Privacy Nutrition Label = "Data Not Collected" and no ATT** — no analytics/ad/login SDKs, no `ATTrackingManager`; only user-initiated LinkPresentation favicon fetches (stored on-device). Recommendation: answer "Data Not Collected", Tracking = No, no `NSUserTrackingUsageDescription`; keep in sync if analytics/cloud sync is ever added. Skill: `apple-skills:legal`

**Nonsense brand name "Fil" has zero organic search discoverability** — subtitle/keywords carry all discovery. Recommendation: benefit- and keyword-rich subtitle/keyword set (see Listing Kit); treat the memorable name as a press/word-of-mouth strength, not a search one. Skill: `apple-skills:app-store`

**Dense blob grid and horizontal header/composer rows will overflow at accessibility text sizes** — once Theme fonts scale, fixed-height containers (`NoteCardView:66,174`; `NoteGridView:253,318-327`; Settings/Onboarding pills `:78`/`:138`) crowd. Recommendation: clamp with `.dynamicTypeSize(...accessibility3)` where geometry is intrinsic, drop fixed heights where possible, and use `ViewThatFits`/size-class checks to stack header/composer vertically. Skill: `xcode-integration:accessibility-dynamic-type-specialist`

**Decorative screensaver/blob canvases not hidden from VoiceOver** — `ContentView.swift:114-137` and `NoteCardView` blob backgrounds lack `.accessibilityHidden(true)` (the widget already does this at `FilPinnedWidgetLiveActivity.swift:131`). Recommendation: hide decorative visuals from VoiceOver or expose a single labeled "Dismiss screensaver" element. Skill: `xcode-integration:accessibility-voiceover-specialist`

**Existing note-count screensaver unlocks are a ready-made Pro hook** — `ContentView.swift:401-405`. Recommendation: when Pro ships, offer "unlock all screensavers instantly" as a Pro perk while keeping the earn-by-usage path free. Skill: `apple-skills:monetization`

**No conversion/analytics instrumentation to price or tune a paywall** — no event tracking exists. Recommendation: add lightweight, privacy-respecting first-party analytics (paywall impressions, trial starts, conversions, note-creation frequency) before/at Pro launch; no third-party ad SDKs. Skill: `apple-skills:generators`

---

## Monetization Recommendation

**Recommended model: ship v1.0 FREE (no paywall, no StoreKit), then fast-follow with Freemium + Subscription ("Fil Pro") at ~v1.1–1.2 — once the summary / "zoom out" feature actually ships.** Readiness scores 2/6 ("focus on product / soft-launch"): pre-launch with no users, no retention data, and — decisively — the marketed hero feature does not exist yet (it is hardcoded onboarding preview text; `OpenTodoSummaryService.swift` was deleted). You cannot sell a feature that isn't built, and because all AI runs on-device (zero marginal cost) the "cover API bills" subscription rationale does not apply and must not be used.

**Tiers**
- **Free:** unlimited voice notes + on-device transcription, on-device AI titles, home-screen widget, Live Activity / Dynamic Island, share extension, and the existing note-count screensaver unlocks. Free must stay genuinely useful on one device.
- **Fil Pro — $3.99/mo or $24.99/yr** (~48% annual saving; consider a one-time Lifetime at $49.99): the "zoom out" AI summaries (This Week / Month / Year / All-Time — the onboarding hero), todo roll-up / open-loops summary, all screensavers unlocked immediately, plus later iCloud sync + Mac/Vision when those ship. Price sits in the utility/habit low band, correct against free Notes/Voice Memos.

**Trial:** 7-day introductory free trial on the annual plan; onboard users *into* the Pro summary feature during the trial, with a "trial ending" nudge at day 5.

**Commissions:** enroll in the Small Business Program (15% cut), so $24.99/yr nets ~$21.24. At 10k MAU and a conservative 3% conversion (~300 subs), that is ~$530/mo net — treat Pro as sustaining-a-passion-project money and keep the free tier excellent.

**What to build before charging a cent:** (1) the real zoom-out/summary feature; (2) StoreKit 2 + In-App Purchase capability + an auto-renewable subscription group (Monthly/Annual) with a StoreKit Configuration file; (3) a paywall framed on convenience/power (not AI costs); (4) privacy policy + terms/EULA linked from the paywall and Settings with the required auto-renew disclosure text; (5) lightweight first-party conversion analytics to validate pricing with introductory offers. iCloud/CloudKit sync + Mac/Vision are the strongest future paywall anchors (Future).

---

## App Store Listing Kit

*Privacy-claim caveat: until `requiresOnDeviceRecognition = true` is set, do NOT use absolute claims like "100% on-device", "nothing leaves your phone", or "no internet required" for transcription. Titling via FoundationModels IS genuinely on-device and may be claimed as such. The drafts below use the safe framing "no account, no ads, your notes stay on your device."*

**Category:** Primary = Productivity, Secondary = Utilities.

**App name (30 max):** `Fil - Voice Notes & Ideas` (26). Alt: `Fil: Voice to Note` (18).

**Subtitle (30 max):** `Speak, transcribe, remember` (27). Alts: `Voice memos with smart titles` (29); `Talk to note in seconds` (23).

**Keywords (100 max, deduped vs name/subtitle):** `memo,dictate,dictation,transcribe,speech,record,journal,idea,capture,todo,thought,private,quick,scratchpad`. Avoid standalone `app`, `free`, `best`, `#1`, `AI`.

**Promotional text (170 max):** "The fastest way from thought to note. Just talk — Fil transcribes and titles every note on-device, so it's easy to find later. No account. No ads." (145)

**Description (draft):**
> Your thoughts move faster than your thumbs. Fil is the fastest way to capture them — just talk, and your words become a titled, searchable note.
>
> Tap once and speak. Fil transcribes what you said and uses on-device Apple Intelligence to give every note a short, natural title — so a week later you can find "call the landlord" instead of scrolling a wall of text.
>
> **WHY FIL** — Talk, don't type. Smart titles written on your device by Apple's on-device Foundation Models. No account, no ads, no feed; your notes live on your device. A clean, calming home so your notes feel like a place, not a pile.
>
> **CAPTURE FROM ANYWHERE** — Home Screen widget, Live Activity & Dynamic Island, and a Share Sheet to send a link, image, or text from any app into Fil.
>
> **BUILT FOR THE WAY YOU THINK** — Weekly, monthly, yearly, and all-time views to zoom out across your notes. A quiet, considered design with optional sound effects, an ambient screensaver, and a lowercase writing mode.
>
> **PERFECT FOR** — capturing ideas the moment they strike, voice memos and quick reminders, a private low-friction journal, and turning messy spoken thoughts into something findable.
>
> No sign-up. No subscription. Open it and talk. Questions or feedback? mason@garcera.us

**What's New (1.0):** "Say hello to Fil. Talk, and your words become a titled, searchable note — with on-device smart titles, a home screen widget, Live Activity, and a Share Sheet to send anything straight into Fil. This is v1.0; tell us what to build next: mason@garcera.us"

**Screenshot shot-list (6.9″/6.7″, capture on iPhone 16/15 Pro Max):**
1. **Hero** — "Just talk. Fil does the rest." — ComposerBar mid-capture over the ambient gradient.
2. **Core** — "Every note gets a smart title." — NoteGridView/NoteCardView with several auto-titled notes.
3. **Differentiator** — "Titled on your device." — ArticleView with the generated title highlighted (claim on-device only for *titling*).
4. **Widget + Dynamic Island** — "Your note, one glance away." — home screen with the Pinned widget + Dynamic Island composited.
5. **Zoom out** — "See what keeps coming up." — the week/month/year/all-time scope selector.
6. **Privacy/CTA** — "No account. No ads. Just you." — clean home or Settings About.

Put caption keywords ("voice", "transcribe", "notes", "private") in top/bottom safe zones (Apple OCR indexes screenshot text). A 15s "tap → speak → titled note" App Preview is optional but lifts conversion.

---

## Legal & Privacy Checklist

**Documents to produce**
- **Privacy Policy (P0, required):** short local-first policy; host at a public URL (e.g. `https://masongarcera.github.io/fil/privacy` or `garcera.us/fil/privacy`); enter in App Store Connect → App Privacy; link in Settings → About. Must name Microphone, Speech Recognition, and Camera and explain each. **Its speech wording must match the on-device decision** (see the speech-transcription P0): if `requiresOnDeviceRecognition = true`, state transcription is fully on-device; otherwise disclose that audio may be processed by Apple's Speech service under Apple's Privacy Policy. Draft provided by the Legal domain (fill `CONTACT_EMAIL`).
- **Support URL (P1, required):** a support page with mailto + short FAQ.
- **Terms of Service (optional):** nice-to-have for a free/no-account app.
- **EULA (Future / optional):** Apple's Standard Licensed Application EULA auto-applies; a custom EULA is unnecessary for a free, no-account, no-UGC app — do not block launch on it.

**Missing `PrivacyInfo.xcprivacy` (P0)** — add to the main target (and widget + share extension): `NSPrivacyTracking=false`, empty `NSPrivacyTrackingDomains`, empty `NSPrivacyCollectedDataTypes`, and one `NSPrivacyAccessedAPICategoryUserDefaults` entry with reasons `["CA92.1"]` (add `1C8F.1` for app-internal reads/writes). Add to Copy Bundle Resources.

**Data-collection nutrition-label answers (local-first app)** — **Data Not Collected** for every category; **Tracking = No**; no `NSUserTrackingUsageDescription` and no IDFA. This is honest *provided* transcription is forced on-device; if server transcription is retained, the label and description must disclose it. LinkPresentation favicon fetches are user-initiated and stored on-device — not developer data collection, so they do not change the answer, but note them so future ATS/required-reason audits are not misled.

---

## Platform Scope

**visionOS + macOS removal (iPhone-only v1)** — purely a `project.pbxproj` / asset-catalog edit; there is zero visionOS/macOS Swift in the codebase, so removal is clean and low-risk. In the Fil app target (Debug + Release):
1. `SUPPORTED_PLATFORMS` (`:520,569`): change to `"iphoneos iphonesimulator"` — the single most important edit (drops both visionOS and macOS).
2. `TARGETED_DEVICE_FAMILY` (`:526,575`): change `"1,2,7"` → `"1"` for a strictly iPhone-only v1 (or `"1,2"` if you keep iPad-capable listing; extensions are already `"1,2"`).
3. Delete `XROS_DEPLOYMENT_TARGET` (`:527,576`).
4. `SDKROOT` (`:518,567`): `auto` → `iphoneos` to prevent silent re-resolution.
5. Delete `MACOSX_DEPLOYMENT_TARGET` (`:513,562`) and `LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]` (`:512,561`).
6. Remove the `"mac"` idiom entries (and macOS PNGs) from `AppIcon.appiconset/Contents.json`.
7. No scheme edit required; clear DerivedData and confirm only iPhone run destinations appear. No Swift changes needed. In App Store Connect, uncheck iPad/Mac availability.

**iPadOS future-readiness (non-blocking)** — the code leans cross-platform-friendly (generic `WindowGroup`, `#if os(iOS)` audio guards), but the UI is portrait-locked single-column with no `horizontalSizeClass`/`NavigationSplitView`/idiom adaptivity, so iPad renders as a stretched phone. Before an iPad launch: introduce a size-class-aware / `NavigationSplitView` layout, verify keyboard/pointer, and test both orientations. Do not market iPad support until the adaptive layout exists.

**macOS future-readiness (non-blocking)** — `AudioSessionCoordinator.swift` and `VoiceRecorderViewModel.swift:77` wrap all `AVAudioSession` work in `#if os(iOS)`, so a native Mac build compiles those out with recording unimplemented; FoundationModels availability also differs by platform/hardware. For a real Mac app: provide macOS AVAudioEngine/permission paths, adopt a windowed layout, and gate FoundationModels behind availability with a graceful fallback. A "Designed for iPad" Mac listing is lighter but still needs the iPad adaptive layout first.

---

## Growth & Launch Plan

**Positioning (the whole engine):** a local-first, on-device voice-to-note app with two press angles — (1) *innovative Apple tech* (one of the first shipping apps built on on-device FoundationModels for titling/summarization, plus Live Activity/Dynamic Island, widget, and share-into-Fil), and (2) *privacy-first / scratch-your-own-itch*, paired with the authentic "from mason" founder voice already in onboarding.

**Pre-launch (T-4 to T-1 weeks)**
- Build the growth infrastructure that doesn't exist yet: one-page website (App Store link + `/press`), press kit (1024 icon, 6–8 framed+raw screenshots, short/medium/long copy, fact sheet, founder bio/photo), and a 20–30s promo (tap → AI title → zoom-out summary).
- Cut a 2–3 week TestFlight beta; seed 20–50 testers from r/iosapps, r/apple, r/productivity, #buildinpublic (they become launch-day reviews).
- Draft ASO before submission (subtitle/keywords carry all discovery for a coined name).
- Line up ONE Tier-1 exclusive (MacStories or 9to5Mac) with 1–2 week embargoed access; invite 5–10 Tier-2/3 under an embargo lifting launch day 9am ET. Pitch Tue–Thu 9–11am; avoid WWDC/iPhone-event weeks.
- Start building in public now on one channel (Twitter/X or Mastodon — Mastodon skews privacy-conscious); post widget/Dynamic Island/on-device-AI clips 3×/week; line up an indie podcast for the founder story.

**Launch day**
- Embargo lifts; email the exclusive + embargo group the live App Store link + press kit at 9am ET.
- Ship a Product Hunt launch and a Show HN / self-post framed on privacy + on-device AI.
- Post the promo video across social + relevant subreddits (add value, don't just drop a link).
- Ask the TestFlight cohort to download day-one and leave honest reviews.

**Post-launch (first 30–90 days)**
- Instrument the App Store Connect funnel (no third-party SDK): impressions → tap-through (>8%) → product-page conversion (>40%) → D1 (>35%)/D7 (>20%)/D30 (>10%); watch D7 closely for the used-once cliff — the widget/Live Activity and a gentle capture reminder are your habit hooks.
- Add the missing referral loops: `SKStoreReviewController` after a delightful moment, and an outbound share of a note/summary card (`ImageRenderer` plumbing exists at `ArticleView.swift:959`) — each share is a free impression.
- Weekly cadence: reply to every review/mention, ship one visible improvement, post a Friday "what shipped"; monthly, a metrics recap and a technical blog post ("How I built voice notes on Apple's on-device FoundationModels") — catnip for iOS Dev Weekly/HN.
- **Day-30 decision gate:** D7 > 40% and growing organic installs → INVEST (then reconsider monetization/platforms); D7 20–40% → ITERATE on the retention cliff. Mac/Vision are a credible post-PMF expansion story, not a launch item.

**Metrics priority:** product-page conversion & tap-through → D1/D7 retention → rating count/average (>4.5) → share/referral rate → press/PH/HN referral traffic.

---

## Sequenced Remediation Roadmap

*Ordered for a sensible execution flow: unblock the build, then the binary/config, then submission metadata, then reliability/accessibility, then growth/monetization, then future.*

**Phase 1 — Hard build/submission blockers (do first)**
1. [x] Guard FoundationModels with `SystemLanguageModel.default.availability` + `keywordFallback()`; move the throwing call so notes always insert — `apple-skills:apple-intelligence`
2. [x] Trim `SUPPORTED_PLATFORMS`/`TARGETED_DEVICE_FAMILY`/`SDKROOT`, delete XROS/MACOSX targets + Mac runpath, drop iPad orientation key + Mac AppIcon idioms — `apple-skills:ios` *(mac runpath left inert — see worklog)*
3. [x] Unify `IPHONEOS_DEPLOYMENT_TARGET` across app, widget, and share extension — `apple-skills:ios` *(unified at 26.4)*
4. [x] Add `ITSAppUsesNonExemptEncryption = NO` — `apple-skills:release-review`
5. [x] Add `PrivacyInfo.xcprivacy` (app + extensions) with UserDefaults `CA92.1`/`1C8F.1` and empty collection/tracking — `apple-skills:legal`
6. [x] Set `requiresOnDeviceRecognition = true` (gated on `supportsOnDeviceRecognition`) OR reconcile all on-device claims — `apple-skills:apple-intelligence` *(code done; privacy-policy wording for no-on-device-support devices tracked in Phase 2 #9)*
7. [x] Fix the Speech usage string (and camera trailing space) — `apple-skills:release-review`
8. [x] Make `Theme.dmSans/dmMono` Dynamic-Type-aware + `UIFontMetrics` for `SelectableTextView`; convert inline sites — `xcode-integration:accessibility-dynamic-type-specialist` *(Theme + SelectableTextView + root clamp done; inline `.system(size:)` conversion folded into P2 #23)*

**Phase 2 — Submission metadata & App Store Connect**
9. [x] Write + host the Privacy Policy; enter Privacy Policy URL in ASC — `apple-skills:legal` *(drafted `docs/legal/privacy-policy.md`; you host + enter URL)*
10. [x] Stand up a Support page; enter Support URL — `apple-skills:growth` *(drafted `docs/support/`; you host + enter URL)*
11. [x] Complete the App Privacy nutrition label ("Data Not Collected", Tracking = No) consistent with the manifest — `apple-skills:legal` *(answers in `AppStore/app-privacy.md`; you enter in ASC)*
12. [x] Add in-app Settings links: Privacy Policy, Contact/Feedback, Rate Fil — `apple-skills:generators` + `apple-skills:legal` *(+ Terms; URLs are placeholders in FilLinks.swift until hosted)*
13. [x] Set the App Store name + subtitle + deduped keywords — `apple-skills:app-store` *(finalized in `AppStore/metadata.md`: "Fil — Let Thoughts Be"; you enter in ASC)*
14. [x] Produce the 6-shot 6.9″/6.7″ screenshot set (+ optional preview) — `apple-skills:app-store` + `apple-skills:generators` *(shot-list spec in `AppStore/screenshots.md`; you capture + upload)*

**Phase 3 — Reliability, UX & accessibility hardening**
15. [ ] Add permission priming + a Settings-redirect on denial — `apple-skills:generators` (permission-priming)
16. [ ] Fix the `transcribe()` continuation leak (single-resume + timeout) — `apple-skills:swift`
17. [ ] Warm/reuse + prewarm the FoundationModels session — `apple-skills:apple-intelligence`
18. [ ] Add VoiceOver labels (dark-mode toggle, composer buttons, note cards + selection action); hide decorative canvases — `xcode-integration:accessibility-voiceover-specialist`
19. [ ] Replace `fatalError` with graceful fallback; tighten the store-reset heuristic (move-aside, not delete) — `apple-skills:swiftdata`
20. [ ] Apply `.completeFileProtection` and truncate the pinned-snapshot `previewText`; protect shared-draft + audio files; add app-switcher privacy blur — `apple-skills:security`
21. [ ] Adopt Swift 6 / strict concurrency; remove force-unwraps; wrap meaningful saves with logging — `apple-skills:swift` + `apple-skills:ios`
22. [ ] Warm SoundscapeManager off-main; debounce the idle detector — `apple-skills:performance`
23. [ ] Clamp Dynamic Type / add `ViewThatFits` for dense grid + header/composer rows — `xcode-integration:accessibility-dynamic-type-specialist`

**Phase 4 — Growth infrastructure (pre-launch → launch)**
24. [ ] Build website + press kit + promo video — `apple-skills:app-store` + `apple-skills:growth`
25. [ ] Add outbound share / summary-card social export — `apple-skills:generators` (share cards)
26. [ ] Add `SKStoreReviewController` review prompt after an "aha" moment — `apple-skills:generators` (review prompt)
27. [ ] Run the TestFlight beta, press embargo, Product Hunt / Show HN launch; instrument the ASC funnel — `apple-skills:growth`

**Phase 5 — Monetization (fast-follow, v1.1–1.2)**
28. [ ] Build the real zoom-out/summary feature (the hero worth paying for) — `apple-skills:monetization`
29. [ ] Add StoreKit 2 + IAP capability + subscription group (Monthly/Annual) + StoreKit config — `apple-skills:generators`
30. [ ] Build the convenience-framed paywall (+ screensaver-unlock perk) with legal disclosures — `apple-skills:monetization` + `apple-skills:legal`
31. [ ] Add first-party conversion analytics to validate pricing — `apple-skills:generators`

**Phase 6 — Future (post-PMF)**
32. [ ] iCloud/CloudKit sync as the flagship Pro anchor — `apple-skills:monetization`
33. [ ] iPad adaptive (`NavigationSplitView`/size-class) layout — `apple-skills:ios`
34. [ ] Native macOS support (audio paths, windowed layout, FoundationModels availability) — `apple-skills:macos`
35. [ ] Listing localization / keyword cross-localization (es-MX/en-GB first) — `apple-skills:app-store`
