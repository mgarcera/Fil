# Perzine — the successor to Fil

Decided 2026-10-02. Fil becomes archival; the paged-covers / message-thread / briefing design that
grew in Fil's debug sandbox ships as a new app called **Perzine**, built in a **new Xcode project
and a new repo**, with a **new App Store Connect record**.

A *perzine* is the personal zine: one person's own writing, assembled and circulated. The name was
chosen over **Knit** later the same day, after the search below.

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
| **Name** | App Store name `Perzine`. Subtitle deferred to submission, since it is editable between versions and the name is not. |
| **Targets in v1** | The app and a **share extension**. No widget in the first submission. Two identifiers, two builds to keep version-matched. |
| **What crosses from Fil** | The sandbox (covers, nest, bubbles, briefing) plus the capture paths it already uses: text, photo, voice, to-dos, filaments. **Not** the canvas home, article view, folder browser, search or surfacing. |
| **Fil's removal from sale** | When Knit ships, not before. The live listing stays available as a reference while Knit's is written. |
| **Repo** | New repo under `~/Documents/GitHub/mgarcera/`, so the `mgarcera` account, per the account-follows-folder rule. |
| **Cloudflare** | A new worker and secret for Knit rather than Fil's. Lets Fil's be retired on its own schedule. |

## The name

**Perzine is unclaimed and, more usefully, uncontested.** A US App Store search for "perzine"
returns three results, none named Perzine and none related: fuzzy matches on "permis" and "perk".
Nobody is competing for the word. The nearest neighbour in the category is `Zine - Enjoy Writing`
in Productivity, a different string and a different word.

**It names what is already on the screen.** The cover page is an editorial magazine cover: display
type in Fraunces Black, a photograph behind it, a drawn outline on the letters. That design was
arrived at visually before any name existed, and the name now describes it.

**Knit was the alternative and lost on search.** No app is named exactly `Knit`, so it was probably
available, but thirteen of the top fourteen results for "knit" are knitting apps and yarn puzzle
games, including `KNIT – Knitting journal`. A notes app does not win that word. Knit also described
nothing visible in the product, so the subtitle would have carried the whole explanation.

Both availability checks are indicative, not authoritative: names are held for unreleased records
and by removed apps, and only App Store Connect answers.

**The tension to keep in view.** A perzine is made to be circulated. Printing it and handing it to
someone is the form's whole point, and the app as designed shares nothing, so the name promises an
act the product does not perform. The structure is most of the way to making it honest: a folder is
a cover with a title and a summary followed by pages, which is a publication, and Fil already
exports a `.filbox`. Exporting a folder as a small publication is the feature that would settle it.
Not v1, and the name is a reason to keep it on the list.

## Order of operations, because two steps are one-way doors

1. **Check the name in App Store Connect first.** It is claimed at record creation and must be
   unique across the whole store. A refusal here changes everything below it.
2. **SKU** is set at record creation and can never be edited. Match the convention the account's
   other apps use.
3. **Bundle identifier** is frozen at the first build upload, not at record creation, so it only
   has to be right before the first archive.
4. Everything else (listing, screenshots, privacy answers, age rating) is editable later.
