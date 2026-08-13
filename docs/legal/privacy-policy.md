<!--
STAGED — revised 2026-08-13, NOT publishable as-is.

Three things must resolve before this goes live, all marked inline:

1. {{ENTITY}} — the contracting party. Rootcause LLC is being dissolved. Replace with either
   Mason Garcera personally, or the Illinois DBA if it lands and Apple accepts it. The same
   name must appear in the terms and in the App Store copyright line.
2. {{DATE}} — the publication date.
3. The "Smart search" and "Subscriptions" sections assume Fil Pro ships as an Anthropic-backed
   subscription. Both are on hold pending the Private Cloud Compute test. If Fil ships without a
   paywall, the Subscriptions section is deleted and smart search stops being described as paid.
   If Fil ships on Apple's Private Cloud Compute instead of Anthropic, the processor, the
   retention wording, and the training claim all change — Apple's terms, not Anthropic's.

Live copy is served from src/app/fil/privacy/page.tsx in the website repo; update both together
during the migration sweep. See docs/entity-migration.md.
-->

# Fil Privacy Policy

*Last updated: {{DATE}}*

Fil is built to keep your thoughts yours. It is a **local-first** app: your fils (voice
recordings, transcripts, text, images, links, and titles) live on your device, not on our
servers. {{ENTITY}} (the maker of Fil) does not run a server that collects your content,
and Fil has no account to sign into.

There is one optional exception, and we want to be upfront about it: **smart search**, which sends
your fils' text to an AI provider that finds and reflects the ones relevant to a question you ask.
It only runs when you choose to use it. Details are in "Smart search" below.

## The short version
- We don't collect, sell, or share your personal data.
- Your fils are created, stored, and searched by keyword entirely on your device.
- The **only** time anything leaves your device is when you run a **smart search**. That sends your
  fils' text to our AI provider (Anthropic), which picks and reflects the ones relevant to your
  question. It is **not used to train AI models** and is **deleted within 30 days**.
- No ads, no analytics SDKs, no third-party trackers, no login.

## What Fil stores, and where
Everything you create in Fil is stored **locally on your device** using Apple's on-device
storage. A small amount is shared between Fil and its own widgets, Lock Screen surfaces, and Share
extension through a private App Group container **on your device**. None of it is transmitted to us.
The one exception is smart search, described below.

## Smart search (cloud AI)
Creating fils, storing them, and searching them by keyword all happen entirely on your device and
never leave it. **Smart search** is optional: when you ask Fil a question in your own words (for
example, "what am I forgetting?"), the text of your fils is sent securely to our AI provider,
**Anthropic**, which picks the ones relevant to your request and returns a short reflection.

- This happens **only** when you run a smart search. If you never do, nothing leaves your device.
- The text is used **only to answer your request**. Under Anthropic's commercial terms, it is **not
  used to train any AI models**, and Anthropic **deletes it within 30 days**.
- No name or account is attached; Fil has no account.
- **Keyword search never uses the cloud** and never leaves your device.

## Subscriptions
<!-- CONDITIONAL: delete this section entirely if v1 ships without a paywall. -->
Fil Pro is an auto-renewing subscription sold through Apple's App Store. Apple handles the payment;
we never see your payment details. To verify that smart search is available to you, Fil confirms your
subscription status with Apple. Manage or cancel anytime in **iOS Settings › Apple Account ›
Subscriptions**.

## Permissions Fil asks for, and why
- **Microphone**: to record voice notes. Recording only happens when you start it.
- **Speech Recognition**: to turn recordings into text. Fil requests **on-device** transcription
  whenever your device supports it, so your audio stays on the device. On devices that don't
  support on-device speech recognition, iOS may send the audio to **Apple's** speech recognition
  service to produce the transcript; that is handled by Apple under Apple's Privacy Policy, and
  Fil does not receive or store that audio anywhere else.
- **Camera**: only if you choose to add a photo to a fil.

You can change these any time in **iOS Settings › Fil**.

## How fils get their titles
A fil's title is simply the first line of what you wrote or said — taken from your own text, on your
device. No AI writes it, and nothing is sent anywhere to produce it.

## Link previews
If you save or share a link into Fil, the app fetches that page's icon and title to show a
preview (via Apple's LinkPresentation). That request goes to the website you linked (the same as
opening the link), and the preview is stored on your device.

## What we don't do
- No analytics, no advertising, no tracking across apps or websites.
- No IDFA, no third-party SDKs.
- We don't build a profile of you.

## Children
Fil is not directed at children under 13 and does not knowingly collect information from them.

## Your control
Your data lives on your device, so you're in control: delete a fil in the app, or delete Fil to
remove its data from your device. If you back up your device to iCloud or a computer, your Fil
data is included under Apple's terms.

## Changes
If this policy changes, we'll update this page and the date above.

## Contact
Questions? Email **mason@smidgecraft.com**.
