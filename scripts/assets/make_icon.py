#!/usr/bin/env python3
"""Build Shoes On icon derivatives from the source drawn by draw_icon.py."""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/assets/forward_time_icon.png"
ICON_SIZE = 1024


def load_icon() -> Image.Image:
    with Image.open(SOURCE) as source:
        if source.width != source.height:
            raise ValueError(f"Icon source must be square, got {source.size}")
        return source.convert("RGB").resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)


def rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, img.size[0] - 1, img.size[1] - 1],
        radius=radius,
        fill=255,
    )
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def main() -> None:
    icon = load_icon()
    for rel in [
        "ShoesOn/Assets.xcassets/AppIcon.appiconset",
        "ShoesOnWatch/Assets.xcassets/AppIcon.appiconset",
    ]:
        path = ROOT / rel
        path.mkdir(parents=True, exist_ok=True)
        icon.save(path / "icon_1024.png")

    mark = ROOT / "ShoesOn/Assets.xcassets/OnboardingMark.imageset"
    mark.mkdir(parents=True, exist_ok=True)
    rounded(icon.resize((264, 264), Image.LANCZOS), 60).save(
        mark / "onboarding_mark.png"
    )
    icon.resize((256, 256), Image.LANCZOS).save(ROOT / "docs/icon_256.png")
    print("icons written")


if __name__ == "__main__":
    main()
