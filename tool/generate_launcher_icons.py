#!/usr/bin/env python3
"""Regenerate the Android launcher icons from the logo.

Run by hand, not by CI:

    pip install Pillow && python3 tool/generate_launcher_icons.py

It needs Pillow, which is not a project dependency and never will be — the
output is committed, so nobody building the app has to run this. It exists so
the icons are *reproducible* from the artwork rather than being opaque binaries
somebody once exported from a design tool.

Three things about the output are deliberate.

**The adaptive foreground is opaque, black-backed, not matted.** The artwork
sits on a textured near-black, and the darkest ink in the mark (the navy
outline, ``#111240``) is barely brighter than that texture — so any
alpha-from-luminance matte eats the outline and fringes the whole flower. The
background layer is the same black, so an opaque foreground is pixel-identical
to a perfectly matted one over it, and has no keying artifacts at all. It costs
nothing: the mask clips both layers, and parallax moves black over black.

**The monochrome layer knocks the kanji out of the petals** rather than being a
solid silhouette. Android 13+ themed icons use only the alpha channel, so a
filled flower blob would lose the one element that says which app this is.
Keeping the navy as a hole means the tinted icon still reads as 才 in a flower.

**Content stops at 62% of the adaptive canvas.** The guaranteed-safe zone is
66dp of 108dp (61%); the flower's bounding box corners are empty, so 62% of the
box keeps the ink itself inside the circle on every launcher mask.
"""

import colorsys
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "branding", "otaku_reader_logo.jpg")
RES = os.path.join(HERE, os.pardir, "android", "app", "src", "main", "res")

# Measured off the artwork, not picked by eye. See CLAUDE.md.
GROUND = (10, 10, 11)

# The flower alone, excluding the "OTAKU READER" wordmark: at 48dp the wordmark
# is three pixels tall and turns to mush, so the icon is the mark's symbol only.
FLOWER_BOX = (67, 54, 935, 861)

# Android's launcher-icon densities, as multiples of the mdpi baseline.
DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}

ADAPTIVE_DP = 108  # the adaptive-icon canvas
LEGACY_DP = 48  # the pre-API-26 launcher icon
SAFE_FRACTION = 0.62  # of the adaptive canvas; the safe circle is 66/108
LEGACY_FRACTION = 0.84  # of the legacy square, which is not masked as hard
ROUND_FRACTION = 0.72  # of the round icon's diameter


def _is_ink(r, g, b):
    """True for artwork, false for the textured black it sits on."""
    high, low = max(r, g, b), min(r, g, b)
    return high > 80 or (high - low > 28 and high > 45)


def _is_petal(r, g, b):
    """True for the pink and coral inks, false for the navy and the ground.

    This is what the monochrome layer keeps, so the navy kanji reads as a hole.
    """
    if not _is_ink(r, g, b):
        return False
    hue, light, sat = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    degrees = hue * 360
    return sat > 0.25 and light > 0.28 and (degrees >= 290 or degrees <= 60)


def _flower():
    return Image.open(SOURCE).convert("RGB").crop(FLOWER_BOX)


def _fitted(source, canvas, fraction):
    """Scale `source` so its longest side is `fraction` of `canvas`, centred."""
    target = max(1, round(canvas * fraction))
    scale = target / max(source.size)
    size = (max(1, round(source.width * scale)), max(1, round(source.height * scale)))
    resized = source.resize(size, Image.LANCZOS)
    return resized, ((canvas - size[0]) // 2, (canvas - size[1]) // 2)


def _write(image, density, name):
    """Save one mipmap, in the smallest encoding that does not lose anything.

    The artwork is a halftone-textured JPEG, so a straight truecolour PNG of it
    compresses badly — the xxxhdpi foreground alone is 110 KB, and there are
    twenty of these. Two encodings fix that without a visible difference:

    * opaque layers quantise to a 256-colour palette. Measured against the
      truecolour original that is a **mean absolute error of 0.44/255** for
      **half the bytes**, on artwork that was already dithered.
    * the monochrome layer is one colour and an alpha mask, so it is stored as
      greyscale-plus-alpha rather than as three identical channels.

    The round layer keeps its truecolour encoding: palette PNGs carry alpha as
    a `tRNS` table, which quantises the anti-aliased circle edge into visible
    steps. It is the smallest of the four anyway.
    """
    folder = os.path.join(RES, "mipmap-" + density)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name + ".png")
    if image.mode == "RGB":
        image = image.quantize(colors=256, method=Image.MEDIANCUT,
                               dither=Image.FLOYDSTEINBERG)
    elif name.endswith("monochrome"):
        image = image.convert("LA")
    image.save(path, optimize=True)
    print("  {:>28}  {}x{}  {}".format(
        os.path.relpath(path, RES), *image.size, os.path.getsize(path)))


def _monochrome_mask(flower):
    """An alpha mask of the petals, with the navy kanji punched out."""
    mask = Image.new("L", flower.size, 0)
    pixels = flower.load()
    out = mask.load()
    for y in range(flower.height):
        for x in range(flower.width):
            if _is_petal(*pixels[x, y]):
                out[x, y] = 255
    return mask


def main():
    flower = _flower()
    mono_source = Image.new("RGBA", flower.size, (255, 255, 255, 0))
    mono_source.putalpha(_monochrome_mask(flower))

    for density, factor in DENSITIES.items():
        adaptive = round(ADAPTIVE_DP * factor)
        legacy = round(LEGACY_DP * factor)

        # Foreground: opaque, on the same black as the background layer.
        canvas = Image.new("RGB", (adaptive, adaptive), GROUND)
        art, at = _fitted(flower, adaptive, SAFE_FRACTION)
        canvas.paste(art, at)
        _write(canvas, density, "ic_launcher_foreground")

        # Monochrome: alpha only. Android 13+ tints it and ignores the colour.
        #
        # Pasted **without** a mask. Passing `art` as its own mask looks like the
        # careful thing to do and squares the alpha: PIL composites every band,
        # including alpha, so against a transparent canvas the result is
        # `a*a` rather than `a`. Measured, that pushed 12,772 antialiased edge
        # pixels down to 7,986 — roughly 4,800 of them to fully transparent —
        # and hardened what was left. A plain paste into a transparent canvas is
        # a straight band copy, which is exactly the alpha the mask already has.
        # Found by `codeant-ai`.
        mono = Image.new("RGBA", (adaptive, adaptive), (255, 255, 255, 0))
        art, at = _fitted(mono_source, adaptive, SAFE_FRACTION)
        mono.paste(art, at)
        _write(mono, density, "ic_launcher_monochrome")

        # Legacy square, for API 24-25, which have no adaptive icons at all.
        square = Image.new("RGB", (legacy, legacy), GROUND)
        art, at = _fitted(flower, legacy, LEGACY_FRACTION)
        square.paste(art, at)
        _write(square, density, "ic_launcher")

        # Round, for launchers that ask for one.
        circle = Image.new("RGBA", (legacy, legacy), (0, 0, 0, 0))
        hole = Image.new("L", (legacy * 4, legacy * 4), 0)
        ImageDraw.Draw(hole).ellipse((0, 0, legacy * 4 - 1, legacy * 4 - 1), fill=255)
        hole = hole.resize((legacy, legacy), Image.LANCZOS)
        circle.paste(Image.new("RGB", (legacy, legacy), GROUND), (0, 0), hole)
        art, at = _fitted(flower, legacy, ROUND_FRACTION)
        circle.paste(art, at)
        circle.putalpha(hole)
        _write(circle, density, "ic_launcher_round")


if __name__ == "__main__":
    main()
