# Fil — Product Video Brief

*Drafted 2026-08-18. Grounded against `AppStore/metadata.md`, `AppStore/screenshots.md`,
`AppStore/screenshots/`, `docs/v1-route.md`, `docs/website/website-copy-v2.md`. Voice per the
`fil-voice` skill (marketing branch).*

> **Editor's note.** The original draft reported the Lock Screen accessory widget as unbuilt,
> citing v1-route #20, and treated it as a blocker on the film's strongest opening. That was
> wrong — the doc was stale. `FilPinnedWidget.swift:273` declares `.systemSmall`,
> `.accessoryRectangular`, `.accessoryCircular` and `.accessoryInline`, each with its own view.
> The permanent lock-screen surface exists. v1-route has been corrected; the "needs filming"
> list below is amended accordingly.

---

## 1. What's the product?

**Fil puts the folder you're in the middle of — the trip, the move, the dinner you're planning — on
your Lock Screen, in your Dynamic Island and on your Home Screen, so you can see what's in it
without opening anything.**

From the app name, the subtitle, and the description's first paragraph, which names those three
situations verbatim. "Without opening anything" is the honest form: decision 17c forbids "no app to
open," since you do open Fil to read, add and rearrange.

## 2. Who's it for?

**A person three weeks out from a trip they're planning, who already has the packing list in Notes,
the photo in Photos, the park link in a Safari tab and "call the ranger station" in a text to
themselves — and who checks their phone forty times a day without any of it being there.**

Not invented: `02-folder-yosemite.png` is a Yosemite trip holding four to-dos ("water filter",
"trail map, paper one"), one photo, one note ("call the ranger station about fire restrictions"),
one link (nps.gov). `09-pinning.mov` shows the shelf: *The move* (3), *Yosemite* (5), *Reading* (2).
Decision #19 names the Yosemite pattern as the onboarding seed.

**Why it must be narrow.** The product holds exactly one pin. Multiple pins were scoped and
rejected because the single slot *is* the product — "the constraint is the thesis." An app that
holds one thing is for a person who currently has one thing. Widen the audience and you are selling
a folder app; the pin stops meaning anything.

**Rejected:** "people who abandoned a dozen second brains" and "voice-first thinkers" — both from
the superseded July privacy/voice-led positioning, and both define the audience by what they fled
rather than what they are doing, which gives a film no situation to open on.

## 3. The one promise

**The thing you're in the middle of is already on your screen, so you never open the app to check.**

**Promise sentence for the shot list:** *For someone in the middle of one thing that keeps
generating scraps, Fil makes the folder they're living in visible without opening anything, because
it lives on the Lock Screen, the Dynamic Island and the Home Screen instead of behind an app icon.*

**Runners-up, and why each lost:**

- **"No two thoughts look alike."** The strongest image Fil has and the film's whole visual
  identity — but website-copy-v2 files it as the reward, not the wedge. It answers a question
  nobody arrives with. It stays the look; it does not become the claim.
- **"Better inside."** "Great outside. Better inside." is a two-act line by construction. Making
  the room the promise inverts the sentence.
- **"Nothing to keep up with."** Cut on voice rule 2 — the site already killed its own "you
  shouldn't have to go looking" section for arguing by negation, and every chip plants a feature
  Fil doesn't have.
- **Privacy / on-device.** Demoted to honest footnote at #17. Resurrecting it is the specific
  mistake this brief exists to avoid.
- **Smart search / File for me.** Paid. Decision #18 puts the entire door in the free tier because
  "the door is how the habit forms." Leading on Extra advertises what most viewers won't buy.

## 4. Where does it run?

**One bespoke cut: a 30s vertical master for the App Store preview. Derive the 15s for social. Give
the website raw clips, not a film.**

