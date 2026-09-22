#!/usr/bin/env python3
"""Draws the Shoes On icon: an open door with daylight behind it."""
from pathlib import Path

from PIL import Image, ImageDraw

S = 4  # supersample
N = 1024 * S
INK = (23, 25, 28)
CREAM = (247, 244, 236)
GREEN = (33, 160, 110)
ROOT = Path(__file__).resolve().parents[2]


def s(v: float) -> int:
    return int(v * S)


def draw_icon() -> Image.Image:
    img = Image.new("RGB", (N, N), INK)
    d = ImageDraw.Draw(img)
    left, top, right, floor = 330, 200, 694, 812
    t = 40  # frame thickness
    # Daylight through the doorway.
    d.rectangle([s(left), s(top), s(right), s(floor)], fill=GREEN)
    # Frame: two posts and a lintel, square to the floor.
    d.rectangle([s(left - t), s(top - t), s(left), s(floor)], fill=CREAM)
    d.rectangle([s(right), s(top - t), s(right + t), s(floor)], fill=CREAM)
    d.rectangle([s(left - t), s(top - t), s(right + t), s(top)], fill=CREAM)
    # Door panel swung in, hinged on the left post.
    panel = [(left, top), (560, top + 64), (560, floor - 64), (left, floor)]
    d.polygon([(s(x), s(y)) for x, y in panel], fill=CREAM)
    d.ellipse([s(514), s(494), s(542), s(522)], fill=INK)
    # Floor.
    d.rounded_rectangle([s(210), s(floor), s(814), s(floor + 36)], radius=s(18), fill=CREAM)
    return img.resize((1024, 1024), Image.LANCZOS)


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


if __name__ == "__main__":
    icon = draw_icon()
    for rel in ["ShoesOn/Assets.xcassets/AppIcon.appiconset", "ShoesOnWatch/Assets.xcassets/AppIcon.appiconset"]:
        path = ROOT / rel
        path.mkdir(parents=True, exist_ok=True)
        icon.save(path / "icon_1024.png")
    mark = ROOT / "ShoesOn/Assets.xcassets/OnboardingMark.imageset"
    mark.mkdir(parents=True, exist_ok=True)
    rounded(icon.resize((264, 264), Image.LANCZOS), 60).save(mark / "onboarding_mark.png")
    icon.resize((256, 256), Image.LANCZOS).save(ROOT / "docs/icon_256.png")
    print("icons written")
