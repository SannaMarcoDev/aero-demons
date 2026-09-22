extends SceneTree
## Catalog, connected native roads, bridge elevation, exclusions and preserved airfield.
const Development = preload("res://scripts/maps/garda_development.gd")
const ORIGIN := Vector3(-36418.484, 234.52104, 413.42773)

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for frame in 5:
		await physics_frame
		await process_frame

func _run() -> void:
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/airport/source/city_layout.json"))
	assert(layout.revision == "approved-catalog-roadmanager")
	assert(layout.blocks.size() == 42 and layout.roads.size() == 64 and layout.trees.is_empty())
	var reached: Dictionary = {}
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var vertex: int = pending.pop_back()
		if reached.has(vertex):
			continue
		reached[vertex] = true
		for edge: Dictionary in layout.road_graph.edges:
			if int(edge.a) == vertex and not reached.has(int(edge.b)):
				pending.append(int(edge.b))
			if int(edge.b) == vertex and not reached.has(int(edge.a)):
				pending.append(int(edge.a))
	assert(reached.size() == layout.road_graph.vertices.size(), "No disconnected district, quay, logistics or turbine spur")
	var map: Node3D = load("res://scenes/maps/garda_final.tscn").instantiate()
	map.get_node("Forests").enabled = false
	map.get_node("GroundCover").process_mode = Node.PROCESS_MODE_DISABLED
	map.get_node("TutorialBoundaryController").process_mode = Node.PROCESS_MODE_DISABLED
	var terrain: Terrain3D = map.get_node("GardaTerrain")
	terrain.collision_mode = 0
	var camera := Camera3D.new()
	camera.position = ORIGIN + Vector3(-1300, 200, 500)
	camera.current = true
	map.add_child(camera)
	var city := map.get_node("AirportCity") as Node3D
	assert(city.position.is_equal_approx(ORIGIN) and city.transform == map.get_node("Airport").transform)
	var catalog: Dictionary = {}
	for building: Node3D in city.get_node("Buildings").get_children():
		var model: String = building.get_meta("catalog_model")
		catalog[model] = catalog.get(model, 0) + 1
		assert(building.has_node("Collision/MeshShape"))
		assert(building.get_node("Collision/MeshShape").shape is ConcavePolygonShape3D)
		assert(building.find_children("*", "MeshInstance3D", true, false).size() == 1)
	assert(city.get_node("Buildings").get_child_count() == layout.buildings.size())
	assert(catalog.size() == 17, "Ten approved buildings, three original standards, tower and three dishes")
	for model in ["residence_gabled","residence_courtyard","residence_l","residence_terraced","industrial_shed","offices_twins","office_spire","research_center","civic_canopy","warehouse_vault","standard_1","standard_2","standard_3"]:
		assert(catalog.has(model), model)
	for name in ["retained_wind_farm","retained_telecommunications","retained_airport_support","retained_waterfront","retained_viaduct_structure_bay_viaduct"]:
		assert(city.get_node("Infrastructure").find_child(name, true, false) != null, name)
	assert(city.find_children("*", "MultiMeshInstance3D", true, false).is_empty(), "All 168 courtyard trees removed; natural forests are separate")
	assert(city.find_children("*", "AnimationPlayer", true, false).is_empty())
	for mesh: MeshInstance3D in city.find_children("*", "MeshInstance3D", true, false):
		assert(not str(mesh.name).begins_with("city_details_"))
		assert(not str(mesh.name).begins_with("city_road_"), "No Blender carriageways")
	var manager := city.get_node("RoadManager") as RoadManager
	var conformer := city.get_node("RoadTerrain") as RoadTerrainConformer
	var elevated := manager.get_node("Elevated") as RoadContainer
	assert(conformer.excluded_containers == [elevated])
	root.add_child(map)
	await _settle()
	assert(conformer.terrain == terrain)
	var region := terrain.data.get_regionp(ORIGIN)
	var original_hash := hash(region.get_height_map().get_data())
	var junction_count := 0
	var segment_count := 0
	var projected_count := 0
	for container: RoadContainer in manager.get_containers():
		assert(not container.flatten_terrain)
		junction_count += container.get_intersections().size()
		segment_count += container.get_segments().size()
		for node: Node in container.get_children():
			if node is RoadPoint:
				assert(not node.auto_lanes)
				assert(node.traffic_dir.size() in [2,4])
				for link in [node.prior_pt_init,node.next_pt_init]:
					if not link.is_empty():
						assert(node.get_node_or_null(link) is RoadGraphNode)
		var roads := container.get_segments()
		roads.append_array(container.get_intersections())
		for road: Node3D in roads:
			var mesh: MeshInstance3D = road._mesh if road is RoadIntersection else road.road_mesh
			assert(mesh != null and mesh.mesh.get_surface_count() > 0, str(road.get_path()))
			assert(mesh.find_children("*", "CollisionShape3D", true, false).size() > 0)
			if container == elevated:
				assert(not conformer._sources.has(mesh), "Never project bridge decks onto water/terrain")
			else:
				assert(conformer._sources.has(mesh), "All ground roads and intersections drape")
				projected_count += 1
				var source_area := _area(conformer._sources[mesh].source, mesh.global_transform)
				var projected_area := _area(mesh.mesh, mesh.global_transform)
				assert(absf(source_area-projected_area) < source_area * 0.002, "Terrain projection lost road coverage: %s %f / %f" % [road.name,projected_area,source_area])
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				assert(vertices.size() == normals.size() and vertices.size() == uvs.size())
				for i in range(0, vertices.size(), maxi(1, vertices.size()/12)):
					assert(vertices[i].is_finite() and normals[i].is_finite() and uvs[i].is_finite())
	assert(junction_count >= 70 and segment_count >= 180 and projected_count > 220)
	var target := map.get_node("RoadManager/TwoLaneRoads/WestEnd") as RoadPoint
	var link := manager.get_node("Ground/UserRoadLink") as RoadPoint
	assert(target.get_next_road_node() == link and link.get_prior_road_node() == target, "Native connection to the preserved user road")
	assert(link.global_position.is_equal_approx(target.global_position))
	var saved_deck_mesh: Mesh = elevated.get_segments()[0].road_mesh.mesh
	conformer.refresh()
	await _settle()
	assert(elevated.get_segments()[0].road_mesh.mesh == saved_deck_mesh)
	assert(hash(region.get_height_map().get_data()) == original_hash, "City roads never sculpt the DEM")
	var space := city.get_world_3d().direct_space_state
	var bridge := ORIGIN + Vector3(-1150, 204.0 - ORIGIN.y, -1800)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(bridge + Vector3.UP * 3, bridge - Vector3.UP * 3))
	assert(not hit.is_empty() and absf(hit.position.y - bridge.y) < 0.15, "Native bridge carriageway and collision at 204 m")
	assert(space.intersect_ray(PhysicsRayQueryParameters3D.create(ORIGIN + Vector3(0,8,1200), ORIGIN + Vector3(0,8,-1200))).is_empty(), "Runway remains clear")
	assert(space.intersect_ray(PhysicsRayQueryParameters3D.create(ORIGIN + Vector3(425,6,1160), ORIGIN + Vector3(425,6,900))).is_empty(), "Hangar aisle remains clear")
	for block: Dictionary in layout.blocks:
		assert(Development.contains(ORIGIN + Vector3(block.center[0],0,block.center[1])))
	for road: Dictionary in layout.roads:
		for p: Array in road.points:
			assert(Development.contains(ORIGIN + Vector3(p[0],0,p[1])), road.name)
	for item: Dictionary in layout.buildings:
		assert(Development.contains(ORIGIN + Vector3(item.position[0],0,item.position[2])))
	assert(not Development.contains(ORIGIN + Vector3(-3000,0,1300)), "Natural woodland remains outside the exclusion mask")
	assert(not Development.contains(Vector3.ZERO) and not Development.contains(Vector3(NAN,0,0)))
	if DisplayServer.get_name() != "headless":
		var clouds = map.get_node("SunshineCloudsDriverGD").clouds_resource
		map.get_node("Sky3D").compositor = null
		RenderingServer.call_on_render_thread(clouds.clear_compute)
		await RenderingServer.frame_post_draw
	print("PASS: AIRPORT CITY thirteen building models; buildings=",layout.buildings.size()," junctions=",junction_count," native_segments=",segment_count," three dishes, retained infrastructure, zero urban trees, connected user roads, elevated bridge, unchanged terrain")
	map.queue_free()
	for frame in 8:
		await process_frame
	quit()

func _area(mesh: Mesh, world: Transform3D) -> float:
	var area := 0.0
	var faces := mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var a := world.basis * (faces[i+1]-faces[i])
		var b := world.basis * (faces[i+2]-faces[i])
		area += absf(a.cross(b).y) * 0.5
	return area
