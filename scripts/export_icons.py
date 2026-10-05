"""Export the approved Night Owl reference icon to existing platform asset slots.

Run from any directory: python3 scripts/export_icons.py (requires Pillow).
This performs size/format exports; the creative source stays unchanged.
"""
from pathlib import Path
import json
from PIL import Image

root = Path(__file__).resolve().parents[1]
source = Image.open(root / "assets/icons/night_owl_icon.png").convert("RGB")

def export(path, size):
    source.resize((size, size), Image.Resampling.LANCZOS).save(path)

ios = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for row in json.loads((ios / "Contents.json").read_text())["images"]:
    export(ios / row["filename"], round(float(row["size"].split("x")[0]) * int(row["scale"][0])))
for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    folder = root / f"android/app/src/main/res/mipmap-{density}"
    export(folder / "ic_launcher.png", size)
    adaptive_size = round(size * 108 / 48)
    export(folder / "ic_launcher_foreground.png", adaptive_size)
    Image.new("RGB", (adaptive_size, adaptive_size), "#0B0D17").save(folder / "ic_launcher_background.png")
for size in [192, 512]:
    export(root / f"web/icons/Icon-{size}.png", size)
    export(root / f"web/icons/Icon-maskable-{size}.png", size)
export(root / "web/favicon.png", 48)
print("Exported Night Owl icons for iOS, Android and web.")