| Placement | Cut for it? | Ratio | Sound | First frame | Text |
|---|---|---|---|---|---|
| **App Store preview** | **Yes — the only bespoke cut** | Portrait 1320×2868 (existing footage already is) | Sound-off; autoplays muted | Poster frame = **expanded Dynamic Island full of blobs** | Burned in, top/bottom safe zone — Apple OCR-indexes it, so captions pay ASO rent |
| **Marketing site** | No | n/a | Silent loops | n/a | None |
| **Instagram Reels** | Re-cut of the 15s | 9:16, **phone inset in frame** | Sound-off argument | Push in so the Island fills a third | Heavy; label the four surfaces |
| **X** | No — post the 15s as-is | — | Muted autoplay | The Island | Post copy carries the words |

**App Store is primary** — the only placement where the viewer has already decided to look, which is
what buys the second act. Setting the poster to the expanded Dynamic Island also resolves the hero
decision v1-route records as drifted: it is the one frame unmistakably an iPhone, not an app screen,
with no counterpart in any competitor's listing.

**The site already specifies its own treatment** — *Four places that aren't the app*, "one clip
playing at a time." That is four copy-tied loops, not a film. Give it the four door clips trimmed to
clean loop points, muted, plus a 3s silent Dynamic Island loop for the hero.

**Reels is the one real change, not a trim.** The store puts no chrome over the frame; Reels covers
the bottom fifth with caption and CTA and the top tenth with the profile row — exactly where a Live
Activity and the Dynamic Island sit. The phone must be inset, the surfaces get smaller, and the
Island push-in becomes mandatory rather than stylistic.

## 5. How long?

Two films, not one trimmed. **The 15s never goes inside the app. The 30s crosses the threshold.**

Concept both implement: **"The Pattern"** — the same pinned folder found in one place after another.
Demonstration; the 30s adds a vignette turn when you tap in.

### The 15s — hook, demo, payoff · 5 shots

| Time | Beat | Shot | Source |
|---|---|---|---|
| 0.0–2.5 | **Hook** | Dynamic Island, expanded, full of coloured blobs; held still for the first 0.4s | `08-dynamic island.mp4` ~2.0–4.5 |
| 2.5–5.0 | Demo | Lock Screen, same folder, blob row along the activity | `lock screen.mp4` 0.0–2.5 |
| 5.0–8.5 | Demo | Home Screen widget → swipe right → Today View, **one continuous take** | **needs filming** |
| 8.5–12.0 | **Payoff** | The folder shelf; pin moves from *The move* to *Yosemite* | `09-pinning.mov` 3.0–6.5 |
| 12.0–15.0 | Mark | End card | **needs building** |

Five shots reads confident rather than cheap; every hold clears the ~1.5s a shot needs to register.
Surfaces three and four are one shot because the phone genuinely does that in one motion.

**Sound-off legibility of the opening frame:** a black pill on a wallpaper holding five saturated
circles, on an otherwise ordinary Home Screen. It reads in half a second as *an iPhone doing
something I don't recognise* — the only job a thumbnail has.

**What the 15s does that the 30s can't:** it repeats. Four surfaces at near-equal weight, cut on a
beat, so the rhythm is the argument. Compressed into 30s beside a second act, the same four surfaces
read as a feature list.

### The 30s — "Great outside. Better inside." · situation, turn, reveal · 11 shots

| Time | Beat | Shot | Source |
|---|---|---|---|
| 0.0–2.0 | Hook | Same Dynamic Island frame — deliberately identical, so the thumbnail is one asset | `08-dynamic island.mp4` |
| 2.0–4.0 | Situation | Phone face-up beside a paper trail map and a headlamp; screen lights; the folder is already there | **needs filming** |
| 4.0–6.5 | Door | Lock Screen | `lock screen.mp4` |
| 6.5–9.5 | Door | Home Screen widget → swipe → Today View, one take | **needs filming** |
| 9.5–13.0 | Door | Pinning; *The move / Yosemite / Reading* | `09-pinning.mov` |
| 13.0–16.0 | **Turn** | Tap the Lock Screen activity, land inside the folder. No cut | `lock screen.mp4` 2.5–4.7 (also `today view.mp4` 2.5–4.4) |
| 16.0–19.0 | Reveal | The folder: to-dos, photo, note, links, each with its own blob | `02-folder-yosemite.png` — **prefer filming the scroll** |
| 19.0–22.0 | Reveal | The player: warm blob, transport, scrub bar | `06-player.mov` |
| 22.0–24.5 | Reveal | The canvas, blobs drifting, none alike | `08-home-canvas.mov` |
| 24.5–27.0 | Reveal | Ambient screensaver | `07-screensaver.mov` |
| 27.0–30.0 | Mark | End card | **needs building** |

