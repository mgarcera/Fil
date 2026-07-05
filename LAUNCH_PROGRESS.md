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

