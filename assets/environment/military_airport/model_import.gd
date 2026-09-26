@tool
extends EditorScenePostImport

const MATERIALS := "res://assets/environment/military_airport/materials/"
var _scene: Node

func _post_import(scene: Node) -> Object:
	_scene = scene
	_apply(scene)
	return scene

func _apply(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(i)
			if original:
				var path: String = MATERIALS + original.resource_name + ".tres"
				if ResourceLoader.exists(path):
					node.set_surface_override_material(i, load(path))
		if "Buildings/" in get_source_file() or "Props/" in get_source_file():
			var body := StaticBody3D.new()
			body.name = "Collision"
			node.add_child(body)
			body.owner = _scene
			var shape := CollisionShape3D.new()
			shape.shape = node.mesh.create_trimesh_shape()
			body.add_child(shape)
			shape.owner = _scene
	for child in node.get_children():
		if child is MeshInstance3D or child is Node3D and not child is StaticBody3D:
			_apply(child)
