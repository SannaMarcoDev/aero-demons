extends SceneTree
## Bake the authoring manifest into a small CPU exclusion mask and static street-tree scene.
## No Terrain3D data or user roads are modified. Run after exporting build_city.py.
const MINIMUM := Vector2(-4000, -3300)
const PIXEL_METRES := 7.0
var mask := Image.create(1024, 1024, false, Image.FORMAT_L8)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "Use a graphics renderer: Godot's dummy renderer does not serialize MultiMesh transforms")
	for audio in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/airport/source/city_layout.json"))
	for rect: Array in layout.exclusions:
		_rect(Vector2(rect[0], rect[1]), Vector2(rect[2], rect[3]))
	# Operational pavement and approach strips, not the old 4 km empty disk.
	_rect(Vector2(-615, -1260), Vector2(580, 1280))
	_rect(Vector2(-165, -2800), Vector2(165, 3100))
	# Existing user-authored demonstration road, retained exactly as delivered.
	_rect(Vector2(1295, 2555), Vector2(1545, 2920))
	for road: Dictionary in layout.roads:
		var points: Array = road.points
		for i in range(points.size() - 1):
			_segment(Vector2(points[i][0], points[i][1]), Vector2(points[i + 1][0], points[i + 1][1]), road.width * 0.5 + 14.0)
	assert(ResourceSaver.save(mask, "res://resources/terrain/garda_development.res", ResourceSaver.FLAG_COMPRESS) == OK)
	# Medium-detail shared tree mesh; courtyard trees are static, not a new population system.
	var assets: Terrain3DAssets = load("res://resources/terrain/garda_surface_assets.tres")
	var asset := assets.get_mesh_asset(1)
	var tree_material: ShaderMaterial = asset.material_override.duplicate()
	tree_material.set_shader_parameter("wind_strength", 0.0)
	var city := Node3D.new()
	city.name = "AirportCity"
	var visuals: Node3D = load("res://assets/environment/airport/airport_city.glb").instantiate()
	visuals.name = "Visuals"
	city.add_child(visuals)
	visuals.owner = city
	var groups: Dictionary = {}
	for p: Array in layout.trees:
		var cell := Vector2i(floori(p[0] / 256.0), floori(p[1] / 256.0))
		if not groups.has(cell): groups[cell] = []
		groups[cell].append(p)
	for cell: Vector2i in groups:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = asset.get_mesh(1)
		batch.instance_count = groups[cell].size()
		var node := MultiMeshInstance3D.new()
		node.name = "StreetTrees_%d_%d" % [cell.x, cell.y]
		node.position = Vector3(cell.x * 256, 0, cell.y * 256)
		node.material_override = tree_material
		node.multimesh = batch
		node.visibility_range_end = 6000.0
		node.visibility_range_end_margin = 500.0
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in groups[cell].size():
			var p: Array = groups[cell][i]
			var pos := Vector3(p[0], p[2], p[1]) - node.position
			batch.set_instance_transform(i, Transform3D(Basis(Vector3.UP, i * 2.4).scaled(Vector3.ONE * 0.7), pos))
		assert(batch.get_instance_transform(0).basis.determinant() > 0.3, "Tree transforms must survive renderer readback")
		city.add_child(node)
		node.owner = city
	var packed := PackedScene.new()
	assert(packed.pack(city) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/maps/airport_city.tscn") == OK)
	city.free()
	print("PASS: CITY PREPARE blocks=", layout.blocks.size(), " roads=", layout.roads.size(), " street_trees=", layout.trees.size())
	quit()

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
