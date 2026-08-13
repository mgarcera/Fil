# Fil — the route to v1 (2026-08-13)

Produced from a full walkthrough of every open thread on 2026-08-13. This is the
current map: what's decided, what's parked and on whom, and what order the
remaining work goes in.

**Read this before `LAUNCH_PROGRESS.md` or `AppStore/submission-checklist.md`** —
both of those describe an app and a plan that moved on. They've been corrected,
but this doc is the forward view; they are the record.

---

## Where things actually stand

The **paid spine is done**. Pivot-plan phases 1–6 all shipped between Jul 11 and
Jul 13: Cloudflare proxy holding the key server-side, free local keyword search,
StoreKit client, server-side subscription verification via the App Store Server
API, paywall, disclosures. Cost controls (per-user KV attribution, ~200/day
circuit-breaker, payload pre-filter) landed Jul 12.

Since then: **97 commits, 85 of them in August** — the full-screen player, the
dock and composer, folders, fil-card language, sound and haptics, titles from
first line. Craft, not launch work.

All four `rootcause.ltd/fil/*` pages are live (verified 200). The ASC app record
exists (`appStoreID` is a real ID). Nothing has been submitted.

---

## Decided on 2026-08-13

| # | Thread | Decision |
|---|--------|----------|
| 1 | Screenshots & assets | All redone against the current app. Capture automated via the simulator; PNGs live in the repo. Harness depth, seed-data source, and the shot list itself are build-time calls. |
| 2 | Device verification | Done for the two checklist items. Open question: whether the August surface (Live Activities, Control Center controls, player audio) was covered. |
| 5 | `Note.kind` refactor | **Deferred to post-launch.** Its only pre-ship rationale was groundwork for Fil a Folder. ~50 references across 8 files; a refactor that size in submission week buys nothing. |
| 6 | Capture modes | **Done** — voice, photo, and link capture all live in `CanvasHome`, and the seed reveal with them. Phase 8 of the pivot plan is effectively complete. |
| 6b | Onboarding | **Still needs polish.** Open v1 work item; scope to be defined when we do it. |
| 7 | Fil a Folder | **Post-v1, not a priority.** Consequence: smart-organize *stays in v1*, so punch-list items 4, 5, and 8 (rip out the `organize` endpoint and UI) are void, not deferred. |
| 8 | Sound | Reuse-only pass is the v1 scope. Sourced/generated sounds are post-launch. |
| 8b | Mirelo connector | Evaluated and **banked**, not run. 5,000 credits available; 40 credits and ~1.5s per four-variant exploration. Viable for the shopping-list roles; see `docs/features/sound-design-audit.md` for the assessment and the caveats. |
| 11 | Trial mechanics | **Ship the conventional StoreKit free trial** already built (`P2W` intro offer on both products). The reverse trial in the pivot plan was never implemented, and can't be safely: per-user attribution and the circuit-breaker key on `originalTransactionId`, which a non-purchaser doesn't have. Revisit with real conversion data. |
| 11b | Pro gating | **Additive gating in; folder cap in; filament cap out.** See below. |
| 12 | Circuit-breaker | Ship the ~200/day value as-is; nothing to tune from pre-launch. |
| 12b | Prompt caching | Already implemented and correctly placed — the pivot plan's "worth it once payloads are known" is stale. See the threshold analysis below. |
| 14 | Anthropic spend cap | **Confirmed set.** |
| 15 | Trunk | `main` fast-forwarded to the current app; `blank-canvas-home`, `launch-prep`, and `dynamic-island-share-capture` deleted after verifying every commit was an ancestor. One branch now. |

### Decided later the same day — positioning, and what it dragged with it

