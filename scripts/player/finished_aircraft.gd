@tool
extends Node3D
## Applies the supplied finished livery to every mesh in the imported FBX.

@export_enum("Blue Camo", "Brown Camo") var livery: String = "Blue Camo"

const TEXTURE_ROOT := "res://assets/aircraft/finished/Texture finished/"
const TEXTURE_NAME := "Aereo Caccia_openPBR_shader1_"

func _ready() -> void:
	_apply_livery()

func _apply_livery() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(_texture_path("BaseColor"))
	material.metallic_texture = load(_texture_path("Metallic"))
	material.roughness_texture = load(_texture_path("Roughness"))
	material.normal_enabled = true
	material.normal_texture = load(_texture_path("Normal"))

	var mesh_count := 0
	for mesh_instance in find_children("*", "MeshInstance3D", true, false):
		mesh_instance.material_override = material
		mesh_count += 1
	if mesh_count == 0:
		push_warning("Finished aircraft imported without any MeshInstance3D nodes.")

func _texture_path(map_name: String) -> String:
	return "%s%s/%s%s.png" % [TEXTURE_ROOT, livery, TEXTURE_NAME, map_name]
