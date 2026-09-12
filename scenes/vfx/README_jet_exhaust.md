# Jet exhaust

Instance **`res://scenes/vfx/jet_exhaust.tscn`** behind the nozzle.
The **origin is the nozzle exit centre; local +Z points aft**, into the exhaust.
Dimensions are metres. Match `nozzle_radius` to the opening rather than stretching
individual axes. The reusable scene contains no nozzle model or environment.

```gdscript
$LeftExhaust.throttle = engine_throttle  # 0–1; smoothing is internal.
$RightExhaust.throttle = engine_throttle
```

Default throttle is **0 (off)**. Instances have independent materials/flow phases;
the shader, mesh and generated noise texture are shared.

## Inspector controls

| Control | Purpose |
| --- | --- |
| `nozzle_radius` | Opening radius; default 0.45 m. |
| `plume_length`, `heat_haze_length` | Full-power luminous / distorted-air reach; 3.8 / 7 m. Bounds always contain the plume. |
| `heat_distortion` | Background displacement; default 12, zero disables displacement. |
| `brightness`, `hot_color`, `edge_color` | Radiance and warm-centre / cool-envelope colours. |
| `turbulence`, `flow_speed` | Irregularity / downstream animation rate. |
| `response_speed` | Spool response; default 5 reaches 95% of a change in about 0.6 s. |
| `afterburner_enabled`, `afterburner_start` | Optional smooth augmentor onset; default above 0.85. |
| `volume_samples`, `max_distance` | 16/24/40 samples; fades over the last quarter of the default 350 m range. |

Low power is mostly shimmer; medium/high dry thrust adds a faint core and short
neutral efflux. Near full throttle adds a blue-violet envelope and warmer shock
cells. These are artistic mappings, not calibrated engine RPM/fuel-flow values.

## Preview / validation

Run **`preview/jet_exhaust_preview.tscn`** with F6. All test geometry is original
and separate from the effect. Use the throttle slider/presets and **1–6** for
rear, side, rear-quarter, close, gameplay (~52 m) and twin views.
**T** sweeps throttle, **B** toggles afterburner, **D** toggles distortion,
**H** hides the UI. The twin deliberately runs at 65% of the first engine's throttle.

```sh
godot --path . --script res://scenes/vfx/preview/check_jet_exhaust.gd -- --visual
```

Checks clamping, frame-rate-independent smoothing, afterburner onset, independent
twins, transformed bounds, and off/distance culling. Also captures six views/five
throttle states and asserts actual background-pixel displacement with emission
disabled. Images go to the OS temporary folder `jet_exhaust_validation` (or
`user://jet_exhaust_validation` without `TEMP`). For logic-only checks, omit
`-- --visual` and add `--headless`; this project's audio autoload can report an
unrelated WAV/playback resource leak on headless shutdown.

Visually iterated in **Godot 4.7.1 / Forward+ / D3D12**, including all listed views
and throttle states. Iterations replaced sheet-like noise with seamless 3D noise,
removed marching bands, widened/softened compression cells, and strengthened haze.

## Cost and limits

- One bounded mesh draw per visible engine; two shared 48³ noise texture reads per
  ray sample. No particles, lights or CPU simulation. Off/distant engines skip drawing.
  Use 16 samples for groups; large screen coverage costs more. Fleet-scale and
  lower-end-GPU performance have not been profiled.
- Targets **Forward+ perspective cameras**. Glow is optional, supplied by the host
  `WorldEnvironment`; no project settings or lighting are changed.
- Screen-space haze sees opaque geometry/sky, **not transparent objects, other
  exhausts or off-screen content**. Overlapping transparent volumes retain normal
  sorting/compositing limitations. Depth clipping and a foreground-depth guard
  reduce intersection/silhouette artifacts but cannot remove all screen-space limits.
- Attached near-field exhaust, not a persistent world-space wake.

## External references

Original implementation: no existing project VFX, shaders, particle setups,
scripts or aircraft scenes were used as references. Terrain/imports are untouched.

- [F100 afterburner side-quarter close-up](https://www.dvidshub.net/image/9255819/igniting-readiness-engine-test-cell): translucent blue envelope, warm compression bands, bright interior.
- [Daylight F-16 / heat distortion](https://www.dvidshub.net/image/9900732/thunderbird-tears-through-sky-smoke-trailed-climb): distorted background extends beyond visible flame.
- [Actual F-16 engine-test footage](https://www.dvidshub.net/video/512154/177th-fighter-wing-gas-turbine-engine-testing): changing exhaust during an engine run, rather than a continuous rocket flame.
- [Rear/departure afterburner reference](https://www.yokota.af.mil/News/Photos/igphoto/2001561848/): collected during research; direct image access was blocked.
- [F-16 taxi / hot-refuelling report](https://www.dvidshub.net/news/383341/expeditionary-airmen-accelerate-change): documents heat haze at taxi power.

Colour/visibility depend on engine, exposure, ambient light and viewing angle.
Dark test-cell exposure is intentionally not reproduced at daylight brightness.
