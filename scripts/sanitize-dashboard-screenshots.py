#!/usr/bin/env python3
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except Exception as exc:  # pragma: no cover - dependency check path
    raise SystemExit(f"Pillow is required to sanitize screenshots: {exc}")


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "docs/wiki/assets"
LIVE_DIR = ASSET_DIR / "live"


def label(draw, rect, text):
    draw.rectangle(rect, fill=(245, 247, 250), outline=(205, 213, 223))
    draw.text((rect[0] + 12, rect[1] + 12), text, fill=(55, 65, 81))


def sanitize_wazuh():
    source = LIVE_DIR / "wazuh-authenticated-overview.png"
    target = ASSET_DIR / "wazuh-authenticated-overview-sanitized.png"
    image = Image.open(source).convert("RGB")
    draw = ImageDraw.Draw(image)

    masks = [
        ((210, 95, 320, 170), "count redacted"),
        ((500, 110, 1370, 245), "live alert volumes redacted"),
        ((1325, 0, 1435, 52), "user redacted"),
    ]
    for rect, text in masks:
        label(draw, rect, text)

    image.save(target)


def sanitize_oci():
    source = LIVE_DIR / "oci-log-analytics-explorer.png"
    target = ASSET_DIR / "oci-log-analytics-explorer-sanitized.png"
    image = Image.open(source).convert("RGB")
    draw = ImageDraw.Draw(image)

    masks = [
        ((1030, 84, 1265, 130), "time/job redacted"),
        ((1388, 0, 1440, 60), "user redacted"),
        ((690, 170, 1000, 430), "chart counts redacted"),
        ((890, 500, 1370, 1000), "log volumes redacted"),
        ((1235, 478, 1375, 500), "result count redacted"),
    ]
    for rect, text in masks:
        label(draw, rect, text)

    image.save(target)


def main():
    sanitize_wazuh()
    sanitize_oci()


if __name__ == "__main__":
    main()
