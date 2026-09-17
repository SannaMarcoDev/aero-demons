# Garda and N26 metric scale

## Sources and vertical conversion

The original `C:/Users/sanna/Workspace/Assets/Terrain/terrain_250km_worldmachine.r16`
is an 8192² little-endian unsigned R16 Copernicus GLO-30 scan, **250 × 250 km**.
Its accompanying `terrain_250km_info.txt` defines 0 = -13.09 m and 65535 = 3977.87 m.
SHA-256: `5f7681a6cbb0f45dd051bc2e5146ca09c792d6370000a193f3a93b90ec427a19`.

`Documents/World Creator Projects/Lago di Garda/lago di garda.wcr` references
that R16 and normalizes its stamp to **8.450164–2000 m**, with HeightScale 1,
HeightOffset 0, Overwrite and full blending. The archived Godot import then
multiplied WC heights by 3.814697265625, incorrectly coupling vertical and
horizontal enlargement.

The corrected import uses the inverse *documented stamp range*, not a fitted
regression or a remap of the exported extrema:

```
Y = archived_Y / 3.814697265625 * 2.0039468397214644 - 30.023679442928085
```

`terrain/garda_geographic_250km/` contains new region resources and a manifest
with source checksums. Original exports and `garda_final_wc_uniform_250km/`
remain untouched. Horizontal placement, 256 regions, vertex spacing
15.2587890625 m, textures, color maps and control maps remain unchanged.
The scene reuses the original texture assets. Highest imported point changes
from **7365.625 to 3839.306 m**; the original scan reaches **3977.87 m**, not 3000 m.

This fixes metric normalization, **not WC's authored deviations from the DEM**.
The WCR includes erosion, chipped/rocky filters and Add/Set height processing.
The clockwise-aligned 16,384-point comparison against the original R16 has
approximately 116.44 m residual RMSE after calibration. Do not replace WC
geometry, flatten peaks, or repaint masks to eliminate this residual in Godot.
Any exact-geography revision belongs in World Creator and needs a new export.

Water receives the same affine conversion (408.07687 → 184.34834 m) to preserve
the existing shoreline. This is the authored water level, **not a claim that
Lake Garda's real elevation is 184 m**. Moving just the water to 65 m would
break its alignment with the WC terrain.

Rebuild into an absent destination:
`godot --headless --audio-driver WASAPI --path . --script res://tools/restore_garda_height.gd`.
The importer refuses an existing destination and verifies exact preservation
of color/control images and original resource hashes.

## Aircraft

The N26 mesh's native size is **20.7585 m long × 14.0784 m wide × 4.7440 m high**.
The catalog keeps its half-size local rig for the loadout preview. The player
scene now uses `airframe_scale = 2.0`, giving mesh scale 1.0 and scaling exhaust,
weapons, lights, damage emitters and collision geometry together. AI retains
its existing 0.5 scale. Chase camera distances and orbit pivot increase fourfold
to preserve framing; FOV and aircraft speed are unchanged. Projectile launch
transforms retain scaled socket positions but strip rig scale from their basis,
so detached missiles/bullets do not inherit aircraft size or a scaled launch speed.
Mission/spawn altitudes are
unchanged: this task corrects physical scale, not mission layout.

## Regression checks

- `tests/garda_final_import_check.gd`: source hashes, all 256 color/control maps,
  height hashes, 4096 seam/interior queries, 16,384 independent DEM samples,
  250 km bounds and corrected peak/water level. No dependency on the mutable
  World Creator Sync folder (currently an Utah export).
- `tests/aircraft_selection_check.gd`: native dimensions, nozzle alignment,
  attachment scaling, camera clearance, selection/weapon behavior and AI isolation.
- `tests/player_camera_check.gd`: camera transform behavior.

Run headless checks with a bounded process-tree-cleaning runner. These checks
explicitly stop autoload audio playback and wait for resource release; validation
used `--audio-driver WASAPI`. Require a PASS marker, exit 0 and no script errors.

Validation: the three regression checks above passed. Garda freeroam/tutorial
and Utah freeroam reached `live` with clean current-run game/editor logs; N26
size and chase distance were measured at runtime. Screenshots checked framing
and lit exhaust alignment both at spawn and in a temporary 2300 m diagnostic pose.
All runtime diagnostics were stopped without saving scene state.

Two unrelated existing issues remain: `gun_handling_check.gd:87` expects a
first-frame input ramp below 0.2, while the unchanged 0.05 s preset produces
0.3333; its earlier physical bullet/missile assertions succeeded. Utah tutorial
reaches `live` but reports a missing `../../FlightContact` in the unchanged
`tutorial_mission.gd`; that node is absent from the original Utah scene too.
Headless runs also report existing N26 texture UID fallback warnings and a
Terrain3D deprecated interpolation API warning.
