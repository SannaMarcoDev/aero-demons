extends CanvasLayer
class_name CombatHUD

const OptionsPanel = preload("res://scripts/ui/options_panel.gd")

const TAPE_Y := 286.0
const TAPE_HALF_WIDTH := 290.0
const TAPE_PIXELS_PER_DEGREE := 4.0
const RADAR_SIZE := Vector2(300.0, 300.0)
const RADAR_MARGIN := Vector2(44.0, 24.0)
const RADAR_RANGE := 20000.0
const MARKER_RANGE := 40000.0
## Half span of the aircraft times the vertical focal length in pixels, so the hexagon wraps the
## airframe up close and settles to a fixed pip once it stops being readable.
const MARKER_PIXEL_METRES := 4900.0
const MARKER_RADIUS_MIN := 13.0
const MARKER_RADIUS_MAX := 40.0
## Band inside the border of the frame over which a marker fades. A marker whose centre crosses
## the border would appear and vanish on a single pixel of aircraft movement.
const MARKER_EDGE_FADE := 80.0
## The reticle turns red on the real lock gate, and only drops back to green once the target is
## clearly outside a widened copy of it and has stayed there this long. A target riding the cone
## or range border crosses the real gate several times a second, and a reticle following that
## literally strobes.
const ENGAGED_HOLD_MS := 400.0
const ENGAGED_RELEASE_MARGIN := 1.2
## How long the marker takes to slide to a newly cycled target.
const SWITCH_DURATION_MS := 300.0
const WHITE := Color(0.95, 0.98, 1.0, 0.96)
const SHADOW := Color(0.01, 0.03, 0.06, 0.82)
const GREEN := Color(0.32, 1.0, 0.08, 0.95)
const GREEN_DIM := Color(0.25, 0.8, 0.28, 0.8)
const RED_ORANGE := Color(1.0, 0.28, 0.12, 0.95)
const ALLY_BLUE := Color(0.25, 0.75, 1.0, 0.95)
const RADAR_LINE := Color(0.68, 0.84, 0.9, 0.43)

@export var player_path: NodePath = NodePath("")
@export var camera_path: NodePath = NodePath("")
@export var targeting_path: NodePath = NodePath("")
@export var weapons_path: NodePath = NodePath("")
@export var wave_spawner_path: NodePath = NodePath("")
@export var mission_controller_path: NodePath = NodePath("")
@export var mode_label := "DOGFIGHT"

var player
var camera
var targeting
var weapons
var wave_spawner
var mission_controller
var _font: Font
var _canvas: Control
var _target
var _target_switch_start := -1.0
var _target_switch_from := Vector2.ZERO
var _engaged_until := -1.0
var _engaged := false
var _locked_missile_targets: Array = []
var _missile_lock_limit := 1
var _hit_remaining := 0.0

@onready var _objectives_line: Label = $HudText/ObjectivesLine
@onready var _score_label: Label = $HudText/Score
@onready var _speed_value: Label = $HudText/SpeedValue
@onready var _altitude_value: Label = $HudText/AltitudeValue
@onready var _radar_label: Label = $HudText/RadarLabel
@onready var _gun_label: Label = $HudText/GunLabel
@onready var _missile_title: Label = $HudText/MissileTitle
@onready var _missile_label: Label = $HudText/MissileLabel
@onready var _secondary_missile_label: Label = $HudText.get_node_or_null("SecondaryMissileLabel")
@onready var _hull_value: Label = $HudText/HullValue
@onready var _mission_overlay: Control = $HudText/MissionOverlay
@onready var _mission_title: Label = $HudText/MissionOverlay/Title
@onready var _mission_detail: Label = $HudText/MissionOverlay/Detail
@onready var _pause_overlay: Control = $HudText/PauseOverlay
@onready var _pause_panel: PanelContainer = $HudText/PauseOverlay/Panel
@onready var _resume_button: Button = $HudText/PauseOverlay/Panel/Menu/ResumeButton
@onready var _restart_button: Button = $HudText/PauseOverlay/Panel/Menu/RestartButton
@onready var _options_button: Button = $HudText/PauseOverlay/Panel/Menu/OptionsButton
@onready var _pause_options: PanelContainer = $HudText/PauseOverlay/PauseOptions
@onready var _options_panel: OptionsPanel = $HudText/PauseOverlay/PauseOptions/Menu/OptionsPanel
var _pause_menu_was_paused := false
var _flight_mouse_mode := Input.MOUSE_MODE_VISIBLE


