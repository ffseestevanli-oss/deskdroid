"""KDE colour scheme (DDParty.colors) and Konsole colour scheme."""
import os, sys
from palette import *


def colorset(bg, alt, fg=TEXT, inactive=MUTED, active=MAGENTA_TEXT, focus=MAGENTA_TEXT, hover=MAGENTA_TEXT):
    return {
        "BackgroundAlternate": alt,
        "BackgroundNormal": bg,
        "DecorationFocus": focus,
        "DecorationHover": hover,
        "ForegroundActive": active,
        "ForegroundInactive": inactive,
        "ForegroundLink": CYAN,
        "ForegroundNegative": RED,
        "ForegroundNeutral": ORANGE,
        "ForegroundNormal": fg,
        "ForegroundPositive": GREEN,
        "ForegroundVisited": PURPLE,
    }


def scheme():
    sets = {
        "Colors:Button": colorset(BUTTON, "#161624"),
        "Colors:Complementary": colorset(BG, "#0A0A12"),
        "Colors:Header": colorset(HEADER, "#10101B"),
        "Colors:Header][Inactive": colorset(HEADER, "#10101B", inactive=DIM),
        "Colors:Selection": colorset(MAGENTA, MAGENTA_HI, fg=TEXT, inactive="#F0C4D8", active=TEXT),
        "Colors:Tooltip": colorset(BUTTON, "#161624"),
        "Colors:View": colorset(VIEW, "#11111C"),
        "Colors:Window": colorset(BG, "#0D0D16"),
    }
    out = []
    out.append("[ColorEffects:Disabled]\nColor=56,56,72\nColorAmount=0\nColorEffect=0\nContrastAmount=0.65\nContrastEffect=1\nIntensityAmount=0.1\nIntensityEffect=2\n")
    out.append("[ColorEffects:Inactive]\nChangeSelectionColor=true\nColor=112,111,110\nColorAmount=0.025\nColorEffect=2\nContrastAmount=0.1\nContrastEffect=2\nEnable=false\nIntensityAmount=0\nIntensityEffect=0\n")
    for name, d in sets.items():
        out.append(f"[{name}]\n" + "".join(f"{k}={kde(v)}\n" for k, v in d.items()))
    out.append("[General]\nColorScheme=DDParty\nName=DD Party\nshadeSortColumn=true\n")
    out.append("[KDE]\ncontrast=4\n")
    out.append("[WM]\n" + "".join(f"{k}={kde(v)}\n" for k, v in {
        "activeBackground": HEADER, "activeBlend": TEXT, "activeForeground": TEXT,
        "inactiveBackground": HEADER, "inactiveBlend": DIM, "inactiveForeground": DIM,
    }.items()))
    return "\n".join(out)


def konsole():
    normal = ["#12121E", RED, GREEN, YELLOW, CYAN, MAGENTA_TEXT, "#5EE7E0", SOFT]
    intense = ["#4A4A66", "#FF6B82", "#7DFFB0", "#FFEB85", "#7AD8FF", PINK, "#9CF5EF", TEXT]
    faint = [mix(c, BG, 0.4) for c in normal]
    s = [f"[General]\nBlur=true\nColorRandomization=false\nDescription={NAME}\nOpacity={glass(0.95, 0.60)}\nWallpaper=\n"]
    s.append(f"[Background]\nColor={kde(BG)}\n")
    s.append(f"[BackgroundIntense]\nColor={kde(BUTTON)}\n")
    s.append(f"[BackgroundFaint]\nColor={kde(BG)}\n")
    s.append(f"[Foreground]\nColor={kde(TEXT)}\n")
    s.append(f"[ForegroundIntense]\nColor=255,255,255\n")
    s.append(f"[ForegroundFaint]\nColor={kde(MUTED)}\n")
    for i in range(8):
        s.append(f"[Color{i}]\nColor={kde(normal[i])}\n")
        s.append(f"[Color{i}Intense]\nColor={kde(intense[i])}\n")
        s.append(f"[Color{i}Faint]\nColor={kde(faint[i])}\n")
    return "\n".join(s)


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(f"{out}/color-schemes", exist_ok=True)
    os.makedirs(f"{out}/konsole", exist_ok=True)
    if not GLASS:  # the glass variant shares the colour scheme
        open(f"{out}/color-schemes/DDParty.colors", "w").write(scheme())
    open(f"{out}/konsole/{CAMEL}.colorscheme", "w").write(konsole())
    open(f"{out}/konsole/{CAMEL}.profile", "w").write(
        f"[Appearance]\nColorScheme={CAMEL}\nFont=Hack,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n\n[General]\nName={NAME}\nParent=FALLBACK/\n\n[Scrolling]\nScrollBarPosition=1\n")
