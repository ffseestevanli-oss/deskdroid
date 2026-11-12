"""Plasma style (desktoptheme) "dd-party". Files we don't provide fall back
to Breeze ("default"), drawn in our colours via the bundled colors file."""
import os, sys, json, shutil, gzip
from palette import *
from ninepatch import Frame, hint, shadow_pieces, svg


class Sheet:
    def __init__(self):
        self.parts, self.y, self.w, self.defs = [], 0, 0, ""

    def frame(self, prefix, f, sep="-", hints=None, parts=None):
        self.parts.append(f.render(prefix, 0, self.y, sep=sep, parts=parts))
        x = f.W + 4
        for name, (w, h) in (hints or {}).items():
            hid = f"{prefix}{sep}{name}" if prefix else name
            self.parts.append(hint(hid, x, self.y, w, h))
            x += w + 2
        self.w = max(self.w, x + 4)
        self.y += f.H + 6

    def shadow(self, prefix, size, alpha=0.55, color="#000000"):
        body, W = shadow_pieces(prefix, size, 0, self.y, color=color, alpha=alpha)
        self.parts.append(body)
        self.w = max(self.w, W)
        self.y += W + 6

    def raw(self, s, h=0, w=0):
        self.parts.append(s)
        self.y += h + 6
        self.w = max(self.w, w)

    def svg(self):
        if not any('id="hint-stretch-borders"' in p for p in self.parts):
            self.raw(hint("hint-stretch-borders", 0, self.y, 2, 2), 2)
        return svg("\n".join(self.parts), max(self.w, 64), self.y + 4)


def margins(t, r=None, b=None, l=None):
    r = t if r is None else r
    b = t if b is None else b
    l = r if l is None else l
    return {"hint-top-margin": (1, t), "hint-bottom-margin": (1, b),
            "hint-left-margin": (l, 1), "hint-right-margin": (r, 1)}


def prefixed(m, p):
    return {f"{k}": v for k, v in m.items()}


# ---------------------------------------------------------------- frames
def panel():
    s = Sheet()
    for loc, accent in [("", "top"), ("south", "top"), ("north", "bottom"), ("west", "right"), ("east", "left")]:
        f = Frame((12, 12, 12, 12), cuts=(10, 0, 10, 0))
        f.bordered(HEADER, BORDER, 1, fill_opacity=0.93)
        f.band(accent, 2, "rainbow-h" if accent in ("top", "bottom") else "rainbow-v")
        prefix = loc
        s.frame(prefix, f)
        x = f.W + 4
        for k, v in margins(6).items():
            s.parts.append(hint((f"{loc}-{k}" if loc else k), x, s.y - f.H - 6, *v))
            x += 10
    s.shadow("shadow", 18, 0.5)
    return s.svg()


def dialog(rainbow=True, cut=14, fill=HEADER, op=0.97, border=BORDER, shadow=24, margin=10, accent_w=3):
    s = Sheet()
    f = Frame((16, 16, 16, 16), cuts=(cut, 0, cut, 0))
    f.bordered(fill, border, 1, fill_opacity=op)
    if rainbow:
        f.band("top", accent_w, "rainbow-h")
    s.frame("", f, hints=margins(margin))
    s.shadow("shadow", shadow, 0.55)
    return s.svg()


def tooltip():
    s = Sheet()
    f = Frame((10, 10, 10, 10), cuts=(8, 0, 8, 0))
    f.bordered(BUTTON, MAGENTA_TEXT, 1, fill_opacity=0.98, border_opacity=0.9)
    s.frame("", f, hints=margins(7, 9, 7, 9))
    s.shadow("shadow", 14, 0.5)
    return s.svg()


def tasks():
    s = Sheet()
    for loc, side in [("", "bottom"), ("south", "bottom"), ("north", "top"), ("west", "left"), ("east", "right")]:
        rb = "rainbow-h" if side in ("top", "bottom") else "rainbow-v"
        p = (loc + "-") if loc else ""
        states = {
            "normal": lambda f: f.band(side, 2, MAGENTA_TEXT, 0.55),
            "focus": lambda f: (f.solid(MAGENTA, 0.32), f.band(side, 3, rb)),
            "hover": lambda f: (f.solid("#FFFFFF", 0.07), f.band(side, 2, MAGENTA_TEXT, 0.9)),
            "attention": lambda f: (f.solid(ORANGE, 0.22), f.band(side, 3, ORANGE)),
            "minimized": lambda f: f.band(side, 2, DIM, 0.6),
            "progress": lambda f: (f.solid(CYAN, 0.18), f.band(side, 3, rb)),
        }
        for st, paint in states.items():
            f = Frame((6, 6, 6, 6), cuts=(6, 0, 6, 0))
            paint(f)
            s.frame(p + st, f, hints=margins(4))
    return s.svg()