class HudCanvas extends Control:
	var hud

	func _draw() -> void:
		if hud != null and is_instance_valid(hud):
			hud._draw_hud(self)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_sources()
	if is_instance_valid(weapons):
		weapons.hit_confirmed.connect(_on_hit_confirmed)
	if targeting != null and is_instance_valid(targeting) and targeting.has_signal("target_changed"):
		targeting.target_changed.connect(_on_target_changed)
	_font = load("res://assets/fonts/Michroma-Regular.ttf")
	_canvas = HudCanvas.new()
	_canvas.name = "HudCanvas"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.hud = self
	$HudText.add_child(_canvas)
	$HudText.move_child(_canvas, 0)
	$HudText.move_child(_mission_overlay, $HudText.get_child_count() - 1)
	$HudText.move_child(_pause_overlay, $HudText.get_child_count() - 1)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_update_labels()


func _on_hit_confirmed() -> void:
	_hit_remaining = 0.25


func _process(delta: float) -> void:
	if not get_tree().paused:
		_hit_remaining = maxf(_hit_remaining - delta, 0.0)
	_update_labels()
	if is_instance_valid(_canvas):
		_canvas.queue_redraw()


func show_mission_result(title: String, detail: String) -> void:
	_mission_title.text = title
	_mission_detail.text = "%s\n[R] RIPROVA  ·  [ESC / START] MENU" % detail
	_mission_overlay.visible = true


func _open_pause_menu() -> void:
	if _pause_overlay.visible:
		return
	_pause_menu_was_paused = get_tree().paused
	_flight_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause_panel.visible = true
	_pause_options.visible = false
	_pause_overlay.visible = true
	get_tree().paused = true
	_resume_button.disabled = mission_result_visible()
	if _resume_button.disabled:
		_restart_button.grab_focus()
	else:
		_resume_button.grab_focus()


func _close_pause_menu() -> void:
	if _pause_options.visible:
		_options_panel.save()
		_pause_options.visible = false
		_pause_panel.visible = true
	_pause_overlay.visible = false
	get_tree().paused = _pause_menu_was_paused
	Input.mouse_mode = _flight_mouse_mode


func _on_resume_pressed() -> void:
	_close_pause_menu()


func _on_options_pressed() -> void:
	_pause_panel.visible = false
	_pause_options.visible = true
	_options_panel.grab_first_focus()


func _on_options_back_pressed() -> void:
	_options_panel.save()
	_pause_options.visible = false
	_pause_panel.visible = true
	_options_button.grab_focus()


func _on_restart_pressed() -> void:
	GameSession.change_scene(get_tree(), get_parent().scene_file_path)


func _on_loadout_pressed() -> void:
	GameSession.change_scene(get_tree(), GameSession.LOADOUT)


func _on_main_menu_pressed() -> void:
	GameSession.menu_section = ""
	GameSession.change_scene(get_tree(), GameSession.MAIN_MENU)


func _on_quit_pressed() -> void:
	_pause_overlay.visible = false
	get_tree().paused = false
	get_tree().quit()


func hide_mission_result() -> void:
	_mission_overlay.visible = false


func mission_result_visible() -> bool:
	return _mission_overlay.visible


func _resolve_sources() -> void:
	player = _node_from_path(player_path)
	camera = _node_from_path(camera_path)
	targeting = _node_from_path(targeting_path)
	weapons = _node_from_path(weapons_path)
	wave_spawner = _node_from_path(wave_spawner_path)
	mission_controller = _node_from_path(mission_controller_path)


func _node_from_path(path: NodePath):
	if path.is_empty():
		return null
	return get_node_or_null(path)


