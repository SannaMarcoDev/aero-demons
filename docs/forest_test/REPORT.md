# Forest Scatter Test — Valtellina (Terrain3D)

Targeted fix pass on HEAD `f35c3e2`. This run addressed the six review findings
(D1–D6) from the independent review, re-baked deterministically, re-rendered and
re-benchmarked. **Terrain data, heightmaps and the working Valtellina scenes were
not modified** (verified: sampled region `.res` md5 == pristine backup; R16 and
metadata untouched).

## Environment

| Item | Value |
|---|---|
| Engine | Godot **4.7.2** stable |
| Terrain3D addon | **1.0.2**, GDExtension `libterrain.linux.debug.x86_64.so` |
| Renderer | Vulkan **Forward+** |
| GPU | AMD Radeon RX 9070 XT (RADV GFX1201) |
| Terrain data | `terrain/valtellina_data` (576 regions, 24×24, vertex_spacing 5 m, region_size 256) |
| Height range | `get_height_range()` → (0.0, 3678.425) m |

## Review findings — disposition

| # | Finding | Disposition |
|---|---|---|
| D1 | Top-down ortho screenshots show zero forest pixels | **Fixed.** Top views now render trees (see below). Root cause: the old top view was centred on the valley-floor clearing and the trees were sub-pixel at 620 m; not a frustum-culling bug. Camera is now repositioned over the densest forest point and zoomed to 320 m with a bright-green unshaded override. |
| D2 | `minimum_spacing` is not a real minimum (min NN 2.7 m) | **Fixed.** Real 15 m minimum enforced by deterministic spatial-hash rejection; verified min pairwise = **15.000 m**. |
| D3 | `_compute_cell_aabb` uses the global height range (culling effectively off) | **Fixed.** Cell AABBs are now the union of the actual transformed mesh bounds (canopy, scale, rotation) per instance, not the global terrain range. Verified it is **not** the cause of D1 (see D1). |
| D4 | Mask origin +15360 weakly justified / partly circular | **Kept as calibrated, unresolved assumption.** Made centrally configurable; the exact forest-mask origin is not provable to sub-texel certainty (see §Mapping). |
| D5 | Report mask means use max-normalisation, not the bake's /65535 | **Fixed.** Report now quotes the true Godot grayscale /65535 values. |
| D6 | `mask_test_block.png` is 68×69 px and nearly useless | **Fixed.** Added an enlarged, coordinate-labelled diagnostic overlay (`tree_density_nn.png`) with the test-area mask block and tree sites. |

---

## Mask mapping and orientation

Requirement text says `U=(X+15000)/30000, V=(Z+15000)/30000` (nominal). The **data**
is region-snapped. The mapping is now **centrally configurable** in
`scripts/forest_config.gd` (`mask_world_min`, `mask_world_span`, `mask_flip_v`,
`mask_size`) and is used by both the bake and the test scene.

**Default: `+15360`, no V flip** — `U=(X+15360)/30000, V=(Z+15360)/30000`.

### Evidence for the calibrated origin

1. **Terrain/R16 origin (measured, strong).** Independently re-measured against the
   raw `valtellina_heightmap_6000x6000.r16` (6000×6000, 5 m): mapping the 396 CSV
   validation points with the **−15360** origin gives max vertical error
   **0.0003 m**; the nominal **−15000** origin gives max error **~2271 m**. The
   Terrain3D heights therefore sit at origin **(−15360, −15360)**, centre
   (−360, −360), because the 30 km heightmap was snapped onto the 24×24 region grid
   (region_size 256 × 5 m = 1280 m/region → 12 regions × 1280 = 15360).
2. **Forest-mask ↔ colormap (zero-offset correlation).** The density mask
   (1025×1025) correlates with the visually-verified World Machine colormap at
   **(dx=0, dy=0)** (r ≈ 0.62 with the vegetation index). This supports a shared
   1025×1025 pixel grid, but does not independently establish its world-space origin.
3. **No V flip.** Elevation-under-mask sampling (no flip) gives dense forest on the
   mid/lower valley slopes (mean ~611 m, 1.3% above 1700 m); flipping V puts dense
   forest on the high peaks (16.4% above 1700 m), which is wrong.

### Honest limitation (D4)

The R16 origin at −15360 is **measured and certain**. The forest-mask origin is a
**calibrated assumption**: it follows from the zero-offset colormap correlation and
the shared pixel grid, but that only proves the two *World Machine* products share a
grid, not (to sub-pixel certainty) that the grid sits at −15360 on the terrain. The
visual colormap alignment is resolution-limited (~29.3 m/texel).

**The user originally requested +15000.** The −15000 vs −15360 distinction is
**360 m = 12 mask pixels** (not negligible: it would shift every tree ~360 m if the
mask were regenerated on the nominal grid). We **do not** assert +15360 as absolute
proof. It is the best calibrated assumption; if the mask is ever regenerated on a
nominal −15000 grid, set `mask_world_min = 15000.0` in `forest_config.gd`/`.tres`.
The elevation test alone does not discriminate 360 m (both give "sensible" forests);
the no-flip elevation correlation is supporting evidence, not absolute mathematical
proof.

