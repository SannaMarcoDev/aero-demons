# Native 1080p / 5 ms budget: integrated cloud presets

## Result and scope

**The integrated Ultra preset exceeds 200 average FPS in all measured warmed
scenarios on this PC. This is not a locked 200 FPS guarantee.** The slowest measured
active cases are airport flight (228 FPS) and the eight-enemy combat workload
(226 FPS). Combat p99 remains 6.57 ms; cold first-use effects and occasional long
frames remain unresolved. Hangar/taxi/takeoff have not received release timing
certification, and the combat workload is not an entire completed mission.

Hardware: Ryzen 5 7500F, Radeon RX 9070 XT, Windows, Godot 4.7.1 release export,
D3D12 Forward+. Scene/render target **1920×1080, scale 1, upscaler OFF, TAA**,
VSync OFF, unlimited FPS, no frame generation. Only clouds are reconstructed from
960×540. No terrain geometry, collisions, map composition or World Creator source
assets were changed.

## Delivered configuration

`SettingsManager.CLOUD_PRESETS` supplies both normal gameplay and benchmark
settings. The authored startup resource and Garda/Utah drivers match Ultra;
runtime checks verify resource, compositor, driver and uploaded light data.

| Cloud quality | Resolution | Main / lighting / sun steps | Blur quality | LOD bias | Lighting reach |
|---|---|---|---|---|---|
| Low | Eighth | 128 / 8 / 6 | 1 | 1.6 | 1500 |
| Medium | Quarter | 256 / 12 / 12 | 1.5 | 1.3 | 2000 |
| High | Half | 384 / 12 / 12 | 1 | 1.0 | 2500 |
| Ultra | Half | **700 / 16 / 16** | **1** | **0.9** | **3000** |
| Immutable old Ultra | Native | 700 / 32 / 32 | 2 | 0.9 | 3000 |

Master Low still disables volumetric clouds; its separate cloud-quality option
remains available. Ultra retains SSAO, glow, 8 km/four-cascade/4096 shadow atlas,
700-step reach, 50–140 step distances, coverage 0.834, accumulation 0.85, detail,
cloud floor/ceiling and lighting distance. This is **not High renamed Ultra**.
High now uses a coherent lower lighting budget instead of costing more per light
than Ultra. User resolution, AA, upscaler and weather controls remain independent.

The renderer reuses its existing temporal history and bicubic reconstruction.
Small correctness changes reset history on fresh buffers/render-target changes,
>1 km teleports and >30° single-frame rotations; clamp history loads before
out-of-screen rejection; and remove an extra camera translation from reprojection.
No second history system or unvalidated raymarch rewrite was introduced.

Combat validation also exposed a DialogueManager resource→line→resource cycle.
Copying the per-line dictionary before inserting its runtime resource reference
fixes the actual shared cause, not just benchmark teardown. This is a memory
lifetime correction, **not an FPS gain claim**.

## Comparable results

Three six-second measurement windows per location, with 3.5 seconds of warmup
before each. Frozen weather/cameras for the first table except the scripted low
flight path; real player physics, camera, wind and boundary processing in the
second table. FPS is total frames / total measured time; p95/p99 pool all raw
frame times. **No spikes/outliers were discarded.** Values are milliseconds unless
marked FPS. Stutter = frames >16.667 ms. Headroom = 5 ms minus mean frame time.

