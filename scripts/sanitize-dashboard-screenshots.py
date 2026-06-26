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
    sanitize_named_wazuh("wazuh-authenticated-overview", "wazuh-authenticated-overview-sanitized")


def sanitize_named_wazuh(source_name, target_name):
    source = LIVE_DIR / f"{source_name}.png"
    target = ASSET_DIR / f"{target_name}.png"
    if not source.exists():
        return False
    image = Image.open(source).convert("RGB")
    if source_name == "wazuh-authenticated-overview" and looks_like_wazuh_login(image):
        print(f"skip={source.name} reason=wazuh_login_screen")
        return False
    draw = ImageDraw.Draw(image)

    masks = [
        ((210, 95, 320, 170), "count redacted"),
        ((500, 110, 1370, 245), "live alert volumes redacted"),
        ((1325, 0, 1435, 52), "user redacted"),
    ]
    for rect, text in masks:
        label(draw, rect, text)

    image.save(target)
    return True


def looks_like_wazuh_login(image):
    width, height = image.size
    sample_points = [
        (min(50, width - 1), min(50, height - 1)),
        (width // 2, height // 2),
        (width // 2, min(height - 1, int(height * 0.72))),
    ]
    pixels = [image.getpixel(point) for point in sample_points]
    blue_background = pixels[0][2] > 180 and pixels[0][0] < 90 and pixels[0][1] > 100
    central_form = pixels[1][0] > 200 and pixels[1][1] > 200 and pixels[1][2] > 200
    lower_blue = pixels[2][2] > 180 and pixels[2][0] < 90 and pixels[2][1] > 100
    return blue_background and central_form and lower_blue


def sanitize_oci():
    sanitize_named_oci("oci-log-analytics-explorer", "oci-log-analytics-explorer-sanitized")


def sanitize_named_oci(source_name, target_name):
    source = LIVE_DIR / f"{source_name}.png"
    target = ASSET_DIR / f"{target_name}.png"
    if not source.exists():
        return False
    image = Image.open(source).convert("RGB")
    draw = ImageDraw.Draw(image)

    masks = [
        ((0, 0, 1440, 92), "account banner redacted"),
        ((1030, 84, 1265, 130), "time/job redacted"),
        ((1388, 0, 1440, 60), "user redacted"),
        ((690, 170, 1000, 430), "chart counts redacted"),
        ((995, 145, 1362, 930), "live volume counts redacted"),
        ((890, 500, 1370, 1000), "log volumes redacted"),
        ((1235, 478, 1375, 500), "result count redacted"),
    ]
    for rect, text in masks:
        label(draw, rect, text)

    image.save(target)
    return True


def main():
    sanitize_wazuh()
    sanitize_oci()
    sanitize_named_wazuh("wazuh-discover-live", "wazuh-discover-live-sanitized")
    sanitize_named_wazuh("wazuh-dashboard-live", "wazuh-dashboard-live-sanitized")
    sanitize_named_oci("oci-log-analytics-dashboard-live", "oci-log-analytics-dashboard-live-sanitized")


if __name__ == "__main__":
    main()