def button():
    s = Sheet()
    def fr(): return Frame((6, 6, 6, 6), cuts=(6, 0, 6, 0))
    s.frame("normal", fr().bordered(BUTTON, BORDER, 1), hints=margins(6, 10))
    s.frame("hover", fr().ring(MAGENTA_TEXT, 1.2), hints=margins(6, 10))
    s.frame("focus", fr().ring(MAGENTA_TEXT, 1.6), hints=margins(6, 10))
    s.frame("pressed", fr().bordered(MAGENTA, MAGENTA_TEXT, 1), hints=margins(6, 10))
    s.frame("toolbutton-hover", fr().solid("#FFFFFF", 0.08), hints=margins(5))
    s.frame("toolbutton-focus", fr().ring(MAGENTA_TEXT, 1.4), hints=margins(5))
    s.frame("toolbutton-pressed", fr().solid(MAGENTA, 0.85), hints=margins(5))
    s.raw(hint("hint-focus-over-base", 0, s.y, 2, 2), 2)
    return s.svg()


def lineedit():
    s = Sheet()
    def fr(): return Frame((6, 6, 6, 6), cuts=(6, 0, 6, 0))
    s.frame("base", fr().bordered(VIEW, BORDER, 1), hints=margins(6, 9))
    s.frame("hover", fr().ring(MUTED, 1, 0.6), hints=margins(6, 9))
    s.frame("focus", fr().ring(MAGENTA_TEXT, 1.6), hints=margins(6, 9))
    s.frame("focusframe", fr().ring(MAGENTA_TEXT, 1.6), hints=margins(6, 9))
    s.raw(hint("hint-focus-over-base", 0, s.y, 2, 2), 2)
    return s.svg()


def viewitem():
    s = Sheet()
    def fr(): return Frame((6, 6, 6, 6), cuts=(6, 0, 6, 0))
    s.frame("normal", fr(), hints=margins(4, 6))
    s.frame("hover", fr().solid("#FFFFFF", 0.06).band("left", 2, MAGENTA_TEXT, 0.7), hints=margins(4, 6))
    s.frame("selected", fr().solid(MAGENTA, 0.55).band("left", 3, MAGENTA_TEXT), hints=margins(4, 6))
    s.frame("selected+hover", fr().solid(MAGENTA, 0.75).band("left", 3, MAGENTA_TEXT), hints=margins(4, 6))
    return s.svg()


def tabbar():
    s = Sheet()
    for loc, side in [("north", "bottom"), ("south", "top"), ("west", "right"), ("east", "left")]:
        rb = "rainbow-h" if side in ("top", "bottom") else "rainbow-v"
        f = Frame((6, 6, 6, 6))
        f.solid("#FFFFFF", 0.03).band(side, 3, rb)
        s.frame(f"{loc}-active-tab", f, hints=margins(4, 8))
    return s.svg()


def plasmoidheading():
    s = Sheet()
    f = Frame((4, 4, 4, 4)); f.solid(HEADER, 0.6).band("bottom", 1, BORDER)
    s.frame("header", f)
    f = Frame((4, 4, 4, 4)); f.solid(HEADER, 0.6).band("top", 1, BORDER)
    s.frame("footer", f)
    s.raw("".join(hint(k, 40 + i * 10, 0, *v) for i, (k, v) in enumerate(margins(6).items())), 0)
    s.raw(hint("hint-stretch-borders", 0, s.y, 2, 2), 2)
    return s.svg()


def bar_meter():
    s = Sheet()
    f = Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0)); f.solid(EMPTY)
    s.frame("bar-inactive", f)
    f = Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0)); f.solid("rainbow-h")
    s.frame("bar-active", f)
    s.raw(hint("hint-bar-size", 0, s.y, 6, 6) + hint("hint-stretch-borders", 10, s.y, 2, 2), 6)
    return s.svg()


def diamond(cx, cy, r, fill, stroke=None, sw=0):
    pts = f"{cx},{cy - r} {cx + r},{cy} {cx},{cy + r} {cx - r},{cy}"
    st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    return f'<polygon points="{pts}" fill="{fill}"{st}/>'


