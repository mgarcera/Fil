# Type bake-off — 2026-09-14/15

The app's body and display sans. Judged on device, whole app swapped at once via a temporary
Settings → Appearance → Type switch (stripped after the verdict). No screenshots: Mason's eyes on
hardware were the verdict surface.

| Face | Cuts bundled | Verdict | In his words |
|---|---|---|---|
| **Fredoka** (incumbent, since July) | Light–Bold | lost | — |
| Manrope | Light–Bold, static from Google Fonts | lost, 2026-09-14 | "no dice" |
| **Gabarito** | Regular–Bold, instanced from the variable font | **won, 2026-09-15** | "seems to be more legible, let's keep it. i can always revert" |

Sizes were left as they were for the comparison. Gabarito has no Light cut (axis 400–900), so
Fredoka's Light call sites now render Regular.

## Regenerating the cuts

`Gabarito[wght].ttf` here is the source (google/fonts, OFL). `instance.py` writes the four static
cuts the app registers; change the weight list to add or move a cut.

## Reverting

`git show 1247205^:Fil/Resources/Fonts/` has the Fredoka files; `Theme.gabarito` is the single
entry point, so a revert is the font files plus that one function's name map.
