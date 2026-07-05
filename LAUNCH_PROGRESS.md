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

