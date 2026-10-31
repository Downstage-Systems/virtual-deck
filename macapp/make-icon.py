#!/usr/bin/env python3
"""Draws the app icon: the builders' device and green stage line, with Stream Deck keys on its screen.
    make-icon.py out-dir    writes app-icon.png (1024) and AppIcon.icns"""
import os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw

BEZEL_EDGE, BEZEL, SCREEN = "#20262e", "#14181d", "#0b0d10"
SLATE, GREEN, VIOLET, LIGHT = "#2e3640", "#2fd97b", "#8e6fe6", "#e8ecef"


def draw(size=1024):
    k = 4                               # drawn big and scaled down for clean corners
    im = Image.new("RGBA", (size * k, size * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def rect(x0, y0, x1, y1, r, **kw):
        d.rounded_rectangle([x0 * k, y0 * k, x1 * k, y1 * k], r * k, **kw)
    rect(112, 230, 912, 760, 92, fill=BEZEL_EDGE)
    rect(122, 240, 902, 750, 84, fill=BEZEL)
    rect(146, 264, 878, 726, 62, fill=SCREEN)
    colors = {(0, 0): GREEN, (2, 0): LIGHT, (1, 1): VIOLET, (3, 2): GREEN}
    w, h, gx, gy = 138, 112, 28, 26
    x0, y0 = 512 - (4 * w + 3 * gx) // 2, 495 - (3 * h + 2 * gy) // 2
    for r in range(3):
        for c in range(4):
            x, y = x0 + c * (w + gx), y0 + r * (h + gy)
            rect(x, y, x + w, y + h, 18, fill=colors.get((c, r), SLATE))
    rect(272, 812, 752, 860, 24, fill=GREEN)                 # the stage line from the Downstage mark
    return im.resize((size, size), Image.LANCZOS)


def main(out):
    big = draw()
    big.save(os.path.join(out, "app-icon.png"))
    tmp = tempfile.mkdtemp(); iconset = os.path.join(tmp, "AppIcon.iconset"); os.mkdir(iconset)
    for s in (16, 32, 128, 256, 512):
        big.resize((s, s), Image.LANCZOS).save(os.path.join(iconset, f"icon_{s}x{s}.png"))
        big.resize((s * 2, s * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{s}x{s}@2x.png"))
    subprocess.check_call(["iconutil", "-c", "icns", iconset, "-o", os.path.join(out, "AppIcon.icns")])
    shutil.rmtree(tmp)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
