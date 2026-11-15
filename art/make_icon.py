"""Draw a purple, script-like, neon i over the grass block icon.

The glyph is stroked as a tapered nib line so it reads as handwriting rather
than a font: a stem that swells at the waist and exits fine, a hairline swash
leaving its shoulder, a foot that curls right, and a dot set clear above. Three
passes make the neon: a soft violet halo, a dark rim that keeps the letter
readable on grass at 60 px, and a near-white core inside the tube.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
BASE = HERE / "base-grass.png"
OUT = HERE / "icon-horizon-1024.png"

SIZE = 1024
SS = 3
CANVAS = SIZE * SS
UNIT = CANVAS / 1024.0  # authored coordinates are in 1024 units

VIOLET = (162, 92, 255)
VIOLET_DEEP = (112, 44, 200)
MAGENTA = (208, 130, 255)
CORE = (252, 240, 255)
RIM = (32, 6, 58)


def bezier(p0, p1, p2, p3, steps=110):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1.0 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        out.append((x, y))
    return out


def stroke(draw, points, width_at):
    for i, (x, y) in enumerate(points):
        r = max(width_at(i / max(len(points) - 1, 1)) * 0.5, 0.6)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=255)


def nib(entry: float, peak: float, exit_: float, scale: float):
    """Width in 1024 units: `entry` at the start, `peak` at the waist, `exit_` at the end."""

    def at(t):
        if t < 0.5:
            k = t / 0.5
            w = entry + (peak - entry) * math.sin(k * math.pi * 0.5)
        else:
            k = (t - 0.5) / 0.5
            w = peak + (exit_ - peak) * (1 - math.cos(k * math.pi * 0.5))
        return w * 1.08 * UNIT * scale

    return at


def build(scale: float):
    """The glyph at supersampled size; `scale` shrinks every stroke for the core."""
    layer = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(layer)

    # The glyph is drawn about its own centre and grown a little, so it still
    # reads at 60 px on a home screen.
    grow = 1.16
    cx0, cy0 = 500.0, 500.0

    def q(x, y):
        return ((cx0 + (x - cx0) * grow) * UNIT, (cy0 + (y - cy0) * grow) * UNIT)

    stroke(draw, bezier(q(514, 410), q(492, 492), q(536, 566), q(514, 686)),
           nib(30, 62, 18, scale))
    stroke(draw, bezier(q(506, 470), q(432, 454), q(374, 406), q(358, 346)),
           nib(14, 18, 2, scale))
    stroke(draw, bezier(q(514, 686), q(556, 710), q(616, 710), q(648, 690)),
           nib(12, 20, 2, scale))

    cx, cy = q(516, 300)
    rx = 40 * 1.16 * scale * UNIT
    ry = 42 * 1.16 * scale * UNIT
    draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    return layer


def coloured(mask: Image.Image, top, bottom):
    w, h = mask.size
    grad = Image.new("RGBA", (w, h))
    px = grad.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        row = (
            round(top[0] + (bottom[0] - top[0]) * t),
            round(top[1] + (bottom[1] - top[1]) * t),
            round(top[2] + (bottom[2] - top[2]) * t),
            255,
        )
        for x in range(w):
            px[x, y] = row
    out = grad.copy()
    out.putalpha(mask)
    return out


def main() -> int:
    base = Image.open(BASE).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    out = Image.alpha_composite(base, Image.new("RGBA", (SIZE, SIZE), (38, 10, 66, 92)))

    body = build(1.0).resize((SIZE, SIZE), Image.LANCZOS)
    core = build(0.30).resize((SIZE, SIZE), Image.LANCZOS)

    halo = body.filter(ImageFilter.GaussianBlur(40))
    out.alpha_composite(coloured(halo.point(lambda v: int(v * 0.7)), VIOLET, VIOLET_DEEP))

    rim = body.filter(ImageFilter.MaxFilter(13)).filter(ImageFilter.GaussianBlur(6))
    out.alpha_composite(coloured(rim.point(lambda v: int(v * 0.85)), RIM, RIM))

    # A thin edge light on the tube: the letter keeps a violet body with a
    # bright lip, which is what makes the neon read at icon size.
    edge = body.filter(ImageFilter.GaussianBlur(2))
    out.alpha_composite(coloured(edge.point(lambda v: int(v * 0.55)), MAGENTA, VIOLET))
    out.alpha_composite(coloured(body, VIOLET, VIOLET_DEEP))
    out.alpha_composite(
        coloured(core.filter(ImageFilter.GaussianBlur(4)).point(lambda v: int(v * 0.78)),
                 CORE, MAGENTA)
    )

    out.save(OUT)
    out.resize((180, 180), Image.LANCZOS).save(HERE / "icon-horizon-180.png")
    print("wrote", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