func _update_labels() -> void:
	_objectives_line.text = _objectives_text()
	if GameSession.free_flight:
		_score_label.text = "MODE : FREE FLIGHT"
	elif wave_spawner == null:
		_score_label.text = "MODE : " + mode_label
	else:
		_score_label.text = "TOTAL SCORE : %s" % _format_int(_read_int(wave_spawner, "score", 0))
	_speed_value.text = "%d" % roundi(_read_float(player, "speed", 0.0) * 3.6)
	_altitude_value.text = "%d" % roundi(_player_altitude())
	_radar_label.text = "RDR RANGE  %.1f KM" % (RADAR_RANGE / 1000.0)
	_gun_label.text = "GUN - %s" % _format_int(_read_int(weapons, "gun_ammo", 0))
	var active_label: String = "MSL"
	if weapons != null and is_instance_valid(weapons) and weapons.has_method("get_equipped_label"):
		active_label = "MSL · %s" % weapons.call("get_equipped_label")
	if _missile_title != null:
		_missile_title.text = active_label
	_missile_label.text = "%d" % _read_int(weapons, "missile_ammo", 0)
	if _secondary_missile_label != null:
		if weapons != null and is_instance_valid(weapons) and weapons.has_method("get_secondary_missile_id") and weapons.has_method("get_secondary_ammo"):
			var sec_id: String = str(weapons.call("get_secondary_missile_id"))
			if not sec_id.is_empty():
				var sec_ammo: int = int(weapons.call("get_secondary_ammo"))
				_secondary_missile_label.text = "[%s  %d]" % [sec_id, sec_ammo]
				_secondary_missile_label.visible = true
			else:
				_secondary_missile_label.visible = false
		else:
			_secondary_missile_label.visible = false
	var health_max := maxf(_read_float(player, "max_health", 100.0), 0.001)
	_hull_value.text = "%d" % roundi(clampf(_read_float(player, "health", health_max) / health_max, 0.0, 1.0) * 100.0)
	_target = _current_target()
	_refresh_missile_locks()
	_update_engaged()


func _draw_hud(canvas: Control) -> void:
	_draw_missile_alert(canvas)
	_draw_heading_tape(canvas)
	_draw_pipper(canvas)
	_draw_multi_lock_status(canvas)
	_draw_high_g(canvas)
	_draw_spin_dash(canvas)
	_draw_enemy_markers(canvas)
	_draw_target(canvas)
	_draw_radar(canvas)
	_draw_hull(canvas)
	_draw_boundary_warning(canvas)
	if _hit_remaining > 0.0 and _font != null:
		var text_size := _font.get_string_size("HIT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24)
		var position := canvas.size * 0.5 + Vector2(-text_size.x * 0.5, _font.get_ascent(24) - text_size.y * 0.5)
		_draw_text(canvas, position, "HIT", 24, WHITE)


func _draw_missile_alert(canvas: Control) -> void:
	if player == null or not is_instance_valid(player) or not player.has_method("active_missiles"):
		return
	var incoming: Array = player.call("active_missiles")
	if incoming.is_empty():
		return
	if fmod(Time.get_ticks_msec() / 1000.0, 0.6) > 0.36:
		return
	var center := canvas.size * 0.5
	_draw_text(canvas, Vector2(center.x - 96.0, center.y - 168.0), "MISSILE", 34, RED_ORANGE)


func _draw_heading_tape(canvas: Control) -> void:
	var heading := _heading_degrees()
	var tape_center := Vector2(canvas.size.x * 0.5, TAPE_Y)
	var tape_y := tape_center.y + 17.0
	canvas.draw_line(Vector2(tape_center.x - TAPE_HALF_WIDTH, tape_y), Vector2(tape_center.x + TAPE_HALF_WIDTH, tape_y), WHITE, 1.0, true)
	for marker in range(0, 360, 5):
		var offset := _angle_delta(float(marker), heading) * TAPE_PIXELS_PER_DEGREE
		if absf(offset) > TAPE_HALF_WIDTH + 6.0:
			continue
		var x := tape_center.x + offset
		var length := 8.0
		if marker % 90 == 0:
			length = 20.0
		elif marker % 10 == 0:
			length = 13.0
		canvas.draw_line(Vector2(x, tape_y - length * 0.5), Vector2(x, tape_y + length * 0.5), WHITE, 1.0, true)
		if marker % 90 == 0:
			_draw_text(canvas, Vector2(x - 8.0, tape_y - 17.0), _cardinal(marker), 19, WHITE)
	canvas.draw_line(Vector2(tape_center.x, tape_y - 27.0), Vector2(tape_center.x, tape_y + 3.0), WHITE, 1.0, true)
	_draw_text(canvas, Vector2(tape_center.x - 7.0, tape_y - 36.0), "V", 17, WHITE)
	var heading_box := Rect2(tape_center.x - 25.0, tape_y + 9.0, 50.0, 25.0)
	canvas.draw_rect(heading_box, WHITE, false, 1.0)
	_draw_text(canvas, Vector2(heading_box.position.x + 8.0, heading_box.position.y + 19.0), "%03d" % roundi(heading), 14, WHITE)


func _draw_pipper(canvas: Control) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(weapons):
		return
	var world_point: Vector3 = weapons.get_gun_boresight_point()
	var center: Vector2 = _gun_screen_point(canvas, world_point)
	var bounds := Rect2(Vector2.ONE * 22.0, canvas.size - Vector2.ONE * 44.0)
	if camera.is_position_behind(world_point) or not bounds.has_point(center):
		var local: Vector3 = camera.global_transform.affine_inverse() * world_point
		var edge_direction := Vector2(local.x, -local.y).normalized()
		if edge_direction.is_zero_approx():
			edge_direction = Vector2.DOWN
		var half_size := bounds.size * 0.5
		var reach := minf(half_size.x / maxf(absf(edge_direction.x), 0.0001),
			half_size.y / maxf(absf(edge_direction.y), 0.0001))
		var edge := canvas.size * 0.5 + edge_direction * reach
		var side := edge_direction.orthogonal() * 5.0
		canvas.draw_line(edge - edge_direction * 10.0 + side, edge, WHITE, 1.5, true)
		canvas.draw_line(edge - edge_direction * 10.0 - side, edge, WHITE, 1.5, true)
	else:
		_draw_gun_boresight(canvas, center)
	var solution: Dictionary = weapons.get_gun_solution(_current_target())
	if solution.is_empty():
		return
	# Both barrel references use the same depth, so aligned directions overlap exactly.
	var aim: Vector3 = weapons.get_gun_muzzle_position() + solution.direction * maxf(weapons.gun_solution_range, 1.0)
	if camera.is_position_behind(aim):
		return
	var lead := _gun_screen_point(canvas, aim)
	if bounds.has_point(lead):
		var distance: float = weapons.get_gun_muzzle_position().distance_to(_current_target().global_position)
		var color := GREEN if distance <= 700.0 else GREEN_DIM
		canvas.draw_arc(lead, WeaponController.GUN_LEAD_RADIUS, 0.0, TAU, 48, color, 1.5, true)
		canvas.draw_circle(lead, 2.0, color)
		if distance > 700.0:
			_draw_text(canvas, lead + Vector2(30.0, 5.0), "CLOSE IN · GUN 300–700 M", 12, color)


func _gun_screen_point(canvas: Control, point: Vector3) -> Vector2:
	return canvas.get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(point)


func _draw_gun_boresight(canvas: Control, center: Vector2) -> void:
	canvas.draw_circle(center, WeaponController.GUN_BORESIGHT_RADIUS, WHITE, false, 1.2, true)
	canvas.draw_line(center + Vector2(-15.0, 0.0), center + Vector2(-8.0, 0.0), WHITE, 1.0, true)
	canvas.draw_line(center + Vector2(8.0, 0.0), center + Vector2(15.0, 0.0), WHITE, 1.0, true)
	canvas.draw_line(center + Vector2(0.0, -15.0), center + Vector2(0.0, -8.0), WHITE, 1.0, true)
	canvas.draw_line(center + Vector2(0.0, 8.0), center + Vector2(0.0, 15.0), WHITE, 1.0, true)


## High-G hold under the pipper. No cooldown: the cost is speed bleed.
func _draw_high_g(canvas: Control) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not _read_bool(player, "high_g_active", false):
		return
	var text := "HIGH G"
	var width := 0.0
	if _font != null:
		width = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18).x
	var center := canvas.size * 0.5
	_draw_text(canvas, Vector2(center.x - width * 0.5, center.y + 78.0), text, 18, RED_ORANGE)