| Scenario | Old FPS → Ultra FPS | Mean before → after | p95 before → after | p99 before → after | Stutters before → after | Final headroom |
|---|---:|---:|---:|---:|---:|---:|
| Spawn | 154.0 → 278.8 | 6.49 → 3.59 | 7.08 → 3.84 | 7.47 → 4.15 | 0 → 0 | 1.41 |
| Clouds | 144.9 → 393.8 | 6.90 → 2.54 | 7.46 → 2.75 | 7.78 → 3.06 | 0 → 0 | 2.46 |
| Lake | 130.2 → 282.1 | 7.68 → 3.55 | 8.23 → 3.87 | 8.54 → 4.12 | 0 → 2 | 1.45 |
| Alps | 99.7 → 301.0 | 10.03 → 3.32 | 10.55 → 3.61 | 10.90 → 3.89 | 0 → 0 | 1.68 |
| Airport | 120.1 → 238.7 | 8.33 → 4.19 | 8.92 → 4.72 | 9.23 → 5.00 | 0 → 0 | 0.81 |
| Low flight path | 116.6 → 262.9 | 8.58 → 3.80 | 9.41 → 4.38 | 9.86 → 4.68 | 4 → 0 | 1.20 |

| Active simulation | Old FPS → Ultra FPS | Mean before → after | p95 before → after | p99 before → after | Stutters before → after | Final headroom |
|---|---:|---:|---:|---:|---:|---:|
| Neutral flight | 153.9 → 271.8 | 6.50 → 3.68 | 7.17 → 3.99 | 7.46 → 4.29 | 0 → 0 | 1.32 |
| Cloud traversal | 150.5 → 352.9 | 6.65 → 2.83 | 7.77 → 3.19 | 8.36 → 3.45 | 0 → 0 | 2.17 |
| Airport flyover | 110.3 → 228.3 | 9.07 → 4.38 | 9.83 → 4.77 | 10.03 → 5.15 | 0 → 0 | 0.62 |
| Combat **parameters-only comparison** | 137.4 → 226.1 | 7.28 → 4.42 | 8.75 → 5.84 | 9.34 → 6.57 | 2 → 4 | 0.58 |

Combat uses the delivered renderer for **both** parameter configurations, unlike
the other rows' archived original renderer baseline. It runs the actual tutorial
third encounter (eight authored enemies, two wingmen, director, targeting, guns,
missiles, HUD, damage/effects), three 12-second windows after 3.5-second warmup.
Player follows neutral flight and retains tutorial invulnerability; timers request
normal weapon fire without bypassing locks/cooldowns. Seven or eight enemies
remain at window end. AI timing/kills are not perfectly identical across FPS.
Do not present this row as a bit-identical deterministic battle replay.

### Spikes, drift and attribution

- Final full run: lake maximum **43.80 ms**, two >16.667 ms frames; airport's
  third window fell from ~243 to 229 FPS, with GPU median 3.90→4.14 ms. It is
  retained in the result, not removed as inconvenient noise.
- Same executables restored afterward: original spawn/Alps/airport
  **158.8/100.4/120.8 FPS**, integrated **280.8/302.7/245.2 FPS**. The last airport
  slowdown did not persist; precise clock/scheduler cause is unproven. Do not
  claim small percent differences inside that drift band.
- Final combat has four >16.667 ms frames, max **37.94 ms**, one >33.333 ms.
  First exploratory combat launch had a **1304.81 ms** stall and 197 FPS overall;
  subsequent warmed runs are 223–233 FPS. First-use compilation/resource work is
  a hypothesis, not a captured GPU-profiler diagnosis. Cold combat is not certified.
- The bulk gain is **changed effect resolution and sampling budgets**, not shader
  algebra. With identical Half700/16/blur1 parameters, history-before/after Alps
  screening was 303.4/301.9 FPS, GPU 3.10/3.09 ms: no measured speed gain.
- Healthy old executable baseline was established before editing. Historical
  editor-restart/residency recovery from `performance-ultra.md` is **not added** to
  these gains. No user GPU processes were terminated and no editor restart was
  used to manufacture the final comparison.

## Remaining costs and memory

Final diagnostic ablations, GPU median ms (one short screening window each):

| View | Base | Clouds off | Terrain off | Shadows off | HUD off | Water off | Airport off | SSAO+glow off |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Spawn | 3.36 | 1.89 | 2.18 | 3.29 | 3.35 | 3.36 | 3.36 | 2.82 |
| Alps | 3.13 | 1.59 | 2.33 | 3.01 | 3.11 | 3.04 | 3.12 | 2.52 |
| Airport | 3.88 | 1.80 | 2.99 | 3.66 | 3.89 | 3.87 | 4.11 | 3.66 |

