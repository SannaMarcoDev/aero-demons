extends CanvasLayer

const Catalog = preload("res://scripts/weapons/missile_catalog.gd")
const Session = preload("res://scripts/ui/game_session.gd")
const Bindings = preload("res://scripts/ui/controller_bindings.gd")
const AircraftCatalog = preload("res://scripts/aircraft/aircraft_catalog.gd")

@onready var slot1_btn: Button = $Main/LeftPanel/VBox/SlotRow/Slot1Button
@onready var slot2_btn: Button = $Main/LeftPanel/VBox/SlotRow/Slot2Button
@onready var missile_list: VBoxContainer = $Main/LeftPanel/VBox/MissileList
@onready var map_label: Label = $Main/LeftPanel/VBox/MapLabel
@onready var detail_label: Label = $Main/RightPanel/VBox/DetailLabel
@onready var preview_root: Node3D = $Main/RightPanel/VBox/SubViewportContainer/PreviewViewport/PreviewRoot
@onready var preview_camera: Camera3D = $Main/RightPanel/VBox/SubViewportContainer/PreviewViewport/PreviewCamera
@onready var avvia_btn: Button = $Main/LeftPanel/VBox/AvviaButton
@onready var back_btn: Button = $Main/LeftPanel/VBox/BackButton
@onready var _speed_bar: ProgressBar = $Main/LeftPanel/VBox/StatsBox/SpeedRow/SpeedBar
@onready var _tracking_bar: ProgressBar = $Main/LeftPanel/VBox/StatsBox/TrackingRow/TrackingBar
@onready var _damage_bar: ProgressBar = $Main/LeftPanel/VBox/StatsBox/DamageRow/DamageBar
@onready var _ammo_bar: ProgressBar = $Main/LeftPanel/VBox/StatsBox/AmmoRow/AmmoBar
@onready var _speed_value: Label = $Main/LeftPanel/VBox/StatsBox/SpeedRow/SpeedValue
@onready var _tracking_value: Label = $Main/LeftPanel/VBox/StatsBox/TrackingRow/TrackingValue
@onready var _damage_value: Label = $Main/LeftPanel/VBox/StatsBox/DamageRow/DamageValue
@onready var _ammo_value: Label = $Main/LeftPanel/VBox/StatsBox/AmmoRow/AmmoValue

@onready var aircraft_selection = $AircraftSelection

var _aircraft_step := true
var _preview_aircraft_id := ""
var _group: ButtonGroup
var _active_slot := 0
var _selected_missiles: Array[String] = ["STDM", "HSSTDM"]
var _missile_buttons: Dictionary = {}
var _missile_button_list: Array[Button] = []
var _launching := false
var _transitioning := true
@onready var hangar_camera = $HangarViewportContainer/SubViewport/MenuAircraftStage/Camera3D
@onready var hangar_lights: Node3D = $HangarViewportContainer/SubViewport/MenuAircraftStage/Lighting
@onready var hangar_environment: WorldEnvironment = $HangarViewportContainer/SubViewport/MenuAircraftStage/WorldEnvironment
@onready var loading_screen: ColorRect = $LoadingScreen

