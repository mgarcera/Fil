<!--
STAGED — rewritten 2026-08-13 against the new positioning. NOT ready to paste into ASC.

Pending, all marked inline:
1. Entity resolved 2026-08-18: ASC copyright `Mason Garcera`; legal pages `Mason Garcera d/b/a Smidgecraft`.
2. URLs are written as smidgecraft.com, but the live pages are still served from rootcause.ltd.
   They switch together during the migration sweep — see docs/entity-migration.md.
3. The subscription ships. Pricing settled 2026-08-17 at $2.99/mo + $24.99/yr; the CONDITIONAL
   markers are gone. ASC products must use com.smidgecraft.Fil.extra.monthly / .annual.
4. Bundle ID and App Store ID both change when Fil is recreated under the new individual account.

Superseded from the July version: the name and subtitle (privacy/voice-led → surfaces-led), the
"no folders" claim (folders shipped), and the claim that Apple's on-device intelligence writes
titles (it doesn't — titles are the first line of the user's own text).
-->

# Fil — App Store Listing Metadata

*Copy these into App Store Connect. Character counts are noted; Apple's limits in parentheses.
Verify counts in ASC (it's the source of truth).*

- **App name** (30): `Fil: Folders Outside the App` — 28 chars. Colon, not an em dash: the dash
  renders cramped at App Store card sizes, and the colon reads as a label rather than an aside.
- **Subtitle** (30): `Lock screen & dynamic island` — 28 chars
- **Primary category:** Lifestyle   ·   **Secondary category:** Utilities
- **Bundle ID:** `com.smidgecraft.Fil` — registered fresh on the new individual account, 2026-08-17.
  The old `com.masongarcera.Fil` is abandoned with the lapsing org account rather than transferred:
  deleting an ASC record does not release its identifier, so reuse would have meant waiting on the
  lapse. Extensions follow the namespace (`.FilPinnedWidget`, `.FilShareExtension`), as does the app
  group `group.com.smidgecraft.Fil`. App Groups is the only capability any target needs.

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
Pin what you're in the middle of to your Lock Screen, Dynamic Island, Home Screen, and more. See the shape of your thoughts at a glance without unlocking your screen.
```

## Description
```
Pin the thing you're in the middle of (the trip, the move, the dinner you're planning) and it lives on your Lock Screen, in your Dynamic Island, on your Home Screen, and more. Glance and it's there. Open Fil when you want to dig in.

Five places that aren't the app:

- Lock Screen Live Activity: Your pinned folder at a glance.
- Lock Screen Accessory: Your pinned folder, always on.
- Dynamic Island: Tap it and you're straight into what you're working in.
- Home Screen: A widget that changes depending on what you've pinned.
- Today View: The same widget, one swipe away.

And open the app in four ways, without touching the actual icon:

- Control Center: Start a voice thought or a written one from anywhere.
- Share Sheet: Send a paragraph, a link, or a photo from any app straight into Fil.
- Action Button: One press and you're recording.
- Siri: Say "New thought in Fil" and it takes what you say next.

No two thoughts look alike. Every thought arrives with its own color, its own shape, its own gradient. You don't pick it and you can't change it; it's given, the way the thought was. You don't read your folder, you recognize it.

It gets even better when you go in. A voice thought reads like a music player. Photos become a carousel. Links and to-dos each get their own function. Every action has its own sound and its own feel. Slow drifting gradients and an ambient screensaver. Fil is an app you can leave closed or open.

What you can do:

- Speak or type a thought, and your voice becomes a note transcribed on your device.
- Add a photo, save a link, write a note with to-dos.
- Attach a filament (more info) to any word: a note, a link, a photo, a PDF, or another thought.
- File what you want into folders. Pin the one you're living in.
- As many thoughts, folders, and filaments as you like. There is no limit on any of them.

Fil Extra adds:

- Smart search: Ask in your own words and Fil goes by what you meant rather than by matching words, then tells you what it found.

- File for me: Hand it a pile of loose thoughts and it proposes which of your folders each one belongs in, and you can change any of it before a single one moves. It also organizes a whole library into folders and can write a folder's caption from what's inside it.

- Screensavers: The rest of the ambient screensavers open up, each one made out of your own thoughts.

- App icons: A set of alternate icons, the same word rendered in different materials, with more arriving over time.

No account, no ads, no tracking. Your thoughts stay on your phone. Fil Extra is the one thing that leaves to AI, and only when you ask. That text is never used to train the model and is deleted within 30 days.

(Fil Extra is an optional auto-renewing subscription, monthly or yearly, and it starts with a free trial. Payment is charged to your Apple Account and renews unless canceled at least 24 hours before the period ends. Manage it in iOS Settings.)

Terms: https://smidgecraft.com/fil/terms
Privacy: https://smidgecraft.com/fil/privacy

Questions, ideas, or feedback? mason@smidgecraft.com
```

## What's New (version 1.0)
```
the first Fil. pin what you're working on to your lock screen, dynamic island, or home screen, and
glance at it without unlocking. every thought arrives with its own color and shape, so you know it
on sight. send anything in from any app. no account, no ads. tell me what to build next:
mason@smidgecraft.com
```

## Also set in App Store Connect
- **Legal entity / copyright:** `Mason Garcera`. Set the app's copyright to `© 2026 Mason Garcera`.
  The legal pages name `Mason Garcera d/b/a Smidgecraft` — the same legal party, since a DBA is a trade name
  rather than a separate entity, so the two lines do not conflict.
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
- **Subscription:** create the Fil Extra group plus monthly/yearly products with the
  free trial in Monetization → Subscriptions, and add a review screenshot for each. Skip entirely if
  v1 ships without a paywall.
- **Price:** free app with an optional Fil Extra auto-renewing subscription at $2.99/mo or
  $24.99/yr. Create the products with the IDs `com.smidgecraft.Fil.extra.monthly` and
  `.annual` — they must match `StoreManager.ProductID` exactly, and are immutable once created.

## App Review Information

- **Sign-in required:** No. Fil has no accounts. Nothing is gated behind a login.
- **Contact:** Mason Garcera · mason@smidgecraft.com · (phone as entered in ASC)
- **Demo account:** none needed.

### Notes — paste verbatim

```
No account is required. Open the app and start writing; everything works immediately.

TESTING FIL EXTRA
Smart search and "File for me" are the two features behind the Fil Extra subscription. Both are
reachable from the main screen: the search field for smart search, and the folder browser's
"File for me" button for filing. The subscription starts with a two-week free trial, so a sandbox
account can enable both without a charge. Without Extra those two features show the paywall — that
is intended, not a defect.

WHAT LEAVES THE DEVICE
Fil is local-first. Creating, storing and keyword-searching thoughts happen entirely on device and
transmit nothing. Smart search is the only feature that sends content off device: when a subscriber
asks a question in their own words, the text of their thoughts is sent to our proxy and on to
Anthropic to produce the answer. This is disclosed in the privacy policy and in an in-app note
before first use, and it is declared in App Privacy as User Content, used for App Functionality,
not linked to identity, not used for tracking.

EXPECTED BEHAVIOUR THAT MIGHT LOOK LIKE A BUG
After you create your first thought, a short welcome thought signed "from mason" appears, inside
a folder called "From Mason". It is seeded intentionally on first run, not leftover test data.
Tapping the highlighted words in it opens attached notes; that is the app's filament feature
demonstrating itself.

Alternate app icons are part of Fil Extra. iOS shows its own confirmation alert when an icon
changes; that alert is the system's and cannot be suppressed.
```