These are **end-to-end deltas, not additive pass timings**. Removing occluders can
increase cloud work (airport-off is slower). Clouds remain the principal GPU
opportunity (~1.5–2.1 ms net); terrain is next (~0.8–1.2 ms net). HUD, water and
shadows are not the primary cause of the original 10 ms Alpine frames. CPU render
submission is ~0.24–0.43 ms in the static final cases and ~0.35–0.39 ms in combat;
this is not a full CPU simulation profile. Forests already use Terrain3D runtime
instances/batching; hiding the generator node is not a valid forest ablation.
No speculative forest/culling system, terrain simplification or reduced-precision
rewrite was added. Terrain normal/triplanar/multiscale shader work remains unchanged.

Godot tracked render memory: **4570 → 4400 MiB** for every free-flight view,
**4641 → 4494 MiB** maximum in combat. Windows process GPU counters during loading:
original **4913 dedicated / 210 shared MiB**, final **4742 / 210 MiB**. These are
snapshots, not certified peak residency. Actual adapter snapshot during startup/warmup of the native-combat process
was ~9927 MiB dedicated / 797 MiB shared; this is not a peak-combat measurement
and does not show VRAM exhaustion. Editor stayed open/stopped during measurements,
~1097 MiB dedicated; Firefox ~1 GiB and Steam helper ~976 MiB were left running.
DWM's per-process counter reported an impossible ~17 GiB: **do not sum that counter
as physical residency**. Adapter counters and process-local changes are separated.

Startup-through-initial-warmup is logged separately in each JSON (~26 seconds in
the final frozen-scene run); terrain/forest creation is outside measured windows.
It is not credited as a sustained frame optimization. No texture formats or source
asset sizes were changed; Half reduces existing cloud work/history buffers.

## Visual trade-offs and experiment decisions

See [operational log](performance-budget-log.md) for the isolated screening table.
Half700 was retained over reduced main steps: it preserves cloud reach/structure.
Native384 did not help the worst Alpine view. Quarter was not selected for Ultra
because its grain/detail compromise was unnecessary. Longer steps and lower detail
LOD were rejected; lowering Ultra's main steps to 512 did not help Alps. Original
High was only a comparison, not the delivered Ultra definition. Prior failed
workgroup/unrolling changes and Vulkan were not repeated without new evidence.

Aligned captures exist locally for legacy, Half, Quarter, lighting and blur probes.
Selected frames from translation, 60°/s rotation, a 60° cut and convergence were
inspected at Alps, cloud traversal and airport. Half preserves large silhouettes,
lighting/depth and aircraft/terrain separation but has **softer fine cloud detail**.
A history reset exposes grain for initial frames instead of blending stale history;
this is visible and not hidden from the report. Static frozen-dither screenshots
exaggerate noise and do not represent continuously accumulated play. No change to
coverage/structure was used to win sampling comparisons.

Selected-frame inspection is **not** exhaustive human motion approval. Shimmer,
disocclusion and all camera transitions still merit continuous-video review. No
claim of pixel equivalence, universal absence of ghosting or flawless high-quality
presentation is made from clean startup alone.

## Reproduce and audit

Reference: `tools/performance_legacy_ultra.json` records immutable revision
`27c3c879805e119867d243bf2e208498d00a59e4`, original source hashes and parameters.
`--preset=legacy` restores parameters, **not historical code**. To reproduce old
renderer results, use that revision plus the parameterized measurement tooling,
or the preserved local `reference-build/AeroDemons.exe`. Do not overwrite that
reference when exporting candidates.

Local raw logs, individual frame times, captures and executables:
`.pi/performance/budget-pass/`. Versioned condensed results, exact executable
hashes, command arguments, resolutions and runtime SPIR-V hashes:
[performance-budget-results.json](performance-budget-results.json).

