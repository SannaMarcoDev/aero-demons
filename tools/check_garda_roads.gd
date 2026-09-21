extends SceneTree
## Read-only on disk. Exercises regeneration, terrain sculpt signals, geometry and collisions.
## node tools/run_godot_check.cjs 120 subagent-artifacts/roads/check.log <godot> --headless --path . --script res://tools/check_garda_roads.gd
## Add --editor to exercise editor-only collision suppression (no map is loaded).

func _initialize() -> void:
	_run.call_deferred()


func _settle() -> void:
	for i in range(4):
		await physics_frame
		await process_frame


func _run() -> void:
	if Engine.is_editor_hint():
		await _check_editor_collisions()
		quit()
		return
	assert(load("res://addons/road-generator/plugin.gd").can_instantiate())
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var map: Node3D = load("res://scenes/maps/garda_final.tscn").instantiate()
	assert(not map.has_node("RoadReviewCamera"), "Do not override the gameplay camera")
	assert(map.get_node("TutorialBoundaryController").process_mode != Node.PROCESS_MODE_DISABLED)
	map.get_node("TutorialBoundaryController").process_mode = Node.PROCESS_MODE_DISABLED
	var terrain: Terrain3D = map.get_node("GardaTerrain")
	assert(terrain.data_directory == "res://terrain/garda_geographic_250km")
	assert(terrain.collision_mode == 1, "Terrain collision must be Dynamic / Game")
	terrain.collision_mode = 0 # Geometry regression reads height data, not terrain physics.
	map.get_node("Forests").enabled = false
	map.get_node("GroundCover").process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new() # Test-only; gameplay supplies its own camera.
	camera.position = map.get_node("RoadManager").position + Vector3(80, 80, -80)
	camera.current = true
	map.add_child(camera)
	root.add_child(map)
	await _settle()
	var manager: RoadManager = map.get_node("RoadManager")
	var container: RoadContainer = manager.get_node("TwoLaneRoads")
	var conformer = map.get_node("RoadTerrain")
	assert(conformer.terrain == terrain and conformer.road_manager == manager)
	assert(not container.flatten_terrain and not container.generate_ai_lanes)
	assert(container.get_intersections().size() == 2)
	assert(container.get_node("T_Junction").edge_points.size() == 3)
	assert(container.get_node("X_Junction").edge_points.size() == 4)
	for point in container.get_children():
		if point is RoadPoint:
			assert(point.traffic_dir == [RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD])
			assert(point.gutter_profile == Vector2.ZERO)
			assert(is_equal_approx(point.lane_width, 3.5))
			for link in [point.prior_pt_init, point.next_pt_init]:
				if not link.is_empty():
					assert(point.get_node_or_null(link) is RoadGraphNode)
	var region: Terrain3DRegion = terrain.data.get_regionp(manager.global_position)
	var original_hash := hash(region.get_map(Terrain3DRegion.TYPE_HEIGHT).get_data())
	var count := _check_geometry(container, terrain, conformer.clearance)
	_check_junctions(container, conformer)
	# Reprojection must use source geometry, not accumulate subdivisions/offsets.
	conformer.refresh()
	await _settle()
	assert(_check_geometry(container, terrain, conformer.clearance) == count)
	# Native road editing signal: do not manually call refresh after this change.
	container.get_node("Bend").position.x += 12.0
	await _settle()
	_check_geometry(container, terrain, conformer.clearance)
	container.position.z += 8.0
	await _settle()
	_check_geometry(container, terrain, conformer.clearance)
	_check_uvs(conformer, manager.global_position)
	container.get_node("X_East").position.z += 2.0
	await _settle()
	_check_geometry(container, terrain, conformer.clearance)
	assert(hash(region.get_map(Terrain3DRegion.TYPE_HEIGHT).get_data()) == original_hash, "Road edits must not sculpt terrain")
	# Simulate one brush edit in memory and test the native terrain signal path.
	var grid := (manager.global_position / terrain.vertex_spacing).floor() * terrain.vertex_spacing
	var old_height := terrain.data.get_height(grid)
	var mesh_before_sculpt: Mesh = container.get_segments()[0].road_mesh.mesh
	terrain.data.set_height(grid, old_height + 1.0)
	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT)
	terrain.data.maps_edited.emit(AABB(grid - Vector3.ONE * 20.0, Vector3.ONE * 40.0))
	var sculpted_hash := hash(region.get_map(Terrain3DRegion.TYPE_HEIGHT).get_data())
	await _settle()
	assert(container.get_segments()[0].road_mesh.mesh != mesh_before_sculpt, "Terrain edit did not trigger reprojection")
	_check_geometry(container, terrain, conformer.clearance)
	assert(hash(region.get_map(Terrain3DRegion.TYPE_HEIGHT).get_data()) == sculpted_hash, "Projection changed the sculpted heightmap")
	terrain.data.set_height(grid, old_height)
	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT)
	await _settle()
	assert(hash(region.get_map(Terrain3DRegion.TYPE_HEIGHT).get_data()) == original_hash)
	print("PASS: GardaFinal roads, runtime collisions, rounded T/X junctions, automatic spline/sculpt updates, stable refresh, untouched heightmap; vertices=", count)
	map.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit()


