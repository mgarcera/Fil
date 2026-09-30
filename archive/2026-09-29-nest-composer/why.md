# The nest's composer — Add | Ask, and why it lost to the shipped one

2026-09-29. Two bars were built for the nest and flipped between on the device on
axis B of the sandbox. The shipped `ComposerBar`, in the home's own liquid-glass
dock, won. This records the one that did not, because a diff shows what the
winner became and never what the loser looked like.

## The loser: a grouped two-level row

A full-bleed black slab pinned to the bottom of the nest. At rest it offered two
words:

```
                    Add                    Ask
```

Tapping one replaced the row with that group's members — never both, so the most
it ever showed was four:

```
        Text        Photo       To-Do       Voice
   ────────────────────────────────────────────────
   add to CommunityHealth                        ↑
```

Beneath the row sat a single field line, 56pt, riding directly on the keyboard.
Selection was carried by opacity alone, 1.0 against 0.4. Tapping the lit option
returned to rest.

It went through four shapes in one evening:

1. `Navigate | Add | Chat | Search`, with a 330pt writing room above the keyboard.
   Total translation 666pt. Rejected: "330+keyboard is too much after all."
2. The same four with `Navigate` dropped — "i don't think navigate needs its own
   section. the options can just be selected or deselected."
3. Six peers: `Text | Photo | To-Do | Voice | Chat | Search`. Never built — at
   402pt wide that is 67pt a word, and the ask that produced it was for FEWER
   buttons, not more.
4. `Add | Ask` revealing four and two, with the room deleted entirely. What is
   recorded above.

## What it got right, and what the winner has to keep

- **Capture types as peers.** Text, Photo, To-Do and Voice on one row, chosen in
  one tap. The shipped composer buries three of them in a `+` menu (Record / Add
  photo / Take a photo) with a checklist button beside it. This is the one place
  the loser is better and it is worth revisiting.
- **One spring for everything.** The page's translation and the bar's were a
  single animated value, so nothing could drift. `ComposerBar` carries four
  `.animation` modifiers of its own plus a fifth on its to-do rows, all
  independent of the page.
- **Selection by opacity, never by weight.** Swapping HelveticaNeue for
  HelveticaNeue-Medium is a different font resource, which is a different view,
  which cross-fades. See Pattern 8 and 9 in `swiftui-animation-performance` —
  both were written from this bar's failures.

## Why it lost

It was a composer built from nothing beside one that already exists and already
works. `ComposerBar` carries multi-photo staging up to eight with removal, real
to-do pills with return-to-add-next and auto-removal of empty rows, camera
capture, a keyboard-dismiss control, send-with-dissolve, and a four-state search
button. The nest bar had a text field and an arrow.

And the glass decided it. Mounted on the black slab the comparison was wrong —
the glass is not in `ComposerBar` at all, it is in `CanvasHome`'s dock, which
wraps composer and baskets in one container. Given its real treatment
(`.padding(14)` → `.glassEffect(.regular, in: .rect(cornerRadius: 30))` → inset
12/8, floating rather than full-bleed) the verdict was immediate: "the glass is
better."

Radius went 30 → 40 → 60 after that.

## What the loser cost to build, and what it left behind

Three motion faults, each of a different kind, all found in this bar and all now
written up:

- Labels cross-fading at two heights mid-travel (a font-resource swap).
- The row arriving at three different heights in one frame — the page moving by
  `.offset` while the bar grew by animating a height, one spring, two mechanisms.
- Folders with a cover photograph stuttering while folders without one did not:
  `FolderCoverGround.init` decoding a 900px JPEG on every render pass.

Those three are the durable output of this branch, and they survive it.
