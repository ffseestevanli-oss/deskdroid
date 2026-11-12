"""DD Party palette: the phone app's "party" colours (app/.../ui/Party.kt) with
Steven's magenta, #990045, for selection and focus."""

BG = "#07070D"
VIEW = "#0D0D16"
BUTTON = "#12121E"
HEADER = "#0C0C16"
CARD = "#10101B"
CARD_ON = "#1A0F22"
BORDER = "#2A2A3D"
BORDER_SOFT = "#262638"
TEXT = "#F2F2F7"
SOFT = "#C9C9DC"
MUTED = "#A6A6C0"
DIM = "#8A8AA6"
EMPTY = "#1E1E2E"

MAGENTA = "#990045"       # selection, focus fills
MAGENTA_HI = "#B8105A"    # hover on a magenta fill
MAGENTA_TEXT = "#FF4D94"  # magenta for small text and thin lines on near-black

RED = "#FF3B5C"
ORANGE = "#FF9F1C"
YELLOW = "#FFE14D"
GREEN = "#3DFF8B"
CYAN = "#2EC5FF"
PURPLE = "#8B5CFF"
PINK = "#FF4FD8"
RAINBOW = [RED, ORANGE, YELLOW, GREEN, CYAN, PURPLE, PINK]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def kde(h):
    return ",".join(str(v) for v in rgb(h))


def mix(a, b, t):
    ra, rb = rgb(a), rgb(b)
    return "#%02X%02X%02X" % tuple(round(x + (y - x) * t) for x, y in zip(ra, rb))


def rainbow_at(t):
    n = len(RAINBOW) - 1
    p = max(0.0, min(1.0, t)) * n
    i = min(int(p), n - 1)
    return mix(RAINBOW[i], RAINBOW[i + 1], p - i)


def rainbow_stops(opacity=1):
    out = []
    for i, c in enumerate(RAINBOW):
        out.append(f'<stop offset="{i / (len(RAINBOW) - 1):.3f}" stop-color="{c}" stop-opacity="{opacity}"/>')
    return "".join(out)
