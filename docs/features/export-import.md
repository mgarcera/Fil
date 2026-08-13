# Export & Import — spec

*Drafted 2026-08-13. Status: SPEC / not built. Free tier — never gate this.*

## Why this exists

Fil is device-local. That's fine until one of these happens:

| Situation | Today | With export |
|---|---|---|
| New phone, via Quick Start or an iCloud Backup restore | ✅ everything transfers | unchanged |
| New phone, backups off or full | ❌ everything gone | ✅ restore from a file |
| Delete the app and reinstall | ❌ everything gone (backups restore devices, not apps) | ✅ restore from a file |
| Phone lost or broken, no backup | ❌ everything gone | ✅ if the file lives elsewhere |
| "Is this really mine?" | no answer | ✅ here it is, as a file |

It also makes a marketing claim honest: the site says a Fil canvas becomes *"a landscape of distinct
things you made"* after six months. A six-month promise needs a way to carry six months of stuff.

---

## The one non-negotiable: identity has to travel

`blobShapeSeed` is an FNV-1a hash of `uuid.uuidString` (`NoteCardView.swift:203`). The gradient is
stored on the fil (`gradientStartHex` / `gradientEndHex`). So a fil's face is a pure function of
**uuid + two hex strings**.

> **The importer must never regenerate `uuid`.** A naive importer mints fresh IDs to avoid
> conflicts — and every thought comes back wearing a different face, which breaks the one promise
> the whole product rests on. Preserve `uuid` and the hexes and the blob returns bit-identical.

Conveniently, this is the same rule that makes merge-on-import safe. Identity and dedupe are one
requirement.

---

## What's actually in a fil

Two storage classes, and the exporter has to walk **both**. This is the part CloudKit can't do.

### A. Inline `Data` in SwiftData
| Field | On |
|---|---|
| `imageData` (`.externalStorage`) | Note |
| `sourceFaviconData` (`.externalStorage`) | Note |
| `data` (`.externalStorage`) | NoteImage |
| `imageData`, `pdfData`, `faviconData` | AttachmentEntry |

### B. Loose files in the documents directory, referenced by name
| Reference | Kind | Notes |
|---|---|---|
| `Note.audioFilePath` | voice recording | written by `VoiceRecorderViewModel` |
| `AttachmentEntry.text` where `kind == .video` | video | `text` *is* the filename |
| `AttachmentEntry.text` where `kind == .file` | any file | `text` = filename, `fileName` = display name |

**Both classes must be exported and both must be re-pointed on import** — a documents-dir path is
not stable across installs, so paths get rewritten to the new location as part of import.

### Field inventory

**Note** — `uuid`, `title`, `transcript`, `audioFilePath`, `timestamp`, `duration`, `todos`,
`completedTodos`, `todoIDs`, `calibrationNotes`, `keyword`, `gradientStartHex`, `gradientEndHex`,
`originalTitle`, `originalTranscript`, `threadedBacklinks`, `sortIndex`, `sourceURLString`,
`sourceTitle`, `sourceDescription`, `sourceFaviconData`, `imageData`, plus relationships to
`folder`, `attachments`, `imageFilImages`.

**Folder** — `id`, `name`, `summary`, `gradientStartHex`, `gradientEndHex`, `createdAt`,
`sortIndex`, `summarySignature`, `summaryParts`.

**KeywordAttachment** — `keyword`, `entries: [AttachmentEntry]`, `note`.
**AttachmentEntry** — `id`, `kind` (`image`/`recording`/`link`/`textNote`/`linkedNote`/`pdf`/
`video`/`file`), `imageData`, `text`, `linkedNoteID`, `faviconData`, `pdfData`, `pdfName`,
`noteTitle`, `linkCaption`, `fileName`.

**NoteImage** — `id`, `order`, `data`.

### Cross-references that must survive
- `Note.folder` → folder `id`
- `AttachmentEntry.linkedNoteID` → another fil's `uuid` (as a string)
- `ThreadedFilBacklink.parentNoteID` + `parentKeyword` → another fil
- `Note.todoIDs` → stable to-do identity

All of these are ID-based, so **they survive automatically if uuids are preserved** — and break
completely if they aren't. Same rule as above.

### Deliberately not exported
- **Fil Pro entitlement** — owned by StoreKit; restoring a backup must never grant Pro.
- **`UserProfile`** — vestigial since the onboarding rework.
- **App settings / `@AppStorage`** — arguably nice-to-have; out of scope for v1 (see Open decisions).
- **Pinned-folder and Bin snapshots** — derived state, rebuilt on next launch.

---

## Format

A zip with a custom extension so tapping it opens Fil:

```
fil-2026-08-13.filbox
├── manifest.json      schemaVersion, appVersion, exportedAt, counts, mediaBytes
├── fils.json          every Note, with folder id + attachment/image references
├── folders.json       every Folder
├── media/
│   ├── <note-uuid>.m4a
│   ├── <noteimage-id>.jpg
│   ├── <entry-id>.pdf
│   └── <entry-id>-<original-name>
└── readable/
    └── <folder>/<title>.md
```

**Two layers, two jobs.** `fils.json` + `media/` is *insurance* — exact fidelity, re-importable,
faces intact. `readable/` is *ownership* — plain Markdown anyone can open in ten years without Fil
existing. You're already walking every record; the second layer is nearly free.

Register a UTI for `.filbox` (a `public.zip-archive` conformer) so Files → tap → Fil → import.
Without it, import is a menu nobody finds.

