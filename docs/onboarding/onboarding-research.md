# First-Run Onboarding → First-Fil Activation — Research

*Evidence review for redesigning Fil's first-run onboarding, optimized for one metric: a brand-new
user creating their **first fil in session one** (D1 activation). Scope: first launch → first core
action only. Compiled 2026-07-07 via direct web research (the packaged deep-research harness failed
on its own plumbing; sources gathered + synthesized directly).*

> **Evidence-quality caveat, up front:** much of the quantified material below comes from
> **analytics/onboarding vendors** (Userpilot, Appcues, Amplitude, Digia, SaaSFactor) who sell
> onboarding tools — treat specific percentages as **directional, not laws**. The sturdier,
> conflict-free sources are **Nielsen Norman Group** (carousels, permission requests) and the
> **Amplitude 2025 Product Benchmark Report** (activation→retention correlation across 2,600+
> companies). Where a claim is single-case or vendor-sourced, it's flagged.

---

## What the evidence says

### 1. Speed to first value is the whole game
- Activation (experiencing core value) is the behavior most correlated with retention; **time-to-
  first-value (TTFV) is a primary predictor**. Users who reach value fast are far likelier to stay
  (vendor figures range 3–5× for <60s value, and "activate within 3 days → ~90% more likely to
  continue" — directional).
- Amplitude's 2,600-company benchmark: **>98% of new users churn within two weeks if they never hit
  a value milestone**, and strong Day-7 activation is the strongest cross-temporal predictor of
  3-month retention. (This is the most credible dataset in the set.)
- Onboarding *completion* ≠ value. Many apps report high completion and weak retention. Optimize
  for the value moment, not slides viewed.

### 2. Value-first beats gate-first; onboarding is "bumpers," not the value
- Consensus: **don't gate the first value behind setup/sign-up.** Pull the aha moment forward; make
  the first session produce **something the user can keep** (a draft, a result) so there's a reason
  to return.
- **Fil is already ahead here:** no account, no sign-up — the single biggest activation-killer is
  simply absent.

### 3. Passive carousels underperform; interactive/"learn by doing" wins
- **NN/G explicitly does *not* recommend "deck-of-cards" (carousel) onboarding** shown at launch —
  it makes the app look more complicated and strains memory.
- Users have **"learned blindness"** to the 3–5-slide intro carousel and swipe past it reflexively.
- What works: **hands-on, action-based** first-run (do the core thing immediately), ideally with an
  *optional* tour + a light persistent checklist as "soft bumpers." Forced passive tours hurt.

### 4. Permission priming (directly relevant — Fil is voice-first)
- Ask **in-context, after motivation** — never at launch. Deferring the prompt → **~28% higher grant
  rate** (vendor-cited research).
- A **priming screen with benefit-driven copy** and **soft buttons** ("Got it"/"Next", not
  "Allow/Deny") protects the one-shot iOS prompt; strong copy showed large lifts in a controlled
  contacts study (~81%, single study). Always offer a **non-permission fallback**.
- **Fil already implemented exactly this** (the `MicPrimingSheet` + Settings-redirect from Phase 3,
  audit #15). The research validates that work as best-practice-aligned.

### 5. Screen count: "fewer" is a heuristic, not a law
- Common guidance: **1–3 screens / under ~90s** for simple consumer apps.
- But the real principle from the more careful sources: **cut friction that serves *you*
  (sign-up, tracking, "where'd you hear about us")**; **keep friction that serves the *user*** —
  i.e. personalization that *visibly* changes their experience. Passive education screens are the
  weak middle: neither. For a simple, no-account app like Fil, that means **keep it minimal.**

---

## What this means for Fil (prioritized recommendations)

Fil's current first-run (per `OnboardingView`) shows **time-scoped summary previews + a "use
lowercase" toggle** *before* the user makes anything — that's a passive, carousel-ish education gate
in front of value, and it markets a **feature that no longer exists**. The evidence says that's the
weakest possible shape. Reshape around the first fil:

1. **Lead with the action, not explanation.** First launch should land the user at the composer /
   an inviting empty state — *"tap and say what's on your mind"* (or type). **The first fil IS the
   onboarding.** This is the single highest-leverage change (value-first + interactive + kills the
   carousel).
2. **Cut the summary-preview screens.** They're passive education *and* promise a removed feature.
   Removing them serves both the evidence and the pending stale-copy fix.
3. **Keep the mic priming you built (#15) as-is** — it's already evidence-aligned. Optional polish:
   make the copy even more benefit-forward ("say it out loud, fil writes it down").
4. **Move the lowercase toggle (and any prefs) into Settings.** They don't drive activation; they're
   friction before value. Defaults now, preferences later.
5. **Make the aha moment shine.** Fil's real aha is *"I spoke and it became a titled note."* On the
   first fil, let the AI-title reveal land with a beat — that's the value moment worth reinforcing
   (no gamification needed; it fits the calm brand).
6. **Everything skippable, nothing forced.** Matches both the evidence (forced passive tours hurt)
   and Fil's anti-optimization soul. A single gentle nudge, not a wizard.
7. **Instrument activation cheaply (no third-party SDK).** Log two first-party, on-device
   timestamps — `firstLaunchDate` and `firstFilCreatedDate` — and derive **session-1 activation**
   and **TTFV** (median / p75). That plus App Store Connect's install & retention charts is enough
   to know if a change helped. (Pairs with the light analytics noted in the monetization plan.)

**Brand fit check:** none of this requires gamification, streaks, or pressure. "Get out of the way
and let them make a fil" is *more* on-brand than the current explain-first flow, not less. The one
place common advice conflicts with Fil — "add personalization questions" — we intentionally skip;
Fil has nothing to personalize and the brand rejects it.

**Empirical caveat:** the *magnitude* of any lift is unknowable pre-launch. The move is: ship the
minimal action-first flow, instrument the two timestamps, and treat onboarding as a post-launch
optimization target once real session-1 activation data exists.

---

## Sources
- [Nielsen Norman Group — Mobile-App Onboarding: Analysis of Components and Techniques](https://www.nngroup.com/articles/mobile-app-onboarding/)
- [Nielsen Norman Group — 3 Design Considerations for Effective Mobile-App Permission Requests](https://www.nngroup.com/articles/permission-requests/)
- [Amplitude — Time to Value Drives User Retention](https://amplitude.com/blog/time-to-value-drives-user-retention)
- [Appcues — Asking nicely: 3 strategies for successful mobile permission priming](https://www.appcues.com/blog/mobile-permission-priming)
- [Appcues — 26 Best User Onboarding Examples by Tactic](https://www.appcues.com/blog/best-user-onboarding-examples)
- [Userpilot — Enhancing the Onboarding Experience](https://userpilot.com/blog/onboarding-experience/)
- [Userpilot — Mobile Carousels & User Fatigue](https://userpilot.com/blog/mobile-carousels/)
- [Digia — Mobile App Onboarding Guide: Activation, Patterns, and Retention](https://www.digia.tech/post/mobile-app-onboarding-activation-retention/)
- [Digia — App Onboarding Rate statistics](https://www.digia.tech/post/app-onboarding-rates-statistics)
- [RevenueCat — Why your onboarding experience might be too short](https://www.revenuecat.com/blog/growth/why-your-onboarding-experience-might-be-too-short/)
- [Setgreet — What the Numbers Actually Say About Mobile App Onboarding](https://www.setgreet.com/blog/what-the-numbers-actually-say-about-mobile-app-onboarding-(and-what-to-track))
- [Businessofapps — App Onboarding Rates (2025)](https://www.businessofapps.com/data/app-onboarding-rates/)
- [UXmatters — A Framework for Choosing Types of Onboarding Experiences](https://www.uxmatters.com/mt/archives/2024/07/a-framework-for-choosing-types-of-onboarding-experiences.php)