---

## Real minimum spacing (D2)

`minimum_spacing=15` is now a **real pairwise minimum**, enforced deterministically
in `valtellina_forest_bake.gd`:

- A spatial hash (cell size = `minimum_spacing`) records placed trees. Any two trees
  closer than `spacing` must lie in cells whose indices differ by ≤ 1 on each axis,
  so checking the 3×3 neighbourhood is sufficient. A candidate whose jittered
  position is within `minimum_spacing` of an already-placed tree is **rejected**.
- Candidates are **clamped to the exact test bounds** (`[center−half, center+half]`),
  so no tree escapes the bounded area.
- **Black-mask exclusion**: a zero-density cell is never a tree site (`dens <= 0.0`
  → reject).
- Two independent verifications confirm the minimum: the GDScript
  `_verify_min_spacing()` (fresh spatial grid, all-pairs) and the standalone Python
  `scripts/forest_verify.py` (separate implementation).

Result (default bake, 2000 m area, seed 1337):

```
count=5903 | min pairwise distance = 15.000m (required >= 15.0m)
effective height: min=20.001m max=29.996m (target 20.0..30.0m)
bounds x[-1000,1000] z[-1360,640] all_inside=True
black-mask rejection: trees on zero-density cells = 0
density bias: tree-site mask mean 0.5405 vs area mask mean 0.5207 (true /65535)
nearest-neighbour: min=15.00 p1=15.06 median=18.00 mean=18.86 p99=29.57 max=46.02
```

Count dropped from the old 9352 (grid + jitter only) to **5903** because the 15 m
minimum is now genuinely enforced. The old "avg tree spacing 20.7 m" line was
`sqrt(area/count)`, not a spacing guarantee; it is removed.

---

## Tree models — height, grounding, orientation

All 4 models are Z-up in mesh-local space, rotated to Y-up by the GLB import basis.
Real world-space heights (verified against mesh `POSITION` AABBs): rt_1=2.2446 m,
rt_2=4.9110 m, rt_3=3.9265 m, rt_4=5.5552 m. Every model has **baseY = 0.0**
(pivot at trunk base). Each instance Y = `terrain.data.get_height(x,0,z)`, so the
trunk base sits on the surface. Each tree is normalised so its **final effective
height** (real height × uniform scale) is in **[20, 30] m** (scale 3.60–13.36).
Every tree keeps a **random yaw** and the upright import basis (mesh-transform
correct). Verified: effective heights min 20.001 m, max 29.996 m; 0 trees outside the
band.

---

## MultiMesh AABBs (D3)

`valtellina_forest_test.gd` `_cell_aabb_from_transforms()` computes each cell batch
`custom_aabb` as the **union of the actual transformed mesh bounds** of every
instance in the cell (mesh `get_aabb()` corners transformed by each instance's
basis+scale+rotation+position, including the canopy). This is in the correct local
coordinate system (node is at origin, so local == world). It no longer uses the
global terrain height range (0–3678 m). The default bake produces **71 cell batches**
(5903 trees, chunk 500 m).

This makes frustum culling real (tight per-cell AABBs) but, as verified in D1, it is
**not** the cause of the earlier invisible top views — those were a camera-position
problem, not a culling problem.

---

## Render evidence (D1)

Screenshots regenerated at runtime (`--capture-forest`), saved in `docs/forest_test/`.
Green fraction measured with a bright-green detector (g>150, r<120, b<120):

| File | View | Bright-green fraction | What it shows |
|---|---|---|---|
| `01_top.png` | ortho 320 m over densest forest point, green override | **0.00295** | Individual bright-green trees clearly visible |
| `05_top_pattern.png` | ortho full test area (~2200 m), green override | **0.00098** | Full-area forest pattern |
| `02_oblique.png` | medium oblique | 0.00000 (lit) | Dense conifer forest on the valley slope |
| `03_close.png` | close among trees | 0.00000 (lit) | Tall upright trees, grounded, lit |
| `04_trunk.png` | ground-level side | 0.00000 (lit) | Trunk bases meet the ground |