func _draw_spin_dash(canvas: Control) -> void:
	if player == null or not is_instance_valid(player):
		return
	var active := _read_bool(player, "spin_dash_active", false)
	var cooldown := 0.0
	if player.has_method("spin_dash_cooldown_ratio"):
		cooldown = float(player.call("spin_dash_cooldown_ratio"))
	if not active and cooldown <= 0.0:
		return
	var color := GREEN if active else GREEN_DIM
	var text := "SPIN DASH"
	var width := 0.0
	if _font != null:
		width = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18).x
	var center := canvas.size * 0.5
	_draw_text(canvas, Vector2(center.x - width * 0.5, center.y + 104.0), text, 18, color)
	var bar := Rect2(center.x - 60.0, center.y + 114.0, 120.0, 4.0)
	canvas.draw_rect(bar, _faded(color, 0.25), true)
	var fill := 1.0 if active else 1.0 - cooldown
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), color, true)


func _refresh_missile_locks() -> void:
	_locked_missile_targets.clear()
	_missile_lock_limit = 1
	if weapons == null or not is_instance_valid(weapons):
		return
	if weapons.has_method("get_equipped_def"):
		var def = weapons.call("get_equipped_def")
		if def is Dictionary:
			_missile_lock_limit = maxi(int(def.get("max_locks", 1)), 1)
	if _missile_lock_limit <= 1 or not weapons.has_method("get_locked_missile_targets"):
		return
	for candidate in weapons.call("get_locked_missile_targets"):
		if _target_alive(candidate):
			_locked_missile_targets.append(candidate)


