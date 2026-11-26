#!/usr/bin/env python3
"""Combine each light/dark screenshot pair into one diagonally split PNG.

Raw captures come from integration_test/screenshots_test.dart (Linux runner).
Usage: python3 tool/compose_screenshots.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RAW = Path("/tmp/opencode/nowpill-shots")
OUT = ROOT / "doc" / "screenshots"
PAGES = ["today", "tasks", "habits", "stats", "chat", "settings"]
TARGET_WIDTH = 480
MAX_BYTES = 80 * 1024
MINT = "#2DD4A8"


def compose(page: str) -> Path:
    light = Image.open(RAW / f"{page}-light.png").convert("RGBA")
    dark = Image.open(RAW / f"{page}-dark.png").convert("RGBA")
    if light.size != dark.size:
        raise ValueError(f"{page}: light/dark capture sizes differ")
    width, height = light.size

    # Light on the upper-left triangle, dark everywhere else. The seam runs
    # from the top-right corner to the bottom-left corner.
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).polygon([(0, 0), (width, 0), (0, height)], fill=255)
    combined = dark.copy()
    combined.paste(light, (0, 0), mask)

    # A subtle mint seam makes the diagonal read as intentional.
    draw = ImageDraw.Draw(combined)
    draw.line([(width, 0), (0, height)], fill=MINT, width=6)

    target_height = round(height * TARGET_WIDTH / width)
    combined = combined.convert("RGB").resize(
        (TARGET_WIDTH, target_height), Image.Resampling.LANCZOS
    )

    path = OUT / f"{page}-split.png"
    # 128-colour quantization keeps the flat M3 surfaces crisp while cutting
    # each asset to a fraction of its truecolour size.
    combined.quantize(colors=128, method=Image.Quantize.MEDIANCUT).save(
        path, optimize=True
    )
    if path.stat().st_size > MAX_BYTES:
        raise ValueError(f"{path.name} exceeds {MAX_BYTES // 1024} KiB")
    return path


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.png"):
        old.unlink()
    for page in PAGES:
        path = compose(page)
        print(f"{path.name}: {path.stat().st_size / 1024:.0f} KiB")


if __name__ == "__main__":
    main()
