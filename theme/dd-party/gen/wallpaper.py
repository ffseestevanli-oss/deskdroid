"""DD Party wallpaper: near-black with soft glows (#990045, violet, cyan) like the
app's GlowBackground, a faint chamfered frame and a thin rainbow line."""
import os, sys, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from palette import *


def render(w, h):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    s = min(w, h)
    img = np.zeros((h, w, 3), np.float32)
    img[:] = np.array(rgb(BG), np.float32)

    def glow(cx, cy, r, color, a):
        d = np.sqrt(((x - cx * w) / (r * s)) ** 2 + ((y - cy * h) / (r * s)) ** 2)
        k = np.clip(1 - d, 0, 1) ** 2.2 * a
        return k[..., None] * (np.array(rgb(color), np.float32) - img)

    for cx, cy, r, c, a in [
        (0.86, 0.12, 0.95, MAGENTA, 0.95),
        (0.97, 0.05, 0.45, "#FF2E8A", 0.35),
        (0.10, 0.92, 0.85, "#4B2A9E", 0.75),
        (0.62, 0.95, 0.55, "#0E5A7A", 0.55),
        (0.40, 0.40, 0.60, "#1A0F22", 0.5),
    ]:
        img += glow(cx, cy, r, c, a)

    # dither against banding
    img += np.random.default_rng(7).normal(0, 1.1, img.shape)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))

    # faint chamfered frame + rainbow line, lower right
    over = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    u = s / 1080
    x0, y0, x1, y1, c = w * 0.56, h * 0.50, w * 0.94, h * 0.86, 60 * u
    pts = [(x0, y0 + c), (x0 + c, y0), (x1, y0), (x1, y1 - c), (x1 - c, y1), (x0, y1), (x0, y0 + c)]
    d.line(pts, fill=(255, 255, 255, 22), width=max(1, round(2 * u)))
    # rainbow line along the frame's top edge
    seg = 7
    lx0, lx1 = x0 + c + 10 * u, x1
    for i in range(seg):
        a = lx0 + (lx1 - lx0) * i / seg
        b = lx0 + (lx1 - lx0) * (i + 1) / seg
        d.rectangle([a, y0 - 5 * u, b, y0 - 1 * u], fill=rgb(RAINBOW[i]) + (150,))
    # a second, smaller chamfer outline
    x0, y0, x1, y1, c = w * 0.62, h * 0.57, w * 0.88, h * 0.80, 36 * u
    pts = [(x0, y0 + c), (x0 + c, y0), (x1, y0), (x1, y1 - c), (x1 - c, y1), (x0, y1), (x0, y0 + c)]
    d.line(pts, fill=(255, 79, 216, 26), width=max(1, round(1.5 * u)))
    glowl = over.filter(ImageFilter.GaussianBlur(6 * u))
    im = im.convert("RGBA")
    im.alpha_composite(glowl)
    im.alpha_composite(over)
    return im.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1] + "/wallpapers/DDParty"
    os.makedirs(out + "/contents/images", exist_ok=True)
    sizes = [(1920, 1080), (2560, 1440), (3840, 2160), (2560, 1600), (3440, 1440), (2400, 1080), (1080, 2400)]
    for w, h in sizes:
        render(w, h).save(f"{out}/contents/images/{w}x{h}.png", optimize=True)
    render(1920, 1080).resize((480, 270), Image.LANCZOS).save(out + "/contents/screenshot.png")
    json.dump({"KPlugin": {"Authors": [{"Name": "DeskDroid"}], "Id": "DDParty", "License": "CC-BY-SA-4.0",
                           "Name": "DD Party"}}, open(out + "/metadata.json", "w"), indent=2)