func _ready() -> void:
	hangar_camera.set_view(1.0)
	# The stage environment is shared; dim only this instance.
	hangar_environment.environment = hangar_environment.environment.duplicate()
	$Main.modulate.a = 0.0
	$Main.scale = Vector2(0.985, 0.985)
	$Background.modulate.a = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_group = ButtonGroup.new()
	map_label.text = Session.level_name()
	$Main/LeftPanel/VBox/Hint.text = Bindings.menu_hint()
	aircraft_selection.confirmed.connect(_on_aircraft_continue)
	aircraft_selection.back_requested.connect(_on_back_pressed)
	if Session.selected_missiles.size() >= 2:
		_selected_missiles = Session.selected_missiles.duplicate()
	else:
		_selected_missiles = [Session.selected_missile_id, "HSSTDM"]

	slot1_btn.pressed.connect(func(): _select_slot(0))
	slot2_btn.pressed.connect(func(): _select_slot(1))
	slot1_btn.focus_entered.connect(func(): _select_slot(0))
	slot2_btn.focus_entered.connect(func(): _select_slot(1))

	# Popola lista missili
	for id in Catalog.ids():
		var def := Catalog.get_def(id)
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = _group
		btn.text = "%s  ·  %d m/s  ·  %d°  ·  %d dmg%s" % [
			def["label"],
			int(def["speed"]),
			int(def["turn_deg"]),
			int(def["damage"]),
			" + burn" if float(def["burn_total"]) > 0.0 else ""
		]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size.y = 44
		btn.add_theme_font_size_override("font_size", 16)
		var bid: String = id
		btn.pressed.connect(func(): _on_pick(bid))
		btn.focus_entered.connect(func(): _preview_missile(bid))
		btn.mouse_entered.connect(func(): _preview_missile(bid))
		_missile_buttons[id] = btn
		_missile_button_list.append(btn)
		entry.add_child(btn)
		var sub := Label.new()
		sub.text = Catalog.full_name(id)
		sub.add_theme_font_size_override("font_size", 13)
		sub.add_theme_color_override("font_color", Color(0.58, 0.63, 0.73, 1))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.add_child(sub)
		missile_list.add_child(entry)

	_setup_stats()
	_select_slot(0)
	preview_camera.look_at(Vector3(0, -0.3, 0), Vector3.UP)
	_set_aircraft_step(true)
	await aircraft_selection.fade(true)
	_transitioning = false

func _show_aircraft_model(id: String) -> void:
	if _preview_aircraft_id != id:
		for child in preview_root.get_children():
			preview_root.remove_child(child)
			child.queue_free()
		preview_root.add_child(AircraftCatalog.create_model(id))
		preview_root.rotation.y = PI
		_preview_aircraft_id = id
	$Main/RightPanel/VBox/RightTitle.text = AircraftCatalog.get_def(id).label

func _set_aircraft_step(enabled: bool) -> void:
	_aircraft_step = enabled
	aircraft_selection.visible = enabled
	aircraft_selection.set_process(enabled)
	$Main.visible = not enabled
	$Background.visible = not enabled
	$HangarViewportContainer.visible = not enabled
	if enabled:
		aircraft_selection.restore_selection()
	else:
		$Main/LeftPanel/VBox/Title.text = "2 / 2 · ARMAMENTO"
		avvia_btn.text = "DECOLLA" if Session.free_flight else "AVVIA MISSIONE"
		back_btn.text = "VEDI AEREO"
		_show_aircraft_model(Session.selected_aircraft_id)
		_setup_focus_navigation()
		_select_slot(_active_slot)
		slot1_btn.grab_focus()

func _on_aircraft_continue() -> void:
	if _launching or _transitioning:
		return
	_transitioning = true
	await aircraft_selection.fade(false)
	_set_aircraft_step(false)
	$Main.modulate.a = 0.0
	await hangar_camera.fade_ui($Main, true, $Background).finished
	_transitioning = false

