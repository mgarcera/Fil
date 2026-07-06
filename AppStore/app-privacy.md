# Fil — App Privacy (App Store Connect answers)

Fil is local-first with no analytics, ads, accounts, or third-party SDKs. Answer the App Privacy
questionnaire as follows.

## Data collection
**"Do you or your third-party partners collect data from this app?" → No.**
Select **"Data Not Collected."** Everything is processed and stored on the device; nothing is sent
to the developer. This is the whole questionnaire once you pick it.

## Tracking (ATT)
**No.** Fil does not track. There is no `NSUserTrackingUsageDescription`, no IDFA, and no ATT
prompt.

## Why this is accurate (keep for your records)
- **On-device speech:** transcription is on-device when supported; on devices without support,
  iOS may use **Apple's** speech recognition service. That processing is Apple's, not developer
  collection, so "Data Not Collected" remains correct. It is disclosed in the Privacy Policy.
- **Link previews:** user-initiated requests to the linked site via Apple's LinkPresentation —
  not collected by the developer.
- **Privacy manifest:** `PrivacyInfo.xcprivacy` is already in the app + widget + share extension
  (`NSPrivacyTracking=false`, empty collected-data types, UserDefaults reasons `CA92.1` + `1C8F.1`).

## ASC checklist
- [ ] App Privacy → Data Types → **Data Not Collected**
- [ ] Tracking → **No**
- [ ] Privacy Policy URL entered (hosted policy → `FilLinks.privacyPolicy`)
- [ ] Support URL entered (hosted support page → `FilLinks.support`)
- [ ] Age rating completed (expected 4+)
- [ ] Export compliance handled by `ITSAppUsesNonExemptEncryption = NO` (already in the build)
