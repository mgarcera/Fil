# Knit — the successor to Fil

Decided 2026-10-02. Fil becomes archival; the paged-covers / message-thread / briefing design that
grew in Fil's debug sandbox ships as a new app called **Knit**, built in a **new Xcode project and
a new repo**, with a **new App Store Connect record**.

Design decisions for the cover briefing live in `docs/features/cover-briefing.md`.

## Why a new project rather than renaming Fil

**The bundle identifier freezes once a build is uploaded against it, and builds have been.** The
App Store display name can change between versions; `com.smidgecraft.Fil` cannot. Renaming in place
would ship Knit on `com.smidgecraft.Fil`, `group.com.smidgecraft.Fil` and two extension identifiers
carrying the old name, permanently. That identifier is the one thing an in-place rename preserves,
and it is the thing Mason wanted gone.

**A new record is cheap here because the capability surface is almost nothing.** All three Fil
targets share a single entitlement: one App Group, `group.com.smidgecraft.Fil`. No iCloud
container, no push, no managed entitlement, nothing Apple has to grant. Registering identifiers for
a new app is minutes of work.

**Nothing expensive is lost.** A subscription group cannot move between apps, and none is live.
Ratings and reviews cannot move, and Fil has none that matter. The SKU, age rating, privacy
answers, screenshots and listing copy would all be written fresh for a renamed app anyway.

**The leak an in-place rename produces, by example.** Three permission strings in Fil's project
hardcode the word Fil, including the microphone and speech-recognition descriptions App Review
reads. `Fil/Views/MicPrimingSheet.swift` already reads the name from `CFBundleDisplayName` instead;
that is the pattern the new project follows everywhere.

## Decisions (2026-10-02)

| | |
|---|---|
| **Name** | App Store name `Knit`, subtitle `Notes that reply`. Two separately indexed fields rather than one; the subtitle is editable between versions without touching the name. |
| **Targets in v1** | The app and a **share extension**. No widget in the first submission. Two identifiers, two builds to keep version-matched. |
| **What crosses from Fil** | The sandbox (covers, nest, bubbles, briefing) plus the capture paths it already uses: text, photo, voice, to-dos, filaments. **Not** the canvas home, article view, folder browser, search or surfacing. |
| **Fil's removal from sale** | When Knit ships, not before. The live listing stays available as a reference while Knit's is written. |
| **Repo** | New repo under `~/Documents/GitHub/mgarcera/`, so the `mgarcera` account, per the account-follows-folder rule. |
| **Cloudflare** | A new worker and secret for Knit rather than Fil's. Lets Fil's be retired on its own schedule. |

## The name, with the thing that is wrong with it

No app named exactly `Knit` appears in a US App Store search, so the name is **probably** available.
That check is indicative and not authoritative: only App Store Connect can answer, names are held
for unreleased records and by removed apps, and the answer is given at record creation.

What the search does settle is that **the word belongs to yarn**. Of the top 14 results for "knit",
thirteen are knitting apps or yarn puzzle games, including one called `KNIT – Knitting journal` in
Lifestyle. A notes app will not win the search term "knit" and should not try. The name has to work
as a brand that people arrive at already knowing, with the subtitle carrying the words anyone would
actually search. That is a legitimate position; it is just not a discovery strategy.

## Order of operations, because two steps are one-way doors

1. **Check the name in App Store Connect first.** It is claimed at record creation and must be
   unique across the whole store. A refusal here changes everything below it.
2. **SKU** is set at record creation and can never be edited. Match the convention the account's
   other apps use.
3. **Bundle identifier** is frozen at the first build upload, not at record creation, so it only
   has to be right before the first archive.
4. Everything else (listing, screenshots, privacy answers, age rating) is editable later.
