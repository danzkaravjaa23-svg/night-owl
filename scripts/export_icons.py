"""Export the approved Night Owl reference icon to existing platform asset slots.

Run from any directory: python3 scripts/export_icons.py (requires Pillow).
This performs size/format exports; the creative source stays unchanged.

Full-bleed slots (iOS, legacy Android ic_launcher.png, web Icon-192/512 with
purpose "any", favicon) get the opaque master `night_owl_icon.png` as before.

Masked slots get the transparent owl mark `night_owl_mark.png` with safe-zone
padding so no launcher mask can clip the ear tufts:
- Android adaptive foreground: 108 dp transparent layer; the whole owl
  (ear tips included) fits a circle of radius OWL_RADIUS_ADAPTIVE (31.5 dp),
  inside the guaranteed 66 dp safe circle (radius 33 dp).
- Web maskable: solid #0B0D17 square; the owl fits a circle of radius
  OWL_RADIUS_MASKABLE (37 percent of the icon), inside the 80 percent
  maskable safe circle (radius 40 percent).
- Android 13+ themed icon (monochrome layer): the same owl silhouette and
  placement, with the light eye rings and beak cut out as holes.
"""
from pathlib import Path
import json
import math
from PIL import Image, ImageChops, ImageFilter

root = Path(__file__).resolve().parents[1]
source = Image.open(root / "assets/icons/night_owl_icon.png").convert("RGB")
NAVY = "#0B0D17"  # Brand Midnight Navy, also the adaptive background layer.

# Fraction of the canvas width used as the radius of the circle that must
# contain every opaque owl pixel.
OWL_RADIUS_ADAPTIVE = 31.5 / 108
OWL_RADIUS_MASKABLE = 0.37


def export(path, size):
    source.resize((size, size), Image.Resampling.LANCZOS).save(path)


def load_owl():
    """Return the cleaned owl mark cropped to its alpha box, plus the point
    (in cropped pixels) to place at the canvas centre and the owl's radius
    around that point.

    The mark has alpha-1 dust outside the owl and alpha ~251-253 inside it;
    snap both so the foreground is crisp and fully opaque.
    """
    mark = Image.open(root / "assets/icons/night_owl_mark.png").convert("RGBA")
    alpha = mark.getchannel("A").point(
        lambda v: 0 if v <= 2 else (255 if v >= 245 else v))
    mark.putalpha(alpha)
    mark = mark.crop(alpha.getbbox())
    alpha = mark.getchannel("A")

    # Opaque points on a coarse grid, enough to measure the outline.
    step = 3
    w, h = mark.size
    points = [(x, y) for y in range(0, h, step) for x in range(0, w, step)
              if alpha.getpixel((x, y)) > 128]

    def radius(cy):
        return max(math.hypot(x - w / 2, y - cy) for x, y in points)

    # The smallest enclosing circle (x fixed at the horizontal centre)
    # sits high because of the ear tufts; the box centre sits low. Use the
    # midpoint between them so the round body stays visually centred while
    # the tufts keep a margin.
    tight = min(range(0, h, 4), key=radius)
    cy = (tight + h / 2) / 2
    return mark, (w / 2, cy), radius(cy) + step


OWL, OWL_CENTRE, OWL_RADIUS = load_owl()


def monochrome_owl():
    """Single-colour owl for the themed icon: opaque silhouette minus the
    light parts (eye rings, beak), so the face reads under any tint."""
    solid = OWL.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    light = OWL.convert("RGB").convert("L").point(lambda v: 255 if v > 175 else 0)
    shape = ImageChops.subtract(solid, light.filter(ImageFilter.MedianFilter(9)))
    mono = Image.new("RGBA", OWL.size, (255, 255, 255, 0))
    mono.putalpha(shape)
    return mono


MONO = monochrome_owl()


def export_owl(path, size, radius_fraction, background, art=None):
    """Place the owl so its enclosing circle has radius_fraction * size."""
    art = art or OWL
    scale = radius_fraction * size / OWL_RADIUS
    # Render at 4x and reduce, for clean edges at small sizes.
    big = size * 4
    owl_w = round(OWL.width * scale * 4)
    owl_h = round(OWL.height * scale * 4)
    owl = art.resize((owl_w, owl_h), Image.Resampling.LANCZOS)
    left = round(big / 2 - OWL_CENTRE[0] * scale * 4)
    top = round(big / 2 - OWL_CENTRE[1] * scale * 4)
    canvas = Image.new("RGBA", (big, big), background or (0, 0, 0, 0))
    canvas.alpha_composite(owl, (left, top))
    canvas = canvas.resize((size, size), Image.Resampling.LANCZOS)
    (canvas.convert("RGB") if background else canvas).save(path)


ios = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for row in json.loads((ios / "Contents.json").read_text())["images"]:
    export(ios / row["filename"], round(float(row["size"].split("x")[0]) * int(row["scale"][0])))
for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    folder = root / f"android/app/src/main/res/mipmap-{density}"
    export(folder / "ic_launcher.png", size)
    adaptive_size = round(size * 108 / 48)
    export_owl(folder / "ic_launcher_foreground.png", adaptive_size, OWL_RADIUS_ADAPTIVE, None)
    export_owl(folder / "ic_launcher_monochrome.png", adaptive_size, OWL_RADIUS_ADAPTIVE, None, MONO)
    Image.new("RGB", (adaptive_size, adaptive_size), NAVY).save(folder / "ic_launcher_background.png")
for size in [192, 512]:
    export(root / f"web/icons/Icon-{size}.png", size)
    export_owl(root / f"web/icons/Icon-maskable-{size}.png", size, OWL_RADIUS_MASKABLE, NAVY)
export(root / "web/favicon.png", 48)
scale = OWL_RADIUS_ADAPTIVE * 108 / OWL_RADIUS
print(f"Owl in adaptive layer: {OWL.width * scale:.1f} x {OWL.height * scale:.1f} dp "
      f"({OWL.width * scale / 108:.1%} of 108 dp), enclosing radius {OWL_RADIUS_ADAPTIVE * 108:.1f} dp.")
scale = OWL_RADIUS_MASKABLE / OWL_RADIUS
print(f"Owl in maskable icon: {OWL.width * scale:.1%} of the width, "
      f"enclosing radius {OWL_RADIUS_MASKABLE:.0%} (safe circle 40%).")
print("Exported Night Owl icons for iOS, Android and web.")
