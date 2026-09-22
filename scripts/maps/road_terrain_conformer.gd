@tool
class_name RoadTerrainConformer
extends Node
## Drapes generated road surfaces over Terrain3D. Never writes terrain data.
## RoadGenerator still owns spline editing, lane UVs, junctions and materials.

@export var terrain: Terrain3D:
	set(value):
		terrain = value
		if is_inside_tree():
			_bind_sources.call_deferred()
@export var road_manager: RoadManager:
	set(value):
		road_manager = value
		if is_inside_tree():
			_bind_sources.call_deferred()
## Engineered decks/ramps retain RoadGenerator's authored elevations.
@export var excluded_containers: Array[RoadContainer] = []
## Small separation in metres, not an embankment or terrain excavation.
@export_range(0.01, 0.2, 0.01) var clearance := 0.05:
	set(value):
		clearance = clampf(value, 0.01, 0.2)
		if is_inside_tree():
			refresh.call_deferred()
@export_tool_button("Refresh road surface", "Reload") var refresh_action: Callable = refresh

var _manager: RoadManager
var _data: Terrain3DData
var _pending: Dictionary = {}
var _sources: Dictionary = {}


func _ready() -> void:
	_bind_sources()


func _enter_tree() -> void:
	if is_node_ready():
		_bind_sources.call_deferred()


func _exit_tree() -> void:
	_disconnect_sources()
	_pending.clear()
	_sources.clear()


func _disconnect_sources() -> void:
	if is_instance_valid(_manager):
		if _manager.on_road_updated.is_connected(_queue_roads):
			_manager.on_road_updated.disconnect(_queue_roads)
		if _manager.on_container_transformed.is_connected(_queue_container):
			_manager.on_container_transformed.disconnect(_queue_container)
	if is_instance_valid(_data):
		if _data.height_maps_changed.is_connected(refresh):
			_data.height_maps_changed.disconnect(refresh)
		if _data.maps_edited.is_connected(_terrain_edited):
			_data.maps_edited.disconnect(_terrain_edited)


func _bind_sources() -> void:
	if not is_inside_tree():
		return
	_disconnect_sources()
	_pending.clear()
	_manager = road_manager
	_data = terrain.data if is_instance_valid(terrain) else null
	if is_instance_valid(_manager):
		_manager.on_road_updated.connect(_queue_roads)
		_manager.on_container_transformed.connect(_queue_container)
	if is_instance_valid(_data):
		_data.height_maps_changed.connect(refresh)
		_data.maps_edited.connect(_terrain_edited)
	update_configuration_warnings()
	refresh()


func _get_configuration_warnings() -> PackedStringArray:
	if not is_instance_valid(terrain) or not is_instance_valid(road_manager):
		return ["Assign Terrain3D and RoadManager. No terrain is modified by this node."]
	return []


func _terrain_edited(_area: AABB) -> void:
	# ponytail: refresh the whole network after terrain edits; filter by edited AABB for large networks.
	refresh()


func refresh() -> void:
	if not is_inside_tree() or not is_instance_valid(road_manager):
		return
	for container in road_manager.get_containers():
		_queue_container(container)


func _queue_container(container: RoadContainer) -> void:
	_queue_roads(container.get_segments())
	_queue_roads(container.get_intersections())


func _queue_roads(roads: Array) -> void:
	for road in roads:
		if road.container not in excluded_containers:
			_pending[road] = true


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(terrain) or not is_instance_valid(terrain.data):
		return
	if not is_instance_valid(_data) or _data != terrain.data:
		_bind_sources()
	if _pending.is_empty():
		return
	# Do not rebuild collision meshes on every mouse motion while dragging/sculpting.
	if Engine.is_editor_hint() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	for instance in _sources.keys():
		if not is_instance_valid(instance):
			_sources.erase(instance)
	var roads := _pending.keys()
	_pending.clear()
	for road in roads:
		if not is_instance_valid(road) or road.is_queued_for_deletion():
			continue
		var instance: MeshInstance3D = road._mesh if road is RoadIntersection else road.road_mesh
		if not is_instance_valid(instance) or instance.mesh == null:
			continue
		# Keep the unprojected source: repeated refreshes must not subdivide their own output.
		if not _sources.has(instance) or instance.mesh != _sources[instance].projected:
			_sources[instance] = {"source": instance.mesh, "projected": null}
		var projected := project_mesh(_sources[instance].source, instance.global_transform)
		_sources[instance].projected = projected
		instance.mesh = projected
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if projected.get_surface_count() > 0:
			road.container._create_collisions(instance)
		else:
			for child in instance.get_children():
				if child is StaticBody3D:
					child.queue_free()
			push_warning("Road outside Terrain3D coverage or over a hole: %s" % road.get_path())


