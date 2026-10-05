#!/usr/bin/env python3
"""Draw the Shoes On icon source: a dial whose hand leaves through a gap.

Writes scripts/assets/forward_time_icon.png; run make_icon.py after it.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent / "forward_time_icon.png"
SIZE = 1024
SCALE = 4  # supersample, then downscale for smooth edges

BG_TOP = (0xFF, 0xD5, 0x4A)
BG_BOTTOM = (0xFF, 0x9A, 0x2E)
RING = (0x2A, 0x1B, 0x6E)
HAND = (0xFF, 0xFF, 0xFF)

CENTER = (486, 552)
RADIUS, RING_WIDTH = 296, 96
HAND_ANGLE, GAP = -45, 84
SHAFT_WIDTH, HEAD_BASE, HEAD_TIP, HEAD_HALF = 86, 292, 462, 124
HUB_RADIUS = 74


def s(v: float) -> float:
    return v * SCALE


def point(angle: float, r: float) -> tuple[float, float]:
    a = math.radians(angle)
    return (s(CENTER[0]) + s(r) * math.cos(a), s(CENTER[1]) + s(r) * math.sin(a))


def dot(draw: ImageDraw.ImageDraw, c: tuple[float, float], r: float, fill: tuple) -> None:
    draw.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=fill)


def background() -> Image.Image:
    strip = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        strip.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    return strip.resize((s(SIZE), s(SIZE)), Image.BICUBIC)


def draw_ring(draw: ImageDraw.ImageDraw) -> None:
    start, end = HAND_ANGLE + GAP / 2, HAND_ANGLE - GAP / 2 + 360
    outer = RADIUS + RING_WIDTH / 2
    cx, cy = CENTER
    box = [s(cx - outer), s(cy - outer), s(cx + outer), s(cy + outer)]
    draw.arc(box, start, end, fill=RING, width=s(RING_WIDTH))
    for angle in (start, end):
        dot(draw, point(angle, RADIUS), s(RING_WIDTH / 2), RING)


def draw_hand(draw: ImageDraw.ImageDraw) -> None:
    center = (s(CENTER[0]), s(CENTER[1]))
    draw.line([center, point(HAND_ANGLE, HEAD_BASE + 10)], fill=HAND, width=s(SHAFT_WIDTH))
    bx, by = point(HAND_ANGLE, HEAD_BASE)
    nx, ny = math.cos(math.radians(HAND_ANGLE + 90)), math.sin(math.radians(HAND_ANGLE + 90))
    half = s(HEAD_HALF)
    head = [(bx + nx * half, by + ny * half), point(HAND_ANGLE, HEAD_TIP), (bx - nx * half, by - ny * half)]
    draw.polygon(head, fill=HAND)
    dot(draw, center, s(HUB_RADIUS), RING)


def main() -> None:
    img = background()
    draw = ImageDraw.Draw(img)
    draw_ring(draw)
    draw_hand(draw)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
