# Fil — App Store Listing Metadata

*Copy these into App Store Connect. Character counts are noted; Apple's limits in parentheses.
Verify counts in ASC (it's the source of truth).*

- **App name** (30): `Fil — Let Thoughts Be`  — 21 chars (hyphen version `Fil - Let Thoughts Be` also fine)
- **Subtitle** (30): `Speak your mind. Let it be.`  — 27 chars
- **Primary category:** Lifestyle   ·   **Secondary category:** Utilities
- **Bundle ID:** com.masongarcera.Fil

## Keywords (100, comma-separated, no spaces)
```
voice,memo,transcribe,journal,diary,idea,capture,thought,note,private,search,ai,photo,link,pdf
```
~95 chars. Hidden from users; they carry the search load (the visible name/subtitle stay on-ethos).
Don't repeat words already in the name/subtitle. Apple stems plurals, so singulars are fine.

## Promotional text (170)
```
speak, type, or snap a thought and fil keeps it, right on your device. fil pro adds smart search: ask in your own words and find what you meant. no account, no ads.
```

## Description
```
some thoughts are just thoughts.

fil is a quiet place to speak your mind and let it be. tap once and say (or type) what's on your
mind, and fil turns it into a short, titled note you can actually find later, all on your device.

that's it. that's the app.

fil is not a productivity app, a second brain, a journal, or a system to keep up with. there's no
inbox, no folders, no streaks, no due dates. some thoughts just need to exist.

what you can keep:
- speak or type a thought; your voice becomes a titled note, transcribed on your device.
- add a photo, save a link, jot a to-do.
- attach a filament to any word: a note, a link, a photo, a pdf, or another fil.
- titles are written on your device by apple's on-device intelligence.

finding it again:
- free keyword search stays on your device.
- fil pro adds smart search: ask in your own words and fil finds what you meant, by meaning, time,
  and kind, then reflects it back.

private by design: no account, no ads, no tracking. your fils stay on your phone. smart search is
the one thing that leaves, and only when you ask. its text is never used to train ai and is deleted
within 30 days.

speak your mind. let it be.

fil pro is an optional auto-renewing subscription, offered monthly or yearly with a free trial.
payment is charged to your apple account and renews unless canceled at least 24 hours before the
period ends; manage it in ios settings.
terms: https://rootcause.ltd/fil/terms
privacy: https://rootcause.ltd/fil/privacy

questions or ideas? mason@rootcause.ltd
```

## What's New (version 1.0)
```
the first fil. speak, type, or snap a thought and it becomes a short, findable note, right on your
device. attach filaments to any word, and try fil pro smart search to find what you meant. no
account, no ads. tell me what to build next: mason@rootcause.ltd
```

## Also set in App Store Connect
- **Legal entity / copyright:** Rootcause LLC. Set the app's copyright to `© 2026 Rootcause LLC`.
- **Support contact email (App Review Information):** `mason@rootcause.ltd`.
- **Privacy Policy URL:** `https://rootcause.ltd/fil/privacy` (matches `FilLinks.privacyPolicy`).
- **Support URL:** `https://rootcause.ltd/fil/support` (matches `FilLinks.support`).
- **Terms of Use (EULA):** paste the `/fil/terms` text into the custom EULA field (or link it) so it
  matches the paywall + in-app Terms link (`FilLinks.termsOfService`).
- **Subscription:** create the Fil Pro group + monthly/yearly products with the free trial in
  Monetization → Subscriptions.
- **Age rating:** no objectionable content (expected 4+).
- **Price:** Free app with an optional Fil Pro auto-renewing subscription (monthly / yearly, ~2-week
  free trial). Enroll in the **Small Business Program** before the paid tier goes live.
- **Seller name:** shown from the Apple Developer account enrollment. Showing "Rootcause LLC"
  requires an Organization enrollment, not an ASC field.
