# Fil — First-Run Onboarding Design

*Design spec for the action-first onboarding, grounded in `onboarding-research.md`. Decisions
locked with Mason 2026-07-07. Build status: design only (see "When to build"). This redesign also
**replaces the stale summary-preview onboarding**, so it doubles as the pending stale-copy fix.*

North-star: **a new user creates their own first fil in session one.** Everything here serves that,
then rewards it.

Correction baked in: **Fil is not "voice-first."** Text, voice, links, and photos are **equal**
front doors. First-run copy is mode-neutral (the composer's natural default is "tap to write").

---

## The flow

1. **First launch → land on home + composer.** No wizard, no carousel, no summary screens. A single
   gentle, skippable nudge invites the first fil (mode-neutral). Minimal guidance.
2. **User creates their own first fil** (any mode: type, speak, link, photo). This is the activation
   event — theirs, not a seeded one.
3. **A quiet congratulation.** Calm and on-brand (no confetti/gamification). e.g. *"that's a fil.
   it's yours."*
4. **The "from mason" seed fil then arrives — animated as if being created normally**: the gooey
   creation blob appears and morphs into a fil card (reusing `CreatingFilBlobView` +
   `matchedGeometryEffect`), so the reveal *also teaches the creation animation and discoverability*.
   A tiny caption is fine, e.g. *"one more — from mason."*
5. **User can open, read, interact with, and delete it** like any fil — including its filaments.

Result: action-first + learn-by-example + founder-soul, nothing forced, everything skippable.

---

## The seed fil (draft — Mason to edit)

- **Badge / title (fixed, no AI):** `from mason`
- **Gradient:** coral → indigo (`#F24D59` → `#6659CC`) — a warm, distinctive pair so it stands out.
- **Deletable:** yes (landfil like any fil). **Seeded once, ever** — never reappears after deletion.
- **Transcript (draft):**

> hi — i'm mason, and i made fil.
>
> you just made your first fil. this one's mine.
>
> i wanted somewhere to put a thought without turning it into a project. no inbox, no tags, no
> streaks. some thoughts are just thoughts. they just need to exist.
>
> tap a word to attach a **filament**. swipe to **landfil** a fil when you're ready to let it go —
> even this one.
>
> i hope you find as much ful·fil·ment here as i do.

- **Filaments (sample attachments, to showcase the feature):**
  - keyword **"filament"** → text note: *"a filament is a little something you attach to a word — a
    note, photo, recording, or link. you're reading one now."*
  - keyword **"landfil"** → text note: *"landfil = letting a fil go. swipe it away anytime. nothing
    here asks you to keep it."*
  - (Both keywords appear in the transcript, so they highlight and are tappable.)
- **Relationship to `FromMasonFilCard`:** that fuller manifesto stays in Settings; the seed is the
  lightweight, in-context version. The seed can nod to it (*"more from mason in settings"*) — optional.

---

## Gating & lifecycle
- `@AppStorage("didSeedWelcomeFil")` — seed inserted exactly once, after the user's first fil; never
  re-seeded (even if deleted).
- Trigger point: fire the seed reveal right after the first **user-created** fil completes
  (in the `createFil` success path), gated on `!didSeedWelcomeFil`.
- **Remove** the summary-preview screens + preferences step from the current `OnboardingView`; move
  the **lowercase toggle to Settings** (defaults now, preferences later). Reconcile the
  `UserProfile` / `RootView.profiles.isEmpty` gating so "already onboarded" is still tracked cleanly
  once the wizard is gone (e.g. create the `UserProfile` on first launch or key off the seed flag).

## Instrumentation (cheap, first-party, no SDK)
- `firstLaunchDate` and `firstUserFilDate` (stamped only in the composer `createFil` path, so the
  **seed is naturally excluded**). Derive session-1 activation + TTFV (median / p75). Pair with App
  Store Connect installs/retention.

## Implementation notes
- **Reuse the existing creation animation** (`CreatingFilBlobView`, `beginCreatingFil` /
  `finishCreatingFil`, `matchedGeometryEffect`) to animate the seed in as though composed — insert
  the seed `Note` through that same visual path with a short beat.
- Seed `Note` set explicitly (title, transcript, gradient, filaments) — **no FoundationModels call**,
  so it always renders perfectly even where on-device AI is unavailable.
- Mic priming (#15) unchanged. No schema/data-layer changes. No permissions for the text path.

## Open items (Mason)
- Edit the seed transcript / title / filament copy above.
- Confirm gradient choice, and the congratulation line ("that's a fil. it's yours.").
- Confirm the first-launch nudge copy (mode-neutral, one line).

## When to build
- **Doubles as the stale-copy fix**, so it's launch-relevant. Two paths:
  - **Minimal for launch:** just strip the stale summary screens (fast, submittable), build this full
    flow post-launch with activation data.
  - **Full for launch:** build this now so v1 ships with strong onboarding *and* the copy fixed.
- Recommendation: if launch is near, do the minimal strip now; otherwise this flow is contained and
  low-risk (no schema changes) and would be a strong v1 onboarding.