| # | Thread | Decision |
|---|--------|----------|
| 17 | **Positioning** | **Decided, no longer parked.** Fil leads with the surfaces outside the app and pays off with the room behind them. Three pillars: **the door** (six surfaces that aren't the app), **the form** (every thought arrives as its own object, unchosen and unrepeatable), **the room** (worth staying in). Privacy demotes from wedge to an honest data note. Copy drafted in `docs/website/website-copy-v2.md`. |
| 17b | **Name** | `Fil — Folders Outside the App` · `Lock screen & dynamic island` (29 / 28 chars). "Fil" stays the first word. The name states the category; the subtitle carries both searchable surfaces. |
| 17c | **The claim, precisely** | **Not** "no app to open" — untrue, since you open Fil to read, add, and rearrange. The honest claim is that it's *already there when you context-switch*; you never open it just to check. Written into the copy guardrails. |
| 18 | **The door is free** | **Reverses part of 11b.** All six non-app surfaces stay in the free tier — lock screen, Dynamic Island, home screen widget, Today View, Control Center controls, share sheet. The door is how the habit forms; a free user who never installs it never gets far enough to want the room. |
| 19 | **Onboarding scope** | Was "needs polish, scope TBD." Now defined: **first run ends with the door installed**, not with a fil created — Live Activity started, plus instructions to go look at the lock screen or tap the Dynamic Island. Consider seeding a *situational* example folder (the Yosemite pattern: a trip with a to-do list, photos, links) so the utility is visible before the user has built anything. |
| 20 | **Accessory lock-screen widget** | **New v1 item.** `FilPinnedWidget` is `systemSmall` only — there is no `accessoryRectangular`/`accessoryCircular` widget, so the lock-screen surface today is Live-Activity-only. Live Activities are capped around 8 hours *and* share a single slot, so a delivery or a timer evicts Fil's door. Permanent surface = accessory widget; Live Activity keeps the transient loud moment. **The positioning depends on this shipping.** |
| 21 | **Export / import** | **New v1 item, free tier.** Spec'd in `docs/features/export-import.md`. Makes the "landscape after six months" claim honest and covers the delete-and-reinstall case that device backup cannot. |
| 22 | **Store-recovery notice** | ✅ **Shipped** (`d0f614d`). The container recovery paths never destroyed data, but presented as an empty app — indistinguishable from total loss, and the natural reaction (delete and reinstall) was the one thing that would make it real. Now says so on launch. |

### Pro gating (decision detail)

Everything gated today is cloud-cost-bearing and nothing else: AI surfacing +
summary, smart organize, folder captions on demand, and the pinned-folder
caption refresh. Everything else ships free — including all five screensavers,
both Lock Screen Live Activities, both Control Center controls, the share
extension, and unlimited fils, folders, and filaments.

**Direction chosen:**

- **Additive gating** — the assets already exist. Free gets one screensaver, Pro
  gets all five plus auto-screensaver; a sound/ambience pack ties into the sound
  work. The free user never *loses* anything; Pro blooms.
  **Revised same day (see #18): the six non-app surfaces are NOT part of this.**
  Lock Screen, Dynamic Island, home-screen widget, Today View, Control Center,
  and the share sheet all stay free — they're the door, and the door is how the
  habit forms.
  *Consequence worth facing: the additive set is now thinner than it looked, so
  Pro leans harder on surfacing + smart organize + folder captions. Whether that
  carries a $2.99/mo ask is a live question, not a settled one.*
- **Folder cap** — defensible. Folders are an organizing convenience, and v1 is
  the cheapest moment to introduce a cap since there are no libraries to
  grandfather.
- **No filament cap** — deliberately rejected. A filament is part of the thought
  itself; capping it says "you may not finish this thought without paying," in
  an app whose promise is *let thoughts be*.
- **Standing rule:** any new AI mode is Pro by default (it costs money per call).

Three numbers still to set when this is locked: which screensavers stay free,
which Lock Screen surfaces move to Pro, and the folder number. They move
together with positioning — see below.

### Prompt caching (threshold detail)

`proxy/src/index.js` already sets `cache_control: {type: "ephemeral"}` on the
notes block with the query in a separate block after it — textbook
shared-prefix/varying-suffix placement. Whether it ever *hits* is bounded by two
thresholds working against each other:

- **Haiku 4.5 won't cache a prefix under 4,096 tokens**, and fails silently when
  it's shorter. The system prompt is ~4,100 characters (≈1,000 tokens), so the
  notes block must carry roughly 3,000 more before caching engages at all.
- **The payload pre-filter kicks in above ~50 fils**, and from there
  `candidateNotes` varies per query — so the prefix changes each search and the
  cache misses.

Those crossing points sit close together, leaving a narrow band where caching
pays. Don't count on it as a cost lever; measure with `count_tokens` if it
matters.

**Gap found:** the `organize` and `describe` branches set no `cache_control` at
all — and organize sends up to 200 fils, the largest payload in the system. See
"Small tasks" below; the fix is structural, not two lines.

---

## Parked, and on whom

| What | Waiting on | Note |
|---|---|---|
| **ASC state** | Mason | Believes the App Store Connect work was done in July. If so, items 3 and 4 collapse to "update ASC to match what we decided, then update the docs." |
| **Fair-use clause** | inside the terms rewrite | Lands with the legal-page rewrite rather than as its own task. |
| **Cosmetics shop** | open | No longer positioning-blocked. Still undecided: drop, or keep as optional extra support alongside Pro. |
| **Zero Data Retention** | reassess | **Value dropped.** Privacy is no longer the wedge, so a stronger privacy claim buys much less than it would have in July. The 30-day wording is honest and already shipped in `PaywallView.swift:87`. Not worth chasing before launch. |
| **Mirelo spike** | banked | One role, four variants, trimmed, judged against an existing Fil sound. |
| **Gating numbers** | Mason | Which screensavers stay free, and the folder cap. The Lock Screen half of this question is now answered (#18: free). |

### What the positioning decision unlocked

It was the upstream gate on four threads, and all four are now actionable:
the App Store listing copy, the legal pages, the hosted website, and the
screenshot spec (the hero shot is now known: **the expanded Dynamic Island**,
because that's the surface in daily use and no competitor's listing shows
anything like it).

**Factual floor, unaffected by any of it:** the App Privacy answers and
`PrivacyInfo.xcprivacy` describe what the app actually does with data (User
Content › Other User Content, App Functionality, not linked, not tracking).
Those stay true under the new positioning, and they already agree with each
other.

### Data durability — checked 2026-08-13, no action needed on backup

The store lives in `URL.applicationSupportDirectory`; audio and the
`.video`/`.file` attachment payloads live in the documents directory; **nothing
anywhere sets `isExcludedFromBackup`**. Both directories are covered by iCloud
Backup and by device-to-device transfer, so **a phone upgrade carries everything
across**. What device backup cannot cover is delete-and-reinstall, or a phone
lost with backups switched off — which is what export/import (#21) is for.
CloudKit sync stays shelved; the reasoning, with the specific blocking fields,
is in `docs/features/export-import.md`.

---

## Open work, sequenced

1. **Accessory lock-screen widget** (#20) — the positioning's central claim
   depends on a permanent lock-screen surface. Nothing else on this list is
   worth doing if the door closes after eight hours.
2. **Onboarding to the door** (#19) — first run ends with the Live Activity
   started and the user told to go look; optionally a seeded situational folder.
3. **Export / import** (#21) — spec'd, free tier. Makes the six-month claim
   honest and covers reinstall.
4. **Screenshot spec rewrite + capture harness** — hero is the expanded Dynamic
   Island. Needs a seed launch-argument for curated demo data, `simctl
   status_bar` for a shipped-looking status bar, and 6.9″ capture.
5. **ASC subscription products + sandbox tester** — the one hard gate that isn't
   about copy. Local `Products.storekit` has both products; ASC needs its own,
   plus a tester, before the cloud path can be tested end to end.
6. **Listing copy + legal pages + website**, rewritten against
   `website-copy-v2.md`. The hosted legal pages still carry July's language.
7. **Gating implementation** — additive set + folder cap, once the numbers are
   locked. The door is explicitly excluded (#18).
8. **Sound reuse pass** — mic start/stop, select tick, copy tick, folder close;
   delete the two orphaned `addparagraph*` assets.
9. **Device verification of the August surface** — Live Activities, Control
   Center controls, player audio, sounds and haptics on hardware.
10. **Archive → validate → upload → submit**, with a reviewer note covering the
    on-device model, first-run seeding, and how to reach Pro.

---

## Post-v1

- Fil a Folder (design doc stands; punch list needs the void items struck)
- `Note.kind` refactor
- Sourced/generated sound pack (Mirelo or otherwise)
- ZDR upgrade, if pursued and granted
- Reverse trial, if conversion data argues for it

---

## Small tasks

- **Proxy: make cache control structural.** The payload is assembled with a
  ternary chain, so every new mode is a fresh chance to forget the breakpoint.
  Build the corpus block through one helper that always attaches
  `cache_control`, so `organize`, `describe`, and whatever comes next inherit it
  by construction.
- **Delete the orphaned sound assets** `addparagraph.mp3` /
  `addparagraphrefil.mp3` (no method references them).
