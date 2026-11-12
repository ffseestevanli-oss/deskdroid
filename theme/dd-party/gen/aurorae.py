"""Aurorae window decoration "DDParty": chamfered top-left corner, a rainbow line
on the focused window, chamfered title-bar buttons, soft shadow."""
import os, sys, json, shutil
from palette import *
from ninepatch import Frame, chamfer_poly, hint, svg, fmt

P, PT, PB = 20, 14, 26       # shadow padding: sides, top, bottom
CUT = 12                     # top-left chamfer
TITLE = 40                   # TitleEdgeTop + TitleHeight + TitleEdgeBottom


def deco_frame(active):
    f = Frame((P + CUT, PT + 16, P + CUT, PB + 12), cuts=(CUT, 0, 0, 0), inset=(P, PT, P, PB))
    # shadow: stacked, slightly lowered outlines
    # Glass: the shadow, glow and border are drawn around the window only, as
    # rings, so nothing but the tint covers what shows through the title bar.
    def under(poly, paint, op):
        f.add(("ring", poly, f.outline()) if GLASS else poly, paint, op)
    steps = 12
    for i in range(steps):
        g = -(i + 1) * (P / steps)
        under([(x, y + 5) for x, y in f.outline(g)], "#000000", 0.035 if active else 0.025)
    if active:
        under(f.outline(-6), MAGENTA, 0.10)  # faint magenta glow
    if GLASS:
        # A thin, saturated tint (magenta on the focused window) over the blur.
        f.ring("#B8105A" if active else BORDER, 1, 0.9)
        f.add(f.outline(1), MAGENTA if active else "#2A1030", 0.30 if active else 0.24)
    else:
        f.add(f.outline(), "#5A1A48" if active else BORDER)
        f.add(f.outline(1), HEADER)
    if active:
        f.band("top", 3, "rainbow-h")
    else:
        f.band("top", 2, "#3A1D40")
    return f


def maximized(active, y):
    h = TITLE
    band = (f'<rect x="0" y="{y}" width="40" height="3" fill="url(#rbh)"/>' if active
            else f'<rect x="0" y="{y}" width="40" height="2" fill="#3A1D40"/>')
    pid = "decoration-maximized" + ("" if active else "-inactive")
    return (f'<g id="{pid}-center"><rect x="0" y="{y}" width="40" height="{h}" fill="{glass(HEADER, MAGENTA if active else "#2A1030")}" fill-opacity="{glass(1.0, 0.30 if active else 0.24)}"/>{band}</g>', h)


def decoration_svg():
    parts, y = [], 0
    for active in (True, False):
        f = deco_frame(active)
        prefix = "decoration" if active else "decoration-inactive"
        parts.append(f.render(prefix, 0, y))
        parts.append(hint(prefix + "-hint-stretch-borders", f.W + 4, y, 2, 2))
        y += f.H + 8
    if GLASS:
        # The window border's shape, which KWin blurs behind (Aurorae's "mask").
        m = Frame((P + CUT, PT + 16, P + CUT, PB + 12), cuts=(CUT, 0, 0, 0), inset=(P, PT, P, PB))
        m.add(m.outline(), "#000000")
        parts.append(m.render("mask", 0, y))
        y += m.H + 8
    for active in (True, False):
        s, h = maximized(active, y)
        parts.append(s)
        y += h + 8
    parts.append(hint("hint-stretch-borders", 0, y, 2, 2))
    return svg("\n".join(parts), 120, y + 4)


GLYPH = {
    "minimize": lambda c: f'<path d="M9,16 H19" stroke="{c}" stroke-width="1.8" fill="none"/>',
    "maximize": lambda c: f'<path d="M9.5,7.5 H18.5 V16.5 H9.5 Z" stroke="{c}" stroke-width="1.6" fill="none"/>',
    "restore": lambda c: f'<path d="M8.5,10 H16 V17 H8.5 Z M11.5,10 V7.5 H19.5 V14 H16" stroke="{c}" stroke-width="1.5" fill="none"/>',
    "close": lambda c: f'<path d="M9.5,7.5 L18.5,16.5 M18.5,7.5 L9.5,16.5" stroke="{c}" stroke-width="1.9" fill="none"/>',
    "alldesktops": lambda c: f'<path d="M10,8 H18 V10 L15.5,12 V15 H12.5 V12 L10,10 Z M14,15 V18" stroke="{c}" stroke-width="1.4" fill="none"/>',
    "keepabove": lambda c: f'<path d="M9,15 L14,10 L19,15" stroke="{c}" stroke-width="1.8" fill="none"/>',
    "keepbelow": lambda c: f'<path d="M9,9 L14,14 L19,9" stroke="{c}" stroke-width="1.8" fill="none"/>',
    "shade": lambda c: f'<path d="M9,8 H19 M9,15 L14,11 L19,15" stroke="{c}" stroke-width="1.6" fill="none"/>',
    "help": lambda c: f'<path d="M11,9.5 C11,7.5 17,7.5 17,10 C17,12 14,12 14,14" stroke="{c}" stroke-width="1.6" fill="none"/><circle cx="14" cy="16.8" r="1.1" fill="{c}"/>',
}