## "Under fire": the selected target is a valid missile solution right now.
func _update_engaged() -> void:
	if weapons == null or not is_instance_valid(weapons):
		_engaged = false
		return
	if _missile_lock_limit > 1:
		_engaged = _locked_missile_targets.has(_target) \
				and weapons.has_method("can_fire_missile") and bool(weapons.call("can_fire_missile"))
		return
	if not _target_alive(_target):
		_engaged = false
		return
	if weapons.has_method("can_fire_missile") and bool(weapons.call("can_fire_missile")):
		_engaged = true
		_engaged_until = Time.get_ticks_msec() + ENGAGED_HOLD_MS
		return
	if _engaged and not _near_lock_zone() and Time.get_ticks_msec() >= _engaged_until:
		_engaged = false


func _draw_multi_lock_status(canvas: Control) -> void:
	if _missile_lock_limit <= 1:
		return
	var text := "LOCK %d/%d" % [_locked_missile_targets.size(), _missile_lock_limit]
	var size := 18
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x if _font != null else 0.0
	var center := canvas.size * 0.5
	var color := RED_ORANGE if not _locked_missile_targets.is_empty() else GREEN_DIM
	_draw_text(canvas, Vector2(center.x - width * 0.5, center.y + 58.0), text, size, color)


## The widened gate the reticle is released on, a fifth past the cone and the range the lock
## itself uses.
func _near_lock_zone() -> bool:
	if player == null or not is_instance_valid(player) or not _target_alive(_target):
		return false
	var offset: Vector3 = _target.global_position - player.global_position
	var distance := offset.length()
	if distance <= 0.001 or distance > _read_float(targeting, "lock_range", 4500.0) * ENGAGED_RELEASE_MARGIN:
		return false
	var cone := _read_float(targeting, "lock_cone_degrees", 25.0) * ENGAGED_RELEASE_MARGIN
	return (-player.global_basis.z).normalized().angle_to(offset / distance) <= deg_to_rad(cone)


## Every live target in range carries the same green hexagon, creatures and balloons alike, so
## anything hostile stays findable against Alpine terrain long before it is worth aiming at.
## The engaged one is left to _draw_target.
func _draw_enemy_markers(canvas: Control) -> void:
	if player == null or not is_instance_valid(player):
		return
	if camera == null or not is_instance_valid(camera) or not camera.has_method("unproject_position"):
		return
	var viewport_rect := canvas.get_viewport_rect()
	for node in get_tree().get_nodes_in_group("targets") + get_tree().get_nodes_in_group("allies"):
		if node == _target or not _target_alive(node):
			continue
		var distance: float = player.global_position.distance_to(node.global_position)
		if distance > MARKER_RANGE:
			continue
		if camera.is_position_behind(node.global_position):
			continue
		var screen_position: Vector2 = camera.unproject_position(node.global_position)
		var fade := _edge_fade(screen_position, viewport_rect)
		if fade <= 0.0:
			continue
		if node.is_in_group("allies"):
			var ally_color := _faded(ALLY_BLUE, fade)
			canvas.draw_rect(Rect2(screen_position - Vector2(9, 9), Vector2(18, 18)), ally_color, false, 2.0)
			_draw_text(canvas, screen_position + Vector2(14, 5), _target_label(node), 12, ally_color)
			continue
		var multi_locked := _locked_missile_targets.has(node)
		var color := RED_ORANGE if multi_locked else GREEN
		var radius := _marker_radius(distance)
		_draw_hexagon(canvas, screen_position, radius, _faded(color, fade), 3.0 if multi_locked else 2.0, 0.0)
		if multi_locked:
			_draw_lock_crosses(canvas, screen_position, radius, _faded(color, fade), 1.5)


