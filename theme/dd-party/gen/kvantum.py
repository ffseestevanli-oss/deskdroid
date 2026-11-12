"""Kvantum widget style "DDParty" for Qt apps (Dolphin, Kate, System Settings...).

Starts from Kvantum's own KvArcDark (flat, dark, GPL) for the elements we don't
redraw (arrows, spin buttons, MDI buttons...) recoloured to our palette, and
replaces the main widgets with chamfered DD Party frames."""
import os, re, sys, shutil, configparser
import xml.etree.ElementTree as ET
from palette import *
from ninepatch import Frame, DEFS, fmt, chamfer_poly

SVGNS = "http://www.w3.org/2000/svg"
for p, u in {"": SVGNS, "xlink": "http://www.w3.org/1999/xlink",
             "inkscape": "http://www.inkscape.org/namespaces/inkscape",
             "sodipodi": "http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd",
             "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#", "dc": "http://purl.org/dc/elements/1.1/",
             "cc": "http://creativecommons.org/ns#"}.items():
    ET.register_namespace(p, u)

RECOLOR = {
    "#5294e2": MAGENTA_TEXT, "#4693e6": MAGENTA_TEXT, "#58acff": MAGENTA_TEXT, "#3176bf": MAGENTA,
    "#22252e": HEADER, "#404552": VIEW, "#383c4a": BG, "#2f343f": HEADER, "#474d5d": "#2E2E44",
    "#505666": "#34344C", "#4d5367": "#30304A", "#3c404e": BUTTON, "#343844": "#18182A", "#444a58": "#22223A",
    "#2d303b": "#0F0F1A", "#363c48": "#16162A", "#262933": "#0B0B14", "#2d323d": "#0F0F1A",
    "#92959d": MUTED, "#b74aff": PURPLE, "#767b87": DIM, "#111217": "#05050A",
}

# Frame widths (kvconfig frame.*) and drawn chamfer per element.
F = 5


def frame(cut=F, f=F, inset=(0, 0, 0, 0)):
    return Frame((f, f, f, f), cuts=(cut, 0, cut, 0), center=10, inset=inset)


class Out:
    def __init__(self):
        self.parts, self.y, self.ids = [], 2000, set()

    def frame(self, name, fr, interior=True, frame_parts=True):
        parts = [p for p in ["topleft", "top", "topright", "left", "right", "bottomleft", "bottom", "bottomright"]] if frame_parts else []
        if parts:
            self.parts.append(fr.render(name, 0, self.y, parts=parts))
            self.ids |= {f"{name}-{p}" for p in parts}
        if interior:
            body = fr.render("", 0, self.y, parts=["center"]).replace('id="center"', f'id="{name}"', 1)
            self.parts.append(body)
            self.ids.add(name)
        self.y += fr.H + 6

    def raw(self, name, s, h):
        self.parts.append(s)
        self.ids.add(name)
        self.y += h + 6