func _check_editor_collisions() -> void:
	var manager := RoadManager.new()
	var container := RoadContainer.new()
	var instance := MeshInstance3D.new()
	instance.mesh = BoxMesh.new()
	manager.add_child(container)
	container.add_child(instance)
	# Also remove old colliders, rather than only preventing future generation.
	instance.create_trimesh_collision()
	assert(instance.get_child_count() == 1)
	container._create_collisions(instance)
	await process_frame
	assert(instance.get_child_count() == 0, "Editor kept a stale road collider")
	container._create_collisions(instance)
	assert(instance.get_child_count() == 0, "Editor generated road collision shapes")
	manager.free()
	print("PASS: editor road collisions removed and not regenerated")


func _check_geometry(container: RoadContainer, terrain: Terrain3D, clearance: float) -> int:
	var total := 0
	var roads := container.get_segments()
	assert(roads.size() == 7)
	roads.append_array(container.get_intersections())
	for road in roads:
		var instance: MeshInstance3D = road._mesh if road is RoadIntersection else road.road_mesh
		assert(instance.mesh.get_surface_count() > 0, "Missing road geometry")
		var conformer = container.get_parent().get_parent().get_node("RoadTerrain")
		var source: Mesh = conformer._sources[instance].source
		assert(absf(_area(instance.mesh) - _area(source)) < _area(source) * 0.001, "Projection lost road coverage")
		var bounds := (instance.global_transform * instance.get_aabb()).grow(terrain.vertex_spacing)
		bounds.position.y = -1000000.0
		bounds.size.y = 2000000.0
		var ground := terrain.generate_nav_mesh_source_geometry(bounds, false)
		# Independent oracle: read exact heightmap texels, not get_height()/navmesh
		# heights, which truncate to the wrong neighbour at Garda's fractional spacing.
		for i in ground.size():
			var p := ground[i]
			var cell := Vector2i(roundi(p.x / terrain.vertex_spacing), roundi(p.z / terrain.vertex_spacing))
			var region := terrain.data.get_regionp(p + Vector3(0.25, 0, 0.25) * terrain.vertex_spacing)
			ground[i].y = region.get_map(Terrain3DRegion.TYPE_HEIGHT).get_pixelv(cell - region.location * terrain.region_size).r
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			assert(vertices.size() == normals.size() and uvs.size() == vertices.size())
			for normal in normals:
				assert(normal.is_finite() and normal.y > 0.5, "Invalid road normal %s in %s" % [normal, road.name])
			total += vertices.size()
			for vertex in vertices:
				_check_point(instance.global_transform * vertex, ground, clearance)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size(), 3):
				var center := (vertices[indices[i]] + vertices[indices[i + 1]] + vertices[indices[i + 2]]) / 3.0
				_check_point(instance.global_transform * center, ground, clearance)
		# Native collision meshes must describe the newly draped surface, not the old spline.
		var bodies := instance.find_children("*", "StaticBody3D", false, false)
		var found := false
		for body in bodies:
			if body.is_queued_for_deletion():
				continue
			for shape in body.get_children():
				if shape is CollisionShape3D:
					assert(shape.shape is ConcavePolygonShape3D)
					assert(shape.shape.get_faces() == instance.mesh.get_faces())
					found = true
		assert(found, "Missing projected collision")
	return total


