---
name: cloudflare-diagrams
description: Build architecture diagrams for Cloudflare projects to one shared standard, using the official product icons, the current brand palette and a common generator, so every repo's diagram looks like part of the same set. Also covers Mermaid fences that must render on GitHub. Use when adding, refreshing or reviewing a diagram in a Cloudflare repo (Workers, Durable Objects, Queues, R2, KV, D1, Workers Cache), or when a README needs Mermaid.
---

# Cloudflare Diagrams

There is one generator, `assets/cfdiagram.py`. Use it. Hand rolling a second one is how a set of repos ends up with five different looks, which is the problem this skill exists to prevent.

## Before anything else

**Render the existing diagram and look at it.** Reading its text labels is not looking at it. An existing diagram encodes conventions (canvas shape, boundary, logo placement, icon treatment) that are invisible in its markup, and replacing it without seeing it throws those away.

**Check the palette from source.** Cloudflare changed its brand orange, so any older asset carries the stale value:

```sh
gh api repos/cloudflare/cloudflare-docs/contents/src/styles/globals.css --jq '.content' \
  | base64 -d | grep -iE 'nb-primary:|accent-100|foreground-100|nb-font'
```

## The standard

Encoded in `assets/cfdiagram.py`; these are the decisions behind it.

| | |
| --- | --- |
| Brand | `#FF5E1F` Aerospace Orange, mode invariant. `#F6821F` is the **old** value, still baked into draw.io shape libraries. |
| Light | page/surface `#FFFFFF`, ink `#262626`, muted `#6E6763`, line `#E6E1DF` |
| Dark | page `#151414`, surface `#1E1B1A`, ink `#F0E3DE`, muted `#B5AAA4`, line `#3A3431` |
| Type | Inter for names and labels, JetBrains Mono for identifiers. Cloudflare's own stacks, from `globals.css`. |
| Boundary | Encloses exactly what runs on Cloudflare. Solid 1.2 rule in brand orange, `rx=4`, no fill, lockup inset **inside** the top left corner. |
| Icons | Service icons at 48, lockup at 84. The service icons carry the meaning, so they lead; the lockup is provenance and stays quieter. |

### What the boundary means

The boundary encloses **what runs on Cloudflare**. That is the whole test, and it is about where code executes, not about who owns it, who deployed it, or whether it is trusted.

So the question is: **does this execute on Cloudflare's network?** A Worker, a queue, a bucket, a KV namespace, a Durable Object: inside. A third-party API, a user's browser, a service on another cloud, a script on someone's laptop: outside, and `external=True` too, so its icon is ink rather than brand orange.

Two traps, both of which put a Cloudflare resource wrongly outside:

- **Ownership is not the test.** A caller the repo does not provision can still be a Worker. If it runs on Cloudflare it is inside, in brand colour, even though `cdktn deploy` never creates it.
- **Trust is not the test.** A gatekeeper's untrusted caller sits inside if it is a Worker; a fully trusted first-party backend sits outside if it runs elsewhere.

Read the call mechanism to decide, rather than the label on the box. RPC against a `WorkerEntrypoint` (`env.SVC.method()`) only resolves over a service binding or `ctx.exports`, so **a caller making RPC calls is necessarily itself a Worker, and belongs inside**. A caller arriving over plain HTTP to a route or a `workers.dev` subdomain could be anything, and usually belongs outside.

Getting this wrong is quiet. Nothing overlaps and no label overflows; the picture just puts a service on the wrong side.

### Geometry follows content, never the reverse

Type sizes are **fixed constants**: `TITLE_PX` 15, `LABEL_PX` 12.5, `SUB_PX` 11, `LABELSUB_PX` 10.5, `ANNOT_PX` 11. Nothing is ever shrunk to fit. Instead node width, gap and box height are computed so every label fits at its standard size, which is why `Flow` objects are declared up front alongside the nodes.

The earlier approach did the opposite: pick geometry, then shrink text that overflowed. That produced nine different font sizes across two diagrams (`9.09`, `9.28`, `9.67`, `9.74`, `12.12`…) and no standard at all. If a label genuinely will not fit, shorten the label or wrap it, do not scale it.

