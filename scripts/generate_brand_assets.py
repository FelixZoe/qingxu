#!/usr/bin/env python3
"""Generate Qingxu brand assets from one reproducible serif glyph master."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


CANVAS = 1024
GLYPH = "清"
INK = "#171816"
PAPER = "#F5F2EA"


def render_master(font_path: Path, background: str, foreground: str) -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS), background)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(font_path), 550)
    bounds = draw.textbbox((0, 0), GLYPH, font=font)
    glyph_width = bounds[2] - bounds[0]
    glyph_height = bounds[3] - bounds[1]
    position = (
        (CANVAS - glyph_width) / 2 - bounds[0],
        (CANVAS - glyph_height) / 2 - bounds[1] - 18,
    )
    draw.text(position, GLYPH, font=font, fill=foreground)
    return image


def save_resized(master: Image.Image, destination: Path, size: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    master.resize((size, size), Image.Resampling.LANCZOS).save(destination)


def generate(repo: Path, font_path: Path) -> None:
    dark_master = render_master(font_path, INK, PAPER)
    light_master = render_master(font_path, PAPER, INK)
    transparent_mark = render_master(font_path, "#00000000", "#000000")

    branding = repo / "apps/flutter/assets/branding"
    dark_master.convert("RGB").save(branding / "qingxu-icon-master-black.png")
    light_master.convert("RGB").save(branding / "qingxu-icon-master-white.png")

    ios = repo / "apps/flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    ios_sizes = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for name, size in ios_sizes.items():
        save_resized(dark_master.convert("RGB"), ios / name, size)

    macos = repo / "apps/flutter/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_resized(dark_master.convert("RGB"), macos / f"app_icon_{size}.png", size)

    android = repo / "apps/flutter/android/app/src/main/res"
    for density, size in {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }.items():
        save_resized(
            dark_master.convert("RGB"),
            android / f"mipmap-{density}/ic_launcher.png",
            size,
        )

    mark_set = (
        repo
        / "apps/flutter/ios/Runner/Assets.xcassets/QingxuLaunchMark.imageset"
    )
    for scale, size in (("1x", 160), ("2x", 320), ("3x", 480)):
        save_resized(transparent_mark, mark_set / f"QingxuLaunchMark@{scale}.png", size)

    icon_path = repo / "apps/flutter/windows/runner/resources/app_icon.ico"
    icon_path.parent.mkdir(parents=True, exist_ok=True)
    dark_master.convert("RGBA").save(
        icon_path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--font",
        type=Path,
        default=Path("C:/Windows/Fonts/NotoSerifSC-VF.ttf"),
    )
    args = parser.parse_args()
    if not args.font.is_file():
        raise SystemExit(f"Noto Serif SC font not found: {args.font}")
    generate(args.repo.resolve(), args.font.resolve())


if __name__ == "__main__":
    main()