func _check_point(p: Vector3, ground: PackedVector3Array, clearance: float) -> void:
	for i in range(0, ground.size(), 3):
		var a := ground[i]
		var b := ground[i + 1]
		var c := ground[i + 2]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var wb := ap.cross(ac) / ab.cross(ac)
		var wc := ab.cross(ap) / ab.cross(ac)
		if wb < -0.0003 or wc < -0.0003 or wb + wc > 1.0003:
			continue
		var ground_y := a.y + wb * (b.y - a.y) + wc * (c.y - a.y)
		assert(absf(p.y - ground_y - clearance) < 0.015, "Road not flush: %s gap=%s" % [p, p.y - ground_y])
		return
	assert(false, "Road surface outside terrain coverage: %s" % p)


func _check_junctions(container: RoadContainer, conformer: Node) -> void:
	var material := container.effective_surface_material() as ShaderMaterial
	assert(material.get_shader_parameter("use_world_mapping"), "Asphalt must not restart on each junction triangle")
	container.create_edge_curves = true
	for junction in container.get_intersections():
		assert(junction.settings.resource_path == "res://resources/roads/rounded_rural_junction.tres")
		var source: Mesh = conformer._sources[junction._mesh].source
		var old_shape := IntersectionNGon.new().generate_mesh(junction, junction.edge_points, container)
		assert(_area(source) < _area(old_shape) * 0.995, "Rounded corners must cut into the old polygon")
		assert(_area(source) < 420.0, "Oversized junction footprint")
		var vertices: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for edge in junction.edge_points:
			var path: Path3D = junction.get_node("edge_" + str(edge.name))
			assert(path.curve.point_count == 2, "Generated exterior paths must use the rounded boundary too")
			var corners: Dictionary = junction.settings._edge_exterior_corners(edge, junction)
			for key in ["s0", "s1"]:
				var target: Vector3 = junction.to_local(corners[key])
				var found := false
				for vertex in vertices:
					found = found or vertex.distance_to(target) < 0.001
				assert(found, "Rounded junction detached from a road entry")
		var curve: Curve3D = junction.settings._corner_curve(Vector3(12, 0, 3.9), Vector3(10, 0, 3.9), Vector3(3.9, 0, 10), Vector3(3.9, 0, 12))
		var middle := curve.sample(0, 0.5)
		assert(middle.x < 6.3 and middle.z < 6.3, "Corner must be concave, not a straight chamfer")
		assert(curve.get_point_out(0).normalized().is_equal_approx(Vector3.LEFT))
		assert(curve.get_point_in(1).normalized().is_equal_approx(Vector3.FORWARD))
		print("Junction ", junction.name, ": rounded area=", _area(source), " m2")
	container.create_edge_curves = false


func _area(mesh: Mesh) -> float:
	var faces := mesh.get_faces()
	var area := 0.0
	for i in range(0, faces.size(), 3):
		var ab := faces[i + 1] - faces[i]
		var ac := faces[i + 2] - faces[i]
		area += absf(Vector2(ab.x, ab.z).cross(Vector2(ac.x, ac.z))) * 0.5
	return area


func _check_uvs(conformer: Node, origin: Vector3) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, -20), Vector2(20, 20), Vector2(-20, 20)]:
		tool.set_uv(p / 40.0 + Vector2.ONE * 0.5)
		tool.add_vertex(Vector3(p.x, 0, p.y))
	var source := tool.commit()
	var world := Transform3D(Basis(Vector3.UP, 0.37).scaled(Vector3(1.2, 1.0, 0.8)), origin)
	var projected: ArrayMesh = conformer.project_mesh(source, world)
	assert(projected.get_surface_count() == 1)
	var arrays := projected.surface_get_arrays(0)
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var vertex: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		var expected := Vector2(vertex.x, vertex.z) / 40.0 + Vector2.ONE * 0.5
		assert(expected.distance_to(arrays[Mesh.ARRAY_TEX_UV][i]) < 0.0003, "Projection distorted UVs")
	world.origin = Vector3(1000000, 0, 1000000)
	assert(conformer.project_mesh(source, world).get_surface_count() == 0, "Road outside terrain coverage")
