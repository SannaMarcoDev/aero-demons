## Tutorial map edge hiding and safe return controller.
## Child of the tutorial map root. Reads the real terrain extents from the GardaTerrain
## Terrain3D node, keeps Sunshine as the sole atmosphere, and drives the aircraft's own
## return-to-arena logic (PlayerFlight._return_to_arena) so the player is turned
## back well before the terrain ends. No invisible wall: the aircraft's existing
## last-resort arena clamp stays as its own safety net, sized from real bounds.
extends Node3D

## The player is not part of the map scene (freeroam instances it as a sibling),
## so resolve it by group at runtime. Override with an explicit path if needed.
@export var player_path: NodePath = NodePath("")
@export var clouds_driver_path: NodePath = NodePath("../SunshineCloudsDriverGD")
## Distance from the terrain edge where the forced return begins. Must leave room
## for a full turn before the edge; the aircraft's own warning precedes it.
@export var return_margin: float = 6000.0
## Legacy cloud-ring diagnostic, disabled by default: it saturates the edge cloud layer.
@export var cloud_ring_count: int = 0

var _player: Node3D
var _driver: SunshineCloudsDriverGD
var _bounds := Rect2()  # world-space XZ rect of the actual terrain
var _boundary_warning: bool = false
var _return_distance: float = 0.0
var _bounds_ready := false
var _failed := false
var _player_wait_frames := 0
var _player_warned := false

func _ready() -> void:
	_driver = get_node_or_null(clouds_driver_path) as SunshineCloudsDriverGD
	_try_initialize()


## Terrain3D region data can load after this node's _ready, so retry each tick
## until real bounds resolve. No fabricated fallback bounds: without regions the
## boundary stays inactive.
func _try_initialize() -> void:
	if _bounds_ready or _failed:
		return
	var terrain := get_node_or_null("../GardaTerrain") as Terrain3D
	if not _read_terrain_bounds(terrain):
		return
	_bounds_ready = true
	_return_distance = _fit_return_radius()
	_setup_peripheral_clouds()
	_setup_haze()
	_resolve_player()


## Determine world-space terrain bounds from the imported Terrain3D data.
## Read-only: never modifies terrain data. Returns false when no regions exist.
func _read_terrain_bounds(terrain: Terrain3D) -> bool:
	if terrain == null or terrain.data == null:
		return false
	var locs := terrain.data.get_region_locations()
	if locs.is_empty():
		return false
	var region_size: float = float(terrain.get_region_size()) * terrain.vertex_spacing
	# Region index p covers [p*size, (p+1)*size) on each axis.
	var first := Vector2(locs[0]) * region_size
	var low := first
	var high := first + Vector2.ONE * region_size
	for i in range(1, locs.size()):
		var origin := Vector2(locs[i]) * region_size
		low = low.min(origin)
		high = high.max(origin + Vector2.ONE * region_size)
	_bounds = Rect2(low, high - low)
	return true


## Largest radius that keeps the forced return at least return_margin inside the
## real (possibly asymmetric) terrain edge on every side.
func _fit_return_radius() -> float:
	# The aircraft's _return_to_arena measures distance from the world origin, so
	# the safe radius is limited by the terrain edge closest to the origin.
	var distances := [
		absf(_bounds.position.x), absf(_bounds.end.x),
		absf(_bounds.position.y), absf(_bounds.end.y),
	]
	return distances.min() - return_margin


func _resolve_player() -> void:
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)
	if _player == null:
		# The player lives outside the map scene; find it through its faction group.
		for node in get_tree().get_nodes_in_group("player"):
			if node is Node3D:
				_player = node
				break
	if _player == null:
		return
	# Drive the aircraft's own return mechanism instead of duplicating it.
	if _player.get("return_distance") != null:
		_player.set("return_distance", _return_distance)
	if _player.get("arena_half_size") != null:
		# Keep the last-resort clamp just inside the real terrain edge. The clamp
		# is origin-centred, so use the edge nearest the origin on each axis.
		var half := minf(minf(
			absf(_bounds.position.x), absf(_bounds.end.x)),
			minf(absf(_bounds.position.y), absf(_bounds.end.y)))
		_player.set("arena_half_size", half - 1000.0)


## Place effector nodes in a noisy ring just outside the combat zone to build
## irregular denser peripheral cloud banks. Positive Power adds density.
func _setup_peripheral_clouds() -> void:
	if _driver == null:
		return
	var clouds := _driver.clouds_resource
	var effector_y := 1500.0
	if clouds != null:
		effector_y = (clouds.cloud_floor + clouds.cloud_ceiling) * 0.5
	var effectors_root := Node3D.new()
	effectors_root.name = "BoundaryCloudEffectors"
	add_child(effectors_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42137  # deterministic layout per run
	var effectors: Array[SunshineCloudsEffector] = []
	var center := _bounds.get_center()
	for i in cloud_ring_count:
		var angle := float(i) / float(cloud_ring_count) * TAU
		# Scatter banks through the band between the turn-back line and the edge.
		var radius := _return_distance + rng.randf_range(1500.0, 7000.0)
		var pos := center + Vector2(cos(angle), sin(angle)) * radius
		# Keep effector centres on the terrain so the banks cover the edge.
		pos.x = clampf(pos.x, _bounds.position.x, _bounds.end.x)
		pos.y = clampf(pos.y, _bounds.position.y, _bounds.end.y)
		var effector := SunshineCloudsEffector.new()
		effector.name = "CloudEffector%d" % i
		effector.position = Vector3(pos.x, effector_y, pos.y)
		effector.Radius = rng.randf_range(9000.0, 22000.0)
		effector.Power = rng.randf_range(1.5, 3.0)
		effectors_root.add_child(effector)
		effectors.append(effector)
	# Assign through the setter and re-upload: appending bypasses the driver.
	_driver.tracked_point_effectors = effectors
	_driver.retrieve_texture_data()


## Do not stack Sky3D screen-space fog over Sunshine. Density belongs to its resource.
func _setup_haze() -> void:
	var sky3d := get_node_or_null("../Sky3D")
	if sky3d != null:
		sky3d.fog_enabled = false
	var dome := get_node_or_null("../Sky3D/SkyDome")
	if dome != null:
		dome.fog_visible = false
	if _driver != null and _driver.clouds_resource != null:
		_driver.clouds_resource.fog_effect_ground = 1.0


func _physics_process(_delta: float) -> void:
	if not _bounds_ready:
		_try_initialize()
		return
	if _player == null or not is_instance_valid(_player):
		_resolve_player()
		if _player == null:
			# The player may enter the tree after this controller; only warn once it
			# clearly never arrived.
			_player_wait_frames += 1
			if _player_wait_frames > 120 and not _player_warned:
				_player_warned = true
				push_warning("TutorialBoundaryController: no player in scene; boundary inactive")
			return
		_player_wait_frames = 0
	var pos := _player.global_position
	# Warning leads the forced return so the HUD tells the player to turn back
	# before the aircraft's own _return_to_arena takes over the controls.
	_boundary_warning = _flat_distance(pos) > _return_distance - 5000.0


func _flat_distance(pos: Vector3) -> float:
	return Vector2(pos.x, pos.z).length()


## HUD query; CombatHUD reads this to draw a boundary warning.
func is_boundary_warning() -> bool:
	return _boundary_warning


## Read-only diagnostics for tuning UI or tests.

func get_return_distance() -> float:
	return _return_distance

func get_terrain_bounds() -> Rect2:
	return _bounds