A long resource name wraps on its hyphens (`event-notification-` / `queue`) rather than forcing a wide box. A node's sub-line carries a **resource name**, not a restatement of the service. `Browser Run` needs no `BROWSER binding` underneath it; `R2` needs `upload-bucket` because a second card also says `R2`. Keep a resource name only where it disambiguates: two cards both labelled `R2` need `upload-bucket` and `log-bucket`; a lone queue does not need its name to be understood, but dropping it only there reads as arbitrary.

A flow crossing the boundary centres its label on the stretch clear of the rule, so it never prints across it.

Each arrow carries at most two lines and they are deliberately different: the label is ink at `LABEL_PX` bold, the sub is muted mono at `LABELSUB_PX`. The label says what the hop *is*, the sub says how it is *configured* or *called*. Same pairing in every diagram, so a reader learns it once.

### Sizing is a ratio, not a pixel count

SVG units are arbitrary. What decides legibility is type size **relative to canvas width**, because a README scales the image down to its content column, roughly 830px. A 12.5 label on a 960 canvas survives that; the same label on a 1400 canvas lands at 7px.

`TYPE_RATIO = 0.013` is the base label as a fraction of width. `TARGET_W = 960` is a preferred width, **not a cap**: a diagram that genuinely needs more room may take it, as long as the ratio holds.

### Long chains wrap

A long flow in one row becomes a strip that shrinks to nothing in a narrow viewport. Past `MAX_ASPECT = 4.0`, or once node width would fall under `MIN_NW = 132`, the layout wraps onto balanced rows and uses both dimensions. Four services stay in a row; five or more wrap. `_wrap()` draws the connector across the break.

Pin `per_row` only when the row order carries meaning that wrapping would break, such as an annotation arc spanning several nodes.

### Annotation bands

Paths that run above or below the row (a cache hit returning, a purge going back) need reserved space, or they collide with the lockup or the boundary edge. Pass `band_top` / `band_bot`; the boundary grows to include them.

## Using it

```python
import pathlib, sys; sys.path.insert(0, "<skill>/assets")
from cfdiagram import Diagram, Flow, Node

nodes = [
    Node("src", "r2", "R2", "upload-bucket"),
    Node("q", "queues", "Queues", "event-notification-queue"),
    Node("w", "workers", "Workers", "event-notification-writer", badge="cache: on", badge_kind="ok"),
]
flows = [                                    # declared up front: geometry is sized from them
    Flow(0, 1, ["event", "notification"]),
    Flow(1, 2, "consumes", "100 / 5s"),
]
d = Diagram(nodes, flows, theme, boundary_note="optional note").render()
d.entry(0, "PutObject", "s3:ObjectCreated")  # a caller that is not drawn as a card
pathlib.Path(out).write_text(d.finish())
```

`Flow(i, j, label, sub)` takes **node indices**, and flows go to the constructor rather than being added afterwards, because node width and gap are computed to fit the labels. `d.entry(idx, label, sub)` draws an arrow in from off canvas.

`Node(inside=False)` puts a node outside the boundary; `external=True` colours its icon as ink rather than brand orange, for non-Cloudflare services. The two travel together: anything that is not a Cloudflare resource takes both.

**Short titles, long identifiers underneath.** The title is the service (`R2`, `Queues`); the mono sub-line is the resource (`event-notification-queue`). Long titles force wide boxes, which starve the gaps, which makes arrow labels bleed into the boxes. Stack a long arrow label onto two lines rather than widening the gap.

## Verify before committing

Render **both themes** and look at them, at the width a README actually uses:

```sh
node -e "const {Resvg}=require('@resvg/resvg-js'),fs=require('fs');
const r=new Resvg(fs.readFileSync('arch-diagram.svg','utf8'),{fitTo:{mode:'width',value:830},font:{loadSystemFonts:true}});
fs.writeFileSync('out.png',r.render().asPng());"
```

**Install the fonts first,** or the render lies to you. Without Inter and JetBrains Mono present, resvg silently substitutes and you review a picture nobody else will see.

