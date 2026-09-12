@tool
extends Node3D

## Controller for the F/A-26 Jet Fighter.
## Allows selecting camo liveries (0 to 4) and provides engine/hardpoint sockets.

@export_enum("Camo 0", "Camo 1", "Camo 2", "Camo 3", "Camo 4") var livery: String = "Camo 0":
	set(val):
		livery = val
		_apply_livery()

const MATERIAL_BASE := "res://assets/aircraft/fa_n26/materials/fa_n26_camo_"

@onready var airframe: MeshInstance3D = get_node_or_null("Model/Airframe")
@onready var engine_left: Node3D = get_node_or_null("Model/Airframe/Engine_Left")
@onready var engine_right: Node3D = get_node_or_null("Model/Airframe/Engine_Right")

func _ready() -> void:
	if not airframe:
		airframe = get_node_or_null("Model/Airframe")
	_apply_livery()

func _apply_livery() -> void:
	if not airframe:
		airframe = get_node_or_null("Model/Airframe")
	if not airframe:
		return

	var idx: String = livery.replace("Camo ", "")
	var mat_path := "%s%s.tres" % [MATERIAL_BASE, idx]
	if ResourceLoader.exists(mat_path):
		var mat = load(mat_path)
		airframe.material_override = mat

func get_engine_positions() -> Array[Node3D]:
	var res: Array[Node3D] = []
	if engine_left:
		res.append(engine_left)
	if engine_right:
		res.append(engine_right)
	return res
