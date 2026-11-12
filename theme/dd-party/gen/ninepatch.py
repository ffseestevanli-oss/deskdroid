"""Nine-slice frame pieces as SVG groups, shared by the Plasma style, the
Aurorae decoration and the Kvantum style.

A frame is drawn once as layers of polygons (the chamfered outline, the fill,
accent bands), then each layer is clipped by hand to the nine piece rects, so
every piece is plain geometry with an exact bounding box (no clip-path, which
Qt SVG handles poorly)."""
from palette import *

PARTS = ["topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright"]

DEFS = (
    '<linearGradient id="rbh" x1="0" y1="0" x2="1" y2="0">' + rainbow_stops() + '</linearGradient>'
    '<linearGradient id="rbv" x1="0" y1="0" x2="0" y2="1">' + rainbow_stops() + '</linearGradient>'
)


def clip(poly, x0, y0, x1, y1):
    """Sutherland-Hodgman against an axis-aligned rect."""
    def edge(pts, inside, inter):
        out = []
        for i in range(len(pts)):
            a, b = pts[i - 1], pts[i]
            ia, ib = inside(a), inside(b)
            if ib:
                if not ia:
                    out.append(inter(a, b))
                out.append(b)
            elif ia:
                out.append(inter(a, b))
        return out

    def ix(xv):
        return lambda a, b: (xv, a[1] + (b[1] - a[1]) * (xv - a[0]) / (b[0] - a[0]))

    def iy(yv):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (yv - a[1]) / (b[1] - a[1]), yv)

    p = poly
    for inside, inter in [
        (lambda q: q[0] >= x0, ix(x0)), (lambda q: q[0] <= x1, ix(x1)),
        (lambda q: q[1] >= y0, iy(y0)), (lambda q: q[1] <= y1, iy(y1)),
    ]:
        if not p:
            return []
        p = edge(p, inside, inter)
    return p


def chamfer_poly(x0, y0, x1, y1, tl=0, tr=0, br=0, bl=0):
    pts = []
    pts += [(x0, y0 + tl), (x0 + tl, y0)] if tl else [(x0, y0)]
    pts += [(x1 - tr, y0), (x1, y0 + tr)] if tr else [(x1, y0)]
    pts += [(x1, y1 - br), (x1 - br, y1)] if br else [(x1, y1)]
    pts += [(x0 + bl, y1), (x0, y1 - bl)] if bl else [(x0, y1)]
    return pts


def fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


class Frame:
    """borders = (left, top, right, bottom) piece sizes; cuts = chamfer sizes
    (tl, tr, br, bl); layers are added with fill()/border()/band()."""

    def __init__(self, borders, cuts=(0, 0, 0, 0), center=8, inset=(0, 0, 0, 0)):
        self.L, self.T, self.R, self.B = borders
        self.C = center
        self.W = self.L + self.C + self.R
        self.H = self.T + self.C + self.B
        self.cuts = cuts
        self.inset = inset  # outline drawn inset from the frame edge (shadow room)
        self.layers = []

    def outline(self, grow=0):
        il, it, ir, ib = self.inset
        tl, tr, br, bl = [max(0, c - grow * 0.414) if c else 0 for c in self.cuts]
        return chamfer_poly(il + grow, it + grow, self.W - ir - grow, self.H - ib - grow, tl, tr, br, bl)

    def add(self, poly, paint, opacity=1.0):
        self.layers.append((poly, paint, opacity))
        return self

    def solid(self, color, opacity=1.0):
        return self.add(self.outline(), color, opacity)

    def bordered(self, fill, border, bw=1.0, fill_opacity=1.0, border_opacity=1.0):
        if border:
            self.add(self.outline(), border, border_opacity)
        if fill:
            self.add(self.outline(bw if border else 0), fill, fill_opacity)
        return self

    def band(self, side, thickness, paint, opacity=1.0, inset=0.0):
        """An accent band along one side, inside the outline."""
        il, it, ir, ib = self.inset
        x0, y0, x1, y1 = il + inset, it + inset, self.W - ir - inset, self.H - ib - inset
        rect = {
            "top": (x0, y0, x1, y0 + thickness), "bottom": (x0, y1 - thickness, x1, y1),
            "left": (x0, y0, x0 + thickness, y1), "right": (x1 - thickness, y0, x1, y1),
        }[side]
        return self.add(clip(self.outline(inset), *rect), paint, opacity)

    def ring(self, color, bw=1.0, opacity=1.0):
        """Just the outline stroke, transparent inside (hover/focus overlays)."""
        outer = self.outline()
        inner = self.outline(bw)
        # even-odd ring as one path
        self.layers.append((("ring", outer, inner), color, opacity))
        return self

    def piece_rects(self):
        xs = [0, self.L, self.L + self.C, self.W]
        ys = [0, self.T, self.T + self.C, self.H]
        rects = {}
        for j in range(3):
            for i in range(3):
                rects[PARTS[j * 3 + i]] = (xs[i], ys[j], xs[i + 1], ys[j + 1], i, j)
        return rects

    def render(self, prefix, ox, oy, sep="-", parts=None, skip_empty_center=False):
        out = []
        for part, (x0, y0, x1, y1, col, row) in self.piece_rects().items():
            if parts and part not in parts:
                continue
            if x1 - x0 <= 0 or y1 - y0 <= 0:
                continue
            pid = (prefix + sep + part) if prefix else part
            g = [f'<g id="{pid}">',
                 f'<rect x="{fmt(ox + x0)}" y="{fmt(oy + y0)}" width="{fmt(x1 - x0)}" height="{fmt(y1 - y0)}" fill="#000000" fill-opacity="0.004"/>']
            for poly, paint, op in self.layers:
                g.append(self._layer(poly, paint, op, (x0, y0, x1, y1), col, row, ox, oy))
            g.append("</g>")
            out.append("".join(g))
        return "\n".join(out)

    def _paint(self, paint, col, row):
        if paint == "rainbow-h":
            return {0: RED, 2: PINK}.get(col, "url(#rbh)")
        if paint == "rainbow-v":
            return {0: RED, 2: PINK}.get(row, "url(#rbv)")
        return paint

    def _layer(self, poly, paint, op, rect, col, row, ox, oy):
        fill = self._paint(paint, col, row)
        if isinstance(poly, tuple) and poly and poly[0] == "ring":
            _, outer, inner = poly
            a = clip(outer, *rect)
            b = clip(inner, *rect)
            if not a:
                return ""
            d = path_d(a, ox, oy) + (path_d(b, ox, oy) if b else "")
            return f'<path d="{d}" fill="{fill}" fill-opacity="{op}" fill-rule="evenodd"/>'
        p = clip(poly, *rect)
        if len(p) < 3:
            return ""
        return f'<path d="{path_d(p, ox, oy)}" fill="{fill}" fill-opacity="{op}"/>'