**Render any HTML page you publish, too.** A review page that shows the diagrams in half width panels clips them, and you will be told the diagrams are broken when the page is. Headless Chromium via `playwright-core` screenshots a `file://` page, and the same script can assert nothing overflows:

```js
const clipped = await page.evaluate(() => [...document.querySelectorAll(".proof__stage")]
  .map(el => ({ scroll: el.scrollWidth, client: el.clientWidth }))
  .filter(o => o.scroll > o.client + 1));
```

Recurring defects, all seen in practice:

- Arrow labels bleeding into the box they point at. A gap of N units fits roughly `N / 6` characters at 9.5 mono.
- Arrowheads floating short of their target.
- An entry label centred on a short outside segment and running off the canvas.
- An annotation path crossing the lockup or sitting on the boundary rule.
- Arrows in one diagram a different colour from arrows in another. Semantic colour is for semantics (a hit path, an error path); everything else takes ink. Dashing already distinguishes a secondary flow, so it does not also need a dimmer colour.
- Muted text too dark on dark. Check the small mono sub-lines specifically.
- Node boxes with dead space at the bottom. Box height must follow content: a badge row only earns its space when a node has one.
- An entry arrow shorter than its own arrowhead. Draw it with `d.entry(idx, label, sub)`, which reserves `ENTRY` from the boundary edge; keying it off whether the first node sits outside the boundary is wrong, since every node can be inside and still take an arrow from off canvas.
- The stroke poking past the arrowhead's tip. Anchor the head by its **base** (`refX="0"`) and stop the line `markerWidth * stroke-width` short of the target. With the tip on the line end, the non-tapering stroke shows past the point where the triangle gets thinner than it.
- Duplicate marker ids. Two of these SVGs inlined in one HTML document both defining `id="ar"` means `url(#ar)` resolves to whichever came first, so the dark diagram silently borrows the light one's black arrowhead. Hash the ids per file.
- Arrowheads that point right no matter which way the line runs, **in the PNG preview only**. resvg does not honour `orient="auto-start-reverse"` and leaves the marker unrotated, so every horizontal arrow looks right and every vertical one lies. Browsers render it correctly, so the committed SVG is fine and only the verification step is wrong, which is worse: the check exists to catch bad arrowheads. The generator uses `orient="auto"`, identical for `marker-end` and honoured everywhere. Do not reintroduce `auto-start-reverse` unless a `marker-start` is added.
- Wrapping a diagram that has nodes outside the boundary. The boundary is one rect spanning the full column range of the inside nodes, so on a wrapped layout it encloses whatever sits at those columns on other rows, swallowing the outside nodes. Outside nodes only work at the ends of a single row: pin `per_row` and shorten labels to control width instead.
- A long resource name running past its card edge. `fit()` shrinks a label to stay inside, but check it, since the advance width is estimated.

Then confirm no light value leaked into the dark file. Equal file sizes prove nothing, since hex codes are all the same length:

```sh
grep -o '#[0-9A-Fa-f]\{6\}' arch-diagram-dark.svg | sort -u
```

## Mermaid

Validate every fence before committing; `mermaid.parse` runs headless under jsdom:

```js
import { JSDOM } from "jsdom";
const dom = new JSDOM("<!doctype html><html><body></body></html>", { pretendToBeVisual: true });
for (const k of ["window","document","navigator","Element","SVGElement","HTMLElement","getComputedStyle","MutationObserver","requestAnimationFrame"])
  if (globalThis[k] === undefined && dom.window[k] !== undefined) globalThis[k] = dom.window[k];
const mermaid = (await import("mermaid")).default;
mermaid.initialize({ startOnLoad: false });
for (const [, code] of md.matchAll(/```mermaid\n([\s\S]*?)```/g)) await mermaid.parse(code);
```

**Never hardcode a colour in a fence.** GitHub themes Mermaid to the reader's setting but only themes text and default shapes. A `rect rgb(...)`, a `style ... fill:`, or a `classDef` paints a fixed background that the other theme's text then sits on invisibly. Label a phase with `Note over A,B:` instead of shading it. Check with `grep -n 'rect rgb\|style .*fill:\|classDef'`.

