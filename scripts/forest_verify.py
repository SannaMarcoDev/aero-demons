#!/usr/bin/env python3
"""
Independent Python verification of the baked forest scatter (trees.bin) plus a
labelled diagnostic overlay of tree sites vs the density mask. This is a
separate implementation from the GDScript bake self-check (true cross-check).

Run:  python3 scripts/forest_verify.py
Reads res://assets/forest_test/trees.bin, the density mask, and writes
docs/forest_test/tree_density_nn.png (enlarged, coordinate-labelled, NN stats).
"""
import struct
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MASK = ROOT / "terrain/worldmachine/valtellina_forest_density.png"
# Defaults; override via argv:  python3 forest_verify.py [bin] [area] [cx,cz] [out]
BIN = ROOT / "assets/forest_test/trees.bin"
OUT = ROOT / "docs/forest_test/tree_density_nn.png"
AREA = 2000.0
CENTER = (0.0, -360.0)

# Centrally-configurable mask mapping (mirrors ForestConfig defaults).
WORLD_MIN = 15360.0
WORLD_SPAN = 30000.0
MASK_SIZE = 1025

# Verified per-model real world-space heights (m) from the bake (GLB import basis).
MODEL_HEIGHTS = [2.244587, 4.910969, 3.926477, 5.555243]

# Config defaults (mirror forest_config.tres).
SPACING = 15.0
MIN_H = 20.0
MAX_H = 30.0
SEED = 1337


def load_trees(path):
    data = path.read_bytes()
    magic, version, count, model_count = struct.unpack("<IIII", data[:16])
    assert magic == 0x33444633, "bad magic"
    assert version == 1, "bad version"
    rec = []
    off = 16
    for _ in range(count):
        x, y, z, yaw, scale = struct.unpack("<5f", data[off:off + 20])
        model = struct.unpack("<H", data[off + 20:off + 22])[0]
        off += 22
        rec.append((x, y, z, yaw, scale, model))
    return magic, version, count, model_count, rec


def sample_mask(x, z):
    u = (x + WORLD_MIN) / WORLD_SPAN
    v = (z + WORLD_MIN) / WORLD_SPAN
    if u < 0 or u > 1 or v < 0 or v > 1:
        return 0.0
    px = int(u * (MASK_SIZE - 1))
    py = int(v * (MASK_SIZE - 1))
    return mask_img[py, px] / 65535.0


def min_pairwise(recs):
    """All-pairs-via-spatial-grid minimum distance. cell = SPACING."""
    cell = SPACING
    grid = {}
    for r in recs:
        key = (int(np.floor(r[0] / cell)), int(np.floor(r[2] / cell)))
        grid.setdefault(key, []).append((r[0], r[2]))
    mind = float("inf")
    for r in recs:
        cx = int(np.floor(r[0] / cell))
        cz = int(np.floor(r[2] / cell))
        for ix in range(cx - 1, cx + 2):
            for iz in range(cz - 1, cz + 2):
                for q in grid.get((ix, iz), []):
                    d = ((r[0] - q[0]) ** 2 + (r[2] - q[1]) ** 2) ** 0.5
                    if d > 0 and d < mind:
                        mind = d
    return mind