def build_elements():
    o = Out()
    # ---- push buttons, combos, tool buttons
    for el in ["button", "combo"]:
        o.frame(f"{el}-normal", frame().bordered(BUTTON, BORDER, 1))
        o.frame(f"{el}-focused", frame().bordered(CARD_ON, MAGENTA_TEXT, 1))
        o.frame(f"{el}-pressed", frame().bordered(MAGENTA, MAGENTA_TEXT, 1))
        o.frame(f"{el}-toggled", frame().bordered(MAGENTA, MAGENTA_TEXT, 1))
        o.frame(f"{el}-disabled", frame().bordered(BUTTON, BORDER_SOFT, 1, fill_opacity=0.5))
    # default button: a rainbow ring drawn over the normal look
    o.frame("button-default", frame().ring("rainbow-h", 1.6), interior=False)
    # ---- line edits / spin boxes
    o.frame("lineedit-normal", frame().bordered(VIEW, BORDER, 1))
    o.frame("lineedit-focused", frame().bordered(VIEW, MAGENTA_TEXT, 1.6))
    o.frame("lineedit-disabled", frame().bordered(VIEW, BORDER_SOFT, 1, fill_opacity=0.5))
    # ---- tabs: rainbow underline on the current tab
    t = lambda: Frame((4, 4, 4, 4), center=10)
    o.frame("tab-normal", t())
    o.frame("tab-focused", t().solid("#FFFFFF", 0.05).band("bottom", 2, MAGENTA_TEXT, 0.8))
    o.frame("tab-toggled", t().solid("#FFFFFF", 0.035).band("bottom", 3, "rainbow-h"))
    o.frame("tabframe-normal", Frame((4, 4, 4, 4), center=10).bordered(BG, BORDER_SOFT, 1))
    # ---- progress bars: dark groove, rainbow indicator
    o.frame("progress-normal", Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10).solid(EMPTY))
    o.frame("progress-pattern-normal", Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10).solid("rainbow-h"))
    o.frame("progress-pattern-disabled", Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10).solid(DIM, 0.5))
    # ---- slider groove: rainbow up to the handle
    o.frame("slider-normal", Frame((2, 2, 2, 2), center=10).solid(EMPTY))
    o.frame("slider-toggled", Frame((2, 2, 2, 2), center=10).solid("rainbow-h"))
    o.frame("slider-disabled", Frame((2, 2, 2, 2), center=10).solid(EMPTY, 0.5))
    # ---- scroll bar handles
    sb = lambda: Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10)
    o.frame("scrollbarslider-normal", sb().solid("#4A4A66"))
    o.frame("scrollbarslider-focused", sb().solid(MAGENTA_TEXT))
    o.frame("scrollbarslider-pressed", sb().solid(MAGENTA))
    o.frame("scrollbarslider-disabled", sb().solid("#2A2A3D"))
    # ---- item views: magenta selection with a bright left bar
    iv = lambda: Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10)
    o.frame("itemview-focused", iv().solid("#FFFFFF", 0.06))
    o.frame("itemview-pressed", iv().solid(MAGENTA, 0.75).band("left", 3, MAGENTA_TEXT))
    o.frame("itemview-toggled", iv().solid(MAGENTA, 0.62).band("left", 3, MAGENTA_TEXT))
    o.frame("itemview-toggled-inactive", iv().solid(MAGENTA, 0.35).band("left", 3, MAGENTA_TEXT, 0.6))
    o.frame("itemview-pressed-inactive", iv().solid(MAGENTA, 0.45).band("left", 3, MAGENTA_TEXT, 0.6))
    # ---- menus: dark panel with a rainbow top line
    o.frame("menu-normal", Frame((3, 3, 3, 3), center=10).bordered(HEADER, BORDER, 1).band("top", 2, "rainbow-h"))
    mi = lambda: Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10)
    for st in ["focused", "pressed", "toggled"]:
        o.frame(f"menuitem-{st}", mi().solid(MAGENTA).band("left", 2, MAGENTA_TEXT))
        o.frame(f"menubaritem-{st}", mi().solid(MAGENTA).band("bottom", 2, MAGENTA_TEXT))
    # ---- tooltips
    o.frame("tooltip-normal", Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10).bordered(BUTTON, MAGENTA_TEXT, 1))
    # ---- table headers
    for st, fill in [("normal", HEADER), ("focused", "#14142A"), ("pressed", CARD_ON), ("toggled", CARD_ON)]:
        o.frame(f"header-{st}", Frame((2, 2, 2, 2), center=10).solid(fill).band("bottom", 1, BORDER).band("right", 1, BORDER_SOFT))
    # ---- focus rectangle
    o.frame("focus", Frame((2, 2, 2, 2), cuts=(2, 0, 2, 0), center=10).ring(MAGENTA_TEXT, 1.2), interior=False)
    # ---- generic frames (group boxes, Dolphin panels)
    o.frame("common-normal", Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10).ring(BORDER_SOFT, 1), interior=False)
    o.frame("common-focused", Frame((3, 3, 3, 3), cuts=(3, 0, 3, 0), center=10).ring(MAGENTA_TEXT, 1, 0.45), interior=False)

    # ---- check boxes, radios, slider handle (single elements, 20x20)
    def box(name, fill, stroke, mark=None, scale=1.0):
        y = o.y
        poly = chamfer_poly(1, y + 1, 19, y + 19, tl=5, br=5)
        d = "M" + " L".join(f"{fmt(a)},{fmt(b)}" for a, b in poly) + " Z"
        m = ""
        if mark == "check":
            m = f'<path d="M5,{y + 10} L8.5,{y + 13.5} L15,{y + 6.5}" stroke="{TEXT}" stroke-width="2.4" fill="none"/>'
        elif mark == "tri":
            m = f'<rect x="5" y="{y + 9}" width="10" height="2.4" fill="{TEXT}"/>'
        o.raw(name, f'<g id="{name}"><rect x="0" y="{y}" width="20" height="20" fill="#000" fill-opacity="0.004"/>'
                    f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>{m}</g>', 20)

    def diamond(name, fill, stroke, dot=None, sw=1.5, r=8.5):
        y = o.y
        pts = f"10,{y + 10 - r} {10 + r},{y + 10} 10,{y + 10 + r} {10 - r},{y + 10}"
        m = f'<polygon points="10,{y + 5} 15,{y + 10} 10,{y + 15} 5,{y + 10}" fill="{dot}"/>' if dot else ""
        o.raw(name, f'<g id="{name}"><rect x="0" y="{y}" width="20" height="20" fill="#000" fill-opacity="0.004"/>'
                    f'<polygon points="{pts}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>{m}</g>', 20)

    for pre in ["", "menu-"]:
        box(f"{pre}checkbox-normal", BG, BORDER)
        box(f"{pre}checkbox-focused", BG, MAGENTA_TEXT)
        box(f"{pre}checkbox-pressed", CARD_ON, MAGENTA_TEXT)
        box(f"{pre}checkbox-disabled", BG, BORDER_SOFT)
        box(f"{pre}checkbox-checked-normal", MAGENTA, MAGENTA, "check")
        box(f"{pre}checkbox-checked-focused", MAGENTA_HI, MAGENTA_TEXT, "check")
        box(f"{pre}checkbox-checked-pressed", MAGENTA_HI, MAGENTA_TEXT, "check")
        box(f"{pre}checkbox-checked-disabled", "#3A1028", "#3A1028", "check")
        box(f"{pre}checkbox-tristate-normal", MAGENTA, MAGENTA, "tri")
        box(f"{pre}checkbox-tristate-focused", MAGENTA_HI, MAGENTA_TEXT, "tri")
        box(f"{pre}checkbox-tristate-pressed", MAGENTA_HI, MAGENTA_TEXT, "tri")
        box(f"{pre}checkbox-tristate-disabled", "#3A1028", "#3A1028", "tri")
        diamond(f"{pre}radio-normal", BG, BORDER)
        diamond(f"{pre}radio-focused", BG, MAGENTA_TEXT)
        diamond(f"{pre}radio-pressed", CARD_ON, MAGENTA_TEXT)
        diamond(f"{pre}radio-disabled", BG, BORDER_SOFT)
        diamond(f"{pre}radio-checked-normal", BG, MAGENTA_TEXT, MAGENTA_TEXT)
        diamond(f"{pre}radio-checked-focused", BG, MAGENTA_TEXT, PINK)
        diamond(f"{pre}radio-checked-pressed", CARD_ON, MAGENTA_TEXT, PINK)
        diamond(f"{pre}radio-checked-disabled", BG, BORDER_SOFT, "#3A1028")
    diamond("slidercursor-normal", TEXT, MAGENTA, sw=3, r=7.5)
    diamond("slidercursor-focused", TEXT, MAGENTA_TEXT, sw=3, r=7.5)
    diamond("slidercursor-pressed", MAGENTA_TEXT, TEXT, sw=2.5, r=7.5)
    diamond("slidercursor-disabled", DIM, BORDER, sw=2, r=7.5)
    return o


def build_svg(base_svg, out_svg):
    text = open(base_svg).read()
    for a, b in RECOLOR.items():
        text = re.sub(a, b, text, flags=re.I)
    root = ET.fromstring(text)
    o = build_elements()
    # drop the base theme's versions of everything we redraw
    parent = {c: p for p in root.iter() for c in p}
    for el in list(root.iter()):
        i = el.get("id")
        if i and (i in o.ids):
            parent[el].remove(el)
    # also drop stale state pieces of redrawn elements (e.g. old itemview pieces)
    new = ET.fromstring(f'<svg xmlns="{SVGNS}"><defs>{DEFS}</defs>' + "\n".join(o.parts) + "</svg>")
    for child in list(new):
        root.append(child)
    root.set("height", str(o.y + 20))
    if root.get("viewBox"):
        vb = root.get("viewBox").split()
        root.set("viewBox", f"{vb[0]} {vb[1]} {vb[2]} {o.y + 20}")
    ET.ElementTree(root).write(out_svg, encoding="utf-8", xml_declaration=True)


def build_config(base_cfg, out_cfg):
    cp = configparser.RawConfigParser(strict=False)
    cp.optionxform = str
    cp.read(base_cfg)
    g = cp["%General"]
    g.update({
        "author": "DeskDroid (based on KvArcDark by Tsu Jan)",
        "comment": f"{NAME}: near-black, #990045 magenta, rainbow accents, chamfered corners",
        "composite": "true", "menu_shadow_depth": "6", "tooltip_shadow_depth": "6",
        "scroll_width": "10", "scroll_min_extent": "48", "transient_scrollbar": "true",
        "slider_width": "4", "slider_handle_width": "18", "slider_handle_length": "18",
        "check_size": "18", "progressbar_thickness": "8", "textless_progressbar": "false",
        "spread_progressbar": "true", "animate_states": "true", "dark_titlebar": "true",
        "translucent_windows": "false", "popup_blurring": "true", "blurring": "false",
        "menu_separator_height": "7", "layout_spacing": "6", "layout_margin": "9",
        "button_icon_size": "16", "toolbar_icon_size": "22", "small_icon_size": "16", "large_icon_size": "32",
        "tree_branch_line": "false", "fill_rubberband": "true",
    })
    if GLASS:
        # See-through windows and menus, blurred behind (KWin's blur effect).
        g.update({
            "translucent_windows": "true", "blurring": "true", "popup_blurring": "true",
            "reduce_window_opacity": "58", "reduce_menu_opacity": "40",
            "menu_blur_radius": "6", "tooltip_blur_radius": "6", "contrast": "1.00",
        })
    c = cp["GeneralColors"]
    c.update({
        "window.color": BG, "base.color": VIEW, "alt.base.color": "#11111C", "button.color": BUTTON,
        "light.color": "#2E2E44", "mid.light.color": "#1E1E2E", "dark.color": "#000000", "mid.color": "#0A0A12",
        "highlight.color": MAGENTA, "inactive.highlight.color": "#5A0A30",
        "text.color": TEXT, "window.text.color": TEXT, "button.text.color": TEXT,
        "disabled.text.color": "#F2F2F773", "tooltip.text.color": TEXT, "highlight.text.color": TEXT,
        "link.color": CYAN, "link.visited.color": PURPLE, "progress.indicator.text.color": TEXT,
    })
    for sec in cp.sections():
        s = cp[sec]
        for k in list(s.keys()):
            v = s[k]
            if k.startswith("text.") and k.endswith("color"):
                lv = v.lower()
                if lv in ("white", "#ffffff"):
                    s[k] = "#FFFFFF"
                elif lv.startswith("#ffffff"):
                    s[k] = TEXT if k != "text.normal.color" or lv in ("#ffffffc8",) else MUTED
                elif lv == "#5796e8":
                    s[k] = MAGENTA_TEXT
                elif lv in ("#787878",):
                    s[k] = DIM
    # frame sizes of what we redrew
    def fr(sec, n, exp="0"):
        if sec in cp:
            for side in ["top", "bottom", "left", "right"]:
                cp[sec][f"frame.{side}"] = str(n)
            cp[sec]["frame.expansion"] = exp
    fr("PanelButtonCommand", F); fr("ComboBox", F); fr("LineEdit", F)
    fr("Progressbar", 3); fr("ProgressbarContents", 3); fr("Slider", 2)
    fr("ScrollbarSlider", 3); fr("ItemView", 3); fr("MenuItem", 3); fr("MenuBarItem", 3)
    fr("Menu", 3); fr("ToolTip", 3); fr("Tab", 4); fr("TabFrame", 4); fr("Focus", 2); fr("GenericFrame", 3)
    fr("HeaderSection", 2)
    if "PanelButtonCommand" in cp:
        cp["PanelButtonCommand"]["text.press.color"] = "#FFFFFF"
        cp["PanelButtonCommand"]["text.toggle.color"] = "#FFFFFF"
        cp["PanelButtonCommand"]["text.focus.color"] = "#FFFFFF"
    cp["Hacks"]["normal_default_pushbutton"] = "true"
    cp["Hacks"]["transparent_dolphin_view"] = "true" if GLASS else "false"
    cp["Hacks"]["blur_translucent"] = "true" if GLASS else "false"
    cp["Hacks"]["iconless_pushbutton"] = "false"
    cp["Hacks"]["tint_on_mouseover"] = "0"
    with open(out_cfg, "w") as f:
        cp.write(f, space_around_delimiters=False)


if __name__ == "__main__":
    base = sys.argv[2]  # path to KvArcDark dir
    out = sys.argv[1] + f"/Kvantum/{CAMEL}"
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    build_svg(f"{base}/KvArcDark.svg", f"{out}/{CAMEL}.svg")
    build_config(f"{base}/KvArcDark.kvconfig", f"{out}/{CAMEL}.kvconfig")
