# iCloud / CloudKit Readiness Scope

> **STATUS: SHELVED (2026-07-06).** iCloud sync is **no longer the Fil Pro hero** — the Pro bundle
> is now summaries + all-screensavers + ambience (no CloudKit). This document is preserved as
> reference *if sync is ever revisited as a future v2*. Reasons for shelving: audio recordings
> (loose files) don't sync via SwiftData so voice fils would arrive silent; a prior migration
> attempt cost ~a day and was reverted; highest-risk + fully optional. If revisited: solve audio
> first and do the migration deliberately, not under launch pressure. See `fil-pro-plan.md`.

*Precise, buildable scope for making Fil's SwiftData layer CloudKit-sync-ready. Verified against
Apple's SwiftData "Syncing model data across a person's devices" docs (2026-07-06).*

Execute on the `launch-prep` branch, per-item commits + worklog, same as prior phases. This is a
**schema migration + capability** change; test hard on a seeded store before release.

---

## The CloudKit rules (from Apple docs)

1. **No `.unique` constraints** — CloudKit can't enforce them (`@Attribute(.unique)` and `#Unique`).
2. **All relationships must be optional** — and the `.deny` delete rule is unsupported (`.cascade`
   and `.nullify` are fine).
3. **Every attribute must be optional or have a default value** (NSPersistentCloudKitContainer rule
   SwiftData inherits).
4. **Schema is dev-initialized then promoted to production**, and is **additive-only** after
   promotion (can't delete types or change existing attributes once in production — get it right
   first).
5. **Two capabilities:** iCloud (CloudKit) + Background Modes → Remote notifications.

Fil uses only `.cascade` (✓ allowed) — no `.deny` to fix.

---

## Per-file changes

### `Fil/Models/Note.swift`
- **Remove** `@Attribute(.unique)` from `uuid` → `var uuid: UUID = UUID()`.
- **Add defaults** to the non-optional attributes that lack them:
  `title = ""`, `transcript = ""`, `audioFilePath = ""`, `timestamp: Date = .now`, `duration = 0`,
  `todos: [String] = []`, `completedTodos: [Bool] = []`, `calibrationNotes: [String] = []`,
  `threadedBacklinks: [ThreadedFilBacklink] = []`. (`keyword`, `gradientStartHex`, `gradientEndHex`
  already have defaults; the `Optional`s are fine.)
- Relationships `attachments` / `imageFilImages`: already optional-collection + defaulted + explicit
  inverse + `.cascade` → **no change**.

### `Fil/Models/NoteImage.swift`
- **Remove** `@Attribute(.unique)` from `id` → `var id: UUID = UUID()`.
- `order` → `var order: Int = 0`.
- `@Attribute(.externalStorage) var data: Data` → needs optional-or-default. **Recommend
  `= Data()`** (keeps `Image(data:)` call sites unchanged; externalStorage + default is fine).
  Alternative: make it `Data?` (more correct, but ripples to unwraps).
- `note: Note?` already optional → no change.

### `Fil/Models/KeywordAttachment.swift`
- `keyword` → `var keyword: String = ""`.
- `note: Note?` already optional → no change. `init(keyword:note:)` may keep a non-optional param.
- `entries: [AttachmentEntry] = []` (a Codable blob) is CloudKit-storable as data. **⚠️ Flag:**
  `AttachmentEntry` embeds `imageData` / `pdfData` / `faviconData` **inline**, so a fil with a big
  PDF/image attachment produces one large synced field and can exceed CloudKit's per-record size
  limits → that record fails to sync. **Decision needed** (see Open questions): for sync
  robustness, move attachment binaries into a child `@Model` with `.externalStorage` (becomes
  CKAsset) rather than inline. Can be a follow-up if launch attachments are small, but it's a real
  limitation to acknowledge, not a silent one.

### `Fil/Models/UserProfile.swift`
- `createdAt` → `= .now`, `updatedAt` → `= .now`.

