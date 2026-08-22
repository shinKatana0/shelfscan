#!/usr/bin/env python3
"""Generates app/windows/runner/resources/app_icon.ico from code.

No dependencies: PNG is written by hand (zlib and crc32 are stdlib) and the
VEX container is a header plus one PNG per size. The point is that the icon is
auditable and reproducible rather than a binary nobody can regenerate -- run
this and diff the result if you doubt what is committed.

    python3 tool/make_icon.py

The subject is a shelf of game cases seen head on: four spines standing on a
shelf line, the rightmost leaning, which is the cue that reads as "shelf"
rather than "bar chart" at 16 px. Rendered at 4x and box-filtered down, which
is what keeps the lean from stairstepping at small sizes.
"""

import struct
import zlib

SIZES = [16, 24, 32, 48, 64, 128, 256]
SS = 4  # supersampling factor

BG = (0x1E, 0x24, 0x30, 255)      # slate, dark enough for a light taskbar
SHELF = (0x8A, 0x93, 0xA6, 255)   # the shelf board
SPINES = [
    # (x, width, height, colour) in a 0..1 unit square, y grows downward
    (0.135, 0.105, 0.44, (0xD9, 0x5F, 0x4B, 255)),   # warm red
    (0.255, 0.085, 0.55, (0xE8, 0xB1, 0x4C, 255)),   # amber
    (0.355, 0.115, 0.38, (0x4F, 0x9D, 0x8B, 255)),   # teal
    (0.485, 0.100, 0.50, (0x6F, 0x8A, 0xD4, 255)),   # blue
]
LEAN = (0.685, 0.115, 0.42, (0xC8, 0x7C, 0xD0, 255), -9.0)  # degrees

# The leaning case must not touch the upright beside it. Its top-left corner
# travels left as the lean grows, and at -11 degrees it crossed into the blue
# spine's column and read as one shape rather than two. MIN_GAP is checked at
# import so a change to any of the numbers above cannot quietly restore that.
MIN_GAP = 0.025

SHELF_Y = 0.775   # top of the shelf board
SHELF_H = 0.055
CORNER = 0.18     # background corner radius


def _check_gap():
    poly = _lean_poly(*LEAN[:3], LEAN[4])
    leftmost = min(px for px, _ in poly)
    neighbour = max(x + w for x, w, _, _ in SPINES)
    gap = leftmost - neighbour
    if gap < MIN_GAP:
        raise SystemExit(
            'the leaning case overlaps its neighbour: gap %.3f, minimum %.3f. '
            'Move LEAN right, shorten it, or reduce the angle.' % (gap, MIN_GAP)
        )
    return gap


def _rounded(x, y, r):
    """Inside the unit rounded square?"""
    cx = min(max(x, r), 1 - r)
    cy = min(max(y, r), 1 - r)
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r


def _in_poly(px, py, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > py) != (y2 > py):
            xt = x1 + (py - y1) * (x2 - x1) / (y2 - y1)
            if px < xt:
                inside = not inside
    return inside


def _lean_poly(x, w, h, deg):
    """A spine rotated about the point where it meets the shelf."""
    import math
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    px, py = x + w / 2, SHELF_Y
    pts = [(x, SHELF_Y - h), (x + w, SHELF_Y - h), (x + w, SHELF_Y), (x, SHELF_Y)]
    out = []
    for qx, qy in pts:
        dx, dy = qx - px, qy - py
        out.append((px + dx * ca - dy * sa, py + dx * sa + dy * ca))
    return out


def _over(dst, src):
    """src over dst, both straight RGBA 0..255."""
    sa = src[3] / 255.0
    if sa >= 1.0:
        return src
    da = dst[3] / 255.0
    oa = sa + da * (1 - sa)
    if oa == 0:
        return (0, 0, 0, 0)
    return tuple(
        int(round((src[i] * sa + dst[i] * da * (1 - sa)) / oa)) for i in range(3)
    ) + (int(round(oa * 255)),)


def render(size):
    n = size * SS
    lean_poly = _lean_poly(*LEAN[:3], LEAN[4])
    rows = []
    for py in range(n):
        v = (py + 0.5) / n
        row = []
        for px in range(n):
            u = (px + 0.5) / n
            c = BG if _rounded(u, v, CORNER) else (0, 0, 0, 0)
            if c[3]:
                for x, w, h, col in SPINES:
                    if x <= u <= x + w and SHELF_Y - h <= v <= SHELF_Y:
                        c = _over(c, col)
                # Painted last so it stands in front. Leaning left, its top
                # edge crosses into the upright beside it; painted first, that
                # neighbour cut it down to a wedge rather than a case.
                if _in_poly(u, v, lean_poly):
                    c = _over(c, LEAN[3])
                if SHELF_Y <= v <= SHELF_Y + SHELF_H and 0.10 <= u <= 0.90:
                    c = _over(c, SHELF)
            row.append(c)
        rows.append(row)

    # box filter down to the requested size
    out = bytearray()
    for y in range(size):
        out.append(0)  # PNG filter: none
        for x in range(size):
            acc = [0, 0, 0, 0]
            for dy in range(SS):
                for dx in range(SS):
                    p = rows[y * SS + dy][x * SS + dx]
                    a = p[3]
                    acc[0] += p[0] * a
                    acc[1] += p[1] * a
                    acc[2] += p[2] * a
                    acc[3] += a
            if acc[3]:
                out += bytes(
                    (
                        min(255, acc[0] // acc[3]),
                        min(255, acc[1] // acc[3]),
                        min(255, acc[2] // acc[3]),
                        acc[3] // (SS * SS),
                    )
                )
            else:
                out += b"\0\0\0\0"
    return bytes(out)


def png(size, raw):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main():
    print('gap between the leaning case and its neighbour: %.3f' % _check_gap())
    images = [png(s, render(s)) for s in SIZES]
    out = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    for s, img in zip(SIZES, images):
        d = 0 if s == 256 else s
        out += struct.pack("<BBBBHHII", d, d, 0, 0, 1, 32, len(img), offset)
        offset += len(img)
    out += b"".join(images)

    path = "app/windows/runner/resources/app_icon.ico"
    with open(path, "wb") as f:
        f.write(out)
    print(f"{path}: {len(out)} bytes, {len(images)} sizes {SIZES}")


if __name__ == "__main__":
    main()
