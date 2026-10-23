#!/usr/bin/env python3
"""Generates the light-weight number fonts (BMFont .fnt + .png) for each screen size.

Output goes to common/resources-<shape>-<w>x<h>/fonts/, which the jungle files add
to the resource path for matching devices. Re-run after changing sizes or weights:

    python3 scripts/gen_fonts.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TTF = os.path.join(ROOT, "assets", "fonts", "Inter-Variable.ttf")
ICON_TTF = os.path.join(ROOT, "assets", "fonts", "MaterialSymbolsRounded.ttf")

# Icon font: letter -> Material Symbols codepoint. Code draws these with
# drawText, so they get smooth edges and can be colored per field.
ICONS = {
    "a": 0xF87D,  # footprint      steps
    "b": 0xE87E,  # favorite       heart rate
    "c": 0xF6EA,  # distance       distance
    "d": 0xE564,  # landscape      elevation
    "e": 0xE1C6,  # wb_twilight    sunrise
    "f": 0xFFF1F, # wb_twilight_2  sunset
    "g": 0xE1FF,  # device_thermostat  temperature
    "h": 0xEF55,  # local_fire_department  calories
    "i": 0xF1A9,  # stairs         floors
    "j": 0xE425,  # timer          active minutes
    "k": 0xEA0B,  # bolt           charging
    "l": 0xF159,  # bedtime        do not disturb
}
ICON_SIZE = 0.075

# (shape, width, height) of every screen in the manifests.
SCREENS = [
    ("round", 218, 218), ("round", 240, 240), ("round", 260, 260), ("round", 280, 280),
    ("round", 360, 360), ("round", 390, 390), ("round", 416, 416), ("round", 454, 454),
    ("rectangle", 240, 240), ("rectangle", 320, 360), ("rectangle", 448, 486),
]

# id: (characters, size as a fraction of the short screen side, weight[, x-squeeze])
FONTS = {
    "Hero": ("0123456789.-LOWHIG", 0.29, 300),   # widget glucose
    "Clock": ("0123456789:", 0.20, 300),         # watch face hours:minutes
    "Sec": ("0123456789", 0.085, 300),           # watch face seconds
    # Every character Fmt.value/delta/age can produce: "now", "3m", "2h", ">1d".
    "Line": ("0123456789.+-LOWHIGmhdnow> ", 0.068, 300),  # watch face glucose line
    "Label": (" %+,-./0123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz\u00b0",
              0.064, 500),                       # date, battery, data fields
    # Countdown and "due 1h 05m" / "due >1 day" from Fmt.countdown/elapsed.
    "Small": ("0123456789:+-. dueagohmy>", 0.075, 400),  # widget timer and delta
    "Word": ("LOWHIG", 0.145, 380, 0.62),        # LOW / HIGH: tall but condensed
}


def build(font_id, chars, px, weight, out_dir, squeeze=1.0, glyphs_from=None, hard=False, tracking=0):
    """glyphs_from maps each output character to the codepoint to render (icons).
    hard=True renders 1-bit edges, which stay crisp on 64-color screens."""
    if glyphs_from:
        font = ImageFont.truetype(ICON_TTF, px)
        font.set_variation_by_axes([1, 0, min(48, max(20, px)), weight])  # filled
    else:
        font = ImageFont.truetype(TTF, px)
        font.set_variation_by_axes([min(32, max(14, px)), weight])
    src = (lambda c: chr(glyphs_from[c])) if glyphs_from else (lambda c: c)

    # Common vertical frame: tight around the tallest glyph (digits and caps
    # have no descenders), so VCENTER centers the visible ink.
    inked = [c for c in chars if c != " "]
    top = min(font.getbbox(src(c))[1] for c in inked)
    bottom = max(font.getbbox(src(c))[3] for c in inked)
    pad = max(1, px // 30)
    line_h = bottom - top + 2 * pad

    glyphs = []
    for c in chars:
        x0, y0, x1, y1 = font.getbbox(src(c)) if c != " " else (0, top, 1, top + 1)
        w, h = max(1, x1 - x0), max(1, y1 - y0)
        img = Image.new("L", (w + 2, h + 2), 0)
        ImageDraw.Draw(img).text((1 - x0, 1 - y0), src(c), font=font, fill=255)
        if hard:
            img = img.point(lambda a: 255 if a >= 120 else 0)
        advance = round(font.getlength(src(c)) * squeeze) + tracking
        if squeeze != 1.0:
            # BOX averaging: Lanczos overshoots and leaves halos around strokes.
            img = img.resize((max(1, round(img.width * squeeze)), img.height), Image.BOX)
        glyphs.append((c, img, round(x0 * squeeze) - 1, y0 - 1 - top + pad, advance))

    # Simple row packing.
    sheet_w = 512 if px < 120 else 1024
    x = y = row_h = 0
    placed = []
    for c, img, xo, yo, adv in glyphs:
        if x + img.width + 1 > sheet_w:
            x, y, row_h = 0, y + row_h + 1, 0
        placed.append((c, img, x, y, xo, yo, adv))
        x += img.width + 1
        row_h = max(row_h, img.height)
    sheet_h = y + row_h + 1

    sheet = Image.new("RGBA", (sheet_w, sheet_h), (255, 255, 255, 0))
    for c, img, gx, gy, *_ in placed:
        white = Image.new("RGBA", img.size, (255, 255, 255, 255))
        white.putalpha(img)
        sheet.paste(white, (gx, gy))

    name = font_id.lower()
    sheet.save(os.path.join(out_dir, name + ".png"))
    lines = [
        f'info face="Inter" size={px} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1',
        f"common lineHeight={line_h} base={line_h - pad} scaleW={sheet_w} scaleH={sheet_h} pages=1 packed=0",
        f'page id=0 file="{name}.png"',
        f"chars count={len(placed)}",
    ]
    for c, img, gx, gy, xo, yo, adv in placed:
        lines.append(
            f"char id={ord(c)} x={gx} y={gy} width={img.width} height={img.height} "
            f"xoffset={xo} yoffset={yo} xadvance={adv} page=0 chnl=15"
        )
    with open(os.path.join(out_dir, name + ".fnt"), "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    for shape, w, h in SCREENS:
        out_dir = os.path.join(ROOT, "common", f"resources-{shape}-{w}x{h}", "fonts")
        os.makedirs(out_dir, exist_ok=True)
        entries = []
        for font_id, spec in FONTS.items():
            chars, frac, weight = spec[:3]
            squeeze = spec[3] if len(spec) > 3 else 1.0
            px = round(min(w, h) * frac)
            build(font_id, chars, px, weight, out_dir, squeeze)
            entries.append(f'    <font id="{font_id}" filename="{font_id.lower()}.fnt" antialias="true" />')
        build("Icons", "".join(ICONS), round(min(w, h) * ICON_SIZE), 500, out_dir, glyphs_from=ICONS, hard=True)
        entries.append('    <font id="Icons" filename="icons.fnt" antialias="false" />')
        with open(os.path.join(out_dir, "fonts.xml"), "w") as f:
            f.write("<fonts>\n" + "\n".join(entries) + "\n</fonts>\n")
        print(f"{shape}-{w}x{h}: ok")


if __name__ == "__main__":
    main()
