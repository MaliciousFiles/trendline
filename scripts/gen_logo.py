#!/usr/bin/env python3
"""Draws the Trendline logo: a smooth glucose curve between two faint guide
lines, colored by height like the app (green in range, yellow to orange above
the high line), ending in a dot.

    python3 scripts/gen_logo.py

Writes the launcher icon (common/resources/drawables/launcher_icon.png). The
store icon is built by gen_store_images.py.
"""
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # supersampling factor


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


HIGH_Y, LOW_Y = 0.36, 0.70


def curve_color(y):
    """Color for a point at fractional height y (0 = top)."""
    orange, yellow, green = (255, 120, 40), (255, 214, 40), (40, 230, 110)
    if y >= HIGH_Y + 0.06:
        return green
    if y >= HIGH_Y - 0.02:
        return lerp(yellow, green, (y - (HIGH_Y - 0.02)) / 0.08)
    return lerp(orange, yellow, max(0.0, (y - 0.20) / (HIGH_Y - 0.22)))


def catmull(p0, p1, p2, p3, u):
    return tuple(
        0.5 * (2 * p1[k] + (p2[k] - p0[k]) * u + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * u * u
               + (3 * p1[k] - p0[k] - 3 * p2[k] + p3[k]) * u ** 3)
        for k in range(2)
    )


def draw(size, rounded=True, background=True):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if background:
        radius = s * 0.22 if rounded else 0
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=(12, 14, 18, 255))

    # Guide lines (high / low).
    guide = (70, 76, 86, 255)
    gw = max(SS, round(s * 0.014))
    for gy in (HIGH_Y, LOW_Y):
        x = s * 0.14
        while x < s * 0.86:
            d.line([(x, s * gy), (min(x + s * 0.045, s * 0.86), s * gy)], fill=guide, width=gw)
            x += s * 0.075

    # Control points: in range, a rounded spike above the high line, back to steady.
    pts = [(0.14, 0.58), (0.29, 0.53), (0.41, 0.28), (0.57, 0.28), (0.69, 0.51), (0.84, 0.54)]
    pts = [(x * s, y * s) for x, y in pts]
    ext = [pts[0]] + pts + [pts[-1]]
    samples = []
    for i in range(1, len(ext) - 2):
        for k in range(160):
            samples.append(catmull(ext[i - 1], ext[i], ext[i + 1], ext[i + 2], k / 160))
    samples.append(pts[-1])

    # Draw the stroke (and end dot) as a mask, then fill it with a gradient by
    # height so colors blend without seams at the joints.
    mask = Image.new("L", (s, s), 0)
    md = ImageDraw.Draw(mask)
    width = round(s * 0.085)
    r = width / 2
    for x, y in samples:  # stamp a round brush along the curve
        md.ellipse([x - r, y - r, x + r, y + r], fill=255)
    x, y = pts[-1]
    dot = s * 0.072
    md.ellipse([x - dot, y - dot, x + dot, y + dot], fill=255)

    gradient = Image.new("RGBA", (s, s))
    gd = ImageDraw.Draw(gradient)
    for row in range(s):
        gd.line([(0, row), (s, row)], fill=curve_color(row / s) + (255,))
    img.paste(gradient, (0, 0), mask)

    return img.resize((size, size), Image.LANCZOS)


def main():
    drawables = os.path.join(ROOT, "common", "resources", "drawables")
    # Launcher icons sit on the watch's black background, so no rounded tile.
    draw(80, rounded=False, background=False).save(os.path.join(drawables, "launcher_icon.png"))
    print("ok")


if __name__ == "__main__":
    main()
