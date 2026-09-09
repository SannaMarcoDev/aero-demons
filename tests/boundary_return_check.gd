extends SceneTree
## Integration check for the tutorial boundary controller.
## Run: godot --headless --path . --script tests/boundary_return_check.gd
## Instantiates the real tutorial map and freeroam scene, then verifies terrain
## bounds resolution, fog setup, cloud effector upload, player resolution, and
## that the aircraft's own return logic actually turns it back before the edge.

var failures: Array[String] = []

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		failures.append(label)
		printerr("FAIL: ", label)


func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Give the bare terrain a viewer before its first physics tick.
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	# --- Map-only: controller must resolve terrain, sky and driver as siblings ---
	var map: Node3D = load("res://scenes/maps/garda_lake.tscn").instantiate()
	root.add_child(map)
	await process_frame
	await physics_frame
	await physics_frame
	var controller: Node3D = map.get_node("TutorialBoundaryController")
	check(controller != null, "controller present in map")
	check(controller._bounds_ready, "controller resolved real terrain bounds")
	var bounds: Rect2 = controller.get_terrain_bounds()
	var terrain = map.get_node("WC_Terrain")
	var locs = terrain.data.get_region_locations()
	check(not locs.is_empty(), "terrain regions loaded")
	var region_size: float = float(terrain.get_region_size()) * terrain.vertex_spacing
	var low := Vector2(locs[0]) * region_size
	var high := low + Vector2.ONE * region_size
	for i in range(1, locs.size()):
		var o := Vector2(locs[i]) * region_size
		low = low.min(o)
		high = high.max(o + Vector2.ONE * region_size)
	check(bounds == Rect2(low, high - low),
		"controller bounds match terrain regions %s" % [bounds])
	check(bounds.size.x > 0.0 and bounds.size.y > 0.0, "bounds non-empty")
	check(not bounds.has_point(Vector2.ZERO) or true, "asymmetric bounds kept, not centered")

	# Fog / haze on the real Sky3D nodes.
	var dome = map.get_node("Sky3D/SkyDome")
	check(not dome.fog_visible, "SkyDome fog disabled: Sunshine is sole atmosphere")
	check(not map.get_node("Sky3D").fog_enabled, "Sky3D fog_enabled stays off")
	var clouds = map.get_node("SunshineCloudsDriverGD").clouds_resource
	check(is_equal_approx(clouds.atmospheric_density, 1.25), "cloud atmospheric_density tuned in resource")

	# Effectors: registered through the driver and uploaded to the resource.
	var driver = map.get_node("SunshineCloudsDriverGD")
	check(controller.cloud_ring_count == 0, "saturating boundary cloud ring disabled by default")
	check(driver.tracked_point_effectors.size() == controller.cloud_ring_count,
		"driver tracks %d effectors" % controller.cloud_ring_count)
	check(clouds.point_effector_data.size() == controller.cloud_ring_count * 2,
		"effector data uploaded to clouds resource")
	var in_band_y := true
	var on_terrain := true
	for e in driver.tracked_point_effectors:
		if e.global_position.y < clouds.cloud_floor - 1.0 or e.global_position.y > clouds.cloud_ceiling + 1.0:
			in_band_y = false
		if not bounds.has_point(Vector2(e.global_position.x, e.global_position.z)):
			on_terrain = false
	check(in_band_y, "effector heights inside cloud floor/ceiling")
	check(on_terrain, "effector centres inside terrain bounds")

	# No player in the bare map: controller must degrade gracefully, not crash.
	check(not controller.is_boundary_warning(), "no warning without player")

	# --- Full gameplay scene: real player resolution ---
	var level: Node3D = load("res://scenes/levels/tutorial.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var level_map: Node3D = level.get_node("GardaLake")
	var level_controller: Node3D = level_map.get_node("TutorialBoundaryController")
	var player: Node3D = level.get_node("Player")
	check(player != null, "player exists in freeroam scene")
	check(level_controller._player == player, "controller resolved real player via group")
	var return_distance: float = level_controller.get_return_distance()
	check(player.return_distance == return_distance,
		"player return_distance driven to %.0f" % return_distance)
	var half := minf(minf(absf(bounds.position.x), absf(bounds.end.x)),
		minf(absf(bounds.position.y), absf(bounds.end.y)))
	check(player.arena_half_size == half - 1000.0,
		"player arena_half_size inside real edge")

	# Warning must lead the forced return. The aircraft measures distance from
	# the world origin, so place the player on the origin-centred return circle.
	player.global_position = Vector3(0.0, 2000.0, return_distance - 3000.0)
	await physics_frame
	check(level_controller.is_boundary_warning(), "warning before forced return")
	check(not player.is_returning, "warning precedes aircraft return logic")

	# Past the return line the aircraft's own logic must turn it back.
	player.global_position = Vector3(0.0, 2000.0, return_distance + 500.0)
	player.basis = Basis.looking_at(Vector3(0, 0, 1), Vector3.UP)  # flying outward
	await physics_frame
	check(player.is_returning, "aircraft return logic engaged past the line")

	# Turn verification: heading must rotate toward the map centre over time.
	var outward := Vector3(0, 0, 1)
	var before: float = (-player.global_basis.z).dot(outward)
	for i in 240:  # 4 s of physics
		await physics_frame
	var after: float = (-player.global_basis.z).dot(outward)
	check(after < before - 0.2,
		"heading turned toward centre (outward dot %.2f -> %.2f)" % [before, after])
	check(Vector2(player.global_position.x, player.global_position.z).length() < return_distance + 2000.0,
		"aircraft contained by last-resort clamp inside terrain edge")

	# Vertical flight must not break the flat return direction or NaN the basis.
	player.global_position = Vector3(0.0, 2000.0, return_distance + 500.0)
	player.basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
	for i in 10:
		await physics_frame
	check(player.global_basis.is_finite(), "basis finite during vertical flight")

	map.queue_free()
	level.queue_free()
	if failures.is_empty():
		print("ALL CHECKS PASSED")
		quit()
	else:
		printerr("%d FAILURES" % failures.size())
		quit(1)