def button_svg(kind):
    close = kind == "close"
    states = {
        "active": (BUTTON, BORDER_SOFT, SOFT, 1.0),
        "hover": (CARD_ON, MAGENTA_TEXT, TEXT, 1.0),
        "pressed": (MAGENTA, MAGENTA_TEXT, TEXT, 1.0),
        "inactive": (BUTTON, BORDER_SOFT, DIM, 0.55),
        "hover-inactive": (CARD_ON, MAGENTA_TEXT, TEXT, 1.0),
        "pressed-inactive": (MAGENTA, MAGENTA_TEXT, TEXT, 1.0),
        "deactivated": (BUTTON, BORDER_SOFT, DIM, 0.35),
        "deactivated-inactive": (BUTTON, BORDER_SOFT, DIM, 0.25),
    }
    if close:
        states.update({
            "active": ("#2A0F18", RED, "#FF6B82", 1.0),
            "hover": (RED, RED, "#FFFFFF", 1.0),
            "pressed": ("#B3203D", RED, "#FFFFFF", 1.0),
            "inactive": ("#1A0D14", "#5A2A36", "#A05060", 0.7),
            "hover-inactive": (RED, RED, "#FFFFFF", 1.0),
            "pressed-inactive": ("#B3203D", RED, "#FFFFFF", 1.0),
        })
    parts, y = [], 0
    for st, (fill, stroke, glyph, op) in states.items():
        outer = chamfer_poly(0.5, 0.5, 27.5, 23.5, tl=6, br=6)
        d = "M" + " L".join(f"{fmt(x)},{fmt(yy)}" for x, yy in outer) + " Z"
        fop = glass(1.0, 0.30) if fill in (BUTTON, "#2A0F18", "#1A0D14") else 1.0
        parts.append(f'<g id="{st}-center" opacity="{op}" transform="translate(0,{y})">'
                     f'<rect width="28" height="24" fill="#000" fill-opacity="0.004"/>'
                     f'<path d="{d}" fill="{fill}" fill-opacity="{fop}" stroke="{stroke}" stroke-width="1"/>'
                     f'<g transform="translate(0,0)">{GLYPH[kind](glyph)}</g></g>')
        y += 30
    return svg("\n".join(parts), 28, y)


RC = """[General]
ActiveTextColor=242,242,247
InactiveTextColor=138,138,166
TitleAlignment=Left
TitleVerticalAlignment=Center
Animation=150
UseTextShadow=false
Shadow=true

[Layout]
BorderLeft=1
BorderRight=1
BorderBottom=1
TitleEdgeTop=8
TitleEdgeBottom=8
TitleEdgeLeft=12
TitleEdgeRight=10
TitleEdgeTopMaximized=8
TitleEdgeBottomMaximized=8
TitleEdgeLeftMaximized=10
TitleEdgeRightMaximized=8
TitleBorderLeft=10
TitleBorderRight=10
TitleHeight=24
ButtonWidth=28
ButtonHeight=24
ButtonSpacing=6
ButtonMarginTop=0
ButtonMarginTopMaximized=0
ExplicitButtonSpacer=10
PaddingTop=%d
PaddingBottom=%d
PaddingLeft=%d
PaddingRight=%d
""" % (PT, PB, P, P)


if __name__ == "__main__":
    out = sys.argv[1] + f"/aurorae/themes/{CAMEL}"
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    open(out + "/decoration.svg", "w").write(decoration_svg())
    for k in GLYPH:
        open(f"{out}/{k}.svg", "w").write(button_svg(k))
    open(out + f"/{CAMEL}rc", "w").write(RC)
    open(out + "/metadata.desktop", "w").write(
        f"[Desktop Entry]\nName={NAME}\nComment=Chamfered, rainbow-lit title bars from DeskDroid\n"
        f"X-KDE-PluginInfo-Author=DeskDroid\nX-KDE-PluginInfo-Name={CAMEL}\nX-KDE-PluginInfo-Version=1.0\n"
        "X-KDE-PluginInfo-License=GPL-2.0-or-later\nX-Plasma-API=declarativeappletscript\n")
    json.dump({"KPlugin": {"Authors": [{"Name": "DeskDroid"}], "Description": "Chamfered, rainbow-lit title bars from DeskDroid",
                           "Id": CAMEL, "License": "GPL-2.0-or-later", "Name": NAME, "Version": "1.0"},
               "X-Plasma-API": "declarativeappletscript"}, open(out + "/metadata.json", "w"), indent=2)