def path_d(p, ox, oy):
    return "M" + " L".join(f"{fmt(ox + x)},{fmt(oy + y)}" for x, y in p) + " Z"


def hint(id_, x, y, w, h):
    return f'<rect id="{id_}" x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" fill="#000000" fill-opacity="0.004"/>'


def shadow_pieces(prefix, size, ox, oy, color="#000000", alpha=0.55, center=8, sep="-"):
    """Soft square shadow frame (Plasma's shadow-* elements)."""
    s = size
    W = 2 * s + center
    out = []
    gid = f"{prefix}sh"
    out.append(f'<defs>'
               f'<radialGradient id="{gid}c" cx="0" cy="0" r="1" gradientUnits="objectBoundingBox"><stop offset="0" stop-color="{color}" stop-opacity="{alpha}"/><stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>'
               f'</defs>')
    def grad(name, x1, y1, x2, y2):
        out.append(f'<defs><linearGradient id="{gid}{name}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{color}" stop-opacity="{alpha}"/><stop offset="1" stop-color="{color}" stop-opacity="0"/></linearGradient></defs>')
    grad("t", 0, 1, 0, 0); grad("b", 0, 0, 0, 1); grad("l", 1, 0, 0, 0); grad("r", 0, 0, 1, 0)
    def pid(p):
        return f"{prefix}{sep}{p}" if prefix else p
    def rect(p, x, y, w, h, fill, extra=""):
        out.append(f'<rect id="{pid(p)}" x="{ox + x}" y="{oy + y}" width="{w}" height="{h}" fill="{fill}" {extra}/>')
    # corners: radial centred on the inner corner
    for p, cx, cy, x, y in [("topleft", 1, 1, 0, 0), ("topright", 0, 1, s + center, 0),
                            ("bottomleft", 1, 0, 0, s + center), ("bottomright", 0, 0, s + center, s + center)]:
        out.append(f'<defs><radialGradient id="{gid}{p}" cx="{cx}" cy="{cy}" r="1"><stop offset="0" stop-color="{color}" stop-opacity="{alpha}"/><stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient></defs>')
        rect(p, x, y, s, s, f"url(#{gid}{p})")
    rect("top", s, 0, center, s, f"url(#{gid}t)")
    rect("bottom", s, s + center, center, s, f"url(#{gid}b)")
    rect("left", 0, s, s, center, f"url(#{gid}l)")
    rect("right", s + center, s, s, center, f"url(#{gid}r)")
    rect("center", s, s, center, center, color, 'fill-opacity="0"')
    return "\n".join(out), W


def svg(body, w, h, extra_defs=""):
    return (f'<?xml version="1.0" encoding="UTF-8"?>\n'
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
            f'<defs>{DEFS}{extra_defs}</defs>\n{body}\n</svg>\n')
