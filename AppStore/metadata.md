<!--
STAGED — rewritten 2026-08-13 against the new positioning. NOT ready to paste into ASC.

Pending, all marked inline:
1. {{ENTITY}} — the contracting party and copyright holder. Rootcause LLC is dissolving.
2. URLs are written as smidgecraft.com, but the live pages are still served from rootcause.ltd.
   They switch together during the migration sweep — see docs/entity-migration.md.
3. The subscription blocks assume Fil Pro ships. On hold pending the Private Cloud Compute test;
   if v1 has no paywall, delete every block marked CONDITIONAL.
4. Bundle ID and App Store ID both change when Fil is recreated under the new individual account.

Superseded from the July version: the name and subtitle (privacy/voice-led → surfaces-led), the
"no folders" claim (folders shipped), and the claim that Apple's on-device intelligence writes
titles (it doesn't — titles are the first line of the user's own text).
-->

# Fil — App Store Listing Metadata

*Copy these into App Store Connect. Character counts are noted; Apple's limits in parentheses.
Verify counts in ASC (it's the source of truth).*

- **App name** (30): `Fil — Folders Outside the App` — 29 chars
- **Subtitle** (30): `Lock screen & dynamic island` — 28 chars
- **Primary category:** Lifestyle   ·   **Secondary category:** Utilities
- **Bundle ID:** `com.masongarcera.Fil` — *re-registers under the new developer account; confirm it
  can be reused after the old record is deleted, or pick a new one before launch.*

## Keywords (100, comma-separated, no spaces)
```
voice,memo,transcribe,journal,diary,idea,capture,thought,note,widget,search,ai,photo,link,pdf,pin
```
~97 chars. Hidden from users; they carry the search load while the visible name and subtitle carry
the positioning. Don't repeat words already in the name or subtitle — "folders", "lock screen", and
"dynamic island" are all indexed from there, so they're deliberately absent here. Apple stems
plurals, so singulars are fine.

## Promotional text (170)
```
pin what you're in the middle of to your lock screen, dynamic island, home screen. glance without
unlocking. every thought arrives as its own shape. no account, no ads.
```

## Description
```
what you're working on, already out there.

pin the thing you're in the middle of — the trip, the move, the dinner you're planning — and it
lives on your lock screen, in your dynamic island, on your home screen. glance and it's there.
open fil when you want to dig in.

six places that aren't the app:
- lock screen — your pinned folder, there when you pick up the phone
- dynamic island — tap it and you're straight into what you're working on
- home screen — a widget that shows the folder, not a button that opens an app
- today view — the same widget, one swipe from the lock screen
- control center — start a voice fil or a written one without going anywhere first
- share sheet — send a link, a photo, a paragraph from any app straight into fil

no two thoughts look alike. every fil arrives with its own colour, its own shape, its own gradient.
you don't pick it and you can't change it — it's given, the way the thought was. so you know a
thought on sight: you don't read your folder, you recognise it.

and then you go in. a voice fil has a waveform and a transport. photos become a carousel. links,
pdfs, and to-dos each get their own surface. every action has its own sound and its own feel.
ambient screensavers and slow drifting gradients — an app you can leave open.

what you can keep:
- speak or type a thought; your voice becomes a note, transcribed on your device.
- add a photo, save a link, jot a to-do.
- attach a filament to any word: a note, a link, a photo, a pdf, or another fil.
- file what you want into folders. pin the one you're living in.

finding it again:
- keyword search stays on your device.
- smart search adds asking in your own words: fil finds what you meant, by meaning, time, and kind,
  then tells you what it found.

no inbox to clear, no tags to maintain, no streaks, no system to keep up with.

no account, no ads, no tracking. your fils stay on your phone. smart search is the one thing that
leaves, and only when you ask. its text is never used to train ai and is deleted within 30 days.

<!-- CONDITIONAL — delete if v1 ships without a paywall -->
fil pro is an optional auto-renewing subscription, offered monthly or yearly with a free trial.
payment is charged to your apple account and renews unless canceled at least 24 hours before the
period ends; manage it in ios settings.
<!-- /CONDITIONAL -->

terms: https://smidgecraft.com/fil/terms
privacy: https://smidgecraft.com/fil/privacy

questions or ideas? mason@smidgecraft.com
```

## What's New (version 1.0)
```
the first fil. pin what you're working on to your lock screen, dynamic island, or home screen, and
glance at it without unlocking. every thought arrives with its own colour and shape, so you know it
on sight. send anything in from any app. no account, no ads. tell me what to build next:
mason@smidgecraft.com
```

## Also set in App Store Connect
- **Legal entity / copyright:** {{ENTITY}}. Set the app's copyright to `© 2026 {{ENTITY}}`.
- **Support contact email (App Review Information):** `mason@smidgecraft.com`.
- **Privacy Policy URL:** `https://smidgecraft.com/fil/privacy` (must match `FilLinks.privacyPolicy`).
- **Support URL:** `https://smidgecraft.com/fil/support` (must match `FilLinks.support`).
- **Terms of Use (EULA):** paste the `/fil/terms` text into the custom EULA field (or link it) so it
  matches the in-app Terms link (`FilLinks.termsOfService`).
- **Age rating:** no objectionable content (expected 4+).
- **Seller name:** ⚠️ comes from the developer account enrollment, not an ASC field. On an
  **individual** account it shows the enrolled person's legal name — so the listing will read
  **Mason Garcera**, not Smidgecraft, unless a DBA / trade name is approved by Apple. Decide before
  launch how much weight the Smidgecraft name is meant to carry publicly.
- **Small Business Program:** enroll the new individual account. It sets the 15% commission **and**
  it is the eligibility gate for the free Private Cloud Compute tier, which the monetization
  decision depends on.
- **CONDITIONAL — Subscription:** create the Fil Pro group plus monthly/yearly products with the
  free trial in Monetization → Subscriptions, and add a review screenshot for each. Skip entirely if
  v1 ships without a paywall.
- **CONDITIONAL — Price:** free app with an optional Fil Pro auto-renewing subscription. If there's
  no paywall, the app is simply free.

## App Review notes (draft)
- Fil is device-local. Smart search is the only feature that sends data out, and only on request.
- First run seeds a "from mason" welcome fil after the user's own first fil — expected behaviour,
  not test data.
- **CONDITIONAL:** if Pro ships, reviewers need the sandbox path to evaluate smart search, since it
  is gated. Note the trial in the review notes so it isn't reported as a non-functional feature.
