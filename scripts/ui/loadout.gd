extends CanvasLayer

const Catalog = preload("res://scripts/weapons/missile_catalog.gd")
const Session = preload("res://scripts/ui/game_session.gd")
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

@onready var aircraft_scroll: ScrollContainer = $Main/LeftPanel/VBox/AircraftScroll
@onready var aircraft_list: VBoxContainer = $Main/LeftPanel/VBox/AircraftScroll/AircraftList

var _aircraft_step := true
var _aircraft_buttons: Dictionary = {}
var _preview_aircraft_id := ""
var _group: ButtonGroup
var _active_slot := 0
var _selected_missiles: Array[String] = ["STDM", "HSSTDM"]
var _missile_buttons: Dictionary = {}
var _missile_button_list: Array[Button] = []
var _launching := false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_group = ButtonGroup.new()
	map_label.text = Session.level_name()
	if not AircraftCatalog.DEFS.has(Session.selected_aircraft_id):
		Session.selected_aircraft_id = AircraftCatalog.DEFAULT_ID
	_build_aircraft_list()
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

func _build_aircraft_list() -> void:
	var group := ButtonGroup.new()
	for id: String in AircraftCatalog.ids():
		var btn := Button.new()
		btn.text = AircraftCatalog.get_def(id).label
		btn.custom_minimum_size.y = 54
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.button_group = group
		btn.pressed.connect(_on_aircraft_pick.bind(id))
		btn.focus_entered.connect(_preview_aircraft.bind(id))
		btn.mouse_entered.connect(_preview_aircraft.bind(id))
		aircraft_list.add_child(btn)
		_aircraft_buttons[id] = btn

func _on_aircraft_pick(id: String) -> void:
	Session.selected_aircraft_id = id
	for key in _aircraft_buttons:
		_aircraft_buttons[key].button_pressed = key == id
	_preview_aircraft(id)

func _show_aircraft_model(id: String) -> void:
	if _preview_aircraft_id != id:
		for child in preview_root.get_children():
			preview_root.remove_child(child)
			child.queue_free()
		preview_root.add_child(AircraftCatalog.create_model(id))
		preview_root.rotation.y = PI
		_preview_aircraft_id = id
	$Main/RightPanel/VBox/RightTitle.text = AircraftCatalog.get_def(id).label

func _preview_aircraft(id: String) -> void:
	if not _aircraft_step:
		return
	_show_aircraft_model(id)
	var definition := AircraftCatalog.get_def(id)
	var status := "SELEZIONATO" if id == Session.selected_aircraft_id else "A / INVIO / CLIC: seleziona"
	detail_label.text = "[%s]\n%s\n\n%s\n\nPrestazioni di volo condivise · Due slot missili configurabili al passo successivo." % [
		status, definition.label, definition.description,
	]

func _set_aircraft_step(enabled: bool) -> void:
	_aircraft_step = enabled
	aircraft_scroll.visible = enabled
	$Main/LeftPanel/VBox/SlotRow.visible = not enabled
	missile_list.visible = not enabled
	$Main/LeftPanel/VBox/StatsBox.visible = not enabled
	$Main/LeftPanel/VBox/Title.text = "1 / 2 · SCEGLI AEREO" if enabled else "2 / 2 · ARMAMENTO"
	$Main/LeftPanel/VBox/Info.text = "Seleziona il velivolo, poi configura le armi" if enabled else "Scegli due tipi di missile prima del decollo"
	avvia_btn.text = "CONTINUA · ARMAMENTO" if enabled else ("DECOLLA" if Session.free_flight else "AVVIA MISSIONE")
	back_btn.text = "INDIETRO" if enabled else "CAMBIA AEREO"
	if enabled:
		_on_aircraft_pick(Session.selected_aircraft_id)
		var buttons := aircraft_list.get_children()
		for i in buttons.size():
			var btn := buttons[i] as Button
			btn.focus_neighbor_top = back_btn.get_path() if i == 0 else buttons[i - 1].get_path()
			btn.focus_neighbor_bottom = avvia_btn.get_path() if i == buttons.size() - 1 else buttons[i + 1].get_path()
			btn.focus_neighbor_left = btn.get_path()
			btn.focus_neighbor_right = btn.get_path()
		avvia_btn.focus_neighbor_top = buttons.back().get_path()
		avvia_btn.focus_neighbor_bottom = back_btn.get_path()
		back_btn.focus_neighbor_top = avvia_btn.get_path()
		back_btn.focus_neighbor_bottom = buttons.front().get_path()
		for btn: Button in [avvia_btn, back_btn]:
			btn.focus_neighbor_left = btn.get_path()
			btn.focus_neighbor_right = btn.get_path()
		_aircraft_buttons[Session.selected_aircraft_id].grab_focus()
	else:
		_show_aircraft_model(Session.selected_aircraft_id)
		_setup_focus_navigation()
		_select_slot(_active_slot)
		slot1_btn.grab_focus()

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
	var status_text := " [EQUIPAGGIATO]" if is_equipped else " [A / INVIO / CLIC: equipaggia]"
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
	preview_root.rotate_y(delta * 0.35)

func _on_avvia_pressed() -> void:
	if _launching:
		return
	if _aircraft_step:
		_set_aircraft_step(false)
		return
	_launching = true
	Session.selected_missiles = _selected_missiles.duplicate()
	avvia_btn.disabled = true
	back_btn.disabled = true
	avvia_btn.text = "CARICAMENTO…"
	# Let the loading feedback render before loading the terrain scene.
	await get_tree().process_frame
	await get_tree().process_frame
	if Session.change_scene(get_tree(), Session.selected_map) != OK:
		_launching = false
		avvia_btn.disabled = false
		back_btn.disabled = false
		avvia_btn.text = "RIPROVA"
		detail_label.text = "Impossibile caricare la missione. Torna al menu e riprova."

func _on_back_pressed() -> void:
	if _launching:
		return
	if not _aircraft_step:
		_set_aircraft_step(true)
	else:
		Session.change_scene(get_tree(), Session.MAIN_MENU)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
	elif get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
				or event.is_action_pressed("ui_accept"):
			if _aircraft_step:
				_aircraft_buttons[Session.selected_aircraft_id].grab_focus()
			else:
				slot1_btn.grab_focus()
