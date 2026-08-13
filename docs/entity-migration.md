# Entity, domain & brand migration — scope

*Scoped 2026-08-13. Status: NOT STARTED — held deliberately until the Weeklite transfer is
confirmed, then executed as one sweep.*

## The decisions driving this

| | Decision |
|---|---|
| **Label** | **Smidgecraft** replaces Rootcause — a rename, not just a new address. **Capitalised**, unlike the lowercase `rootcause` convention it replaces. |
| **Domain** | `smidgecraft.com`. **rootcause.ltd is kept alive**, not allowed to expire — no hard cut, no broken links mid-migration. |
| **Contact** | `mason@smidgecraft.com` everywhere. Replaces the current three-way split between `mason@rootcause.ltd`, `mason@garcera.us`, and the docs. |
| **Apple account** | New individual account; the org account lapses. Fil is recreated there → **new `appStoreID`**. |
| **Timing** | One coordinated sweep, gated on confirmation that Weeklite can transfer. Nothing changes piecemeal. |

## Why it's gated

Half-migrated is worse than either state. The four Fil URLs are wired into `FilLinks.swift`, the
hosted pages, and (probably) App Store Connect. Changing them in one repo but not the other leaves
the app pointing at pages that don't exist yet, or a listing pointing at a domain that no longer
serves. Doing it in one pass, once the account situation is settled, avoids that entirely.

---

## Inventory — Fil repo

| File | What changes |
|---|---|
| `Fil/FilLinks.swift` | All four URLs (`website`, `privacyPolicy`, `termsOfService`, `support`) → smidgecraft.com. **`appStoreID`** → the new record's ID. |
| `AppStore/metadata.md` | Terms + privacy URLs; contact email ×2; **legal entity** (`Rootcause LLC`); copyright line; support contact; seller-name note. |
| `AppStore/submission-checklist.md` | Hosting section; the two ASC URL fields. |
| `docs/support/index.md` | Email ×2; the `rootcause.ltd/fil/smart-search` reference. |
| `docs/legal/terms-of-service.md` | Contracting entity; email. |
| `docs/legal/privacy-policy.md` | Named entity; email. |
| `docs/website/website-copy.md`, `website-copy-v2.md` | Footer email. |

*Not touched:* `LAUNCH_READINESS_AUDIT.md` — a historical record from July, left as written.

## Inventory — website repo (`~/Downloads/Rootcause Rebrand`)

**Config / identity**
| File | What changes |
|---|---|
| `src/lib/brand.ts` | `name`, `description`, `url`, `email`, and the file's doc comment. The whole identity block. |
| `src/lib/fil.ts` | `contactEmail`; doc comment ("within the Rootcause site"). |
| `src/lib/weeklite.ts` | `contactEmail`; doc comment ("the Rootcause gallery chrome"). |
| `package.json`, `package-lock.json` | `"name": "rootcause"`. |

**Pages**
| File | What changes |
|---|---|
| `src/app/fil/privacy/page.tsx` | Entity name; email ×2 (mailto + display text). |
| `src/app/fil/terms/page.tsx` | Meta description; entity name; email ×2. |
| `src/app/fil/support/page.tsx` | Email ×4; the `rootcause.ltd/fil/smart-search` link. |
| `src/app/weeklite/privacy/page.tsx` | Entity name. |
| `src/app/fil/layout.tsx` | `aria-label="back to rootcause"`; `/rootcause-mark-white.png`. |
| `src/app/weeklite/layout.tsx` | Same pair, black mark. |
| `src/components/site-nav.tsx` | `/rootcause-mark-black.png`. |
| `src/app/(site)/macrotations/layout.tsx` | Comment referencing the title template. |
| `src/app/(site)/page.tsx` | Parent-brand copy — thesis, description, product index framing. |

**Assets** — `public/rootcause-mark-black.png` and `rootcause-mark-white.png` both need Smidgecraft
replacements. **This is the only item that needs design work, not editing**, so it's the long pole.

## Inventory — outside both repos

- **App Store Connect:** Privacy Policy URL, Support URL, App Review contact email, copyright line.
- **Vercel:** add `smidgecraft.com` to the project; keep `rootcause.ltd` attached and redirecting.
- **DNS:** smidgecraft.com → Vercel (Cloudflare, already registered).
- **GitHub:** the repo is `mgarcera/rootcause-rebrand`. Optional rename; cosmetic.
- **Email:** `mason@smidgecraft.com` — already set up.

---

## Two things to settle before the sweep runs

**1. Who is the contracting entity now?** The terms and privacy policy both name **Rootcause LLC**
as the party the user is agreeing with. With the LLC revoked, that sentence is false the moment it's
dissolved, and it is not a find-and-replace — it's a legal identity question. Whatever replaces it
(you personally, or a DBA) has to be the name in both documents and in the App Store copyright line.

**2. The App Store seller name will be your legal name.** An individual Apple developer account
displays the enrolled person's name as the seller unless Apple approves a DBA / trade name. So
"Smidgecraft" can be the label on the website, in the app, and in the copy — but the store listing
will read **Mason Garcera** unless the Illinois DBA lands and Apple accepts it. Worth knowing before
deciding how much weight the Smidgecraft name carries publicly.

---

## What can proceed now, without waiting

The migration is gated. **The copy and positioning work is not** — it touches different lines in the
same files and doesn't depend on the domain or the entity:

- `src/lib/fil.ts` — `tagline` and `hero` → the v2 lines
- `src/app/fil/page.tsx` — the door / form / room restructure (the "from mason" section **stays cut**,
  per the July edit; a maker's note belongs on the parent page if anywhere)
- `docs/website/website-copy-v2.md` — already written

Doing the copy first also means that when the sweep runs, it's a mechanical find-and-replace over
settled text rather than a rewrite and a rename tangled together.