func _setup_focus_navigation() -> void:
	if _missile_button_list.is_empty():
		return

	var first_missile := _missile_button_list[0]
	var last_missile := _missile_button_list[_missile_button_list.size() - 1]

	# Slot Buttons Navigation
	slot1_btn.focus_neighbor_left = slot2_btn.get_path()
	slot1_btn.focus_neighbor_right = slot2_btn.get_path()
	slot1_btn.focus_neighbor_top = back_btn.get_path()
	slot1_btn.focus_neighbor_bottom = first_missile.get_path()

	slot2_btn.focus_neighbor_left = slot1_btn.get_path()
	slot2_btn.focus_neighbor_right = slot1_btn.get_path()
	slot2_btn.focus_neighbor_top = back_btn.get_path()
	slot2_btn.focus_neighbor_bottom = first_missile.get_path()

	# Missile list buttons navigation
	for i in range(_missile_button_list.size()):
		var btn := _missile_button_list[i]
		btn.focus_neighbor_left = slot1_btn.get_path()
		btn.focus_neighbor_right = slot2_btn.get_path()
		if i == 0:
			btn.focus_neighbor_top = slot1_btn.get_path()
		else:
			btn.focus_neighbor_top = _missile_button_list[i - 1].get_path()

		if i == _missile_button_list.size() - 1:
			btn.focus_neighbor_bottom = avvia_btn.get_path()
		else:
			btn.focus_neighbor_bottom = _missile_button_list[i + 1].get_path()

	# Action buttons navigation
	avvia_btn.focus_neighbor_top = last_missile.get_path()
	avvia_btn.focus_neighbor_bottom = back_btn.get_path()
	avvia_btn.focus_neighbor_left = avvia_btn.get_path()
	avvia_btn.focus_neighbor_right = avvia_btn.get_path()

	back_btn.focus_neighbor_top = avvia_btn.get_path()
	back_btn.focus_neighbor_bottom = slot1_btn.get_path()
	back_btn.focus_neighbor_left = back_btn.get_path()
	back_btn.focus_neighbor_right = back_btn.get_path()

func _select_slot(slot: int) -> void:
	_active_slot = slot
	slot1_btn.button_pressed = (_active_slot == 0)
	slot2_btn.button_pressed = (_active_slot == 1)
	_update_slots_ui()
	_update_detail()
	_update_stats()

func _on_pick(id: String) -> void:
	_selected_missiles[_active_slot] = id
	Session.selected_missiles = _selected_missiles.duplicate()
	Session.selected_missile_id = _selected_missiles[0]
	_update_slots_ui()
	_update_detail()
	_update_stats()

func _preview_missile(id: String) -> void:
	var def := Catalog.get_def(id)
	var burn: String = ""
	if float(def["burn_total"]) > 0.0:
		burn = " + %d burn in %.0fs" % [int(def["burn_total"]), float(def["burn_duration"])]
	var slot_title := "SLOT %d (%s)" % [_active_slot + 1, "PRIMARIO" if _active_slot == 0 else "SECONDARIO"]
	var is_equipped: bool = (_selected_missiles[_active_slot] == id)
	var status_text := " [EQUIPAGGIATO]" if is_equipped else " [%s: equipaggia]" % Bindings.action_label("ui_accept")
	detail_label.text = "[%s]%s\n%s — %s\nSpeed %d m/s  ·  Range %d m  ·  Turn %d°  ·  Danni %d%s\n%s" % [
		slot_title,
		status_text,
		def["label"],
		Catalog.full_name(id),
		int(def["speed"]),
		int(def.get("range", 5000.0)),
		int(def["turn_deg"]),
		int(def["damage"]),
		burn,
		Catalog.description(id)
	]
	_show_stats_for(id)

func _update_slots_ui() -> void:
	slot1_btn.text = "Slot 1: %s" % Catalog.label(_selected_missiles[0])
	slot2_btn.text = "Slot 2: %s" % Catalog.label(_selected_missiles[1])
	var current_id := _selected_missiles[_active_slot]
	for id in _missile_buttons:
		_missile_buttons[id].button_pressed = (id == current_id)

func _update_detail() -> void:
	var current_id := _selected_missiles[_active_slot]
	_preview_missile(current_id)

func _setup_stats() -> void:
	var speed_max := 0.0
	var turn_max := 0.0
	var damage_max := 0.0
	var ammo_max := 0.0
	for id in Catalog.ids():
		var def := Catalog.get_def(id)
		speed_max = maxf(speed_max, float(def["speed"]))
		turn_max = maxf(turn_max, float(def["turn_deg"]))
		damage_max = maxf(damage_max, float(def["damage"]) + float(def["burn_total"]))
		ammo_max = maxf(ammo_max, float(def["ammo"]))
	_speed_bar.max_value = speed_max
	_tracking_bar.max_value = maxf(turn_max, 60.0)
	_damage_bar.max_value = damage_max
	_ammo_bar.max_value = ammo_max