```sh
# Export (create the destination first). GODOT = local 4.7.1 executable.
mkdir -p .pi/performance/budget-pass/build
"$GODOT" --headless --path . --export-release "Windows Performance" \
  .pi/performance/budget-pass/build/AeroDemons.exe

# Measurements are GRAPHICAL release, never --headless or --fixed-fps.
EXE=.pi/performance/budget-pass/build/AeroDemons.exe
node tools/run_godot_check.cjs 270 run.log "$EXE" -- \
  --preset=ultra --build=YOUR_BUILD_ID --out=ABSOLUTE_OUTPUT_DIRECTORY
# Repeat with --gameplay (155 s deadline), --combat (150 s), or:
node tools/run_godot_check.cjs 220 diagnose.log "$EXE" -- \
  --preset=ultra --quick --diagnose --views=spawn,alpine,airport --out=ABSOLUTE_DIR
# Isolate parameter changes without saving preferences:
# --preset=legacy --cloud=res:1 --cloud=light_steps:16 --cloud=sun_steps:16 --cloud=blur_q:1
# --motion acquires deterministic visual poses/dither AFTER timed windows, capped
# at 60 only for acquisition. PNG I/O is never included in the measured windows.
```

After shader edits: request editor filesystem scan, verify imported source MD5
matches actual source, export, then compare **loaded runtime SPIR-V hashes** in
results. This was verified for the history prototype: march hash changed from
`d3144c1a…` to `abb80e36…`; post hash stayed `bfa63e7f…`. No include was modified.
Export initially failed because the output directory did not exist. Subsequent
exports produced executables and exited 0, **but their export logs are not clean**:
missing `road_pbr_detail.gdshader` and Asphalt012 texture references, plus headless
dummy-renderer teardown leaks (also documented in earlier repository reports).
Those errors did not occur in the measured release runs. Terrain3D editor DLL
hot-reload warnings, aircraft texture UID fallbacks and deprecated interpolation
warnings are separate issues, not proof of shader freshness.

Benchmarks never save settings. Personal preferences were verified unchanged (SHA-256
`9869ae0a083969327ab916589284e8981453a56a7d1e99357de422c730a5479a`).
Uncapped native test settings are process-local, not a forced change to user choices.

## Validation and remaining work

- Passed: release full/static, real-flight, restoration, diagnostic and final combat
  runs, each with completion marker, exit 0 and no runtime script/error/leak output.
- Passed: graphical `tests/settings_apply_check.gd` (all changed preset paths,
  driver/uploaded steps, fresh history, no unnecessary GPU pipeline rebuild),
  `tests/sunshine_density_check.cjs`, `tests/performance_runner_check.cjs`, and
  headless `tests/dialogue_resource_lifetime_check.gd` (no retained cycle).
- The broader existing `tutorial_mission_check.gd` reached its functional completion
  but reported queue-free/dummy-renderer teardown errors: **not a clean pass**.
  The small dialogue test was isolated and corrected until its strict runner passed.
- MCP opened the delivered tutorial scene and launched it with autosave disabled;
  confirmed live and exercised confirm/acceleration input. Also traversed normal
  main menu → Free Flight → aircraft/loadout → hangar departure → Garda flight,
  then restarted using R. The restarted player was moving in the new scene.
  Current-run game/editor logs had no errors (script warnings/UID fallbacks remain).
  Test playback was stopped and the original options-panel editor tab restored.
  These integration checks are not FPS measurements or visual certification.
- Final `git diff --check` and the focused tests above passed. User settings SHA-256
  was unchanged; no commit, push or user-process termination was performed.

Next concrete work: capture/profile cold first-use combat stalls, then complete
release hangar/taxi/takeoff timing and continuous-video disocclusion/fast-camera
review. For tighter combat p99, reprofile its high-GPU frames before selecting a
structural cloud or terrain change; warmed averages alone do not justify a rewrite.