def main():
    global mask_img, BIN, OUT, AREA, CENTER
    args = sys.argv[1:]
    if len(args) > 0:
        BIN = ROOT / args[0]
    if len(args) > 1:
        AREA = float(args[1])
    if len(args) > 2:
        cx, cz = args[2].split(",")
        CENTER = (float(cx), float(cz))
    if len(args) > 3:
        OUT = ROOT / args[3]
    mask_img = np.asarray(Image.open(MASK).convert("I"))
    magic, version, count, model_count, recs = load_trees(BIN)
    print(f"trees.bin: magic={magic:#x} version={version} count={count} model_count={model_count}")

    xs = np.array([r[0] for r in recs])
    ys = np.array([r[1] for r in recs])
    zs = np.array([r[2] for r in recs])
    scales = np.array([r[4] for r in recs])
    models = np.array([r[5] for r in recs])

    # Count / model distribution.
    dist = {m: int((models == m).sum()) for m in range(model_count)}
    print(f"count={count} model_dist={dist}")

    # Effective heights.
    eff = scales * np.array([MODEL_HEIGHTS[m] for m in models])
    print(f"effective height: min={eff.min():.3f}m max={eff.max():.3f}m (target {MIN_H}..{MAX_H}m)")
    assert MIN_H - 0.01 <= eff.min() and eff.max() <= MAX_H + 0.01, "height band violated"

    # Exact bounds.
    half = AREA / 2.0
    bx0, bx1 = CENTER[0] - half, CENTER[0] + half
    bz0, bz1 = CENTER[1] - half, CENTER[1] + half
    inb = np.all((xs >= bx0) & (xs <= bx1) & (zs >= bz0) & (zs <= bz1))
    print(f"bounds x[{bx0:.0f},{bx1:.0f}] z[{bz0:.0f},{bz1:.0f}] all_inside={inb} "
          f"x[{xs.min():.1f},{xs.max():.1f}] z[{zs.min():.1f},{zs.max():.1f}]")
    assert inb, "trees outside exact test bounds"

    # Black-mask rejection.
    dens = np.array([sample_mask(r[0], r[2]) for r in recs])
    nblack = int((dens <= 0.0).sum())
    print(f"black-mask rejection: trees on zero-density cells = {nblack} (must be 0)")
    assert nblack == 0, "tree placed on black mask cell"

    # Density bias (true /65535 values).
    area_cells = 0
    area_sum = 0.0
    step = SPACING
    x = bx0
    while x <= bx1:
        z = bz0
        while z <= bz1:
            area_sum += sample_mask(x, z)
            area_cells += 1
            z += step
        x += step
    area_mean = area_sum / max(area_cells, 1)
    tree_mean = float(dens.mean())
    print(f"density bias: tree-site mean={tree_mean:.4f} area mean={area_mean:.4f} (true /65535)")
    assert tree_mean > area_mean, "not biased toward dense cells"

    # Minimum pairwise distance (independent spatial grid).
    mind = min_pairwise(recs)
    print(f"min pairwise distance = {mind:.3f}m (required >= {SPACING}m)")
    assert mind >= SPACING - 0.01, "minimum spacing violated"

    # Nearest-neighbour stats (5x5 neighbourhood to capture sparse/isolated trees).
    nn = []
    cell = SPACING
    grid = {}
    for r in recs:
        grid.setdefault((int(np.floor(r[0] / cell)), int(np.floor(r[2] / cell))), []).append((r[0], r[2]))
    for r in recs:
        cx = int(np.floor(r[0] / cell)); cz = int(np.floor(r[2] / cell))
        dmin = float("inf")
        for ix in range(cx - 2, cx + 3):
            for iz in range(cz - 2, cz + 3):
                for q in grid.get((ix, iz), []):
                    if q == (r[0], r[2]):
                        continue
                    d = ((r[0] - q[0]) ** 2 + (r[2] - q[1]) ** 2) ** 0.5
                    if d < dmin:
                        dmin = d
        nn.append(dmin)
    nn = np.array(nn)
    print(f"nearest-neighbour (n={len(nn)}): min={nn.min():.2f} p1={np.percentile(nn,1):.2f} "
          f"median={np.median(nn):.2f} mean={nn.mean():.2f} p99={np.percentile(nn,99):.2f} max={nn.max():.2f}")

    # ---- Diagnostic overlay: enlarged mask block + tree dots + labels ----
    px0 = int((bx0 + WORLD_MIN) / WORLD_SPAN * (MASK_SIZE - 1))
    px1 = int((bx1 + WORLD_MIN) / WORLD_SPAN * (MASK_SIZE - 1))
    py0 = int((bz0 + WORLD_MIN) / WORLD_SPAN * (MASK_SIZE - 1))
    py1 = int((bz1 + WORLD_MIN) / WORLD_SPAN * (MASK_SIZE - 1))
    block = mask_img[py0:py1 + 1, px0:px1 + 1]
    # Enlarge with nearest to preserve mask cell identity.
    scale = 12
    # Normalize the 16-bit source BEFORE converting to 8-bit display values.
    # PIL convert("L") clips uint16 values; dividing that result by 65535
    # would turn the entire diagnostic background black.
    gray_u8 = np.rint(block.astype(np.float64) * (255.0 / 65535.0)).astype(np.uint8)
    im = Image.fromarray(gray_u8).resize(
        (block.shape[1] * scale, block.shape[0] * scale), Image.Resampling.NEAREST
    ).convert("RGB")
    draw = ImageDraw.Draw(im)
    # Tree sites (world -> block pixel).
    for r in recs:
        ux = (r[0] + WORLD_MIN) / WORLD_SPAN
        vz = (r[2] + WORLD_MIN) / WORLD_SPAN
        px = (ux * (MASK_SIZE - 1) - px0) * scale
        py = (vz * (MASK_SIZE - 1) - py0) * scale
        draw.ellipse([px - 3, py - 3, px + 3, py + 3], fill=(255, 40, 40), outline=(255, 255, 255))
    # Coordinate labels (metres, world space) every 500 m.
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 16)
    except Exception:
        font = ImageFont.load_default()
    w, h = im.size
    step_m = 500
    mx = bx0
    while mx <= bx1:
        ux = (mx + WORLD_MIN) / WORLD_SPAN
        px = (ux * (MASK_SIZE - 1) - px0) * scale
        if 0 <= px < w:
            draw.line([(px, 0), (px, h)], fill=(0, 80, 255), width=1)
            draw.text((px + 3, 4), f"{mx:.0f}m", fill=(0, 80, 255), font=font)
        mx += step_m
    mz = bz0
    while mz <= bz1:
        vz = (mz + WORLD_MIN) / WORLD_SPAN
        py = (vz * (MASK_SIZE - 1) - py0) * scale
        if 0 <= py < h:
            draw.line([(0, py), (w, py)], fill=(0, 80, 255), width=1)
            draw.text((4, py + 3), f"{mz:.0f}m", fill=(0, 80, 255), font=font)
        mz += step_m
    draw.text((6, 22), f"test area {AREA:.0f}m | {count} trees | min-spacing {SPACING:.0f}m",
              fill=(255, 255, 0), font=font)
    draw.text((6, 44), f"tree-site density mean={tree_mean:.3f} area mean={area_mean:.3f} | "
              f"NN median={np.median(nn):.1f}m min={nn.min():.1f}m", fill=(255, 255, 0), font=font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    im.save(OUT)
    print(f"diagnostic overlay written: {OUT} ({im.size})")
    print("VERIFY OK")


if __name__ == "__main__":
    main()
