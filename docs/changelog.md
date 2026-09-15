# Fil changelog

One entry per change a user can see or feel, written the way a user would read it. Two things are
built from this file and nothing else: the **Roadmap** page on smidgecraft.com/fil and the
**What's New** field in App Store Connect. Internal work (build fixes, refactors, docs) stays out;
it lives in git.

Rules for an entry:
- Lead with what the user can now do, not what was built.
- One line, sentence case, no trailing period. A second line only if the first would mislead without it.
- Add the entry in the same commit as the change. A change without an entry is not done.

---

## 1.1 — unreleased

### Your fils, as a file
- Export your whole library as a single `.filbox` file from Settings → About: every fil, folder,
  photo, recording and attached file
- Inside the file, every fil is also plain text, sorted by folder, so it opens on any computer
  without Fil
- Import a `.filbox` on any iPhone with Fil. Importing adds what's missing and leaves what's
  already there alone, so an old backup is always safe to bring in

### The dock
- Fold the Bin away with the chevron beside it, for a cleaner dock. The count stays; Fil
  remembers the fold between launches
- Once one thought in the Bin is selected, a tap selects the next and a long press opens it, so
  picking several is quick. Clearing the selection puts tap-to-open back
- Open a thought from the Bin and a Move button sits top-left, so one thought can be filed from
  its reader without selecting it first

### Links
- A saved link now has the same top bar as every other thought: Move and Landfil. The address
  capsule is gone; the link is still one tap away behind the open button

### Settings
- Settings opens full height

---

## 1.0 (5) — submitted 2026-09-08

First release. The lock screen, Dynamic Island, home screen widget, Today View, Control Center
controls and share sheet; voice, photo and link capture; folders, filaments, and Fil Extra.
