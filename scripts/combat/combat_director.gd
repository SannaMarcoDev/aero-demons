extends Node
class_name CombatDirector
## Arena-level assignments and fire permissions. Pilots still fly and fire through their own controllers.

enum Mode { NORMAL, RELIEF }

@export var player_path := NodePath("../Player")
## Scene-local rule: tutorial hostiles engage wingmen, never the player. Normal arenas opt in by default.
@export var allow_player_attacks := true
@export var assignment_interval := 0.5
@export var assignment_duration := 8.0
@export var duel_range := 3200.0
@export var max_player_attackers := 1
@export var max_player_missiles := 2
@export var permission_duration := 4.0
@export var sustained_pressure_duration := 7.0
@export var pressure_gap_duration := 1.5
@export var relief_duration := 3.0
@export var debug_visible := false

var mode := Mode.NORMAL
var player: Node3D
var duel_opponent: Node3D
var pilots: Array = []
var permissions: Dictionary = {}
var clock := 0.0
var pressure_time := 0.0
var relief_time := 0.0
var _quiet_time := 0.0
var _assignment_time := 0.0
var _debug_time := 0.0
var _debug_label: Label


func _ready() -> void:
	process_physics_priority = -10
	add_to_group("combat_director")
	player = get_node_or_null(player_path)
	_refresh_pilots()
	_assign_roles()
	var overlay := CanvasLayer.new()
	overlay.layer = 12
	add_child(overlay)
	_debug_label = Label.new()
	_debug_label.position = Vector2(24, 185)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug_label.add_theme_constant_override("outline_size", 5)
	overlay.add_child(_debug_label)
	_update_debug()


func _physics_process(delta: float) -> void:
	clock += delta
	_refresh_pilots()
	_prune_permissions()
	_update_pressure(delta)
	_assignment_time -= delta
	if _assignment_time <= 0.0:
		_assignment_time = assignment_interval
		_assign_roles()
	_debug_time -= delta
	if _debug_time <= 0.0:
		_debug_time = 0.2
		_update_debug()


static func alive(node) -> bool:
	return is_instance_valid(node) and node is Node3D and node.is_inside_tree() \
		and not node.is_queued_for_deletion() and node.has_method("is_alive") and node.is_alive()


func _refresh_pilots() -> void:
	pilots = get_tree().get_nodes_in_group("combat_ai").filter(alive)
	for pilot in pilots:
		pilot.director = self


func _prune_permissions() -> void:
	if not allow_player_attacks:
		permissions.clear()
		return
	for pilot in permissions.keys():
		if not alive(pilot) or clock >= float(permissions[pilot]) \
				or pilot.assignment_target != player or not alive(player):
			permissions.erase(pilot)


func release_attack(pilot: Node3D) -> void:
	permissions.erase(pilot)


func has_permission(pilot: Node3D) -> bool:
	_prune_permissions()
	return permissions.has(pilot)


func request_attack(pilot: Node3D) -> bool:
	if not alive(pilot) or not alive(pilot.assignment_target):
		return false
	if pilot.assignment_target != player:
		return true
	if not allow_player_attacks:
		return false
	if has_permission(pilot):
		return true
	if mode == Mode.RELIEF or permissions.size() >= max_player_attackers:
		return false
	permissions[pilot] = clock + permission_duration
	return true


func active_player_missiles() -> int:
	# Threat ownership belongs to the target, never the launcher: kills do not refund live missiles.
	return player.active_missiles().size() if alive(player) else 0


func missile_slot_available(count: int = 1) -> bool:
	return active_player_missiles() + count <= max_player_missiles


func _update_pressure(delta: float) -> void:
	if not allow_player_attacks or not alive(player):
		permissions.clear()
		pressure_time = 0.0
		mode = Mode.NORMAL
		return
	if mode == Mode.RELIEF:
		relief_time += delta
		if relief_time >= relief_duration:
			mode = Mode.NORMAL
			pressure_time = 0.0
			_quiet_time = 0.0
		return
	var pressured := active_player_missiles() > 0 or not permissions.is_empty()
	if not pressured:
		pressured = alive(most_dangerous_to(player))
	if pressured:
		pressure_time += delta
		_quiet_time = 0.0
	else:
		_quiet_time += delta
		if _quiet_time >= pressure_gap_duration:
			pressure_time = 0.0
	if pressure_time >= sustained_pressure_duration:
		mode = Mode.RELIEF
		relief_time = 0.0
		# Existing passes/missiles finish. Only new attack authorizations are deferred.


func most_dangerous_to(subject: Node3D) -> Node3D:
	if not alive(subject):
		return null
	var best: Node3D
	var best_score := 0.0
	for pilot in pilots:
		if pilot.faction_group == subject.faction_group or pilot.faction_group != "targets":
			continue
		var offset: Vector3 = subject.global_position - pilot.global_position
		var distance := offset.length()
		if distance < 1.0 or distance > 1800.0:
			continue
		var alignment: float = (-pilot.global_basis.z).dot(offset / distance)
		var behind: float = (-subject.global_basis.z).dot(-offset / distance)
		if alignment < 0.8 or behind > -0.2:
			continue
		var score := alignment * (1.0 - distance / 2000.0)
		if score > best_score:
			best_score = score
			best = pilot
	return best


