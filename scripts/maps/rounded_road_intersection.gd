@tool
extends IntersectionNGon
## Opt-in rounded footprint; RoadGenerator still owns branches and connectivity.
## Use world-mapped asphalt. Terrain projection is handled by RoadTerrainConformer.

func generate_mesh(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
	if edges.size() < 2 or not can_generate_mesh(intersection.transform, edges):
		return super.generate_mesh(intersection, edges, container)
	var vertices := PackedVector3Array()
	var polygon := PackedVector2Array()
	var inverse := intersection.global_transform.affine_inverse()
	# Follow the same right-hand exterior boundaries as native edge_* paths.
	for i in range(edges.size() - 1, -1, -1):
		var edge := edges[i]
		var neighbor := edges[(i - 1 + edges.size()) % edges.size()]
		if _get_edge_facing(edge, intersection) == _IntersectNGonFacing.OTHER:
			return super.generate_mesh(intersection, edges, container)
		var here := _edge_exterior_corners(edge, intersection)
		var there := _edge_exterior_corners(neighbor, intersection)
		var curve := _corner_curve(inverse * here.s1, inverse * here.s1_stop, inverse * there.s0_stop, inverse * there.s0)
		vertices.append(inverse * here.s0)
		var steps := maxi(8, ceili(curve.get_baked_length() / 0.75))
		for step in steps:
			vertices.append(curve.sample(0, float(step) / steps))
	for vertex in vertices:
		polygon.append(Vector2(vertex.x, vertex.z))
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty():
		push_warning("Overlapping junction branches: adjust the entry points")
		return super.generate_mesh(intersection, edges, container)
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(container.effective_surface_material())
	for index in triangles:
		var p := vertices[index]
		# Continuous, non-degenerate UVs confined to the trimsheet's unmarked lane.
		tool.set_uv(Vector2(0.8 + 0.025 * (p.x - bounds.position.x) / maxf(bounds.size.x, 0.001), p.z * 0.1))
		tool.add_vertex(p)
	tool.generate_normals()
	tool.generate_tangents()
	tool.index()
	return tool.commit()


func _corner_curve(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> Curve3D:
	# Cubic quarter-circle handle/chord ratio. Straight opposing arms stay straight.
	var handle := p0.distance_to(p3) * 0.3905243
	var curve := Curve3D.new()
	curve.add_point(p0, Vector3.ZERO, (p1 - p0).normalized() * handle)
	curve.add_point(p3, (p2 - p3).normalized() * handle, Vector3.ZERO)
	return curve


func _assign_edge_curve(path: Path3D, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	var inverse := path.global_transform.affine_inverse()
	path.curve = _corner_curve(inverse * p0, inverse * p1, inverse * p2, inverse * p3)
