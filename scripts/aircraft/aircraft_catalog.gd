extends RefCounted
## Add one definition here to expose another airframe in selection, preview and flight.
## Transforms and exhaust sockets use the player's unscaled local space (-Z forward).

const EXHAUST := preload("res://scenes/vfx/jet_exhaust.tscn")

const DEFAULT_ID := "finished"
const DEFS := {
	"finished": {
		"label": "CACCIA · BROWN CAMO",
		"description": "Il caccia del player, con livrea Brown Camo e motore singolo.",
		"scene": preload("res://scenes/enemies/finished_aircraft.tscn"),
		"transform": Transform3D(Vector3(-24, 0, 0), Vector3(0, 24, 0), Vector3(0, 0, -24), Vector3(0, -5.8, 1.2)),
		"engines": [Vector3(0.0019104928, -0.68315357, 4.90668674)],
	},
	"fighter": {
		"label": "CACCIA · TWIN ENGINE",
		"description": "Il caccia bimotore già utilizzato dagli altri velivoli in missione.",
		"scene": preload("res://assets/aircraft/aircraft_game_ready.glb"),
		"transform": Transform3D(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0, -1.375, 1.88)),
		"engines": [Vector3(-0.96, -0.46, 5.5), Vector3(1.103, -0.46, 5.5)],
	},
	"fa_n26": {
		"label": "F/A-26",
		"description": "Caccia bimotore F/A-26, con livrea Camo 4.",
		"scene": preload("res://scenes/aircraft/fa_n26.tscn"),
		"transform": Transform3D(Vector3(0.5, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 0, 0.5), Vector3(0, -1.2, 0.56)),
		"engines": [Vector3(-0.44074288, -0.70743297, 4.58779818), Vector3(0.44106686, -0.70743297, 4.58779818)],
	},
}


static func ids() -> Array:
	return DEFS.keys()


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[DEFAULT_ID])


static func create_model(id: String) -> Node3D:
	var definition := get_def(id)
	var model := (definition.scene as PackedScene).instantiate() as Node3D
	model.name = "AircraftModel"
	model.transform = definition.transform
	return model


static func apply_to_player(player: Node3D, id: String) -> void:
	var old_model := player.get_node("AircraftModel")
	player.remove_child(old_model)
	old_model.queue_free()
	player.add_child(create_model(id))
	var afterburners := player.get_node("Afterburners") as Node3D
	for child in afterburners.get_children():
		afterburners.remove_child(child)
		child.queue_free()
	afterburners.position = Vector3.ZERO
	for position: Vector3 in get_def(id).engines:
		var exhaust := EXHAUST.instantiate() as Node3D
		exhaust.position = position
		afterburners.add_child(exhaust)