def slider():
    parts = []
    y = 0
    for o in ["horizontal", "vertical"]:
        for st, (fill, stroke) in {"handle": (TEXT, MAGENTA), "hover": (TEXT, MAGENTA_TEXT), "focus": (TEXT, MAGENTA_TEXT)}.items():
            parts.append(f'<g id="{o}-slider-{st}"><rect x="0" y="{y}" width="20" height="20" fill="#000" fill-opacity="0.004"/>'
                         + diamond(10, y + 10, 8, fill, stroke, 3) + "</g>")
            y += 24
        parts.append(f'<g id="{o}-slider-shadow"><rect x="0" y="{y}" width="20" height="20" fill="#000" fill-opacity="0.004"/>'
                     + diamond(10, y + 11, 9, "#000", None) .replace('fill="#000"', 'fill="#000" fill-opacity="0.35"') + "</g>")
        y += 24
    parts.append(hint("hint-handle-size", 30, 0, 20, 20))
    return svg("\n".join(parts), 64, y)


def scrollbar():
    s = Sheet()
    def fr(): return Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0))
    s.frame("slider", fr().solid("#4A4A66"))
    s.frame("mouseover-slider", fr().solid(MAGENTA_TEXT))
    s.frame("background-vertical", Frame((3, 3, 3, 3)).solid("#FFFFFF", 0.03))
    s.frame("background-horizontal", Frame((3, 3, 3, 3)).solid("#FFFFFF", 0.03))
    s.raw(hint("hint-scrollbar-size", 0, s.y, 8, 8), 8)
    return s.svg()


def switch():
    s = Sheet()
    f = Frame((8, 9, 8, 9), cuts=(6, 0, 6, 0)); f.bordered(EMPTY, BORDER, 1)
    s.frame("inactive", f)
    f = Frame((8, 9, 8, 9), cuts=(6, 0, 6, 0)); f.solid("rainbow-h")
    s.frame("active", f)
    for st, (fill, stroke) in {"handle": (TEXT, None), "handle-hover": (TEXT, MAGENTA_TEXT), "handle-focus": (TEXT, MAGENTA_TEXT), "handle-pressed": (MAGENTA_TEXT, None), "handle-shadow": ("#000000", None)}.items():
        st_attr = f' stroke="{stroke}" stroke-width="2"' if stroke else ""
        op = ' fill-opacity="0.3"' if st == "handle-shadow" else ""
        s.raw(f'<g id="{st}"><rect x="0" y="{s.y}" width="18" height="18" fill="#000" fill-opacity="0.004"/>'
              f'<path d="M2,{s.y + 5} L5,{s.y + 2} H16 V{s.y + 13} L13,{s.y + 16} H2 Z" fill="{fill}"{op}{st_attr}/></g>', 18, 18)
    s.raw(hint("hint-bar-size", 0, s.y, 18, 18) + hint("hint-stretch-borders", 24, s.y, 2, 2), 18)
    return s.svg()


def gz(path, text):
    with gzip.open(path, "wb") as f:
        f.write(text.encode())


if __name__ == "__main__":
    out = sys.argv[1] + "/plasma/desktoptheme/dd-party"
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out + "/widgets"); os.makedirs(out + "/dialogs")
    w = {
        "widgets/panel-background": panel(),
        "dialogs/background": dialog(),
        "widgets/background": dialog(cut=12, fill=CARD, op=0.94, shadow=16, accent_w=2),
        "widgets/translucentbackground": dialog(cut=12, fill=CARD, op=0.72, shadow=16, accent_w=2),
        "widgets/tooltip": tooltip(),
        "widgets/tasks": tasks(),
        "widgets/button": button(),
        "widgets/lineedit": lineedit(),
        "widgets/viewitem": viewitem(),
        "widgets/tabbar": tabbar(),
        "widgets/plasmoidheading": plasmoidheading(),
        "widgets/bar_meter_horizontal": bar_meter(),
        "widgets/slider": slider(),
        "widgets/scrollbar": scrollbar(),
        "widgets/switch": switch(),
    }
    for name, text in w.items():
        gz(f"{out}/{name}.svgz", text)
    shutil.copy(sys.argv[1] + "/color-schemes/DDParty.colors", out + "/colors")
    json.dump({
        "KPlugin": {"Authors": [{"Name": "DeskDroid"}], "Category": "",
                    "Description": "Near-black, #990045 magenta and rainbow accents, chamfered corners",
                    "Id": "dd-party", "License": "GPL-2.0-or-later", "Name": "DD Party", "Version": "1.0"},
        "X-Plasma-API": "5.0",
    }, open(out + "/metadata.json", "w"), indent=2)
    open(out + "/plasmarc", "w").write(
        "[ContrastEffect]\nenabled=true\ncontrast=0.3\nintensity=1.0\nsaturation=1.6\n\n"
        "[AdaptiveTransparency]\nenabled=false\n\n[BlurBehindEffect]\nenabled=true\n")
