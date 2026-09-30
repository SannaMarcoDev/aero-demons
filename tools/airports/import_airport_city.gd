@tool
extends EditorScenePostImport
## Keep authored terrain-contact vertices; auto-LOD is still useful on buildings.
func _post_import(scene: Node) -> Object:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var surface := mesh.name.begins_with("city_road_") or mesh.name.begins_with("city_pavement_") or mesh.name.ends_with("_plaza") or mesh.name.begins_with("city_logistics_yard_")
		if surface:
			mesh.lod_bias = 128.0
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		elif mesh.name.begins_with("city_details_"):
			mesh.visibility_range_end = 1800.0
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return scene
