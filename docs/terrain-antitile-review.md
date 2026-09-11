# Terrain anti-tile review — texture repetition fix

Date: 2026-09-11 · Harness: `tools/terrain_antitile_review.gd` · Captures: `subagent-artifacts/terrain-antitile-review/`

## Problem

The 7 Poly Haven texture assets ship `uv_scale = 0.4` (~2.5–5 m tiles) over a 250 km
terrain. `detiling_rotation`/`detiling_shift` are at their `0.0` defaults and
`enable_macro_variation` is off in `garda_final.tscn`, so every tile samples the
texture unmodified → strong "corduroy" repetition, worst on the brown dirt/rock
bands at 0.3–2 km range.

## Shipped fix (in `terrain_wc_override.gdshader`, via `build_terrain_override.gd`)

Two mechanisms, both inside `accumulate_material()`, driven by new `wc_*` uniforms:

- `wc_detile_rot`/`wc_detile_shift` (0.2 / 0.5): added on top of the per-texture
  `_texture_detile_array`, so each texture tile gets a random rotation + offset
  (Terrain3D's built-in detile path, now globally forced on).
- `wc_uv_warp`/`wc_uv_warp_scale` (3.0 m / 90 m): continuous world-space domain
  warp of the texture UV via `noise_texture` — turns the straight stripe grid into
  wavy strata. No seams.

Dormant hooks shipped off (zero cost): `wc_ms_*` (second sample at incommensurate
scale blended by noise, with distance gate `wc_ms_near`/`wc_ms_far`) and
`wc_uv_scale_mult` (global tile-size multiplier).

## Tested and rejected / insufficient alone

| Variant | Result |
| --- | --- |
| Runtime `Terrain3DTextureAsset.uv_scale`/`detiling_*` changes | **No-op** — the private uniform arrays are baked at shader generation; asset changes only reach the shader on (re)import |
| `dual_scaling` material prop | No-op while `shader_override_enabled` (override replaces the generated code) |
| `ov_ds` (dual-scaling generated code patched with wc_*) | Negligible at ≤1 km; the far sample only helps past `dual_scale_far` |
| `uv_scale` ×0.5 / ×0.25 (`ov_scale050`, `uvscale_*`) | Stripes still clearly visible, just wider/softer |
| `wc_ms_*` alone | Subtle modulation only; stripes persist |
| `enable_macro_variation` | Large-scale tint breakup; stripes persist — combine, don't rely |
| `depth_blur`/`bias_distance` | Masks far tiling only |

## Verified

- `ov_identity` parity gate: patched runtime shader ≡ scene shader (MAE 0.0).
- Post-deploy: `ov_wd` ≡ new baseline (MAE 0.0) on `slope_close` + `slope_near`.
- Frame cost: ~7.9 → ~8.0 ms @1080p (RX 9070 XT); warp adds ~2 noise lookups per
  texture id, detile is free.

## Tuning

All knobs are material shader params on `GardaTerrain` (scene leaves them at
shader defaults = the shipped values). Useful ranges: `wc_uv_warp` 1.5–6 m,
`wc_uv_warp_scale` 60–300 m, `wc_detile_rot` 0.1–0.4. If seams ever appear on a
texture, drop `wc_detile_rot` first. For far-field repetition, enable
`wc_ms_amount` ~0.6 with `wc_ms_ratio` ~0.4 and `wc_ms_near/far` ~400/2500.

Rerun the matrix: `godot --path . --script tools/terrain_antitile_review.gd`
(`-- --view=<id> --variant=<a,b> --hold` for interactive A/B).