Prefer the SVG for static topology and Mermaid for behaviour over time, rather than drawing the same picture twice.

## Repo placement

- `src/assets/arch-diagram.svg` and `src/assets/arch-diagram-dark.svg`.
- Under a `## Architecture Diagram` heading, via `<picture>` so GitHub picks the variant. Do **not** use `prefers-color-scheme` inside the SVG: GitHub's camo proxy caches one rendition, so it never tracks the reader's theme.

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./src/assets/arch-diagram-dark.svg">
  <img alt="Architecture Diagram" src="./src/assets/arch-diagram.svg">
</picture>
```

- Add `"!src/assets"` to `files.includes` in `biome.jsonc`, or Biome tries to parse the asset.
- No title or subtitle inside the diagram: the README heading already says what it is.
- No attribution strip on the image.
- No em dashes in any diagram text. See [[no-em-dashes]].
- **Uneven padding around the image.** Everything drawn must sit the same distance from all four edges. Sizing the canvas up front cannot achieve that, because the true extents are only known once everything is drawn: text width, an entry arrow starting left of the boundary, a lockup, an annotation band. Track ink extents on every draw call and emit the SVG header last, with `viewBox` hugging the content plus one uniform `PAD`. Verify by pixel scan, not by arithmetic:
  ```python
  ic = lambda x: any(max(abs(px[x,y][i]-bg[i]) for i in range(3))>12 for y in range(H))
  left = next(x for x in range(W) if ic(x)); right = next(x for x in range(W-1,-1,-1) if ic(x))
  ```
- Lopsided canvas padding. A boundary that wraps one end of the row but not the other juts `PAD_X` past the first node while the last node sits bare, so the right margin ends up double the left. Size the canvas to the real drawn extents, and remember an entry arrow starts at `MARGIN`, left of the boundary, so it counts even though it is not a rect.
- Text too small once a README scales it. Rendered size is `font_units * (container / canvas)`, and the column is roughly 1040px, so a 1200 canvas renders at 87%. The canvas cannot shrink without starving the boxes, so raise the type scale: the boxes carry slack.
- Type size chosen to fill available space rather than to encode rank. Annotations are commentary one level below the flow labels; sizing them up because there is room makes them compete with what they annotate.
- Flattening a real hierarchy in the name of consistency. Two annotations are not automatically the same rank: a diagram's central claim can carry weight that a footnote does not. Match size across captions, but let weight mark what actually matters.
- A band sized by what looked about right, leaving the card in it a different distance from the boundary than the row cards get at the sides. Derive `band_bot` from the clearance it must leave: `connector + card_height + PAD_X - PAD_BOT`. The top strip is the one deliberate exception, since it holds the lockup.
- An off-path card sized by an arbitrary number. A service the main flow only consults, rather than passes through, is legitimately secondary and is drawn at `BRANCH_SCALE` of the row height. Make that the rule, not a literal in one build script: construct the Diagram once to read `nh`, scale it, reserve `band_bot`, and centre the icon and title in the smaller box.
- Node content sitting high with dead space beneath it. Every node centres its own content within the shared box height, so a card with no sub-line does not look top-heavy next to one that has two.
- Annotation captions at different sizes from each other. Every caption on an annotation band uses `ANNOT_PX`, so a hit path and a purge path read as the same class of note. Hardcoding a size per caption is how they drift.
- A two-line label rendering at two sizes, because `fit()` was applied per line. Size a multi-line label once, at the smallest any of its lines needs.
- Reserving entry-arrow space just because the first node sits outside the boundary. A leading actor node is outside and needs no reservation; key it on whether an entry arrow is actually drawn.
- Badges carry one category only. `cache: on` against `cache: off` is per-entrypoint configuration; plan availability or pricing is a different kind of fact and putting it on the same device makes both read as noise. That belongs in prose.
- A caller placed by ownership rather than by where it runs. Check how it calls in: an RPC caller is a Worker and belongs inside even when this repo does not deploy it, while a browser or a third-party service belongs outside.
- No generic actor or user shape. Cloudflare ships no official user icon, and importing one from another set puts a foreign glyph beside official product icons. Name the action on the entry arrow instead.
