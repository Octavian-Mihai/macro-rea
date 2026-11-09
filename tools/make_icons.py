#!/usr/bin/env python3
"""Renders the two app icons (1024x1024, full-bleed; iOS applies the rounded mask).
Run: python3 tools/make_icons.py   (needs Pillow)"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "Macros", "Assets.xcassets")
S = 4                      # supersampling
U = 1024 * S / 180         # design units are the 180pt grid from the mock-ups
RED, BLUE, ORANGE = (255, 69, 58), (10, 132, 255), (255, 159, 10)
RED_L, BLUE_L, ORANGE_L = (255, 59, 48), (10, 132, 255), (255, 159, 10)
BARS = [(42, 112), (79, 84), (116, 58)]   # (y, width), x = 34, height 22

def layer(): return Image.new("RGBA", (1024 * S, 1024 * S), (0, 0, 0, 0))
def rrect(img, x, y, w, h, r, color, alpha=1.0):
    l = layer(); d = ImageDraw.Draw(l)
    d.rounded_rectangle([x * U, y * U, (x + w) * U, (y + h) * U], radius=r * U, fill=(*color, int(255 * alpha)))
    return Image.alpha_composite(img, l)
def circle(img, cx, cy, r, color, alpha=1.0):
    l = layer(); d = ImageDraw.Draw(l)
    d.ellipse([(cx - r) * U, (cy - r) * U, (cx + r) * U, (cy + r) * U], fill=(*color, int(255 * alpha)))
    return Image.alpha_composite(img, l)
def save(img, name):
    img.resize((1024, 1024), Image.LANCZOS).convert("RGB").save(os.path.join(OUT, name, "icon.png"))

# Primary: D1c, navy with glowing tips
img = Image.new("RGBA", (1024 * S, 1024 * S), (16, 20, 43, 255))
for (y, w), c, ga in zip(BARS, (RED, BLUE, ORANGE), (.12, .14, .12)):
    img = rrect(img, 26, y - 8, w + 16, 38, 19, c, ga)
for (y, w), c in zip(BARS, (RED, BLUE, ORANGE)):
    img = rrect(img, 34, y, w, 22, 11, c)
    img = circle(img, 34 + w - 11, y + 11, 14, (255, 255, 255), .12)
    img = circle(img, 34 + w - 11, y + 11, 8, (255, 255, 255))
save(img, "AppIcon.appiconset")

# Alternate: D2a, white with tracks and a soft tinted halo
img = Image.new("RGBA", (1024 * S, 1024 * S), (255, 255, 255, 255))
for (y, _), c in zip(BARS, (RED_L, BLUE_L, ORANGE_L)):
    img = rrect(img, 30, y - 2, 120, 24, 12, c, .14)
for (y, w), c in zip(BARS, (RED_L, BLUE_L, ORANGE_L)):
    fw = {112: 92, 84: 66, 58: 44}[w]
    img = rrect(img, 22, y - 10, fw + 16, 40, 20, c, .10)
    img = rrect(img, 26, y - 6, fw + 8, 32, 16, c, .14)
    img = rrect(img, 30, y - 2, fw, 24, 12, c)
save(img, "AppIconLight.appiconset")
