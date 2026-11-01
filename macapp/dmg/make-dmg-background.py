#!/usr/bin/env python3
"""Draws the disk image window: the Downstage logo over House Black, a green stage line from the app to Applications.
    make-dmg-background.py logo.svg out-dir    writes background.png (660x400), background@2x.png and background.tiff"""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 660, 400
GROUND, GREEN, DIM = "#0b0d10", "#2fd97b", "#9aa4ad"
ICON_Y, LEFT, RIGHT = 212, 165, 495        # make-dmg.sh puts the icons here
MONO = "/Library/Fonts/ShareTechMono-Regular.ttf"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def draw(logo_svg, scale):
    k = scale * 4                          # drawn big and scaled down for clean corners
    size = (W * k, H * k)
    im = Image.new("RGB", size, GROUND)

    # the light a stage line throws, soft behind the arrow
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([W / 2 - 170, ICON_Y - 80, W / 2 + 170, ICON_Y + 80], fill=46)
    glow = glow.filter(ImageFilter.GaussianBlur(52)).resize(size, Image.BICUBIC)
    im.paste(Image.new("RGB", size, GREEN), (0, 0), glow)

    d = ImageDraw.Draw(im)
    def bar(x0, y0, x1, y1, fill):
        d.rounded_rectangle([x0 * k, y0 * k, x1 * k, y1 * k], (y1 - y0) / 2 * k, fill=fill)

    # the arrow is the mark's stage line with a head on it
    y = ICON_Y - 6
    hx = RIGHT - 96
    bar(LEFT + 96, y - 3.5, hx, y + 3.5, GREEN)
    for ex, ey in ((hx - 15, y - 15), (hx - 15, y + 15)):
        d.line([(ex * k, ey * k), (hx * k, y * k)], fill=GREEN, width=7 * k)
        d.ellipse([(ex - 3.5) * k, (ey - 3.5) * k, (ex + 3.5) * k, (ey + 3.5) * k], fill=GREEN)
    d.ellipse([(hx - 3.5) * k, (y - 3.5) * k, (hx + 3.5) * k, (y + 3.5) * k], fill=GREEN)

    f = ImageFont.truetype(MONO, 11.5 * k)
    d.text((W / 2 * k, (y + 26) * k), "DRAG TO INSTALL", font=f, fill=DIM, anchor="ma")

    # the logo, rendered by Chrome because ImageMagick drops the mark's outlined screen
    tmp = tempfile.mkdtemp(); png = os.path.join(tmp, "logo.png"); html = os.path.join(tmp, "logo.html")
    lh = 70 * k; lw = int(lh * 376.76 / 108)
    open(html, "w").write(f'<body style="margin:0;background:transparent"><img src="file://{os.path.abspath(logo_svg)}" style="width:{lw}px;height:{lh}px;display:block">')
    subprocess.check_call([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--default-background-color=00000000",
                           "--allow-file-access-from-files", f"--window-size={lw},{lh}", f"--user-data-dir={tmp}/c",
                           f"--screenshot={png}", f"file://{html}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    logo = Image.open(png).convert("RGBA")
    im.paste(logo, (int((size[0] - logo.width) / 2), 24 * k), logo)
    return im.resize((W * scale, H * scale), Image.LANCZOS)


def main(logo_svg, out):
    a, b = os.path.join(out, "background.png"), os.path.join(out, "background@2x.png")
    one, two = draw(logo_svg, 1), draw(logo_svg, 2)
    one.save(a, dpi=(72, 72)); two.save(b, dpi=(144, 144))
    subprocess.check_call(["tiffutil", "-cathidpicheck", a, b, "-out", os.path.join(out, "background.tiff")],
                          stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
