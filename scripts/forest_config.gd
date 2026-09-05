extends Resource
class_name ForestConfig
## Central exported config for the Valtellina forest scatter test.
## Loaded by both the offline bake (scripts/valtellina_forest_bake.gd) and the
## runtime scene (scripts/valtellina_forest_test.gd).

## Multiplier on the mask probability density. rng < density * this.
@export_range(0.0, 5.0, 0.05) var density_multiplier: float = 1.0
## Candidate grid spacing in metres. The bake enforces this as a REAL minimum
## pairwise distance between any two trees (spatial-hash rejection). The jitter
## only offsets the candidate position within the cell; it cannot bring two
## trees closer than `minimum_spacing`. Lower = denser forest, more instances.
@export_range(2.0, 200.0, 0.5) var minimum_spacing: float = 15.0

# --- Density-mask world mapping (centrally configurable) -------------------
# The density mask maps to world space as U=(X+origin)/span, V=(Z+origin)/span.
# CALIBRATED ASSUMPTION (not absolute proof): Terrain3D snapped the source R16
# heightmap to the region origin (-15360,-15360) — measured directly against the
# R16 (max vertical error 0.0003 m at that origin vs ~2271 m at the nominal
# -15000). The forest mask shares the World Machine 1025x1025 pixel grid with the
# visually-verified colormap (zero-offset correlation), so it uses the same
# -15360 origin. The nominal metadata says -15000. Set these to 15000.0 only if
# the mask is regenerated on the nominal grid; the ~360 m shift is 12 mask
# pixels and would move every tree ~360 m.
@export var mask_world_min: float = 15360.0
## World-space span (extent) of the density mask in metres.
@export var mask_world_span: float = 30000.0
## Flip the V (north/south) axis of the mask. Default false (no flip; verified
## by elevation-under-mask sampling: dense forest on mid/lower slopes, not peaks).
@export var mask_flip_v: bool = false
## Density-mask image size (square, pixels).
@export var mask_size: int = 1025
## Final effective tree height range in metres. Each tree is normalised so its
## real mesh height (including GLB transforms) lands inside this band. The
## random_scale_min/max range below is subordinate to this height range.
@export_range(5.0, 100.0, 1.0) var tree_height_min: float = 20.0
@export_range(5.0, 100.0, 1.0) var tree_height_max: float = 30.0
## Legacy per-model uniform scale range. Subordinate: the height range above
## drives the final scale; these are kept for reference/clamping only.
@export_range(0.1, 3.0, 0.05) var random_scale_min: float = 0.8
@export_range(0.1, 3.0, 0.05) var random_scale_max: float = 1.25
## Deterministic RNG seed for the scatter.
@export var seed: int = 1337
## Side length of the square test area (metres). Test is a 2km block by default.
@export_range(100.0, 6000.0, 50.0) var test_area_size: float = 2000.0
## World-space centre of the test area. Default is the Valtellina valley floor.
@export var test_area_center: Vector3 = Vector3(0, 0, -360)
## Frustum-cull cell batch size for the chunked MultiMeshes.
@export_range(32.0, 2000.0, 32.0) var chunk_size: float = 500.0
## Fraction of the candidate cell used as position jitter (0..0.5). Avoids grid.
@export_range(0.0, 0.5, 0.01) var jitter: float = 0.45
## Tree model PackedScenes used for scatter. Multiple models are supported.
@export var tree_models: Array[String] = [
	"res://assets/trees/tree_rt_1.glb",
	"res://assets/trees/tree_rt_2.glb",
	"res://assets/trees/tree_rt_3.glb",
	"res://assets/trees/tree_rt_4.glb",
]
## Enable directional shadow casting on the tree MultiMeshes (expensive).
@export var cast_shadows: bool = false
## Output path for the baked instance data (relative to res://).
@export var bake_path: String = "res://assets/forest_test/trees.bin"
