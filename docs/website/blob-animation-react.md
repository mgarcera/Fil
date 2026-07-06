# Building the fil blob creation animation in React / Next.js

A faithful web port of Fil's signature moment: the **gooey, wobbling blob** that appears while a
fil is being created, then **solidifies and morphs into the finished card**. The math below is
translated 1:1 from the app (`CreatingFilBlobView` / `BlobShape` and `NoteBlobShape` /
`Theme.gradient` in `Theme.swift`), so it matches the real thing.

> Note: browser `performance.now()` / `Math.random()` are fine here — this is website code, not one
> of the workflow scripts (which forbid them).

---

## 1. Anatomy of the animation

Three parts, in order:

1. **Wobble** — a blob outline whose vertices drift over time via layered sine waves, drawn as a
   smooth closed bezier curve. Two of them are stacked: a solid gradient base + a blurred,
   `plus-lighter` colored overlay whose gradient direction slowly rotates. This is the "thinking /
   creating" state.
2. **Solidify** — the wobble amplitude eases toward the *settled* per-fil shape (a fixed, seeded
   blob) and the animation calms.
3. **Morph** — the settled blob flies/resizes from the creation slot into its place in the grid as
   a real card (a shared-element / FLIP transition — SwiftUI's `matchedGeometryEffect`; on web,
   Framer Motion's `layoutId`).

---

## 2. Rendering choice

Use **inline SVG** (one `<svg>`, two `<path>` layers). It's vector-crisp, gives you real
`<linearGradient>` fills + `feGaussianBlur`, and `mix-blend-mode` works per element. Drive it with
`requestAnimationFrame` and **mutate the path's `d` attribute via a ref** — don't `setState` every
frame (that would re-render React 60×/sec).

Canvas is a fine alternative if you stack many blobs; SVG is nicer for one hero blob with gradients.

---

## 3. The core math (framework-agnostic)

### 3a. Blob path — animated (the creation wobble)

Direct port of `BlobShape.path(in:)`:

```ts
type Pt = [number, number];

/** Smooth closed blob path as an SVG `d` string. */
export function blobPath(opts: {
  cx: number; cy: number; radius: number;
  points: number;        // 5–6 for the creation blob
  deformation: number;   // amplitude in px (see §5)
  time: number;          // seconds
}): string {
  const { cx, cy, radius, points, deformation, time } = opts;
  const pts: Pt[] = [];
  for (let i = 0; i < points; i++) {
    const angle = (i / points) * Math.PI * 2;
    // Two out-of-phase sine waves (matches the app's s1/s2 exactly).
    const s1 = Math.sin(angle * 5.0 - time + 512.0) * 2.0;
    const s2 = Math.sin(angle * 2.0 + time * 1.8 + 21.0) * 2.0;
    const r = radius + (s1 + s2) * deformation;
    pts.push([cx + Math.cos(angle) * r, cy + Math.sin(angle) * r]);
  }
  return smoothClosedPath(pts);
}

/** Catmull-Rom-style cubic bezier through all points, tension 0.2 (matches the app). */
function smoothClosedPath(pts: Pt[]): string {
  const n = pts.length;
  let d = `M ${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`;
  for (let i = 0; i < n; i++) {
    const cur = pts[i], next = pts[(i + 1) % n];
    const prev = pts[(i - 1 + n) % n], after = pts[(i + 2) % n];
    const c1: Pt = [cur[0] + (next[0] - prev[0]) * 0.2, cur[1] + (next[1] - prev[1]) * 0.2];
    const c2: Pt = [next[0] - (after[0] - cur[0]) * 0.2, next[1] - (after[1] - cur[1]) * 0.2];
    d += ` C ${c1[0].toFixed(2)} ${c1[1].toFixed(2)} ${c2[0].toFixed(2)} ${c2[1].toFixed(2)} ${next[0].toFixed(2)} ${next[1].toFixed(2)}`;
  }
  return d + " Z";
}
```

### 3b. Blob path — settled (the finished card shape)

The card uses a *fixed, seeded* shape (`NoteBlobShape`), not the time-driven wobble. Port it so the
morph target matches the app. Each fil derives its `seed` (0–1) from its id.

```ts
function unitNoise(seed: number, salt: number): number {
  const v = Math.sin((seed + 0.137) * (salt + 12.9898) * 78.233) * 43758.5453;
  return v - Math.floor(v); // 0–1
}

/** Settled per-fil blob (matches NoteBlobShape). cx/cy center, `side` = min(w,h). */
export function settledBlobPath(cx: number, cy: number, side: number, seed: number): string {
  const points = 5 + Math.floor(seed * 4.999);           // 5–9
  const amplitude = 0.055 + seed * 0.055;
  const freq2 = 2 + Math.floor(unitNoise(seed, 17) * 4);
  const freq3 = 3 + Math.floor(unitNoise(seed, 23) * 4);
  const phaseA = seed * Math.PI * 2;
  const phaseB = (1 - seed) * Math.PI * 2;
  const rotation = (unitNoise(seed, 29) - 0.5) * 0.7;
  const asymPhase = unitNoise(seed, 37) * Math.PI * 2;
  const asymStrength = (unitNoise(seed, 41) - 0.5) * 0.18;
  const radiusX = side * 0.5 * 0.5;   // NoteBlobShape uses 0.50 of the half-side
  const radiusY = side * 0.5 * 0.46;  // and 0.46 — slightly oval

  const pts: Pt[] = [];
  for (let i = 0; i < points; i++) {
    const angle = (i / points) * Math.PI * 2 + rotation;
    const pointOffset = (unitNoise(seed, i + 101) - 0.5) * 0.22;
    const wave = (Math.sin(angle * freq2 + phaseA) * 0.65 + Math.sin(angle * freq3 + phaseB) * 0.45) * amplitude;
    const asym = Math.cos(angle + asymPhase) * asymStrength;
    const mult = Math.max(0.72, 1 + pointOffset + wave + asym);
    pts.push([cx + Math.cos(angle) * radiusX * mult, cy + Math.sin(angle) * radiusY * mult]);
  }
  return smoothClosedPath(pts);
}
```

### 3c. Gradient (16-stop smoothstep + per-seed angle)

Matches `Theme.gradient` / `smoothGradientStops` / `gradientUnitPoints`:

```ts
const hexToRgb = (h: string) => {
  const n = parseInt(h.replace("#", ""), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const smoothstep = (t: number) => t * t * (3 - 2 * t);

/** 16 eased stops so edge colors hold and the midpoint doesn't go muddy. */
export function gradientStops(startHex: string, endHex: string, steps = 16) {
  const a = hexToRgb(startHex), b = hexToRgb(endHex);
  return Array.from({ length: steps }, (_, i) => {
    const p = i / (steps - 1);
    const e = smoothstep(p);
    const c = a.map((av, k) => Math.round(av + (b[k] - av) * e));
    return { offset: p, color: `rgb(${c[0]},${c[1]},${c[2]})` };
  });
}

/** Per-seed gradient direction as SVG objectBoundingBox coords (matches gradientUnitPoints). */
export function gradientVector(seed: number) {
  const angle = seed * 2 * Math.PI;
  const dx = Math.cos(angle) * 0.5, dy = Math.sin(angle) * 0.5;
  return { x1: 0.5 - dx, y1: 0.5 - dy, x2: 0.5 + dx, y2: 0.5 + dy };
}
```

Use the palettes/hex from `docs/brand/brand-positioning.md` §9 to pick each fil's two colors
(cross-palette pairs allowed).

---

## 4. React components

### 4a. A performant animated blob (ref-mutation, no per-frame re-render)

```tsx
"use client";
import { useEffect, useRef } from "react";
import { blobPath, gradientStops, gradientVector } from "./blob";

export function CreatingFilBlob({ size = 240, startHex = "#F24D59", endHex = "#6659CC" }) {
  const baseRef = useRef<SVGPathElement>(null);
  const overlayRef = useRef<SVGPathElement>(null);
  const gradRef = useRef<SVGLinearGradientElement>(null);
  const reduced = usePrefersReducedMotion();

  useEffect(() => {
    if (reduced) {
      // Static settled shape for reduced-motion users.
      baseRef.current?.setAttribute("d", blobPath({ cx: size/2, cy: size/2, radius: size*0.4, points: 6, deformation: 0, time: 0 }));
      return;
    }
    let raf = 0;
    const loop = () => {
      const t = (performance.now() / 1000) * 0.9;                 // app uses time * 0.9
      const cx = size / 2, cy = size / 2, radius = size * 0.4;
      baseRef.current?.setAttribute("d",
        blobPath({ cx, cy, radius, points: 5, deformation: Math.max(2, size * 0.03), time: t }));
      overlayRef.current?.setAttribute("d",
        blobPath({ cx, cy, radius, points: 6, deformation: Math.max(1.4, size * 0.022), time: t * 0.82 + 1.3 }));
      // Overlay gradient direction slowly rotates (matches spread/rotation in the app).
      const rot = t * 0.6, spread = 0.16 + (Math.sin(t * 1.15) + 1) * 0.16;
      const g = gradRef.current;
      if (g) {
        g.setAttribute("x1", `${0.5 + Math.cos(rot) * spread}`);
        g.setAttribute("y1", `${0.5 + Math.sin(rot) * spread}`);
        g.setAttribute("x2", `${0.5 - Math.cos(rot) * spread}`);
        g.setAttribute("y2", `${0.5 - Math.sin(rot) * spread}`);
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [size, reduced]);

  const stops = gradientStops(startHex, endHex);
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
      <defs>
        <linearGradient id="fil-base" x1="0" y1="0" x2="1" y2="1">
          {stops.map((s, i) => <stop key={i} offset={s.offset} stopColor={s.color} />)}
        </linearGradient>
        <linearGradient id="fil-overlay" ref={gradRef} gradientUnits="objectBoundingBox">
          <stop offset="0" stopColor="rgba(64,140,217,0.7)" />
          <stop offset="1" stopColor="rgba(230,115,51,0.7)" />
        </linearGradient>
        <filter id="fil-goo"><feGaussianBlur stdDeviation={Math.max(4, size * 0.06)} /></filter>
      </defs>
      <path ref={baseRef} fill="url(#fil-base)" />
      <path ref={overlayRef} fill="url(#fil-overlay)" filter="url(#fil-goo)"
            style={{ mixBlendMode: "plus-lighter" }} />
    </svg>
  );
}
```

`usePrefersReducedMotion` is a small hook wrapping `matchMedia("(prefers-reduced-motion: reduce)")`.

### 4b. The morph into a card (Framer Motion `layoutId`)

SwiftUI's `matchedGeometryEffect(id:in:)` = Framer Motion's shared `layoutId`. Give the creation
blob and the final card the same `layoutId`; when you swap which one is mounted, Framer Motion
tweens position + size between them (a FLIP transition).

```tsx
import { motion, AnimatePresence } from "framer-motion";

{creating
  ? <motion.div layoutId={fil.id} className="creation-slot"><CreatingFilBlob {...} /></motion.div>
  : <motion.div layoutId={fil.id} className="grid-card"><FilCard fil={fil} /></motion.div>}
```

To also *calm* the wobble as it solidifies (the app eases amplitude down), animate a `deformation`
value from its lively number toward the settled shape over ~0.5s right before the swap — e.g. drive
`deformation` with a Framer `useMotionValue`/`animate`, or crossfade `CreatingFilBlob` into a
static `settledBlobPath` for that fil's seed. `FilCard`'s blob should use `settledBlobPath` so the
shapes line up at the end of the morph.

---

## 5. Tuning constants (Swift → JS map)

| Meaning | App value | Use in JS |
|---|---|---|
| Global time scale | `time = now * 0.9` | `performance.now()/1000 * 0.9` |
| Base blob points | 5 | `points: 5` |
| Base amplitude | `max(2, side*0.03)` | same |
| Overlay points | 6 | `points: 6` |
| Overlay amplitude | `max(1.4, side*0.022)` | same |
| Overlay time offset | `time*0.82 + 1.3` | same |
| Overlay gradient rotation | `time*0.6` | `rot` |
| Overlay gradient spread | `0.16 + (sin(time*1.15)+1)*0.16` | `spread` |
| Overlay blur | `max(4, side*0.06)` | `feGaussianBlur stdDeviation` |
| Overlay blend | `.plusLighter` | `mix-blend-mode: plus-lighter` |
| Bezier tension | `0.2` | `0.2` in `smoothClosedPath` |
| Settled radii | `0.50 / 0.46` of half-side | in `settledBlobPath` |

---

## 6. Performance & polish

- **Mutate refs, don't `setState`** in the rAF loop (shown above). One `requestAnimationFrame`,
  cancel on unmount.
- **Pause offscreen:** gate the loop with an `IntersectionObserver` so a hero blob stops animating
  when scrolled away.
- **`prefers-reduced-motion`:** render the static `settledBlobPath` instead of animating.
- **`plus-lighter`** isn't universal; fall back to `screen` where unsupported.
- Keep it to **one or two** hero blobs animating at once; render grid cards as static
  `settledBlobPath` SVGs (cheap) rather than animating every one.
- The app pairs this with a soft "creating" sound and a title that reveals out of blur
  (`AnimatedGradientRevealText`) — optional on web, but a gradient-wipe text reveal on the title is
  an easy, on-brand touch.

---

*This recreates the app's signature moment on the web. Keep it calm and organic (see the brand
doc's motion notes) — the blob should feel alive and gooey, never bouncy or gamified.*
