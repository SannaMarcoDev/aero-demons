extends RefCounted
## The current build offers only the Saab JA 37 to the player.

const DEFAULT_ID := "saab_ja37"
const DEFS := {
	"saab_ja37": {
		"label": "SAAB JA 37 · VIGGEN",
		"description": "Caccia Saab JA 37 Viggen di Aero Demon.",
		"scene": preload("res://scenes/aircraft/saab_ja37.tscn"),
		"transform": Transform3D(Vector3(0.5, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 0, 0.5), Vector3(0, -1.2, 0.56)),
	},
}


static func ids() -> Array:
	return [DEFAULT_ID]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[DEFAULT_ID])


static func create_model(id: String) -> Node3D:
	var definition := get_def(id)
	var model := (definition.scene as PackedScene).instantiate() as Node3D
	model.name = "AircraftModel"
	model.transform = definition.transform
	return model


static func apply_to_player(player: Node3D, _id: String) -> void:
	var old_model := player.get_node_or_null("AircraftModel")
	if old_model != null:
		player.remove_child(old_model)
		old_model.queue_free()
	var new_model := create_model(DEFAULT_ID)
	player.add_child(new_model)
	if player.has_method("update_aircraft_references"):
		player.update_aircraft_references()
