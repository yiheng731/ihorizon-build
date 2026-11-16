from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
OUT = HERE / "icon-horizon-1024.png"

SIZE = 1024
SS = 3
CANVAS = SIZE * SS
UNIT = CANVAS / 1024.0

VIOLET = (162, 92, 255)
VIOLET_DEEP = (112, 44, 200)
MAGENTA = (208, 130, 255)
CORE = (252, 240, 255)
RIM = (24, 4, 44)

BG_TOP = (30, 10, 58)
BG_MID = (17, 6, 36)
BG_BOTTOM = (6, 2, 12)
GRID = (150, 96, 240)
HORIZON = (196, 132, 255)

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
    def at(t):
        if t < 0.5:
            k = t / 0.5
            w = entry + (peak - entry) * math.sin(k * math.pi * 0.5)
        else:
            k = (t - 0.5) / 0.5
            w = peak + (exit_ - peak) * (1 - math.cos(k * math.pi * 0.5))
        return w * 1.18 * UNIT * scale

    return at

def build(scale: float):
    layer = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(layer)

    grow = 1.16
    cx0, cy0 = 500.0, 500.0

    def q(x, y):
        return ((cx0 + (x - cx0) * grow) * UNIT, (cy0 + (y - cy0) * grow) * UNIT)

    stroke(
        draw,
        bezier(q(514, 410), q(492, 492), q(536, 566), q(514, 686)),
        nib(30, 62, 18, scale),
    )
    stroke(
        draw,
        bezier(q(506, 470), q(432, 454), q(374, 406), q(358, 346)),
        nib(14, 18, 2, scale),
    )
    stroke(
        draw,
        bezier(q(514, 686), q(556, 710), q(616, 710), q(648, 690)),
        nib(12, 20, 2, scale),
    )

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
        row = tuple(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        ) + (255,)
        for x in range(w):
            px[x, y] = row
    out = grad.copy()
    out.putalpha(mask)
    return out

def backdrop() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    px = img.load()
    cx, cy = SIZE * 0.5, SIZE * 0.40
    far = math.hypot(SIZE * 0.55, SIZE * 0.62)
    for y in range(SIZE):
        v = y / (SIZE - 1)
        if v < 0.60:
            k = v / 0.60
            base = tuple(round(BG_TOP[i] + (BG_MID[i] - BG_TOP[i]) * k) for i in range(3))
        else:
            k = (v - 0.60) / 0.40
            base = tuple(
                round(BG_MID[i] + (BG_BOTTOM[i] - BG_MID[i]) * k) for i in range(3)
            )
        for x in range(SIZE):
            d = math.hypot(x - cx, y - cy) / far
            glow = max(0.0, 1.0 - d) ** 2.6
            px[x, y] = (
                min(255, round(base[0] + 78 * glow)),
                min(255, round(base[1] + 26 * glow)),
                min(255, round(base[2] + 116 * glow)),
                255,
            )

    horizon = round(SIZE * 0.615)
    floor = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fd = ImageDraw.Draw(floor)
    for i in range(14):
        k = (i + 1) / 14
        y = horizon + int((SIZE - horizon) * (k**2.35))
        alpha = round(26 + 96 * k)
        fd.line((0, y, SIZE, y), fill=HORIZON + (alpha,), width=max(1, round(1 + 2 * k)))
    span = SIZE * 2.6
    for i in range(-11, 12):
        x_end = SIZE * 0.5 + i * span / 12
        fd.line((cx, horizon, x_end, SIZE), fill=HORIZON + (58,), width=2)
    floor = floor.filter(ImageFilter.GaussianBlur(0.7))
    floor_cut = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    floor_cut.paste(floor.crop((0, horizon, SIZE, SIZE)), (0, horizon))
    img = Image.alpha_composite(img, floor_cut)

    line = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line)
    ld.line((0, horizon, SIZE, horizon), fill=HORIZON + (150,), width=4)
    img = Image.alpha_composite(img, line.filter(ImageFilter.GaussianBlur(3.0)))

    vign = Image.new("L", (SIZE, SIZE), 0)
    vd = ImageDraw.Draw(vign)
    vd.ellipse(
        (round(-SIZE * 0.30), round(-SIZE * 0.30), round(SIZE * 1.30), round(SIZE * 1.30)),
        fill=255,
    )
    vign = vign.filter(ImageFilter.GaussianBlur(SIZE * 0.10))
    dark = Image.new("RGBA", (SIZE, SIZE), (4, 1, 10, 255))
    dark.putalpha(vign.point(lambda v: round((255 - v) * 0.92)))
    return Image.alpha_composite(img, dark)

def main() -> int:
    out = backdrop()

    body = build(1.0).resize((SIZE, SIZE), Image.LANCZOS)
    core = build(0.24).resize((SIZE, SIZE), Image.LANCZOS)

    halo = body.filter(ImageFilter.GaussianBlur(40))
    out.alpha_composite(coloured(halo.point(lambda v: int(v * 0.75)), VIOLET, VIOLET_DEEP))

    edge = body.filter(ImageFilter.GaussianBlur(2))
    out.alpha_composite(coloured(edge.point(lambda v: int(v * 0.6)), MAGENTA, VIOLET))
    out.alpha_composite(coloured(body, MAGENTA, VIOLET_DEEP))
    out.alpha_composite(
        coloured(
            core.filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.72)),
            CORE,
            MAGENTA,
        )
    )

    out.convert("RGB").save(OUT)
    out.resize((180, 180), Image.LANCZOS).save(HERE / "icon-horizon-180.png")
    print("wrote", OUT)
    return 0

if __name__ == "__main__":
    sys.exit(main())
