# Building the fil gradient-reveal text animation in React / Next.js

A faithful web port of Fil's **title reveal**: each glyph rises out of blur and fades in — filled
with a drifting accent gradient — then settles to a calm resting colour. Translated 1:1 from the app
(`AnimatedGradientRevealText` / `GradientRevealTextRenderer` in `Fil/Views/AnimatedGradientRevealText.swift`),
so the timing and feel match the real thing.

> Website code — browser `performance.now()` is fine here.

---

## 1. Anatomy

A SwiftUI `TextRenderer` walks the text's glyph **slices** and draws each one itself. Per slice,
staggered by its index:

1. **Rise + un-blur + fade in** — `translateY`, `blur`, and `opacity` all ease from a displaced,
   blurred, transparent start to settled.
2. **Gradient fill** — while revealing, the glyph is filled with a two-colour slice of the accent
   gradient (colour `i` → colour `i+1`), so the word reads as a moving rainbow.
3. **Settle** — once a glyph finishes, it drops the gradient and rests at a single muted colour.

The whole run has a computed duration; after it, the loop stops and the settled styles stay.

---

## 2. Rendering choice

Use **DOM spans + CSS**, one `<span>` per character, and drive them with `requestAnimationFrame`,
**mutating each span's `style` via a ref** — never `setState` in the loop (that re-renders React
60×/sec). Text stays selectable and accessible (wrapper `aria-label`, glyphs `aria-hidden`). Canvas
is overkill for a single line of text; reserve it for many glyphs or pixel effects.

Per-glyph gradient fill = `background-image: linear-gradient(...)` + `background-clip: text` +
`color: transparent`.

---

## 3. The component

```tsx
"use client";
import { useEffect, useRef } from "react";

// Theme.accentGradientColors (Apple system colours; tune to brand).
const ACCENTS = ["#33BF99", "#34C759", "#007AFF", "#FF2D55", "#FF9500", "#5856D6"];
const ELEMENT = 0.28;   // per-glyph reveal seconds  (elementDuration)
const DELAY = 0.016;    // stagger between glyphs     (perElementDelay)
const MIN = 1.0;        // floor on total duration    (minDuration)
const EXTRA = 12;       // extra slices in the total  (extraSlices)
const easeOut = (t: number) => 1 - (1 - t) * (1 - t);   // ≈ SwiftUI UnitCurve.easeOut

export function GradientRevealText({
  text,
  restColor = "#8a8a8e",   // settled colour (app rests at secondaryText)
  fontPx = 40,
}: { text: string; restColor?: string; fontPx?: number }) {
  const spans = useRef<(HTMLSpanElement | null)[]>([]);
  const chars = Array.from(text);
  const reduced =
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  useEffect(() => {
    const settle = (s: HTMLSpanElement) => {
      s.style.opacity = "1"; s.style.transform = ""; s.style.filter = "";
      (s.style as any).backgroundImage = ""; s.style.color = restColor;
    };
    if (reduced) { spans.current.forEach(s => s && settle(s)); return; }

    const total = Math.max(MIN, ELEMENT + (chars.length + EXTRA) * DELAY);
    const translateMax = Math.min(12, fontPx * 0.35);   // (1-p) * min(12, glyphH*0.35)
    const blurMax = Math.max(1, fontPx / 18);            // (1-p) * max(1, glyphH/18)
    const start = performance.now();
    let raf = 0;

    const frame = () => {
      const elapsed = Math.min((performance.now() - start) / 1000, total);
      chars.forEach((_, i) => {
        const s = spans.current[i]; if (!s) return;
        const st = Math.max(0, Math.min(elapsed - i * DELAY, ELEMENT));
        const p = st / ELEMENT;
        if (p < 1) {
          const a = ACCENTS[i % ACCENTS.length];
          const b = ACCENTS[(i + 1) % ACCENTS.length];
          s.style.opacity = String(easeOut(p));
          s.style.transform = `translateY(${(1 - p) * translateMax}px)`;
          s.style.filter = `blur(${(1 - p) * blurMax}px) brightness(${1 + (1 - p) * 0.08})`;
          s.style.backgroundImage = `linear-gradient(135deg, ${a}, ${b})`;   // topLeft→bottomRight
          (s.style as any).webkitBackgroundClip = "text";
          s.style.backgroundClip = "text";
          s.style.color = "transparent";
        } else {
          settle(s);
        }
      });
      if (elapsed < total) raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  }, [text, restColor, fontPx, reduced]);

  return (
    <span aria-label={text} style={{ fontSize: fontPx, display: "inline-block", whiteSpace: "pre" }}>
      {chars.map((c, i) => (
        <span
          key={i}
          aria-hidden
          ref={el => { spans.current[i] = el; }}
          style={{ display: "inline-block", willChange: "transform, filter, opacity" }}
        >
          {c}
        </span>
      ))}
    </span>
  );
}
```

Re-run the reveal by changing the `text` prop (mounting/keying it). It's one-shot: the loop stops
once `elapsed ≥ total`, leaving the settled styles.

---

## 4. Tuning constants (Swift → JS map)

| Meaning | App value | JS |
|---|---|---|
| Per-glyph reveal | `elementDuration = 0.28` | `ELEMENT` |
| Stagger between glyphs | `perElementDelay = 0.016` | `DELAY` |
| Duration floor | `minDuration = 1.0` | `MIN` |
| Extra slices in total | `extraSlices = 12` | `EXTRA` |
| Total | `max(min, element + (count+extra)*delay)` | `total` |
| Opacity | `easeOut(progress)` | `easeOut(p)` |
| Rise | `(1-p) * min(12, glyphH*0.35)` | `translateMax` |
| Blur | `(1-p) * max(1, glyphH/18)` | `blurMax` |
| Brighten | `+(1-p)*0.08` | `brightness(1 + (1-p)*0.08)` |
| Glyph fill | gradient `accent[i]`→`accent[i+1]`, TL→BR | `linear-gradient(135deg, a, b)` |
| Settled colour | `settledOpacity` @ text colour | `restColor` |

Accent colours come from `Theme.accentGradientColors` — Apple system colours, approximated above;
swap for your brand palette (`docs/brand/brand-positioning.md`).

---

## 5. Performance & polish

- **Mutate refs, not state**, in the rAF loop; one loop, cancel on unmount.
- **`prefers-reduced-motion`** → render the settled text immediately, no loop.
- **Pause offscreen** with an `IntersectionObserver` if the text is below the fold.
- `background-clip: text` needs the `-webkit-` prefix in some browsers (included above).
- **Optional "thinking" shimmer** (the app's `AccentShimmerText`, shown while a title regenerates):
  before the reveal, loop a leftward-drifting accent gradient over the masked text —
  `background: linear-gradient(90deg, ...accents, ...accents)` sized 2× width, animate
  `background-position` leftward on a ~1.6s loop — then hand off to the reveal.

---

*Recreates the app's title reveal on the web. Keep it calm — glyphs ease in, they don't bounce.*
