extends SceneTree
## Build catalog instances, shared exact collisions and editable RoadManager roads.
## No Terrain3D data, airport asset or existing user roads are written.
const MINIMUM := Vector2(-4000, -3300)
const PIXEL_METRES := 7.0
const LIBRARY := "res://assets/environment/airport/library/"
const CONFORMER = preload("res://scripts/maps/road_terrain_conformer.gd")
const CITY_SCRIPT = preload("res://scripts/maps/airport_city.gd")
const JUNCTION = preload("res://resources/roads/rounded_rural_junction.tres")
var mask := Image.create(1024, 1024, false, Image.FORMAT_L8)
var city := Node3D.new()
var containers: Array[RoadContainer] = []
var points: Dictionary = {}
var crossings: Array = []
var cross_links: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _own(node: Node, parent: Node, label: String) -> void:
	node.name = label
	parent.add_child(node)
	node.owner = city

func _run() -> void:
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/airport/source/city_layout.json"))
	assert(layout.revision == "approved-catalog-roadmanager" and layout.trees.is_empty())
	for rect: Array in layout.exclusions:
		_rect(Vector2(rect[0], rect[1]), Vector2(rect[2], rect[3]))
	_rect(Vector2(-615, -1260), Vector2(580, 1280))
	_rect(Vector2(-165, -2800), Vector2(165, 3100))
	_rect(Vector2(1295, 2555), Vector2(1545, 2920))
	for road: Dictionary in layout.roads:
		for i in range(road.points.size() - 1):
			var a: Array = road.points[i]
			var b: Array = road.points[i + 1]
			_segment(Vector2(a[0], a[1]), Vector2(b[0], b[1]), road.width * 0.5 + 14.0)
	assert(ResourceSaver.save(mask, "res://resources/terrain/garda_development.res", ResourceSaver.FLAG_COMPRESS) == OK)
	city.name = "AirportCity"
	city.set_script(CITY_SCRIPT)
	_own(load("res://assets/environment/airport/airport_infrastructure.glb").instantiate(), city, "Infrastructure")
	_buildings(layout)
	_roads(layout.road_graph)
	var packed := PackedScene.new()
	assert(packed.pack(city) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/maps/airport_city.tscn") == OK)
	city.free()
	print("PASS: CITY PREPARE buildings=", layout.buildings.size(), " native_road_edges=", layout.road_graph.edges.size(), " junctions=", crossings.size(), " urban_trees=0")
	quit()

func _buildings(layout: Dictionary) -> void:
	var group := Node3D.new()
	_own(group, city, "Buildings")
	var foundations := Node3D.new()
	_own(foundations, city, "Foundations")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("898a80")
	stone.roughness = 0.9
	var shapes: Dictionary = {}
	for item: Dictionary in layout.buildings:
		var instance: Node3D = load(LIBRARY + item.model + ".glb").instantiate()
		_own(instance, group, item.name)
		instance.position = Vector3(item.position[0], item.position[1], item.position[2])
		instance.rotation.y = deg_to_rad(item.yaw)
		instance.set_meta("catalog_model", item.model)
		var body := StaticBody3D.new()
		_own(body, instance, "Collision")
		# One shared triangle shape per catalog mesh, not per occurrence. Courtyards,
		# bridges, L-shaped recesses and concave dishes retain their actual openings.
		for mesh: MeshInstance3D in instance.find_children("*", "MeshInstance3D", true, false):
			if not shapes.has(mesh.mesh):
				shapes[mesh.mesh] = mesh.mesh.create_trimesh_shape()
			var shape := CollisionShape3D.new()
			shape.shape = shapes[mesh.mesh]
			var transform := mesh.transform
			var parent := mesh.get_parent() as Node3D
			while parent != instance:
				transform = parent.transform * transform
				parent = parent.get_parent() as Node3D
			shape.transform = transform
			_own(shape, body, "MeshShape")
		var dimensions: Array = layout.catalog_metrics[item.model].dimensions_blender
		var depth: float = item.position[1] - item.foundation_bottom
		var foundation := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(dimensions[0] + 2, depth, dimensions[1] + 2)
		box.material = stone
		foundation.mesh = box
		foundation.position = instance.position - Vector3.UP * depth * 0.5
		foundation.rotation = instance.rotation
		_own(foundation, foundations, item.name)
		var footing := StaticBody3D.new()
		_own(footing, foundation, "Collision")
		var collider := CollisionShape3D.new()
		var volume := BoxShape3D.new()
		volume.size = box.size
		collider.shape = volume
		_own(collider, footing, "Shape")

func _roads(graph: Dictionary) -> void:
	var manager := RoadManager.new()
	manager.auto_refresh = false
	manager.density = 8.0
	_own(manager, city, "RoadManager")
	for label in ["Ground", "Elevated"]:
		var container := RoadContainer.new()
		container.flatten_terrain = false
		container.use_lowpoly_preview = true
		_own(container, manager, label)
		containers.append(container)
	var conformer := CONFORMER.new()
	conformer.road_manager = manager
	conformer.clearance = 0.2 # Same shallow separation as the preceding city, visible through distant DEM morphing.
	conformer.excluded_containers = [containers[1]]
	_own(conformer, city, "RoadTerrain")
	var vertices: Array[Vector3] = []
	var incident: Array[Array] = []
	for p: Array in graph.vertices:
		vertices.append(Vector3(p[0], p[1], p[2]))
		incident.append([])
	for i in graph.edges.size():
		var edge: Dictionary = graph.edges[i]
		incident[int(edge.a)].append(i)
		incident[int(edge.b)].append(i)
	for v in vertices.size():
		var neighbors: Array[int] = []
		var modes: Array[int] = []
		for id: int in incident[v]:
			var edge: Dictionary = graph.edges[id]
			neighbors.append(int(edge.b if int(edge.a) == v else edge.a))
			modes.append(int(edge.elevated))
		if neighbors.size() >= 3:
			var mode := 1 if not modes.has(0) else 0
			var junction := RoadIntersection.new()
			junction.settings = JUNCTION
			junction.position = vertices[v]
			junction.flatten_terrain = false
			_own(junction, containers[mode], "Junction_%03d" % v)
			var branches: Array[RoadPoint] = []
			var approach := 15.0
			for a in neighbors.size():
				for b in range(a + 1, neighbors.size()):
					var da := Vector2(vertices[neighbors[a]].x - vertices[v].x, vertices[neighbors[a]].z - vertices[v].z).normalized()
					var db := Vector2(vertices[neighbors[b]].x - vertices[v].x, vertices[neighbors[b]].z - vertices[v].z).normalized()
					var angle := acos(clampf(da.dot(db), -1.0, 1.0))
					approach = maxf(approach, 12.0 / tan(maxf(angle, 0.05) * 0.5))
			for j in neighbors.size():
				var direction := vertices[neighbors[j]] - vertices[v]
				var offset := minf(approach, direction.length() * 0.28)
				var p := _point(v, j, mode, vertices[v] + direction.normalized() * offset, direction, graph.edges[incident[v][j]].width)
				p.prior_pt_init = NodePath("../" + junction.name)
				p.prior_mag = offset * 0.45
				p.next_mag = minf(32.0, direction.length() * 0.2)
				branches.append(p)
				if mode != modes[j]:
					var paired := _point(v, j, modes[j], p.position, direction, graph.edges[incident[v][j]].width)
					paired.next_mag = p.next_mag
					cross_links.append([p, RoadPoint.PointInit.NEXT, paired, RoadPoint.PointInit.PRIOR])
					p = paired
				points[Vector2i(v, incident[v][j])] = [p, RoadPoint.PointInit.NEXT]
			junction.edge_points = branches
			crossings.append(junction)
		else:
			var direction := vertices[neighbors[0]] - (vertices[neighbors[1]] if neighbors.size() == 2 else vertices[v])
			var p := _point(v, 0, modes[0], vertices[v], direction, graph.edges[incident[v][0]].width)
			p.prior_mag = minf(30.0, vertices[v].distance_to(vertices[neighbors[0]]) * 0.25)
			p.next_mag = p.prior_mag
			points[Vector2i(v, incident[v][0])] = [p, RoadPoint.PointInit.NEXT]
			if v == int(graph.user_link_vertex):
				p.name = "UserRoadLink"
			if neighbors.size() == 2:
				if modes[0] != modes[1]:
					var paired := _point(v, 1, modes[1], p.position, direction, graph.edges[incident[v][1]].width)
					paired.prior_mag = p.prior_mag
					cross_links.append([p, RoadPoint.PointInit.PRIOR, paired, RoadPoint.PointInit.NEXT])
					p = paired
				points[Vector2i(v, incident[v][1])] = [p, RoadPoint.PointInit.PRIOR]
	for i in graph.edges.size():
		var edge: Dictionary = graph.edges[i]
		var a: Array = points[Vector2i(edge.a, i)]
		var b: Array = points[Vector2i(edge.b, i)]
		assert(a[0].get_parent() == b[0].get_parent())
		_connect(a[0], a[1], b[0], b[1])
	# Persist the native plugin's cross-container edge tables, including open ends.
	for container in containers:
		for point: Node in container.get_children():
			if not point is RoadPoint:
				continue
			for dir in [RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.NEXT]:
				if point.get("prior_pt_init" if dir == RoadPoint.PointInit.PRIOR else "next_pt_init") != NodePath(""):
					continue
				container.edge_containers.append(NodePath(""))
				container.edge_rp_targets.append(NodePath(""))
				container.edge_rp_target_dirs.append(-1)
				container.edge_rp_locals.append(NodePath(point.name))
				container.edge_rp_local_dirs.append(dir)
	for link: Array in cross_links:
		for k in [0, 2]:
			var p: RoadPoint = link[k]
			var target: RoadPoint = link[(k + 2) % 4]
			var container: RoadContainer = p.get_parent()
			for i in container.edge_rp_locals.size():
				if container.edge_rp_locals[i] == NodePath(p.name) and container.edge_rp_local_dirs[i] == link[k + 1]:
					container.edge_containers[i] = NodePath("../" + target.get_parent().name)
					container.edge_rp_targets[i] = NodePath(target.name)
					container.edge_rp_target_dirs[i] = link[(k + 3) % 4]
	manager.auto_refresh = true

func _point(v: int, branch: int, mode: int, position: Vector3, direction: Vector3, width: float) -> RoadPoint:
	var point := RoadPoint.new()
	point.auto_lanes = false
	if width >= 14:
		point.traffic_dir = [RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD, RoadPoint.LaneDir.FORWARD]
		point.lanes = [RoadPoint.LaneType.SLOW, RoadPoint.LaneType.MIDDLE, RoadPoint.LaneType.MIDDLE, RoadPoint.LaneType.SLOW]
	else:
		point.traffic_dir = [RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD]
		point.lanes = [RoadPoint.LaneType.SLOW, RoadPoint.LaneType.SLOW]
	point.lane_width = 3.5 if width >= 10 else 2.5
	point.shoulder_width_l = 1.0 if width >= 14 else 0.4
	point.shoulder_width_r = point.shoulder_width_l
	point.gutter_profile = Vector2.ZERO
	point.position = position
	point.basis = Basis.looking_at(-direction.normalized(), Vector3.UP)
	_own(point, containers[mode], "Point_%03d_%d" % [v, branch])
	return point

func _connect(a: RoadPoint, ad: int, b: RoadPoint, bd: int) -> void:
	a.set("prior_pt_init" if ad == RoadPoint.PointInit.PRIOR else "next_pt_init", NodePath("../" + b.name))
	b.set("prior_pt_init" if bd == RoadPoint.PointInit.PRIOR else "next_pt_init", NodePath("../" + a.name))

func _pixel(p: Vector2) -> Vector2i:
	return Vector2i(((p - MINIMUM) / PIXEL_METRES).floor())

func _rect(a: Vector2, b: Vector2) -> void:
	var first := _pixel(a)
	mask.fill_rect(Rect2i(first, _pixel(b) - first + Vector2i.ONE), Color.WHITE)

func _segment(a: Vector2, b: Vector2, radius: float) -> void:
	var first := _pixel(a.min(b) - Vector2.ONE * radius)
	var last := _pixel(a.max(b) + Vector2.ONE * radius)
	for y in range(maxi(0, first.y), mini(1023, last.y) + 1):
		for x in range(maxi(0, first.x), mini(1023, last.x) + 1):
			var point := MINIMUM + (Vector2(x, y) + Vector2.ONE * 0.5) * PIXEL_METRES
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) <= radius + PIXEL_METRES:
				mask.set_pixel(x, y, Color.WHITE)