func _draw_target(canvas: Control) -> void:
	if not _target_alive(_target):
		return
	var target_position: Vector3 = _target.global_position
	if camera == null or not is_instance_valid(camera) or not camera.has_method("unproject_position"):
		return
	var screen_position: Vector2 = camera.unproject_position(target_position)
	var behind: bool = camera.has_method("is_position_behind") and camera.is_position_behind(target_position)
	var viewport_rect := canvas.get_viewport_rect()
	var multi_locked := _locked_missile_targets.has(_target)
	var color := RED_ORANGE if _engaged or multi_locked else GREEN
	# Reticle and off-screen arrow cross-fade through the border band instead of swapping.
	var fade := 0.0 if behind else _edge_fade(screen_position, viewport_rect)
	if fade < 1.0:
		_draw_target_arrow(canvas, target_position, screen_position, behind, viewport_rect, _faded(color, 1.0 - fade))
	if fade <= 0.0:
		return
	var marker_position := screen_position
	var spin := 0.0
	if _target_switch_start >= 0.0:
		var switch_t := (Time.get_ticks_msec() - _target_switch_start) / SWITCH_DURATION_MS
		if switch_t >= 1.0:
			_target_switch_start = -1.0
		else:
			var eased := smoothstep(0.0, 1.0, switch_t)
			marker_position = _target_switch_from.lerp(screen_position, eased)
			# A sixth of a turn is one hexagon step, so the spin lands on the same silhouette.
			spin = PI / 3.0 * eased
	var distance := _target_distance(_target)
	var radius := _marker_radius(distance)
	var marker_color := _faded(color, fade)
	_draw_hexagon(canvas, marker_position, radius, marker_color, 3.0, spin)
	if _engaged or multi_locked:
		_draw_lock_crosses(canvas, marker_position, radius, marker_color, 2.0)
	_draw_text(canvas, marker_position + Vector2(-radius, radius + 28.0), "%s  %05.0f M" % [_target_label(_target), distance], 14, marker_color)


## Flat-topped hexagon: a vertex on each side, horizontal top and bottom edges. Closed by
## repeating the first point, so the outline has no gap at the seam.
func _draw_hexagon(canvas: Control, center: Vector2, radius: float, color: Color, width: float, spin: float) -> void:
	var points := PackedVector2Array()
	for i in 7:
		var angle := spin + float(i % 6) * PI / 3.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_polyline(points, color, width, true)


## The engaged reticle adds a cross off each side of the hexagon, clear of the outline so the
## two shapes stay readable when the marker shrinks to its floor size.
func _draw_lock_crosses(canvas: Control, center: Vector2, radius: float, color: Color, width: float) -> void:
	var arm := clampf(radius * 0.3, 5.0, 11.0)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		# The side vertices reach radius, the flat top and bottom edges only sin(60°) of it.
		var reach := radius if direction.x != 0.0 else radius * 0.866
		var point := center + direction * (reach + arm + 4.0)
		canvas.draw_line(point - Vector2(arm, 0.0), point + Vector2(arm, 0.0), color, width, true)
		canvas.draw_line(point - Vector2(0.0, arm), point + Vector2(0.0, arm), color, width, true)


func _marker_radius(distance: float) -> float:
	return clampf(MARKER_PIXEL_METRES / maxf(distance, 1.0), MARKER_RADIUS_MIN, MARKER_RADIUS_MAX)


## Alpha for a marker near the border of the frame; zero once it is off frame.
func _edge_fade(screen_position: Vector2, viewport_rect: Rect2) -> float:
	var inset := minf(
		minf(screen_position.x - viewport_rect.position.x, viewport_rect.end.x - screen_position.x),
		minf(screen_position.y - viewport_rect.position.y, viewport_rect.end.y - screen_position.y),
	)
	return clampf(inset / MARKER_EDGE_FADE, 0.0, 1.0)


func _faded(color: Color, fade: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(fade, 0.0, 1.0))


## A player-initiated target switch: the previous target was alive until this frame, so the
## marker slides from its old screen position instead of teleporting. Initial acquisition and
## switches after a kill skip the animation.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_run"):
		get_viewport().set_input_as_handled()
		_on_restart_pressed()
	elif event.is_action_pressed("pause_menu"):
		if _pause_options.visible:
			_on_options_back_pressed()
		elif _pause_overlay.visible:
			_close_pause_menu()
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _pause_options.visible:
			_on_options_back_pressed()
			get_viewport().set_input_as_handled()
		elif _pause_overlay.visible:
			_close_pause_menu()
			get_viewport().set_input_as_handled()

func _on_target_changed(_new_target: Node3D) -> void:
	if not _target_alive(_target):
		return
	if camera == null or not is_instance_valid(camera) or not camera.has_method("unproject_position"):
		return
	_target_switch_from = camera.unproject_position(_target.global_position)
	_target_switch_start = Time.get_ticks_msec()


