extends Node
## Destination equivalent of the source mission result flow, without its old maps/wave spawners.

@onready var player: PlayerFlight = get_node("../../Player")
@onready var hud: CombatHUD = get_parent()
var remaining := 0
var terminal := false


func _ready() -> void:
	GameSession.selected_map = hud.get_parent().scene_file_path
	GameSession.free_flight = GameSession.selected_map == GameSession.FREE_FLIGHT
	player.destroyed.connect(_on_player_destroyed)
	if not GameSession.free_flight:
		for target in get_tree().get_nodes_in_group("targets"):
			if target.has_signal("destroyed") and target.is_alive():
				remaining += 1
				target.destroyed.connect(_on_enemy_destroyed)


func objectives_text() -> String:
	return ">FREE FLIGHT" if GameSession.free_flight else ">HOSTILES REMAINING: %d" % remaining


func _on_player_destroyed(_aircraft: Node3D) -> void:
	_finish("MISSIONE FALLITA", "IL TUO AEREO È STATO DISTRUTTO")


func _on_enemy_destroyed(_aircraft: Node3D) -> void:
	remaining = maxi(remaining - 1, 0)
	if remaining == 0:
		_finish("MISSIONE COMPLETATA", "TUTTI I NEMICI ABBATTUTI")


func _finish(title: String, detail: String) -> void:
	if terminal:
		return
	terminal = true
	hud.show_mission_result(title, detail)
	get_tree().paused = true
