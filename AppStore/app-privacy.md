# Fil — App Privacy (App Store Connect answers)

Fil is local-first with no analytics, ads, accounts, or third-party tracking SDKs. **One paid,
opt-in feature (Fil Pro surfacing) transmits user content off-device**, so the questionnaire is no
longer "Data Not Collected." Answer as follows.

## Data collection
**"Do you or your third-party partners collect data from this app?" → Yes.**
Declare exactly one data type:

- **User Content → "Other User Content"** — your fils' text, sent to our AI provider (Anthropic)
  to answer a surfacing query.
  - **Used for:** App Functionality (only).
  - **Linked to the user's identity?** **No.** Fil has no account; nothing identifying is attached.
  - **Used for tracking?** **No.**

Do **not** declare any other type. Creating, storing, and keyword-searching fils are entirely
on-device and collect nothing; the free tier never transmits content.

## Tracking (ATT)
**No.** Fil does not track. No `NSUserTrackingUsageDescription`, no IDFA, no ATT prompt.

## Why this is accurate (keep for your records)
- **Fil Pro surfacing:** when a subscriber asks a question in their own words, their fils' text
  is sent to Anthropic, which produces a reflection + picks the matching fils. Apple treats transmitting user
  content off-device as "collected," so it must be declared — as App Functionality, not linked, not
  tracking. Under Anthropic's commercial terms it is not used to train models and is deleted within
  ~30 days. Disclosed in the Privacy Policy and in an in-app note before first use.
- **Subscription check:** Fil sends the StoreKit transaction id to its proxy to verify Fil Pro with
  Apple. This is Apple's own receipt mechanism used solely for app functionality, not stored by us
  and not linked to identity; it does not add a separate declared data type. (If App Review ever
  pushes back, the fallback is to also declare "Purchases → App Functionality, not linked.")
- **On-device speech:** transcription is on-device when supported; otherwise iOS may use Apple's
  speech service — Apple's processing, not developer collection.
- **Link previews:** user-initiated requests to the linked site via Apple's LinkPresentation — not
  collected by the developer.
- **Privacy manifest:** `PrivacyInfo.xcprivacy` (app target) now lists the "Other User Content" data
  type (App Functionality, not linked, not tracking) to match this. Widget + share extension collect
  nothing and keep empty collected-data types.

## ASC checklist
- [ ] App Privacy → Data Types → **User Content › Other User Content** → App Functionality, **not**
      linked to identity, **not** used for tracking.
- [ ] Tracking → **No**
- [ ] Privacy Policy URL entered (hosted policy → `FilLinks.privacyPolicy`) — reflects the cloud
      surfacing disclosure
- [ ] Support URL entered (hosted support page → `FilLinks.support`)
- [ ] Age rating completed (expected 4+)
- [ ] Export compliance handled by `ITSAppUsesNonExemptEncryption = NO` (already in the build)
