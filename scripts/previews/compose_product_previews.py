#!/usr/bin/env python3
"""Compose Qingxu's real platform screenshots into release-ready previews."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


CANVAS = (2048, 1152)
EXPORT_CANVAS = (3840, 2160)
EXPORT_SHEET = (3840, 2880)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size=size)
    return ImageFont.load_default()


def load(path: Path) -> Image.Image:
    return Image.open(path).convert("RGB")


def cover(image: Image.Image, size: tuple[int, int], focus_y: float = 0.5) -> Image.Image:
    source_ratio = image.width / image.height
    target_ratio = size[0] / size[1]
    if source_ratio > target_ratio:
        new_height = size[1]
        new_width = round(new_height * source_ratio)
    else:
        new_width = size[0]
        new_height = round(new_width / source_ratio)
    resized = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
    left = max(0, (new_width - size[0]) // 2)
    top = max(0, min(new_height - size[1], round((new_height - size[1]) * focus_y)))
    return resized.crop((left, top, left + size[0], top + size[1]))


def rounded_paste(canvas: Image.Image, image: Image.Image, box: tuple[int, int, int, int], radius: int) -> None:
    width, height = box[2] - box[0], box[3] - box[1]
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width, height), radius=radius, fill=255)
    canvas.paste(cover(image, (width, height)), (box[0], box[1]), mask)


def gradient_background() -> Image.Image:
    top = (21, 35, 70)
    bottom = (27, 20, 30)
    canvas = Image.new("RGB", CANVAS)
    pixels = canvas.load()
    for y in range(CANVAS[1]):
        t = y / (CANVAS[1] - 1)
        for x in range(CANVAS[0]):
            side = abs((x / CANVAS[0]) - 0.5) * 0.14
            pixels[x, y] = tuple(
                max(0, min(255, round(top[channel] * (1 - t) + bottom[channel] * t - side * 24)))
                for channel in range(3)
            )
    glow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((1150, 510, 2300, 1400), fill=(120, 78, 71, 92))
    glow = glow.filter(ImageFilter.GaussianBlur(170))
    return Image.alpha_composite(canvas.convert("RGBA"), glow).convert("RGB")


def draw_label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str) -> None:
    draw.rounded_rectangle((xy[0], xy[1], xy[0] + 144, xy[1] + 48), radius=24, fill=(255, 255, 255, 30))
    draw.text((xy[0] + 72, xy[1] + 24), text, font=font(20, True), anchor="mm", fill=(238, 241, 248, 230))


def laptop(canvas: Image.Image, screenshot: Image.Image) -> None:
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((104, 128, 1432, 898), radius=42, fill=(0, 0, 0, 165))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    layer = Image.alpha_composite(layer, shadow)
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((116, 118, 1420, 886), radius=40, fill=(18, 19, 23), outline=(90, 93, 102), width=4)
    draw.rounded_rectangle((138, 142, 1398, 850), radius=23, fill=(7, 8, 10))
    rounded_paste(layer, screenshot, (148, 152, 1388, 840), 16)
    draw.rounded_rectangle((735, 127, 805, 136), radius=5, fill=(6, 7, 9))
    draw.polygon([(70, 886), (1466, 886), (1562, 970), (0, 970)], fill=(26, 27, 31), outline=(83, 86, 94))
    draw.rounded_rectangle((0, 954, 1562, 988), radius=17, fill=(13, 14, 17))
    draw.rounded_rectangle((615, 894, 947, 914), radius=10, fill=(9, 10, 12))
    draw_label(draw, (140, 70), "macOS")
    canvas.paste(layer, (0, 0), layer)


def phone(canvas: Image.Image, screenshot: Image.Image, box: tuple[int, int, int, int], label: str) -> None:
    x0, y0, x1, y1 = box
    width, height = x1 - x0, y1 - y0
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x0 - 10, y0 + 8, x1 + 10, y1 + 26), radius=width // 7, fill=(0, 0, 0, 190)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    layer = Image.alpha_composite(layer, shadow)
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((x0, y0, x1, y1), radius=width // 7, fill=(10, 11, 14), outline=(110, 113, 121), width=4)
    inset = max(10, width // 28)
    screen = (x0 + inset, y0 + inset, x1 - inset, y1 - inset)
    rounded_paste(layer, screenshot, screen, max(24, width // 9))
    island_width = round(width * 0.28)
    island_height = max(15, round(width * 0.045))
    draw.rounded_rectangle(
        (
            x0 + (width - island_width) // 2,
            y0 + inset + 8,
            x0 + (width + island_width) // 2,
            y0 + inset + 8 + island_height,
        ),
        radius=island_height // 2,
        fill=(3, 4, 5),
    )
    draw_label(draw, (x0 + (width - 144) // 2, y0 - 62), label)
    canvas.paste(layer, (0, 0), layer)


def windows_card(canvas: Image.Image, screenshot: Image.Image) -> None:
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((620, 804, 1330, 1085), radius=42, fill=(0, 0, 0, 175))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    layer = Image.alpha_composite(layer, shadow)
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(
        (630, 792, 1320, 1068),
        radius=38,
        fill=(25, 27, 32, 238),
        outline=(255, 255, 255, 34),
        width=2,
    )
    rounded_paste(layer, screenshot, (658, 820, 1292, 1040), 25)
    draw_label(draw, (656, 730), "Windows")
    canvas.paste(layer, (0, 0), layer)


def contact_sheet(images: dict[str, Image.Image], output: Path) -> None:
    sheet = Image.new("RGB", (2048, 1536), (12, 14, 18))
    draw = ImageDraw.Draw(sheet)
    cells = {
        "iOS": (48, 110, 1000, 740),
        "Android": (1048, 110, 2000, 740),
        "macOS": (48, 860, 1000, 1490),
        "Windows": (1048, 860, 2000, 1490),
    }
    for label, box in cells.items():
        draw.text((box[0], box[1] - 58), label, font=font(28, True), fill=(240, 242, 247))
        draw.rounded_rectangle(box, radius=30, fill=(27, 29, 34), outline=(67, 70, 78), width=2)
        inner = (box[0] + 14, box[1] + 14, box[2] - 14, box[3] - 14)
        rounded_paste(sheet, images[label], inner, 22)
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet = sheet.resize(EXPORT_SHEET, Image.Resampling.LANCZOS)
    sheet.save(output, quality=96, optimize=True)


def contain(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    copy = image.copy()
    copy.thumbnail(size, Image.Resampling.LANCZOS)
    return copy


def clean_windows_preview(source: Image.Image) -> Image.Image:
    width = max(960, source.width * 3)
    height = max(300, source.height * 3)
    result = Image.new("RGB", (width, height), (16, 18, 23))
    scaled = contain(source, (width - 96, height - 96))
    x = (width - scaled.width) // 2
    y = (height - scaled.height) // 2
    mask = Image.new("L", scaled.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, scaled.width, scaled.height),
        radius=max(18, scaled.height // 2),
        fill=255,
    )
    result.paste(scaled, (x, y), mask)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ios", type=Path, required=True)
    parser.add_argument("--android", type=Path, required=True)
    parser.add_argument("--macos", type=Path, required=True)
    parser.add_argument("--windows", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    images = {
        "iOS": load(args.ios),
        "Android": load(args.android),
        "macOS": load(args.macos),
        "Windows": clean_windows_preview(load(args.windows)),
    }
    output = args.output_dir
    output.mkdir(parents=True, exist_ok=True)

    hero = gradient_background()
    laptop(hero, images["macOS"])
    windows_card(hero, images["Windows"])
    phone(hero, images["iOS"], (1330, 240, 1668, 1018), "iOS")
    phone(hero, images["Android"], (1652, 314, 1952, 1004), "Android")
    hero = hero.resize(EXPORT_CANVAS, Image.Resampling.LANCZOS)
    hero.save(output / "qingxu-product-hero.png", quality=96, optimize=True)

    contact_sheet(images, output / "qingxu-platform-previews.png")
    for label, source in images.items():
        source.save(output / f"qingxu-preview-{label.lower()}.png", optimize=True)


if __name__ == "__main__":
    main()