`01_top` was previously **0.000** (the review's D1). The forest now renders in the
top-down view. Because `minimum_spacing=15` gives an **open** forest at 20–30 m tree
heights, the top view shows clearly separated trees rather than a closed canopy
(this is the requested behaviour; reducing `minimum_spacing` to 8–10 m would give a
closed canopy).

A separate labelled diagnostic overlay (`docs/forest_test/tree_density_nn.png`) plots
every tree position over the enlarged test-area mask block, with world-space
coordinate labels and a 500 m grid. Final parent review corrected a display-only
16-bit-to-8-bit conversion bug that had made the overlay background black; both
default and stress overlays were regenerated and their verification checks passed.
This does not change the bake, sampled probabilities, or benchmark results. It shows trees clustering in dense (bright)
cells and avoiding black (zero-density) cells. **This overlay is diagnostic, not a
replacement for the actual render.**

---

## Bake / validation commands (repeatable)

Default bounded bake:
```bash
/home/marco-ubuntu/Workspace/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
  --script res://scripts/valtellina_forest_bake.gd
```

Capture:
```bash
/home/marco-ubuntu/Workspace/godot/Godot_v4.7.2-stable_linux.x86_64 --path . --resolution 1400x1000 \
  scenes/real_terrain_valtellina_forest_test.tscn -- --capture-forest
```

Independent verification + diagnostic overlay:
```bash
python3 scripts/forest_verify.py
```

Stress bake (separate profile, 4000 m area, same configs):
```bash
/home/marco-ubuntu/Workspace/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
  --script res://scripts/valtellina_forest_bake.gd -- --size=4000 --out=res://assets/forest_test/trees_stress.bin
python3 scripts/forest_verify.py assets/forest_test/trees_stress.bin 4000 0,-360 docs/forest_test/tree_density_nn_stress.png
```

---

## Performance (vsync OFF, runtime)

See `docs/forest_test/benchmark.log` for the full table. Summary (Forward+, RX 9070 XT,
logical viewport 1152×822, vsync disabled, fixed medium-oblique camera):

Progressive (default bounded bake):

| resident | visible | FPS | avg ms | median ms | p95 ms | draw_calls |
|---|---|---|---|---|---|---|
| 0 | 0 | 595.7 | 1.68 | 1.03 | 1.35 | 103 |
| 1000 | 999 | 590.0 | 1.69 | 1.05 | 1.27 | 139 |
| 3000 | 2999 | 585.5 | 1.71 | 1.06 | 1.27 | 209 |
| 5903 | 5533 | 581.6 | 1.72 | 1.06 | 1.32 | 251 |

Stress (separate 4000 m area, 15068 trees): **564.9 FPS, 1.77 ms avg, 1.11 ms
median, 1.45 ms p95, 459 draw calls, 7980/15068 visible**.

Interpretation: frame time is flat (~1.7 ms) from 0 → 5903 instances; the scene is
terrain/base-bound, not forest-bound. With vsync OFF the uncapped frame time is
~1.7 ms (~580 FPS). The earlier vsync-capped ~94 FPS figure was display-refresh
limited and should not be overclaimed. The stress profile at 15068 instances is a
separate area/profile; it stays distinct from the default bounded test. Culling is
active (7980/15068 resident visible at this camera). No full-world population was
generated. After the stress runs the default bounded `trees.bin` (2000 m / 5903
trees) is restored; the stress data lives in `trees_stress.bin`.

`visible` is an estimate from `Camera3D.is_position_in_frustum()` on each cell batch
AABB centre; the exact renderer-culled instance count is not exposed by Godot.

---

## Files

Modified / created (forest-specific only):
- `scripts/forest_config.gd` — added `mask_world_min/span/flip_v/size`; documented
  `minimum_spacing` as a real enforced minimum.
- `assets/forest_test/forest_config.tres` — added the four mask-mapping fields.
- `scripts/valtellina_forest_bake.gd` — real minimum-spacing spatial-hash rejection,
  exact-bound clamp, black-mask exclusion, independent all-pair min-distance
  verification, true /65535 mask stats.
- `scripts/valtellina_forest_test.gd` — per-cell AABB from transformed mesh bounds,
  config-driven mask mapping, top view over densest forest point, `--bake=` override,
  frustum-visibility estimate, benchmark avg/median/p95.
- `scripts/forest_verify.py` — independent Python verification + labelled diagnostic
  overlay.
- `assets/forest_test/trees.bin` — re-baked (5903 trees, 15 m min spacing, 20–30 m).
- `assets/forest_test/trees_stress.bin` — separate stress profile (15068 trees).
- `docs/forest_test/` — regenerated screenshots, `tree_density_nn.png`,
  `tree_density_nn_stress.png`, `benchmark.log`, this report.

No `git add`/`commit`/`reset` performed. Original `terrain/`, `terrain/valtellina_data`,
heightmaps, metadata and the working Valtellina scenes were not modified.

---

## Residual risks / outstanding

1. **D4 (mask origin).** The exact forest-mask origin is a calibrated assumption
   (+15360), not absolute proof. It is centrally configurable and the nominal +15000
   is documented. A 360 m = 12-pixel shift is not negligible; if the mask is
   regenerated nominally, every tree shifts ~360 m. This is the one genuine
   unresolved item.
2. **Slope base intersection.** Flat-base trees on steep slopes can float/bury
   slightly. Not corrected (would need per-vertex terrain conforming).
3. **Open forest.** `minimum_spacing=15` gives an open forest at 20–30 m tree
   heights (top view shows separated trees). This is the requested behaviour, not a
   defect; a closed canopy needs spacing ~8–10 m.
4. **`visible` is an estimate** (frustum on batch AABB centres), not the exact
   renderer-culled count.
5. **`mask_test_block.png` is still the raw small crop**; the readable reference is
   the enlarged labelled `tree_density_nn.png`.
