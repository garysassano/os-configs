"""Shared generator for Cloudflare architecture diagrams.

Every diagram built through this module gets the same palette, type, geometry
and boundary treatment, so a set of repos reads as one family.

SVG units are arbitrary, so nothing here is a pixel measurement. What decides
legibility is the *ratio* of type size to canvas width, because a README scales
the whole image down to its content column. Keep the base label near TYPE_RATIO
of the width and it survives that scaling at any render size.

The other lever is aspect ratio. A long chain in a single row becomes a thin
strip that shrinks to nothing in a narrow viewport, so once a flow is long
enough the layout wraps onto several rows and uses both dimensions. TARGET_W is
a preferred width, not a cap: wrapping, not clamping, is what keeps a large
diagram readable.
"""

from __future__ import annotations

import pathlib
import re

ICONS = pathlib.Path(__file__).parent / "icons"

# ---------------------------------------------------------------- standard --
TARGET_W = 960        # preferred canvas width, not a cap
MAX_ASPECT = 4.0      # past this a diagram reads as a strip in a narrow viewport
MIN_NW = 132          # below this a node box cannot hold a service name
TYPE_RATIO = 0.013    # base label size as a fraction of canvas width
NH_BADGED = 174       # node box height when any node carries a badge
NH_PLAIN = 148        # ...and when none does, so boxes are not 40% empty
ROW_GAP = 56          # vertical space between wrapped rows
ICON_PX = 48          # service icon; it carries the meaning, so it leads
LOCKUP_W = 84         # provenance mark, deliberately quieter than the icons
PAD_X, PAD_TOP, PAD_BOT = 20, 44, 22   # boundary padding; top holds the lockup
MARGIN = 20
PAD = 24              # uniform space between the drawn content and every edge
ENTRY = 96            # room for an entry arrow AND its label clear of the boundary
ENTRY_INSET = 16      # extra breathing room so an entry label is not crowding the edge

FONT_SANS = ("'Inter Variable', 'Inter', system-ui, -apple-system, "
             "'Segoe UI', Roboto, sans-serif")
FONT_MONO = ("'JetBrains Mono Variable', 'JetBrains Mono', ui-monospace, "
             "'Cascadia Code', 'Source Code Pro', Menlo, Consolas, monospace")
TITLE_PX, SUB_PX, LABEL_PX, LABELSUB_PX, BADGE_PX = 15, 11, 12.5, 10.5, 11
ANNOT_PX = 11         # captions on annotation bands: one rank below LABEL_PX,
                      # same size and weight for every one of them
BRANCH_SCALE = 0.8    # off-path cards are drawn smaller: they are secondary
NODE_PAD = 16         # clear space each side of text inside a node box
GAP_CLEAR = 18        # clear space each side of a label sitting in a gap

# Aerospace Orange is mode invariant. Verified on cloudflare.com, where
# #ff5e1f appears 122 times against two uses of the older #f6821f.
THEMES = {
    "light": dict(PAGE="#FFFFFF", SURFACE="#FFFFFF", INK="#262626", MUTE="#6E6763",
                  LINE="#E6E1DF", CF="#FF5E1F", OK="#1A7F52", EXT="#262626", BADGE_OP="0.12"),
    "dark":  dict(PAGE="#151414", SURFACE="#1E1B1A", INK="#F0E3DE", MUTE="#B5AAA4",
                  LINE="#3A3431", CF="#FF5E1F", OK="#5FC98F", EXT="#F0E3DE", BADGE_OP="0.22"),
}


def _raw(name):    return (ICONS / f"{name}.svg").read_text()
def _inner(name):  return re.sub(r"</svg>$", "", re.sub(r"^<svg[^>]*>", "", _raw(name).strip())).strip()


def _viewbox(name):
    m = re.search(r'viewBox="([-\d.]+) ([-\d.]+) ([\d.]+) ([\d.]+)"', _raw(name))
    return (float(m.group(3)), float(m.group(4))) if m else (48.0, 48.0)


def esc(t): return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def tw(text, size, mono=False):
    """Estimated advance width. Monospace ~0.6em per character, Inter ~0.55em."""
    return len(text) * size * (0.6 if mono else 0.55)


def widest(items, size, mono=False):
    return max((tw(t, size, mono) for t in items if t), default=0.0)


class Flow:
    """A labelled arrow, declared up front so geometry can be sized from it."""

    def __init__(self, i, j, label=None, sub=None):
        self.i, self.j = i, j
        self.label = [] if label is None else ([label] if isinstance(label, str) else list(label))
        self.sub = [] if sub is None else ([sub] if isinstance(sub, str) else list(sub))

    def width(self):
        return max(widest(self.label, LABEL_PX), widest(self.sub, LABELSUB_PX, mono=True))