**What the 30s does that the 15s can't:** it earns the second half of the line. The player, the wall
of blobs and the screensaver only mean something after the door is established. It also buys the one
live-action shot — the only frame saying a person and a situation exist rather than a phone in a
vacuum. The Yosemite folder's own packing list supplies the props.

**For the App Store cut:** drop shot 2 and redistribute those 2s across the door. Apple requires App
Preview footage captured from the app on device, and a tabletop shot breaches that. The version with
live action is the social/site cut; the App Store version is 10 shots, all screen.

### On-screen text (both films, lifted verbatim from shipped copy)

- Card A, over shot 1: **pin what you're in the middle of.**
- Card B, over the widget shot: **glance and it's there.**
- Card C (30s, over the turn): **open Fil when you want to dig in.**
- Card D (30s, over the canvas): **no two thoughts look alike.**
- End card: **Fil: Folders Outside the App** + App Store badge.

Lowercase per `screenshots.md`; "Fil" capitalised per `fil-voice`; no em dashes; every claim
positive. Use the colon form of the name from `metadata.md`, not the em-dash form still in
`website-copy-v2.md`.

## Still needs filming, in priority order

1. **Home Screen widget in use.** `07-home screen.mp4` is 13.6s of the *Add Widget* sheet, not the
   widget working. The widget only appears in use in `today view.mp4`, on the widget page. One of
   the four named surfaces has no footage. Biggest gap.
2. **Lock Screen accessory widget.** *Amended:* it is built and shipping, so this is a capture task,
   not a code task. Every lock-screen frame currently in the repo is Live-Activity-only; the
   permanent surface has never been filmed, and it is the strongest form of the hook.
3. **Status-bar pass.** The door clips read *Sat Jan 1* with a placeholder carrier. v1-route #4
   names the fix (`simctl status_bar`). Re-capture all four.
4. **Continuity pass.** The Island shows *5*, the Lock Screen activity *6 items*, the widget
   *5 fils* — for what is meant to be one folder in one moment. The whole pattern argument depends
   on it visibly being one folder.
5. **Folder scroll** (30s, shot 7). Only a still exists.
6. **Tabletop shot** (30s social cut only).
7. **End card.** No video asset exists.

**Seam warning:** the `.mp4` batch is 13 Aug, the `.mov` batch 14 Aug, and the app moved between
them — the compose bar copy differs ("Add to Yosemite" vs "Tap to write"). Cutting them together
will show it.

## Flagged — not grounded in repo material

- **`AppStore/screenshots.md` is stale and contradicts this brief.** Its preview arc is
  *tap → speak → titled note* (retired voice-led positioning); its captions include
  "no inbox. no tags. no system." (the negation pattern the website cut) and "titled on your device"
  (wrong — titles are the first line of the user's own text). Needs rewriting alongside this.
- **No video is on the route.** `screenshots.md` calls a preview "optional but recommended";
  v1-route's sequenced open items don't mention one. This brief is for unscheduled work.
- **No distribution channel is documented.** Nothing names an Instagram or X account. Those
  recommendations assume accounts that could not be verified.
- **No audio assets.** No music or sound bed anywhere; the Mirelo sound spike is banked, not run.
  Both films are designed sound-off, but a 30s preview with no audio track is a deliberate choice
  someone should make.
- **App Store preview mechanics** (muted autoplay, poster-frame selection, device-capture
  requirement) and **Reels safe-zone proportions** come from general knowledge, not repo files.
- **The hero decision** — expanded Dynamic Island over the blob — is a call, not a citation.
  v1-route records it as drifted and unresolved.