func _show_stats_for(id: String) -> void:
	var def := Catalog.get_def(id)
	var speed := float(def["speed"])
	var tracking := float(def["turn_deg"])
	var damage := float(def["damage"])
	var burn_total := float(def["burn_total"])
	var ammo := float(def["ammo"])
	_speed_bar.value = speed
	_tracking_bar.value = tracking
	_damage_bar.value = damage + burn_total
	_ammo_bar.value = ammo
	_speed_value.text = "%d" % int(speed)
	_tracking_value.text = "%d" % int(tracking)
	_ammo_value.text = "%d" % int(ammo)
	if burn_total > 0.0:
		_damage_value.text = "%d+%d" % [int(damage), int(burn_total)]
	else:
		_damage_value.text = "%d" % int(damage)

func _update_stats() -> void:
	var current_id := _selected_missiles[_active_slot]
	_show_stats_for(current_id)

func _process(delta: float) -> void:
	if $Main/RightPanel/VBox/SubViewportContainer.is_visible_in_tree():
		preview_root.rotate_y(delta * 0.35)

func _on_avvia_pressed() -> void:
	if _launching or _transitioning:
		return
	if _aircraft_step:
		_on_aircraft_continue()
		return
	_launching = true
	Session.selected_missiles = _selected_missiles.duplicate()
	avvia_btn.disabled = true
	back_btn.disabled = true
	if not Session.free_flight:
		await hangar_camera.fade_ui($Main, false, $Background).finished
		await _darken_hangar()
		loading_screen.modulate.a = 0.0
		loading_screen.show()
		await create_tween().tween_property(loading_screen, "modulate:a", 1.0, 0.25).finished
		# Present the fully black loading screen before the synchronous terrain load.
		await get_tree().process_frame
		await get_tree().process_frame
	if Session.change_scene(get_tree(), Session.selected_map) != OK:
		if not Session.free_flight:
			await create_tween().tween_property(loading_screen, "modulate:a", 0.0, 0.3).finished
			loading_screen.hide()
			for light: Light3D in hangar_lights.get_children():
				light.light_energy = light.get_meta("initial_energy")
			hangar_environment.environment.ambient_light_energy = 0.38
		avvia_btn.disabled = false
		back_btn.disabled = false
		avvia_btn.text = "RIPROVA"
		detail_label.text = "Impossibile caricare la missione. Torna al menu e riprova."
		if not Session.free_flight:
			await hangar_camera.fade_ui($Main, true, $Background).finished
		_launching = false
		avvia_btn.grab_focus()

func _darken_hangar() -> void:
	var viewport := hangar_camera.get_viewport() as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var environment := hangar_environment.environment
	create_tween().tween_property(environment, "ambient_light_energy", 0.0, 1.4)
	for light: Light3D in hangar_lights.get_children():
		light.set_meta("initial_energy", light.light_energy)
		await create_tween().tween_property(light, "light_energy", 0.0, 0.2).finished
	environment.ambient_light_energy = 0.0

func _on_back_pressed() -> void:
	if _launching or _transitioning:
		return
	_transitioning = true
	if not _aircraft_step:
		await hangar_camera.fade_ui($Main, false, $Background).finished
		_set_aircraft_step(true)
		await aircraft_selection.fade(true)
		_transitioning = false
	else:
		await aircraft_selection.fade(false)
		if Session.change_scene(get_tree(), Session.MAIN_MENU) != OK:
			aircraft_selection.restore_selection()
			aircraft_selection.get_node("Layout/Footer/Message").text = "Impossibile aprire il menu. Riprova."
			await aircraft_selection.fade(true)
			_transitioning = false

func _input(_event: InputEvent) -> void:
	if _transitioning or _launching:
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _transitioning or _launching:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
	elif get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
				or event.is_action_pressed("ui_accept"):
			if _aircraft_step:
				aircraft_selection.restore_selection()
			else:
				slot1_btn.grab_focus()
			get_viewport().set_input_as_handled()
