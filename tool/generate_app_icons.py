#!/usr/bin/env python3
"""Generate Flutter launcher icons from assets/icon/app_icon.png."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets/icon/app_icon.png"


def _padded_square(src: Image.Image) -> Image.Image:
    """Inset logo ~12% so small launcher sizes stay sharp."""
    src = src.convert("RGBA")
    w, h = src.size
    inset = int(w * 0.12)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    inner = src.resize((w - inset * 2, h - inset * 2), Image.Resampling.LANCZOS)
    canvas.paste(inner, (inset, inset), inner)
    return canvas


def resize(src: Image.Image, size: int) -> Image.Image:
    prepared = _padded_square(src)
    return prepared.resize((size, size), Image.Resampling.LANCZOS)


def save_png(path: Path, img: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


def android_icons(src: Image.Image) -> None:
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in sizes.items():
        save_png(
            ROOT / f"android/app/src/main/res/{folder}/ic_launcher.png",
            resize(src, px),
        )


def ios_icons(src: Image.Image) -> None:
    mapping = {
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
    out = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, px in mapping.items():
        save_png(out / name, resize(src, px))


def macos_icons(src: Image.Image) -> None:
    mapping = {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }
    out = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, px in mapping.items():
        save_png(out / name, resize(src, px))


def web_icons(src: Image.Image) -> None:
    out = ROOT / "web/icons"
    for name, px in (
        ("Icon-192.png", 192),
        ("Icon-512.png", 512),
        ("Icon-maskable-192.png", 192),
        ("Icon-maskable-512.png", 512),
    ):
        save_png(out / name, resize(src, px))
    save_png(ROOT / "web/favicon.png", resize(src, 32))


def windows_ico(src: Image.Image, path: Path) -> None:
    sizes = [16, 32, 48, 64, 128, 256]
    images = [resize(src, s) for s in sizes]
    path.parent.mkdir(parents=True, exist_ok=True)
    images[0].save(
        path,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=images[1:],
    )


def main() -> None:
    if not SRC.is_file():
        raise SystemExit(f"Missing source icon: {SRC}")
    src = Image.open(SRC).convert("RGBA")
    android_icons(src)
    ios_icons(src)
    macos_icons(src)
    web_icons(src)
    windows_ico(src, ROOT / "windows/runner/resources/app_icon.ico")
    print("Generated launcher icons from", SRC)


if __name__ == "__main__":
    main()