func _assign_roles() -> void:
	if not allow_player_attacks or not alive(duel_opponent):
		duel_opponent = null
	for pilot in pilots:
		if not alive(pilot.assignment_target):
			pilot.assign(pilot.role, null)
	var enemies: Array = pilots.filter(func(p): return p.faction_group == "targets")
	var allies: Array = pilots.filter(func(p): return p.faction_group != "targets")
	if enemies.is_empty():
		duel_opponent = null
		for ally in allies:
			ally.assign("COVER" if ally.policy == 1 else "SUPPORT", null)
		return
	var selected: Node3D
	if allow_player_attacks and alive(player):
		var targeting = player.get_node_or_null("TargetLock")
		if targeting != null and alive(targeting.target) and enemies.has(targeting.target):
			var offset: Vector3 = targeting.target.global_position - player.global_position
			if offset.length() <= duel_range and (-player.global_basis.z).dot(offset.normalized()) > 0.3:
				selected = targeting.target
	if alive(selected):
		duel_opponent = selected
	elif not allow_player_attacks or not alive(player):
		duel_opponent = null
	elif not enemies.has(duel_opponent) or player.global_position.distance_to(duel_opponent.global_position) > duel_range * 1.5:
		duel_opponent = _nearest(enemies, player)

	var pressure: Node3D
	for enemy in enemies:
		if allow_player_attacks and enemy != duel_opponent and enemy.role == "PLAYER_PRESSURE" \
				and (enemy.assignment_age < assignment_duration or enemy.state == enemy.State.ATTACK):
			pressure = enemy
			break
	if pressure == null and allow_player_attacks and alive(player):
		var candidates: Array = enemies.filter(func(e): return e != duel_opponent)
		# Rotate only expired pressure roles, without breaking the player's ongoing duel.
		for enemy in candidates:
			if enemy.role != "PLAYER_PRESSURE":
				pressure = enemy
				break
		if pressure == null and not candidates.is_empty():
			pressure = candidates[0]

	var index := 0
	for enemy in enemies:
		if enemy == duel_opponent:
			enemy.assign("PLAYER_DUEL", player)
		elif enemy == pressure:
			enemy.assign("PLAYER_PRESSURE", player)
		elif not allies.is_empty():
			var opponent = enemy.assignment_target
			if not allies.has(opponent) or enemy.assignment_age >= assignment_duration:
				opponent = allies[index % allies.size()]
			enemy.assign("ENGAGE_WINGMAN" if index < allies.size() else "SUPPORT", opponent)
			index += 1
		else:
			enemy.assign("SUPPORT", player if allow_player_attacks and alive(player) else null)

	var danger := most_dangerous_to(player)
	var cover: Node3D
	for ally in allies:
		if ally.policy == 1:
			cover = ally
	var urgent: bool = alive(danger) and (not alive(cover) or cover.global_position.distance_to(player.global_position) > 2500.0 \
		or cover.state in [cover.State.DEFEND, cover.State.EVADE_MISSILE] or player.health < player.max_health * 0.35)
	var claimed: Array = []
	for ally in allies:
		var target: Node3D = ally.assignment_target
		if alive(danger) and (ally.policy == 1 or urgent):
			target = danger
		elif not enemies.has(target) or target == duel_opponent or claimed.has(target) or ally.assignment_age >= assignment_duration:
			var available: Array = enemies.filter(func(e): return e != duel_opponent and not claimed.has(e))
			var engaging: Array = available.filter(func(e): return e.assignment_target == ally)
			# Fight the opponent engaging this wing before chasing a distant pressure aircraft.
			if not engaging.is_empty():
				available = engaging
			# With one opponent, wingmen can still help and earn real kills.
			target = _nearest(available if not available.is_empty() else enemies, ally)
		ally.assign("COVER" if ally.policy == 1 or urgent else "SUPPORT", target)
		claimed.append(target)


func _nearest(candidates: Array, subject: Node3D) -> Node3D:
	var best: Node3D
	var distance := INF
	for candidate in candidates:
		var next: float = subject.global_position.distance_squared_to(candidate.global_position)
		if next < distance:
			distance = next
			best = candidate
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		debug_visible = not debug_visible
		_update_debug()
		get_viewport().set_input_as_handled()


func _update_debug() -> void:
	if _debug_label == null:
		return
	_debug_label.text = "F7 · Dogfight AI"
	if not debug_visible:
		return
	_debug_label.text += "\nPLAYER ATTACKS: %s" % ("ON" if allow_player_attacks else "OFF")
	_debug_label.text += "\nMODE: %s | PLAYER_ATTACKERS: %d / %d | ACTIVE_PLAYER_MISSILES: %d / %d\nPLAYER_DUEL_OPPONENT: %s" % [
		Mode.keys()[mode], permissions.size(), max_player_attackers, active_player_missiles(), max_player_missiles,
		duel_opponent.name if alive(duel_opponent) else "NONE"]
	for pilot in get_tree().get_nodes_in_group("combat_ai"):
		_debug_label.text += "\n" + pilot.debug_text()
