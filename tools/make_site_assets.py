#!/usr/bin/env python3
"""Produces website/img/* (icon, favicons, resized screenshots, social card) from the app icon and the promo images.
Run after tools/make_promo.py:  python3 tools/make_site_assets.py   (needs Pillow)"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "website", "img")
os.makedirs(OUT, exist_ok=True)


def rounded(img, frac=0.2237):
    s = 4
    big = img.convert("RGBA").resize((img.width * s, img.height * s), Image.LANCZOS)
    m = Image.new("L", big.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, big.width - 1, big.height - 1], radius=int(big.width * frac), fill=255)
    big.putalpha(m)
    return big.resize(img.size, Image.LANCZOS)


icon = Image.open(os.path.join(ROOT, "Macros/Assets.xcassets/AppIcon.appiconset/icon.png")).convert("RGB")
rounded(icon.resize((512, 512), Image.LANCZOS)).save(os.path.join(OUT, "icon.png"))
rounded(icon.resize((180, 180), Image.LANCZOS)).save(os.path.join(OUT, "apple-touch-icon.png"))
icon.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, "favicon.png"))

promo = os.path.join(ROOT, "marketing", "appstore")
for name in sorted(os.listdir(promo)):
    if name.endswith(".png"):
        im = Image.open(os.path.join(promo, name)).convert("RGB")
        im.resize((660, round(660 * im.height / im.width)), Image.LANCZOS).save(
            os.path.join(OUT, name.replace("appstore-", "shot-")), optimize=True)

# plain phone render (transparent background) for the hero
sys.path.insert(0, os.path.dirname(__file__))
from make_promo import phone  # noqa: E402
ph = phone(Image.open(os.path.join(ROOT, "marketing", "screenshots", "01_today.png")))
ph.resize((660, round(660 * ph.height / ph.width)), Image.LANCZOS).save(os.path.join(OUT, "phone-today.png"), optimize=True)

# 1200x630 social card
card = Image.new("RGB", (1200, 630), (20, 28, 62))
d = ImageDraw.Draw(card)
for y in range(630):
    t = y / 629
    d.line([(0, y), (1200, y)], fill=(round(30 - 17 * t), round(42 - 26 * t), round(92 - 56 * t)))
card.paste(rounded(icon.resize((220, 220), Image.LANCZOS)), (90, 150), rounded(icon.resize((220, 220), Image.LANCZOS)))
f = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
d.text((350, 170), "Toate Macros", font=ImageFont.truetype(f, 96), fill="white")
d.text((354, 300), "Calorie and macro tracker for iPhone", font=ImageFont.truetype(f, 40), fill=(186, 194, 226))
d.text((354, 360), "Private. Offline-first. No account.", font=ImageFont.truetype(f, 40), fill=(186, 194, 226))
card.save(os.path.join(OUT, "og.png"), optimize=True)
print("ok", sorted(os.listdir(OUT)))