SUB_MAX_W = 132       # a resource name wider than this wraps on its hyphens


def wrap_sub(text):
    """Split a long resource name across lines on its hyphens, rather than
    letting one inline string dictate the node width."""
    if not text or tw(text, SUB_PX, mono=True) <= SUB_MAX_W:
        return [text] if text else []
    parts, lines, cur = text.split("-"), [], ""
    for k, part in enumerate(parts):
        piece = part if not cur else cur + "-" + part
        if tw(piece + ("-" if k < len(parts) - 1 else ""), SUB_PX, mono=True) <= SUB_MAX_W or not cur:
            cur = piece
        else:
            lines.append(cur + "-")
            cur = part
    lines.append(cur)
    return lines


class Node:
    def __init__(self, key, icon, title, sub=None, badge=None, badge_kind="ink",
                 inside=True, dashed=False, external=False, card=True):
        self.key, self.icon, self.title, self.sub = key, icon, title, sub
        self.sublines = wrap_sub(sub)
        self.badge, self.badge_kind = badge, badge_kind
        self.inside, self.dashed, self.external = inside, dashed, external
        self.card = card


class Diagram:
    """Geometry is derived from content, never the other way round.

    Type sizes are fixed constants. Node widths, gaps and box height are then
    computed so every label fits at its standard size. The old approach picked
    the geometry first and shrank text that did not fit, which produced a dozen
    different font sizes across two diagrams and no standard at all.
    """

    NW_MIN, GAP_MIN = 120, 64

    def __init__(self, nodes, flows=(), theme="light", boundary_note=None, per_row=None,
                 band_top=0, band_bot=0):
        self.nodes, self.flows = nodes, list(flows)
        self.T, self.boundary_note = THEMES[theme], boundary_note
        self.band_top, self.band_bot = band_top, band_bot
        n = len(nodes)

        # ---- node box sized to its widest line ----------------------------
        carded = [nd for nd in nodes if nd.card] or nodes
        self.nw = max(self.NW_MIN, max(
            max(tw(nd.title, TITLE_PX),
                widest(nd.sublines, SUB_PX, mono=True),
                tw(nd.badge or "", BADGE_PX, mono=True) + 18)
            for nd in carded) + 2 * NODE_PAD)

        # ---- box height sized to the tallest stack ------------------------
        self.sub_rows = max((len(nd.sublines) for nd in nodes), default=0)
        bottom = 102.0
        if self.sub_rows:
            bottom = 121 + 14 * (self.sub_rows - 1)
        self.badge_y = None
        if any(nd.badge for nd in nodes):
            self.badge_y = bottom + 10
            bottom = self.badge_y + 19
        self.content_bottom = bottom
        self.nh = bottom + 22

        # ---- gap sized to the widest label that sits in it ----------------
        inside_set = {i for i, nd in enumerate(nodes) if nd.inside}
        need = self.GAP_MIN
        for f in self.flows:
            straddles = (f.i in inside_set) != (f.j in inside_set)
            need = max(need, f.width() + 2 * GAP_CLEAR + (PAD_X if straddles else 0))
        self.gap = need

        if per_row is None:
            rows = 1
            while rows < n:
                pr = -(-n // rows)
                w = 2 * MARGIN + 2 * PAD_X + pr * self.nw + (pr - 1) * self.gap
                h = (2 * MARGIN + PAD_TOP + band_top + rows * self.nh
                     + (rows - 1) * ROW_GAP + band_bot + PAD_BOT)
                if w / h <= MAX_ASPECT:
                    break
                rows += 1
            per_row = -(-n // rows)
        self.per_row, self.rows = per_row, -(-n // per_row)

        x0 = MARGIN + PAD_X
        self.ny = MARGIN + PAD_TOP + band_top
        self.cx, self.cy = [], []
        for i in range(n):
            r, c = divmod(i, per_row)
            self.cx.append(x0 + self.nw / 2 + c * (self.nw + self.gap))
            self.cy.append(self.ny + r * (self.nh + ROW_GAP))
        self.bx0 = self.bx1 = None
        import hashlib
        seed = theme + "|" + "|".join(nd.key for nd in nodes)
        self.uid = hashlib.sha1(seed.encode()).hexdigest()[:6]
        self.parts = []
        self.ex = [float("inf"), float("inf"), float("-inf"), float("-inf")]

    # ------------------------------------------------------------ drawing --
    def _mark(self, x0, y0, x1, y1):
        e = self.ex
        e[0], e[1] = min(e[0], x0), min(e[1], y0)
        e[2], e[3] = max(e[2], x1), max(e[3], y1)

    def text(self, x, y, t, size, fill, weight="400", mono=False, anchor="middle"):
        w = tw(t, size, mono)
        x0 = x if anchor == "start" else (x - w if anchor == "end" else x - w / 2)
        self._mark(x0, y - size * 0.82, x0 + w, y + size * 0.24)
        return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="{FONT_MONO if mono else FONT_SANS}" '
                f'font-size="{size}" fill="{fill}" font-weight="{weight}" '
                f'text-anchor="{anchor}">{esc(t)}</text>')

    def icon(self, name, cx, cy, size, colour):
        w, h = _viewbox(name)
        sc = size / max(w, h)
        # Some official icons carry fill="currentColor" on their paths. That
        # resolves from CSS `color`, not from a parent fill attribute, so the
        # group fill never reaches them and they render as the default. Bake
        # the colour in instead of relying on inheritance.
        inner = _inner(name).replace("currentColor", colour)
        self._mark(cx - w * sc / 2, cy - h * sc / 2, cx + w * sc / 2, cy + h * sc / 2)
        return (f'<g transform="translate({cx-w*sc/2:.1f},{cy-h*sc/2:.1f}) scale({sc:.4f})" '
                f'fill="{colour}">{inner}</g>')

    def lockup(self, cx, cy, width=LOCKUP_W):
        inner = _inner("cf-lockup")
        for gid in re.findall(r'id="([^"]+)"', inner):
            inner = inner.replace(f'id="{gid}"', f'id="cf-{gid}"').replace(f'url(#{gid})', f'url(#cf-{gid})')
        inner = (inner.replace('fill="#F6821F"', f'fill="{self.T["CF"]}"')
                 .replace('fill="#000"', f'fill="{self.T["INK"]}"').replace('fill="#fff"', 'fill="none"'))
        sc = width / 231.91
        self._mark(cx - width / 2, cy - 33.9 * sc / 2, cx + width / 2, cy + 33.9 * sc / 2)
        return (f'<g transform="translate({cx-width/2:.1f},{cy-33.9*sc/2:.1f}) '
                f'scale({sc:.5f}) translate(-0.09,-3.013)">{inner}</g>')

    def render(self):
        T, p = self.T, []
        ins = [i for i, nd in enumerate(self.nodes) if nd.inside]
        if ins:
            self.bx0 = min(self.cx[i] for i in ins) - self.nw / 2 - PAD_X
            self.bx1 = max(self.cx[i] for i in ins) + self.nw / 2 + PAD_X
            by0 = min(self.cy[i] for i in ins) - PAD_TOP - self.band_top
            by1 = max(self.cy[i] for i in ins) + self.nh + self.band_bot + PAD_BOT
            self._mark(self.bx0, by0, self.bx1, by1)
            p.append(f'<rect x="{self.bx0:.1f}" y="{by0:.1f}" width="{self.bx1-self.bx0:.1f}" '
                     f'height="{by1-by0:.1f}" rx="4" fill="none" stroke="{T["CF"]}" stroke-width="1.2"/>')
            p.append(self.lockup(self.bx0 + 14 + LOCKUP_W / 2, by0 + 20))
            if self.boundary_note:
                p.append(self.text(self.bx1 - 14, by0 + 24, self.boundary_note, ANNOT_PX, T["MUTE"], anchor="end"))

        for nd, cx, ny in zip(self.nodes, self.cx, self.cy):
            if nd.card:
                stroke = T["CF"] if nd.dashed else T["LINE"]
                dash = ' stroke-dasharray="5 4"' if nd.dashed else ""
                self._mark(cx - self.nw / 2, ny, cx + self.nw / 2, ny + self.nh)
                p.append(f'<rect x="{cx-self.nw/2:.1f}" y="{ny:.1f}" width="{self.nw:.1f}" '
                         f'height="{self.nh:.1f}" rx="12" fill="{T["SURFACE"]}" stroke="{stroke}" '
                         f'stroke-width="1.2"{dash}/>')
            # Centre each node's own content in the shared box height. A node
            # with fewer sub-lines than the tallest would otherwise sit high
            # with dead space beneath it.
            if nd.badge:
                nb = self.badge_y + 19
            elif nd.sublines:
                nb = 121 + 14 * (len(nd.sublines) - 1)
            else:
                nb = 102
            dy = (self.content_bottom - nb) / 2
            p.append(self.icon(nd.icon, cx, ny + 46 + dy, ICON_PX, T["EXT"] if nd.external else T["CF"]))
            p.append(self.text(cx, ny + 102 + dy, nd.title, TITLE_PX, T["INK"], "600"))
            for k, line in enumerate(nd.sublines):
                p.append(self.text(cx, ny + 121 + 14 * k + dy, line, SUB_PX, T["MUTE"], mono=True))
            if nd.badge:
                fill = {"ink": T["INK"], "cf": T["CF"], "ok": T["OK"]}[nd.badge_kind]
                bw = tw(nd.badge, BADGE_PX, mono=True) + 18
                p.append(f'<rect x="{cx-bw/2:.1f}" y="{ny+self.badge_y:.1f}" width="{bw:.1f}" '
                         f'height="19" rx="9.5" fill="{fill}" opacity="{T["BADGE_OP"]}"/>')
                p.append(self.text(cx, ny + self.badge_y + 13.5, nd.badge, BADGE_PX, fill, "600", mono=True))
        self.parts = p
        for f in self.flows:
            self._flow(f)
        return self

    def _flow(self, f):
        T = self.T
        if self.cy[f.i] != self.cy[f.j]:
            return self._wrap(f)
        y = self.cy[f.i] + self.nh / 2
        x1, x2 = self.cx[f.i] + self.nw / 2, self.cx[f.j] - self.nw / 2
        head = 7 * 1.6
        self._mark(x1, y - 1, x2, y + 1)
        self.parts.append(f'<line x1="{x1:.1f}" y1="{y:.1f}" x2="{x2-head:.1f}" y2="{y:.1f}" '
                          f'stroke="{T["INK"]}" stroke-width="1.6" marker-end="url(#ar-{self.uid})"/>')
        # Centre the label on the stretch clear of the boundary rule, so a flow
        # entering or leaving the boundary never prints across it.
        inside = {i for i, nd in enumerate(self.nodes) if nd.inside}
        lo, hi = x1, x2
        if self.bx0 is not None:
            if f.i not in inside and f.j in inside:
                hi = self.bx0
            elif f.i in inside and f.j not in inside:
                lo = self.bx1
        cx = (lo + hi) / 2
        if f.label:
            top = y - 9 - (LABEL_PX + 1) * (len(f.label) - 1)
            self.parts += [self.text(cx, top + (LABEL_PX + 1) * k, ln, LABEL_PX, T["INK"], "600")
                           for k, ln in enumerate(f.label)]
        if f.sub:
            self.parts += [self.text(cx, y + 15 + (LABELSUB_PX + 1) * k, ln, LABELSUB_PX,
                                     T["MUTE"], mono=True)
                           for k, ln in enumerate(f.sub)]

    def _wrap(self, f):
        T = self.T
        y1 = self.cy[f.i] + self.nh
        midy = (y1 + self.cy[f.j]) / 2
        d = (f'M{self.cx[f.i]:.1f} {y1:.1f} L{self.cx[f.i]:.1f} {midy:.1f} '
             f'L{self.cx[f.j]:.1f} {midy:.1f} L{self.cx[f.j]:.1f} {self.cy[f.j]-11.2:.1f}')
        self._mark(min(self.cx[f.i], self.cx[f.j]), min(y1, self.cy[f.j]),
                   max(self.cx[f.i], self.cx[f.j]), max(y1, self.cy[f.j]))
        self.parts.append(f'<path d="{d}" fill="none" stroke="{T["INK"]}" stroke-width="1.6" '
                          f'marker-end="url(#ar-{self.uid})"/>')
        if f.label:
            self.parts.append(self.text((self.cx[f.i] + self.cx[f.j]) / 2, midy - 7,
                                        f.label[0], LABEL_PX, T["INK"], "600"))

    def finish(self):
        """Emit the SVG last, so the viewBox can hug the ink with one uniform
        pad on all four edges."""
        T = self.T
        x0, y0, x1, y1 = self.ex
        vx, vy = x0 - PAD, y0 - PAD
        vw, vh = (x1 - x0) + 2 * PAD, (y1 - y0) + 2 * PAD
        self.W, self.H = vw, vh
        head = [
            '<?xml version="1.0" encoding="UTF-8"?>',
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{vw:.0f}" height="{vh:.0f}" '
            f'viewBox="{vx:.1f} {vy:.1f} {vw:.1f} {vh:.1f}" style="background:{T["PAGE"]}" role="img">',
            '<defs>'
            f'<marker id="ar-{self.uid}" viewBox="0 0 10 10" refX="0" refY="5" markerWidth="7" '
            f'markerHeight="7" orient="auto-start-reverse">'
            f'<path d="M0 0 10 5 0 10z" fill="{T["INK"]}"/></marker>'
            f'<marker id="ok-{self.uid}" viewBox="0 0 10 10" refX="0" refY="5" markerWidth="7" '
            f'markerHeight="7" orient="auto-start-reverse">'
            f'<path d="M0 0 10 5 0 10z" fill="{T["OK"]}"/></marker></defs>',
            f'<rect x="{vx:.1f}" y="{vy:.1f}" width="{vw:.1f}" height="{vh:.1f}" fill="{T["PAGE"]}"/>',
        ]
        return "\n".join(head + self.parts + ["</svg>"])
