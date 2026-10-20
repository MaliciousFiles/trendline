#!/usr/bin/env python3
"""Builds Connect IQ Store images from the raw simulator captures.

    scripts/shots.sh                      # capture bin/shots/raw/*.png first
    python3 scripts/gen_store_images.py

Writes to assets/store/:
    icon-500.png          store icon (500x500, solid background, < 300 KB)
    hero.png              hero image (1440x720)
    screen-*.png/.jpg     framed screenshots (500x500, < 150 KB each)
"""
import io
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_logo  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "bin", "shots", "raw")
OUT = os.path.join(ROOT, "assets", "store")
INTER = os.path.join(ROOT, "assets", "fonts", "Inter-Variable.ttf")

BG_TOP = (24, 38, 58)
BG_BOTTOM = (10, 16, 26)
SCREEN_LIMIT = 150 * 1024
ICON_LIMIT = 300 * 1024

# (raw capture, output name). Missing captures are skipped.
SCREENS = [
    ("widget-venu3-normal", "screen-1-widget"),
    ("face-venu3", "screen-2-watchface"),
    ("widget-venu3-high", "screen-3-high"),
    ("widget-venu3-low", "screen-4-low"),
    ("glance-venu3", "screen-5-glance"),
    ("widget-venu3-gap", "screen-6-signal-loss"),
    ("face-vivoactive3", "screen-7-watchface-mip"),
    ("widget-vivoactive3", "screen-8-widget-mip"),
]


def font(px, weight=400):
    f = ImageFont.truetype(INTER, px)
    f.set_variation_by_axes([min(32, max(14, px)), weight])
    return f


def gradient(w, h, top=BG_TOP, bottom=BG_BOTTOM):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def watch(capture, size):
    """Round watch: bezel, two side buttons and the capture masked to a circle."""
    ss = 3
    s = size * ss
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    bezel = s * 0.47
    screen_r = s * 0.40

    for side, dy in (("r", -0.17), ("r", 0.17)):
        bx = c + bezel - s * 0.01
        by = c + dy * s
        d.rounded_rectangle([bx, by - s * 0.035, bx + s * 0.035, by + s * 0.035], radius=s * 0.012,
                            fill=(58, 62, 70, 255))

    # Bezel with a soft vertical sheen.
    ring = gradient(s, s, (92, 98, 108), (30, 33, 38)).convert("RGBA")
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).ellipse([c - bezel, c - bezel, c + bezel, c + bezel], fill=255)
    img.paste(ring, (0, 0), mask)
    inner = bezel - s * 0.025
    d.ellipse([c - inner, c - inner, c + inner, c + inner], fill=(8, 9, 11, 255))

    shot = capture.convert("RGB").resize((round(screen_r * 2), round(screen_r * 2)), Image.LANCZOS)
    smask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(smask).ellipse([0, 0, shot.size[0] - 1, shot.size[1] - 1], fill=255)
    img.paste(shot, (round(c - screen_r), round(c - screen_r)), smask)

    return img.resize((size, size), Image.LANCZOS)


def with_shadow(base, item, xy, blur=18, offset=10, alpha=150):
    shadow = Image.new("RGBA", item.size, (0, 0, 0, 0))
    shadow.putalpha(item.getchannel("A").point(lambda a: min(alpha, a)))
    pad = blur * 3
    layer = Image.new("RGBA", (item.size[0] + pad * 2, item.size[1] + pad * 2), (0, 0, 0, 0))
    layer.paste(shadow, (pad, pad))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(layer, (xy[0] - pad, xy[1] - pad + offset))
    base.alpha_composite(item, xy)


def save_limited(img, path_base, limit):
    """PNG if it fits under the limit, otherwise the best JPEG that does."""
    buf = io.BytesIO()
    img.convert("RGB").save(buf, "PNG", optimize=True)
    if buf.tell() <= limit:
        path = path_base + ".png"
        open(path, "wb").write(buf.getvalue())
        return path, buf.tell()
    for q in range(92, 50, -4):
        buf = io.BytesIO()
        img.convert("RGB").save(buf, "JPEG", quality=q, optimize=True)
        if buf.tell() <= limit:
            path = path_base + ".jpg"
            open(path, "wb").write(buf.getvalue())
            return path, buf.tell()
    raise SystemExit(f"{path_base}: can't get under {limit} bytes")


def store_icon():
    size = 500
    img = gradient(size, size, (28, 46, 70), (14, 24, 38)).convert("RGBA")
    logo = gen_logo.draw(size - 20, background=False)
    img.alpha_composite(logo, (10, 10))
    return save_limited(img, os.path.join(OUT, "icon-500"), ICON_LIMIT)


def screens():
    results = []
    for raw, name in SCREENS:
        path = os.path.join(RAW, raw + ".png")
        if not os.path.exists(path):
            print(f"skip {name} (no {raw}.png)")
            continue
        img = gradient(500, 500).convert("RGBA")
        w = watch(Image.open(path), 410)
        with_shadow(img, w, (45, 40))
        for old in (".png", ".jpg"):
            p = os.path.join(OUT, name + old)
            if os.path.exists(p):
                os.remove(p)
        results.append(save_limited(img, os.path.join(OUT, name), SCREEN_LIMIT))
    return results


def hero():
    W, H = 1440, 720
    img = gradient(W, H).convert("RGBA")

    # Copy on the left, kept clear of the watches (x < 700).
    logo = gen_logo.draw(140, background=False)
    img.alpha_composite(logo, (92, 160))
    d = ImageDraw.Draw(img)
    d.text((96, 318), "Trendline", font=font(92, 700), fill=(255, 255, 255))
    d.text((100, 432), "Your CGM glucose on your Garmin.", font=font(36, 400), fill=(200, 210, 222))
    d.text((100, 488), "Trend arrow, 3-hour graph, watch face.", font=font(28, 400), fill=(140, 152, 168))
    d.text((100, 552), "Works with Dexcom G6 and G7 via Dexcom Share", font=font(24, 500), fill=(95, 220, 140))

    # Widget behind on the left, watch face in front on the right (its side
    # buttons then sit over open background).
    widget = os.path.join(RAW, "widget-venu3-normal.png")
    face = os.path.join(RAW, "face-venu3.png")
    if os.path.exists(widget):
        with_shadow(img, watch(Image.open(widget), 430), (720, 60), blur=24, offset=14)
    if os.path.exists(face):
        with_shadow(img, watch(Image.open(face), 430), (985, 235), blur=24, offset=14)

    path = os.path.join(OUT, "hero.png")
    img.convert("RGB").save(path, "PNG", optimize=True)
    return path, os.path.getsize(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for path, size in [store_icon(), *screens(), hero()]:
        print(f"{os.path.relpath(path, ROOT)}  {size // 1024} KB")


if __name__ == "__main__":
    main()