### `Fil/FilApp.swift` (container)
- Switch `ModelConfiguration(schema:url:)` to include `cloudKitDatabase:`:
  - **Pro + sync on:** `.private("iCloud.com.smidgecraft.Fil")` (or `.automatic` to read the
    entitlement's first container).
  - **Free / sync off / in-memory fallback:** `.none` (explicitly local-only).
- **Gating:** build the container from `isPro && syncEnabled` at launch. Changing the toggle at
  runtime means **rebuilding the container** (simplest: takes effect next launch — communicate that
  in the toggle's footnote).
- **Dev schema init:** add a `#if DEBUG` block using `NSPersistentCloudKitContainer
  .initializeCloudKitSchema()` (Apple's documented pattern) to create the dev schema, then
  **promote to Production in the CloudKit Console before release**.
- Keep the graceful recovery from #19; the in-memory fallback path should use `.none`.

### `Fil/Fil.entitlements`
- Add `com.apple.developer.icloud-container-identifiers` → `[iCloud.com.smidgecraft.Fil]`.
- Add `com.apple.developer.icloud-services` → `[CloudKit]`.
- (Keep the existing app group.) Easiest via Xcode's **Signing & Capabilities → iCloud (CloudKit)**,
  which also creates the container + provisioning; hand-editing the plist skips provisioning setup.

### `Fil/Info.plist`
- Add `UIBackgroundModes` → `[remote-notification]` (Background Modes → Remote notifications).

### Extensions — no change
The SwiftData store lives in App Support (app-only), and the widget/share extension use **files**
in the app group, not the store — so CloudKit entitlements go on the **main app only**. (Don't move
the store into the app group without revisiting this.)

---

## Migration

- These are schema changes on the existing v1 store → introduce a **`VersionedSchema`**
  (`SchemaV1` = current, `SchemaV2` = CloudKit-ready) + a **`SchemaMigrationPlan`**. Adding defaults
  is lightweight; **removing the `.unique` constraints** is the part to test carefully.
- **Replace the DB-level uniqueness** (we relied on it; `FilApp.shouldResetStore` even handles
  `ZNOTE.ZUUID` collisions) with **app-level guarantees**: creation already assigns fresh UUIDs, so
  add a lightweight dedup guard on insert/merge and drop the collision-reset special-case.
- Test path: seed a store with the current schema → migrate → verify no data loss, then enable sync.

---

## Testing plan

1. **Migration:** seeded v1 store → v2 migrates with zero data loss.
2. **Two-device sync:** create on device A → appears on B (and edits/deletes propagate).
3. **Offline:** create offline → syncs on reconnect.
4. **Pro transition:** free (local, `.none`) → Pro+sync (`.private`) uploads existing local fils
   cleanly; toggling sync off returns to local without loss.
5. **Large attachment:** a fil with a big PDF/image attachment — confirm it syncs or is handled
   gracefully (informs the KeywordAttachment decision).
6. **Schema promoted to Production** in the CloudKit Console before shipping.

---

## Suggested commit sequence (all before wiring the paywall)
1. `SchemaV2` models: remove `.unique`, add defaults, verify relationships (per-file above).
2. `VersionedSchema` + `SchemaMigrationPlan`; drop the ZUUID reset special-case + add dedup guard.
3. Entitlements + Info.plist capabilities.
4. Container: `cloudKitDatabase` gating + DEBUG schema-init.
5. (Then, in the Pro build proper: StoreKit `isPro`, paywall, sync toggle — see fil-pro-plan.)

## Open questions / decisions
- **Attachment binaries** (KeywordAttachment): move to a child `.externalStorage` model now, or ship
  Pro with an "attachments over N MB don't sync" known-limitation and remodel later?
- **Sync scope of media:** audio files + externalStorage image/favicon data — externalStorage syncs
  as CKAsset; confirm audio (stored as loose files in Documents, referenced by `audioFilePath`) is
  **not** covered by SwiftData sync — **audio recordings won't sync** unless moved into the model as
  `.externalStorage` Data or synced separately. **Important:** this means a synced voice fil could
  arrive on device B with a transcript but no playable audio. Decide: move audio into the model
  (heavier records) vs. accept "audio stays local, text syncs" for v1.
- **Container id:** confirm `iCloud.com.smidgecraft.Fil`.
- **Sync default:** on-by-default toggle (recommended) vs auto-on for Pro.
