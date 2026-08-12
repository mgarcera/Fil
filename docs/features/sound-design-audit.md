# Sound-design audit (2026-08-11)

Inventory of Fil's sounds, where they play, the gaps, and a shopping list. Master mute =
`soundEnabled` AppStorage, gated in `SoundscapeManager`. Audio assets: `Fil/Fil/Resources/Audio/`.

## Existing (16 files; 9 active, 7 dead)
Active → method → trigger:
- `click.mp3` → `playOpenFilClick()` → open Bin/folder deep link, open fil in reader (ContentView, ArticleView).
- `settings.mp3` → `playSettingsSound()` → open Settings.
- `transformrefil.mp3` → `playTransformRefilSound()` → launch screensaver / koi pond.
- `tabsound.mp3` → `playTabSound()` → Settings tabs, Lock-Screen option, transcript-edit toggle, folder pin.
- `grid.mp3` → `playGridSound()` → open keyword/filament sheet.
- `landfil.mp3` → `playLandfilSound()` → delete fil (home, article), delete attachment.
- `articlemade.mp3` → `playArticleMadeSound()` → fil created (text/voice/photo), deep-link/shared save.
- `meshduringprocess.mp3` → `start/stopMeshDuringProcessSound()` → looping during creation.
- `todoarticletoggle.mp3` → `playTodoArticleToggleSound()` → add/remove/toggle to-do (article, home, folder).

## Dead (candidates to delete or wire up)
- **Orphaned assets (no method):** `addparagraph.mp3`, `addparagraphrefil.mp3` → delete.
- **Loaded but method never called:** `taptowrite.mp3`, `todosound.mp3`, `lightmode.mp3`, `collapsing.mp3`, `collapsingparttwo.mp3`.
- **Dead methods:** `playTapToWriteSound`, `playTodoSound`, `playLightModeSound`, `playCollapsingSound`, `playCollapsePartTwoSound`.

## Quick wins — reuse assets we already have (no sourcing needed)
SHIPPED 2026-08-11 (1–4 + folder-open):
1. ✅ **Dark-mode toggle** → `playLightModeSound()` (`SettingsView`, `.onChange(of: isDarkMode)`).
2. ✅ **Dock Bin↔Selected switch** → `playTabSound()` (`DockChipsRow.segment`, only on an actual change).
3. ✅ **Folder created** → `playArticleMadeSound()` (`FilFolderBrowser.createFolderFromPrompt`).
4. ✅ **Bulk landfil confirm** → `playLandfilSound()` (`DockChipsRow` alert confirm).
5. ◐ **Folder OPEN** → `playCollapsingSound()` (`FilFolderBrowser.openFolder`). **Folder CLOSE still TODO** — no clean single hook yet; `collapsingparttwo.mp3` still unused, reserve for it.

Still parked (optional / needs a hook):
6. **Composer + expand** → reuse `taptowrite.mp3`, or stay silent.
7. **Promote phrase → to-do** (player) → `playTodoArticleToggleSound()`.
8. **Orphaned assets** `addparagraph.mp3` / `addparagraphrefil.mp3` — safe to delete (no method); left for a later cleanup.

## Gaps grouped (consequential, currently silent)
- **Selection:** select/deselect a fil (haptic only) — soft tick (reuse `tabsound`?).
- **Dock chips:** Move, Copy, bulk Landfil (Move/Copy silent; Landfil needs the confirm sound).
- **Search:** enter search, submit query, results arrive (all silent).
- **Navigation:** advance between fils in the player, folder switch (header), reorder.
- **Voice capture:** recording start / stop (no cue at all).
- **Move/file/drop:** moving fils to a folder (haptic only).

## SHOPPING LIST — new sounds to source
| Role | Where | Note |
|---|---|---|
| **Move whoosh** | move fils to a folder / drop | brief, directional, non-destructive |
| **Mic start** | voice recording begins | short "ready" cue |
| **Mic stop** | voice recording ends | or reuse `articlemade` when it becomes a fil |
| **Search submit** | run a query | processing cue; or a `meshduringprocess` variant |
| **Search results arrive** | results surface | soft reveal; could reuse `grid` |
| **Select tick** (optional) | select/deselect a fil | or just reuse `tabsound` |
| **Copy tick** (optional) | copy to clipboard | or reuse `click` |

## Suggested order when we build it
1. Ship the **quick wins** (all reuse existing assets — no sourcing). 2. Delete the truly orphaned
assets (`addparagraph*`). 3. Source the **shopping-list** sounds (Mason, external) and wire them.
Respect `soundEnabled` throughout. Pair new sounds with the existing haptic roles where they co-fire.