func _draw_target_arrow(canvas: Control, target_position: Vector3, screen_position: Vector2, behind: bool, viewport_rect: Rect2, color: Color) -> void:
	var center := viewport_rect.get_center()
	var direction := screen_position - center
	if behind and camera != null and is_instance_valid(camera):
		var local_direction: Vector3 = camera.global_transform.basis.inverse() * (target_position - camera.global_position)
		direction = Vector2(local_direction.x, -local_direction.y)
	if direction.length_squared() < 0.001:
		direction = Vector2.UP
	direction = direction.normalized()
	var edge_radius := minf(viewport_rect.size.x, viewport_rect.size.y) * 0.5 - 45.0
	var position := center + direction * edge_radius
	position.x = clampf(position.x, 30.0, viewport_rect.size.x - 30.0)
	position.y = clampf(position.y, 30.0, viewport_rect.size.y - 30.0)
	var perpendicular := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([
		position + direction * 17.0,
		position - direction * 9.0 + perpendicular * 10.0,
		position - direction * 9.0 - perpendicular * 10.0,
	])
	canvas.draw_colored_polygon(points, color)
	_draw_text(canvas, position + perpendicular * 14.0, "%s %05.0f M" % [_target_label(_target), _target_distance(_target)], 12, color)


func _draw_radar(canvas: Control) -> void:
	var radar_rect := Rect2(
		Vector2(RADAR_MARGIN.x, canvas.size.y - RADAR_MARGIN.y - RADAR_SIZE.y),
		RADAR_SIZE,
	)
	var radar_center := radar_rect.position + radar_rect.size * 0.5
	var radar_radius := radar_rect.size.x * 0.5 - 10.0
	canvas.draw_rect(radar_rect, Color(0.01, 0.025, 0.05, 0.72), true)
	canvas.draw_rect(radar_rect, WHITE, false, 2.0)
	canvas.draw_line(Vector2(radar_rect.position.x, radar_rect.position.y + 19.0), Vector2(radar_rect.end.x, radar_rect.position.y + 19.0), WHITE, 1.0, true)
	for ring in [0.25, 0.5, 0.75, 1.0]:
		canvas.draw_arc(radar_center, radar_radius * ring, 0.0, TAU, 64, RADAR_LINE, 1.0, true)
	canvas.draw_line(radar_center + Vector2(-radar_radius, 0.0), radar_center + Vector2(radar_radius, 0.0), RADAR_LINE, 1.0, true)
	canvas.draw_line(radar_center + Vector2(0.0, -radar_radius), radar_center + Vector2(0.0, radar_radius), RADAR_LINE, 1.0, true)
	for node in get_tree().get_nodes_in_group("targets") + get_tree().get_nodes_in_group("allies"):
		if not _target_alive(node) or player == null or not is_instance_valid(player):
			continue
		var local_offset: Vector3 = player.global_transform.basis.inverse() * (node.global_position - player.global_position)
		var planar := Vector2(local_offset.x, local_offset.z)
		var distance := planar.length()
		if distance > RADAR_RANGE:
			continue
		var point := radar_center + planar / RADAR_RANGE * radar_radius
		var primary: bool = node == _target
		var multi_locked: bool = _locked_missile_targets.has(node)
		var highlighted: bool = primary or multi_locked
		var blip_color := ALLY_BLUE if node.is_in_group("allies") else Color(0.55, 1.0, 0.72, 0.9)
		if multi_locked:
			blip_color = RED_ORANGE
		elif primary:
			blip_color = RED_ORANGE if _engaged else GREEN
		canvas.draw_circle(point, 4.5 if highlighted else 3.5, blip_color, true)
		if highlighted:
			canvas.draw_arc(point, 8.0, 0.0, TAU, 16, blip_color, 1.5, true)
	var player_triangle := PackedVector2Array([
		radar_center + Vector2(0.0, -10.0),
		radar_center + Vector2(-7.0, 8.0),
		radar_center + Vector2(7.0, 8.0),
	])
	canvas.draw_colored_polygon(player_triangle, WHITE)


func _draw_hull(canvas: Control) -> void:
	var health_max := maxf(_read_float(player, "max_health", 100.0), 0.001)
	var health_ratio := clampf(_read_float(player, "health", health_max) / health_max, 0.0, 1.0)
	var bar := Rect2(canvas.size.x - 310.0, canvas.size.y - 33.0, 280.0, 13.0)
	canvas.draw_rect(bar, Color(0.03, 0.04, 0.05, 0.78), true)
	canvas.draw_rect(bar, WHITE, false, 1.5)
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * health_ratio, bar.size.y)), RED_ORANGE, true)


