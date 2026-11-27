"""Prepare the courtyard's tiling soil colour from the project's CC0 gravel scan."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/third_party/polyhaven/textures/brown_mud_dry/brown_mud_dry_diff.jpg"
OUTPUT = ROOT / "assets/materials/packed_earth.webp"


def lowpass(pixels, radius):
    # A convolution near a tile boundary must see the other end of the same tile.
    pad = 3 * radius
    border = np.pad(pixels, ((pad, pad), (pad, pad), (0, 0)), mode="wrap")
    blurred = Image.fromarray(border).filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(blurred, dtype=float)[pad:-pad, pad:-pad]


if __name__ == "__main__":
    with Image.open(SOURCE) as scan:
        pixels = np.asarray(scan.convert("RGB"))
    clods = lowpass(pixels, 12)
    grains = lowpass(pixels, 2)
    detail = pixels - grains
    # Keep the shape and shade of clods. Pale chip faces should not read as
    # white sparks when several texels share a pixel in the gameplay camera.
    soil = clods + .66 * (grains - clods) + np.where(detail > 0, .24, .52) * detail
    OUTPUT.parent.mkdir(exist_ok=True)
    Image.fromarray(soil.round().clip(0, 255).astype("uint8")).save(OUTPUT, lossless=True)
