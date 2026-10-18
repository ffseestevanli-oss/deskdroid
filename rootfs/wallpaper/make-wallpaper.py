#!/usr/bin/env python3
"""Renders the DeskDroid default wallpaper (dark base, purple/pink/cyan glows) at common sizes.

Output goes into the Plasma wallpaper package under rootfs/overlay. Needs numpy and Pillow.
Usage: rootfs/wallpaper/make-wallpaper.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "overlay/usr/share/wallpapers/DeskDroid/contents"

BASE = (0x07, 0x07, 0x0D)
# (x as fraction of width, y as fraction of height, sigma as fraction of height, opacity, color)
GLOWS = [
    (0.15, 0.92, 0.45, 0.55, (0x8B, 0x5C, 0xFF)),  # purple, bottom left
    (0.86, 0.10, 0.42, 0.45, (0xFF, 0x4F, 0xD8)),  # pink, top right
    (0.70, 0.72, 0.30, 0.32, (0x2E, 0xC5, 0xFF)),  # cyan, lower right
]
SIZES = [
    (3840, 2160), (2560, 1440), (1920, 1080),  # 16:9
    (2560, 1600),                              # 16:10
    (3440, 1440),                              # 21:9
    (5120, 1440),                              # 32:9
    (2160, 3840),                              # portrait monitor
    (2400, 1080),                              # phone landscape 20:9
    (1080, 2400),                              # phone portrait
]

BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) + 0.5) / 16


def render(w, h):
    # Portrait screens use the short side as the glow scale so the glows stay round and soft.
    scale = min(w, h)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    img = np.empty((h, w, 3), np.float32)
    img[:] = BASE
    for fx, fy, fs, alpha, color in GLOWS:
        cx, cy, s = fx * w, fy * h, fs * scale
        a = alpha * np.exp(-((x - cx) ** 2 + (y - cy) ** 2) / (2 * s * s))
        img = img * (1 - a[..., None]) + np.array(color, np.float32) * a[..., None]
    # Ordered dithering hides banding in the dark gradients and, unlike random noise, keeps the PNGs small.
    threshold = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w, None]
    return Image.fromarray(np.clip(np.floor(img + threshold), 0, 255).astype(np.uint8))


def main():
    (OUT / "images").mkdir(parents=True, exist_ok=True)
    for w, h in SIZES:
        render(w, h).save(OUT / "images" / f"{w}x{h}.png", optimize=True)
    render(640, 360).save(OUT / "screenshot.png", optimize=True)


if __name__ == "__main__":
    main()
