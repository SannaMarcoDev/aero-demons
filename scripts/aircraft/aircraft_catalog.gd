extends RefCounted
## Airframe assets. The internal build exposes only DEFAULT_ID to the player.
## Each aircraft scene contains its model, afterburners, and wing damage nodes.

const DEFAULT_ID := "fa_n26"
const DEFS := {
	"finished": {
		"label": "CACCIA · BROWN CAMO",
		"description": "Il caccia del player, con livrea Brown Camo e motore singolo.",
		"scene": preload("res://scenes/aircraft/finished_aircraft.tscn"),
		"transform": Transform3D.IDENTITY,
	},
	"fighter": {
		"label": "CACCIA · TWIN ENGINE",
		"description": "Il caccia bimotore già utilizzato dagli altri velivoli in missione.",
		"scene": preload("res://scenes/aircraft/fighter.tscn"),
		"transform": Transform3D.IDENTITY,
	},
	"fa_n26": {
		"label": "F/A-26",
		"description": "Caccia bimotore F/A-26, con livrea Camo 4.",
		"scene": preload("res://scenes/aircraft/fa_n26.tscn"),
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
	var id := DEFAULT_ID
	var old_model := player.get_node_or_null("AircraftModel")
	if old_model != null:
		player.remove_child(old_model)
		old_model.queue_free()
	var new_model := create_model(id)
	player.add_child(new_model)
	if player.has_method("update_aircraft_references"):
		player.update_aircraft_references()
