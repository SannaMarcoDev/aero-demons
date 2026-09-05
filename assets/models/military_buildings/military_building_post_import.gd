@tool
extends EditorScenePostImport

const SKIP_COLLISION := ["cylinder", "sphere", "door_handle"]


func _post_import(scene: Node) -> Object:
	print("military_building_post_import: processing ", scene.name)
	_recenter_to_ground(scene)
	_prepare_meshes(scene)
	if scene is Node3D:
		(scene as Node3D).add_to_group("military_building", true)
	return scene


func _recenter_to_ground(scene: Node) -> void:
	var aabb := _world_aabb(scene, Transform3D.IDENTITY)
	if aabb.size == Vector3.ZERO:
		return
	var offset := Vector3(
		-(aabb.position.x + aabb.size.x * 0.5),
		-aabb.position.y,
		-(aabb.position.z + aabb.size.z * 0.5)
	)
	if offset.is_zero_approx():
		return
	for child in scene.get_children():
		if child is Node3D:
			(child as Node3D).position += offset


func _prepare_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var lname := mesh_inst.name.to_lower()
		if "glass" in lname:
			mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_tune_glass(mesh_inst)
		else:
			mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh_inst.mesh != null and not _is_tiny_fitting(lname):
			if mesh_inst.get_child_count() == 0 or mesh_inst.find_child("StaticBody3D", true, false) == null:
				mesh_inst.create_trimesh_collision()
	for child in node.get_children():
		_prepare_meshes(child)


func _tune_glass(mesh_inst: MeshInstance3D) -> void:
	var mesh := mesh_inst.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.metallic = maxf(sm.metallic, 0.1)
			sm.roughness = minf(sm.roughness, 0.08)


func _is_tiny_fitting(lname: String) -> bool:
	for token in SKIP_COLLISION:
		if token in lname:
			return true
	return false


func _world_aabb(node: Node, parent_xf: Transform3D) -> AABB:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	var started := false
	var result := AABB()
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh != null:
			result = xf * mesh_inst.get_aabb()
			started = true
	for child in node.get_children():
		var child_aabb := _world_aabb(child, xf)
		if child_aabb.size == Vector3.ZERO:
			continue
		if started:
			result = result.merge(child_aabb)
		else:
			result = child_aabb
			started = true
	return result