---

## Flows

### Export
1. Settings → About → **export backup**.
2. Walk all Folders and Notes; serialise to JSON; copy both media classes into `media/`; render
   `readable/`.
3. Zip to a temp directory, hand to the system share sheet (`.fileExporter` / `ShareLink`).
4. Progress UI — large libraries take real time; show counts, allow cancel.

### Import
1. Open a `.filbox` (share sheet, Files, or Settings → **import a backup**).
2. Read `manifest.json`; refuse politely on an unknown future `schemaVersion`.
3. **Merge by `uuid`** — never replace, never regenerate IDs:
   - fil not present → insert with all fields, media rewritten to the new documents dir
   - fil already present → skip by default (leave the live copy alone)
   - folder not present → insert; already present (by `id`) → reuse, don't duplicate
4. Report plainly: *"added 47 fils and 3 folders. 210 were already here."*

Merge-not-replace means importing an old backup into a live library is safe and idempotent —
importing the same file twice does nothing the second time.

---

## Where it lives in the app

Settings → **About**, at the very bottom, beneath the existing links (from mason · privacy ·
terms · contact · rate fil). It's not a feature people browse for; it's a thing they look for at a
specific anxious moment, and About is where you look when you're asking "is my stuff safe."

Lead with the problem, not the mechanism:

> **your fils**
>
> getting a new phone, or just want a copy you keep yourself? export everything — fils, folders,
> photos, recordings, files — as a single backup file you can store anywhere.
>
> **[ export backup ]**
>
> to bring it back, open the file on any iphone with fil installed, or use import below. importing
> adds what's missing and leaves what's already here alone.
>
> **[ import a backup ]**

---

## Edge cases

| Case | Behaviour |
|---|---|
| Media file missing on export (referenced but deleted) | Export the record, note it in `manifest.json` under `missingMedia`, don't fail the run |
| Media missing on import | Import the fil without it, keep everything else — a silent partial beats a failed import |
| Version skew — older Fil opens a newer `.filbox` | Refuse with a plain message naming the app version needed. Never partially import an unknown schema |
| Version skew — newer Fil opens an older `.filbox` | Supported. Migrate on read; missing newer fields take their defaults |
| Huge library | Stream to disk, never build the archive in memory; show progress; expect hundreds of MB for a couple of years of voice and photos |
| Recording in flight during export | Exclude the in-progress file; it isn't a fil yet |
| `linkedNote` entry whose target isn't in the archive | Import the entry; it resolves if the target arrives later, since both are uuid-keyed |
| Two devices, both edited | Out of scope. Merge is additive; it is not sync and must not be described as sync |
| Duplicate uuid, different content | Skip by default. A "keep both" option would need a new uuid — and a new face — so it's a real product decision, not a default |

---

## Export vs CloudKit sync

They solve different problems and cost wildly different amounts. This is why export goes first.

| | Export / import | CloudKit sync |
|---|---|---|
| Multi-device, live | ❌ | ✅ |
| Survives reinstall | ✅ | ✅ |
| Survives lost phone | ✅ if stored off-device | ✅ |
| User does anything | yes — presses a button | no |
| **Schema changes required** | **none** | `@Attribute(.unique)` must be **removed** from `Note.uuid`, `Folder.id`, `NoteImage.id`; all non-optional properties need defaults; every relationship needs an inverse |
| Loose files (audio, video, attached files) | ✅ carried explicitly | ❌ **do not sync via SwiftData** — a synced voice fil arrives silent |
| Inline attachment blobs | ✅ no size ceiling | ⚠️ `AttachmentEntry` binaries live inline in a Codable array and can exceed CloudKit record limits |
| Migration risk on a shipped app | none — read-only walk | high; a prior attempt cost a day and was reverted |
| Ongoing cost | none | user's iCloud quota, plus support burden |

**The decisive line:** export requires *zero* changes to the model. CloudKit requires dropping the
uniqueness constraints that the importer's whole merge strategy depends on — on an app that has
already shipped. That's why sync was shelved in July and why it stays shelved.

If sync is ever revisited, the loose-file problem must be solved first (move audio/video/files into
SwiftData as `.externalStorage` Data, or into a CloudKit assets container) — not the other way round.

---

## Out of scope for v1

- Automatic scheduled backups. **Strong follow-up** — a weekly `.filbox` written to iCloud Drive is
  most of the value of sync for a fraction of the work, and it converts export from a feature people
  forget into actual insurance. Ship manual first, learn real library sizes, then automate.
- Selective export (one folder, a date range).
- Cross-platform import (there is no other platform).
- Encryption/password on the archive — the file inherits wherever the user stores it.

## Open decisions

1. **Include app settings** (appearance, lowercase, sound, screensaver choice)? Cheap, slightly
   surprising on restore. Leaning yes, in a `settings.json` the importer applies only on an explicit
   "restore settings too" toggle.
2. **`.filbox` or plain `.zip`?** Custom extension enables tap-to-import via a registered UTI; plain
   zip is more obviously openable elsewhere. Leaning `.filbox`, since `readable/` already covers the
   "open it anywhere" need.
3. **Skip vs "keep both" on uuid collision.** Default skip; "keep both" needs a new uuid and
   therefore a new face, which is a product decision.
4. **Where does the readable layer put voice fils?** Transcript as Markdown with the audio filename
   referenced alongside — or omit them from `readable/` entirely.