func _draw_boundary_warning(canvas: Control) -> void:
	var controller = _node_from_path("../GardaLake/TutorialBoundaryController")
	if controller == null:
		controller = _node_from_path("../TutorialBoundaryController")
	if controller == null or not controller.has_method("is_boundary_warning"):
		return
	if not bool(controller.call("is_boundary_warning")):
		return
	var text := "BOUNDARY · TURN BACK"
	var width := 0.0
	if _font != null:
		width = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26).x
	var center := canvas.size * 0.5
	_draw_text(canvas, Vector2(center.x - width * 0.5, 108.0), text, 26, RED_ORANGE)

func _draw_text(canvas: Control, position: Vector2, text: String, size: int, color: Color) -> void:
	if _font == null:
		return
	canvas.draw_string(_font, position + Vector2(2.0, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, _faded(SHADOW, color.a))
	canvas.draw_string(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


func _current_target():
	if targeting == null or not is_instance_valid(targeting):
		return null
	return targeting.get("target")


func _target_alive(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.has_method("is_alive"):
		return bool(node.call("is_alive"))
	return _read_float(node, "health", 1.0) > 0.0


func _target_label(node) -> String:
	if node != null and is_instance_valid(node) and node.has_method("target_label"):
		return str(node.call("target_label"))
	return "TARGET"


func _target_distance(node) -> float:
	if targeting != null and is_instance_valid(targeting) and targeting.has_method("distance_to_target"):
		return maxf(float(targeting.call("distance_to_target")), 0.0)
	if node != null and is_instance_valid(node) and player != null and is_instance_valid(player):
		return player.global_position.distance_to(node.global_position)
	return 0.0


func _objectives_text() -> String:
	if is_instance_valid(mission_controller) and mission_controller.has_method("objectives_text"):
		return mission_controller.objectives_text()
	if GameSession.free_flight:
		return ">FREE FLIGHT"
	if wave_spawner == null or not is_instance_valid(wave_spawner):
		return ">DESTROY CARCINOPTERAS"
	if bool(wave_spawner.get("cleared")):
		return ">ALL WAVES CLEARED"
	if wave_spawner.has_method("is_boss_fight") and bool(wave_spawner.call("is_boss_fight")):
		return ">BOSS - KENTRIPLOKAME  -  CARCINOPTERAS %d" % _read_int(wave_spawner, "remaining", 0)
	if mission_controller != null and is_instance_valid(mission_controller) \
			and mission_controller.has_method("is_timed_mission") \
			and bool(mission_controller.call("is_timed_mission")):
		if bool(mission_controller.call("is_boss_cinematic")):
			return ">BOSS INCOMING..."
		return ">BOSS IN %s  -  CARCINOPTERAS %d" % [
			_format_time(float(mission_controller.call("boss_countdown_seconds"))),
			_read_int(wave_spawner, "remaining", 0),
		]
	if float(wave_spawner.get("_boss_pending_timer")) > 0.0:
		return ">BOSS INCOMING..."
	return ">WAVE %d/%d  -  CARCINOPTERAS %d" % [
		mini(_read_int(wave_spawner, "wave_index", 0) + 1, wave_spawner.call("wave_count")),
		wave_spawner.call("wave_count"),
		_read_int(wave_spawner, "remaining", 0),
	]


func _player_altitude() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	return player.global_position.y


func _heading_degrees() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	var forward: Vector3 = -player.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)) + 360.0, 360.0)


func _angle_delta(marker: float, heading: float) -> float:
	return fposmod(marker - heading + 540.0, 360.0) - 180.0


func _cardinal(marker: int) -> String:
	match marker:
		0:
			return "N"
		90:
			return "E"
		180:
			return "S"
		270:
			return "W"
	return ""


func _read_float(source, property_name: String, fallback: float) -> float:
	if source == null or not is_instance_valid(source):
		return fallback
	var value = source.get(property_name)
	if value == null:
		return fallback
	return float(value)


func _read_int(source, property_name: String, fallback: int) -> int:
	return roundi(_read_float(source, property_name, float(fallback)))


func _read_bool(source, property_name: String, fallback: bool) -> bool:
	if source == null or not is_instance_valid(source):
		return fallback
	var value = source.get(property_name)
	if value == null:
		return fallback
	return bool(value)


func _format_time(seconds: float) -> String:
	var whole_seconds := ceili(maxf(seconds, 0.0))
	return "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]


func _format_int(value: int) -> String:
	var negative := value < 0
	var digits := str(abs(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.substr(digits.length() - 3, 3) + grouped
		digits = digits.substr(0, digits.length() - 3)
	grouped = digits + grouped
	return ("-" if negative else "") + grouped