## Clip each road triangle to native terrain triangles, rather than stretching
## a few projected vertices across hills. Uses only local terrain geometry.
func project_mesh(source: Mesh, world: Transform3D) -> ArrayMesh:
	var result := ArrayMesh.new()
	var inverse := world.affine_inverse()
	for surface in source.get_surface_count():
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs := PackedVector2Array() if arrays[Mesh.ARRAY_TEX_UV] == null else PackedVector2Array(arrays[Mesh.ARRAY_TEX_UV])
		var indices := PackedInt32Array() if arrays[Mesh.ARRAY_INDEX] == null else PackedInt32Array(arrays[Mesh.ARRAY_INDEX])
		if uvs.size() != vertices.size():
			push_warning("Road surface has no lane UVs; skipping projection")
			continue
		if indices.is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(source.surface_get_material(surface))
		var count := 0
		for i in range(0, indices.size(), 3):
			var ids := [indices[i], indices[i + 1], indices[i + 2]]
			var points := PackedVector3Array([world * vertices[ids[0]], world * vertices[ids[1]], world * vertices[ids[2]]])
			# Work near zero for the clipping operation, even on the 250 km maps.
			var origin := Vector2(points[0].x, points[0].z)
			var road_polygon := _xz(points, origin)
			if absf((road_polygon[1] - road_polygon[0]).cross(road_polygon[2] - road_polygon[0])) < 0.000001:
				continue # Zero-width gutters/vertical underside faces are not a road surface.
			var bounds := AABB(points[0], Vector3.ZERO).expand(points[1]).expand(points[2])
			bounds = bounds.grow(terrain.vertex_spacing)
			bounds.position.y = -1000000.0
			bounds.size.y = 2000000.0
			var ground := terrain.generate_nav_mesh_source_geometry(bounds, false)
			for j in ground.size():
				# Terrain3D 1.0.2 truncates CPU pixel coordinates: at non-integer
				# spacing a grid vertex can sample its neighbour (metres too low).
				# Sample inside the intended texel, matching the shader's round().
				var sample := ground[j] + Vector3(0.25, 0.0, 0.25) * terrain.vertex_spacing
				ground[j].y = terrain.data.get_pixel(Terrain3DRegion.TYPE_HEIGHT, sample).r
				if terrain.data.get_control(sample) & (1 << 2):
					ground[j].y = NAN
			for j in range(0, ground.size(), 3):
				var ground_points := PackedVector3Array([ground[j], ground[j + 1], ground[j + 2]])
				if not ground_points[0].is_finite() or not ground_points[1].is_finite() or not ground_points[2].is_finite():
					continue
				var ground_polygon := _xz(ground_points, origin)
				var normal := (ground_points[2] - ground_points[0]).cross(ground_points[1] - ground_points[0]).normalized()
				tool.set_normal((world.basis.transposed() * normal).normalized())
				for polygon in Geometry2D.intersect_polygons(road_polygon, ground_polygon):
					var triangles := Geometry2D.triangulate_polygon(polygon)
					for index in triangles:
						var p: Vector2 = polygon[index]
						var terrain_weights := _barycentric(p, ground_polygon)
						var height := terrain_weights.dot(Vector3(ground_points[0].y, ground_points[1].y, ground_points[2].y))
						var road_weights := _barycentric(p, road_polygon)
						tool.set_uv(uvs[ids[0]] * road_weights.x + uvs[ids[1]] * road_weights.y + uvs[ids[2]] * road_weights.z)
						var local_origin := inverse * Vector3(origin.x, 0.0, origin.y)
						tool.add_vertex(local_origin + inverse.basis * Vector3(p.x, height + clearance, p.y))
						count += 1
		if count > 0:
			tool.generate_tangents()
			tool.index()
			tool.commit(result)
	return result


static func _xz(points: PackedVector3Array, origin: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(points[0].x, points[0].z) - origin,
		Vector2(points[1].x, points[1].z) - origin,
		Vector2(points[2].x, points[2].z) - origin,
	])


static func _barycentric(p: Vector2, triangle: PackedVector2Array) -> Vector3:
	var ab := triangle[1] - triangle[0]
	var ac := triangle[2] - triangle[0]
	var ap := p - triangle[0]
	var b := ap.cross(ac) / ab.cross(ac)
	var c := ab.cross(ap) / ab.cross(ac)
	return Vector3(1.0 - b - c, b, c)
