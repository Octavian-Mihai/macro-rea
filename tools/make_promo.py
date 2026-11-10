#!/usr/bin/env python3
"""Builds the App Store promo images (1320x2868, the 6.9" iPhone size) from raw simulator screenshots.

Usage: python3 tools/make_promo.py <screenshots_dir> [out_dir]
Expects 01_today.png, 02_diary.png, 03_weight.png, 04_insights.png in <screenshots_dir>
(1206x2622 simulator captures). Needs Pillow."""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
NAVY_TOP, NAVY_BOTTOM = (30, 42, 92), (13, 16, 36)
WHITE, SOFT = (255, 255, 255), (186, 194, 226)
RED, BLUE, ORANGE = (255, 69, 58), (10, 132, 255), (255, 159, 10)

SLIDES = [
    ("01_today.png", ["Every macro,", "at a glance"], "Calories, protein, carbs and fat in one view.", RED),
    ("02_diary.png", ["Log meals", "in seconds"], "Search foods or scan a barcode. No account needed.", BLUE),
    ("03_weight.png", ["See your true", "weight trend"], "A smoothed trend line cuts through daily noise.", ORANGE),
    ("04_insights.png", ["Targets that", "adapt to you"], "Weekly check-ins tune your calories to your results.", RED),
]


def gradient():
    img = Image.new("RGB", (W, H))
    px = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        px.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(NAVY_TOP, NAVY_BOTTOM)))
    return img


def glow(img, cx, cy, r, color, strength=0.35):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*color, int(255 * strength)))
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.6))
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def rounded_mask(size, radius, scale=3):
    big = Image.new("L", (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, big.width - 1, big.height - 1], radius=radius * scale, fill=255)
    return big.resize(size, Image.LANCZOS)


def phone(shot):
    """Screenshot inside a dark bezel with a Dynamic Island."""
    sw = 1000
    sh = round(shot.height * sw / shot.width)
    shot = shot.convert("RGB").resize((sw, sh), Image.LANCZOS)
    # the simulator leaves a stray pixel in the top-left corner; the rounded mask removes it
    bezel = 22
    pw, ph = sw + 2 * bezel, sh + 2 * bezel
    body = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    body.paste(Image.new("RGBA", (pw, ph), (28, 28, 34, 255)), (0, 0), rounded_mask((pw, ph), 170))
    body.paste(shot, (bezel, bezel), rounded_mask((sw, sh), 148))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([bezel + 345, bezel + 36, bezel + 655, bezel + 124], radius=44, fill=(0, 0, 0, 255))
    return body


def text_block(img, lines, sub, accent):
    d = ImageDraw.Draw(img)
    f_big = ImageFont.truetype(FONT, 132)
    f_sub = ImageFont.truetype(FONT, 50)
    y = 150
    for i, line in enumerate(lines):
        w = d.textlength(line, font=f_big)
        d.text(((W - w) / 2, y), line, font=f_big, fill=WHITE)
        y += 150
    # accent bar under the headline, echoing the app icon's bars
    d.rounded_rectangle([W / 2 - 60, y + 32, W / 2 + 60, y + 46], radius=7, fill=accent)
    w = d.textlength(sub, font=f_sub)
    if w > W - 140:
        f_sub = ImageFont.truetype(FONT, 44)
        w = d.textlength(sub, font=f_sub)
    d.text(((W - w) / 2, y + 76), sub, font=f_sub, fill=SOFT)


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "marketing", "appstore")
    os.makedirs(out, exist_ok=True)
    for i, (name, lines, sub, accent) in enumerate(SLIDES, 1):
        bg = gradient()
        bg = glow(bg, W * 0.85, 1100, 520, accent, 0.30)
        bg = glow(bg, W * 0.1, 2500, 480, BLUE if accent != BLUE else ORANGE, 0.18)
        text_block(bg, lines, sub, accent)
        p = phone(Image.open(os.path.join(src, name)))
        x, y = (W - p.width) // 2, 650
        shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        shadow.paste(Image.new("RGBA", p.size, (0, 0, 0, 150)), (x, y + 30), rounded_mask(p.size, 170))
        shadow = shadow.filter(ImageFilter.GaussianBlur(40))
        canvas = Image.alpha_composite(bg.convert("RGBA"), shadow)
        canvas.alpha_composite(p, (x, y))
        path = os.path.join(out, f"appstore-{i}-{name[3:-4]}.png")
        canvas.convert("RGB").save(path)
        print(path)


if __name__ == "__main__":
    main()
