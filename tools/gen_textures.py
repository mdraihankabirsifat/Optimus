#!/usr/bin/env python3
"""Generate the cave's stone texture set: albedo, normal, roughness and AO.

Everything here is synthesised from noise, so there is nothing to licence, nothing to
credit, and nothing but a few hundred kilobytes added to the web build.

Run:  python3 tools/gen_textures.py
Out:  assets/textures/*.png

The normal maps are the point. Without them every surface in the cave is lit perfectly
flat no matter how much geometry sits behind it.
"""

import math
import os
import random
from PIL import Image, ImageChops, ImageFilter, ImageOps

SIZE = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")


def seamless_octave(cells, size, seed):
    """One octave of value noise that tiles cleanly.

    The trick is tiling the low-resolution grid 3x3 before upscaling and then cropping
    the middle. Interpolation near the edges then samples the wrapped neighbours, so the
    result matches itself on every side.
    """
    rng = random.Random(seed)
    small = Image.new("L", (cells, cells))
    small.putdata([rng.randint(0, 255) for _ in range(cells * cells)])

    tiled = Image.new("L", (cells * 3, cells * 3))
    for y in range(3):
        for x in range(3):
            tiled.paste(small, (x * cells, y * cells))

    scale = size // cells
    big = tiled.resize((cells * 3 * scale, cells * 3 * scale), Image.BICUBIC)
    return big.crop((size, size, size * 2, size * 2))


def fractal(size, seed, octaves=5, base_cells=4, persistence=0.5):
    """Sum several octaves into one height field.

    Accumulated as a running weighted average with Image.blend rather than a float
    buffer, because Pillow's chop operations reject float-mode images.
    """
    acc = None
    total = 0.0
    amplitude = 1.0
    cells = base_cells
    for i in range(octaves):
        if cells > size:
            break
        layer = seamless_octave(cells, size, seed + i * 977)
        if acc is None:
            acc = layer
            total = amplitude
        else:
            total_new = total + amplitude
            acc = Image.blend(acc, layer, amplitude / total_new)
            total = total_new
        amplitude *= persistence
        cells *= 2
    return acc


def veins(size, seed, sharpness=7.0):
    """Thin dark cracks, from the ridges of a noise field rather than its peaks."""
    n = fractal(size, seed, octaves=4, base_cells=6, persistence=0.55)
    # Ridge transform: values near the midpoint become bright lines.
    ridged = n.point(lambda v: int(max(0.0, 255.0 - abs(v - 128) * sharpness)))
    return ridged.filter(ImageFilter.GaussianBlur(0.6))


def height_field(seed, crack_strength=0.55):
    base = fractal(SIZE, seed, octaves=6, base_cells=4, persistence=0.52)
    detail = fractal(SIZE, seed + 5000, octaves=4, base_cells=32, persistence=0.5)
    h = Image.blend(base, detail, 0.35)
    crack = veins(SIZE, seed + 9000)
    h = ImageChops.subtract(h, crack.point(lambda v, s=crack_strength: int(v * s)))
    return ImageOps.autocontrast(h, cutoff=1)


def to_normal(height, strength=2.6):
    """Sobel the height field into a tangent-space normal map (OpenGL, +Y up)."""
    px = height.load()
    out = Image.new("RGB", (SIZE, SIZE))
    op = out.load()
    for y in range(SIZE):
        yn, yp = (y - 1) % SIZE, (y + 1) % SIZE
        for x in range(SIZE):
            xn, xp = (x - 1) % SIZE, (x + 1) % SIZE
            dx = (px[xp, y] - px[xn, y]) / 255.0 * strength
            dy = (px[x, yp] - px[x, yn]) / 255.0 * strength
            # Normalise (-dx, -dy, 1)
            inv = 1.0 / math.sqrt(dx * dx + dy * dy + 1.0)
            nx, ny, nz = -dx * inv, -dy * inv, inv
            op[x, y] = (int((nx * 0.5 + 0.5) * 255),
                        int((ny * 0.5 + 0.5) * 255),
                        int((nz * 0.5 + 0.5) * 255))
    return out


def to_albedo(height, tint, contrast=0.45):
    """Greyscale-leaning albedo so the material can tint it per surface at runtime."""
    base = height.point(lambda v: int(128 + (v - 128) * contrast))
    r, g, b = tint
    rgb = Image.merge("RGB", (
        base.point(lambda v: min(255, int(v * r))),
        base.point(lambda v: min(255, int(v * g))),
        base.point(lambda v: min(255, int(v * b))),
    ))
    return rgb


def to_roughness(height):
    """Recessed areas hold dust and read rougher; raised areas are worn smoother."""
    return height.point(lambda v: int(255 - (v - 128) * 0.55)).filter(
        ImageFilter.GaussianBlur(1.2))


def to_ao(height):
    """Cheap cavity approximation: how far below its local average each texel sits."""
    blurred = height.filter(ImageFilter.GaussianBlur(7))
    diff = ImageChops.subtract(blurred, height, scale=1, offset=0)
    return ImageOps.invert(diff.point(lambda v: min(255, int(v * 2.2))))


def build(name, seed, tint, crack_strength=0.55, normal_strength=2.6):
    print("  %s ..." % name, end="", flush=True)
    h = height_field(seed, crack_strength)
    to_albedo(h, tint).save(os.path.join(OUT, "%s_albedo.png" % name))
    to_normal(h, normal_strength).save(os.path.join(OUT, "%s_normal.png" % name))
    to_roughness(h).save(os.path.join(OUT, "%s_rough.png" % name))
    to_ao(h).save(os.path.join(OUT, "%s_ao.png" % name))
    print(" done")


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Generating stone texture set at %dx%d" % (SIZE, SIZE))
    # Three surfaces, deliberately different in character so a racer who has just rotated
    # their gravity can still tell floor from wall from ceiling at a glance.
    build("stone_floor", 1337, (1.02, 0.98, 0.94), crack_strength=0.40, normal_strength=2.2)
    build("stone_wall", 4242, (1.00, 1.00, 1.00), crack_strength=0.70, normal_strength=3.2)
    build("stone_ceiling", 8888, (0.96, 0.99, 1.04), crack_strength=0.55, normal_strength=2.8)
    print("Wrote to %s" % os.path.normpath(OUT))


if __name__ == "__main__":
    main()
