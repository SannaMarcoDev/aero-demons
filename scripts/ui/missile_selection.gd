extends Control

signal confirmed
signal back_requested

const Catalog = preload("res://scripts/weapons/missile_catalog.gd")
const Session = preload("res://scripts/core/game_session.gd")
const Bindings = preload("res://scripts/input/controller_bindings.gd")
const PhotoCard = preload("res://scenes/ui/menu_photo_card.tscn")
const PreviewScene = preload("res://scenes/ui/missile_preview.tscn")
const DESIGN_SIZE := Vector2(1920, 1080)
const STAT_NAMES := ["Speed", "Tracking", "Damage", "Ammo"]
const ACCENT := Color(0.73, 1.0, 0.25)

@onready var layout: Control = $Layout
@onready var cards_row: HBoxContainer = $Layout/Carousel/Margin/Cards
@onready var scroll: ScrollContainer = $Layout/Carousel
@onready var preview: SubViewport = $Layout/Studio/Viewport
@onready var accept_button: Button = $Layout/Footer/Accept
@onready var back_button: Button = $Layout/Footer/Back
@onready var slot_buttons: Array[Button] = [$Layout/Slots/Slot1, $Layout/Slots/Slot2]

var _ids: Array = Catalog.ids()
var _cards: Array[Button] = []
var _selected_missiles: Array[String] = ["STDM", "HSSTDM"]
var _active_slot := 0
var _preview_index := 0
var _using_mouse := false
var _clock := 0.0


func _ready() -> void:
	$Layout/Header/Mission.text = Session.level_name()
	$Layout/Footer/Hint.text = Bindings.menu_hint()
	for slot in 2:
		if slot < Session.selected_missiles.size() and Catalog.DEFS.has(Session.selected_missiles[slot]):
			_selected_missiles[slot] = Session.selected_missiles[slot]
		slot_buttons[slot].pressed.connect(_select_slot.bind(slot))
		slot_buttons[slot].focus_entered.connect(_select_slot.bind(slot))
	for s in STAT_NAMES.size():
		var maximum := 1.0
		for id: String in _ids:
			maximum = maxf(maximum, _values(id)[s])
		($Layout/Stats/Margin/Column/Rows.get_node(STAT_NAMES[s] + "/Bar") as ProgressBar).max_value = maximum
	_build_cards()
	accept_button.pressed.connect(func(): confirmed.emit())
	back_button.pressed.connect(func(): back_requested.emit())
	resized.connect(_fit_layout)
	_fit_layout()
	_select_slot(0)


func _values(id: String) -> Array[float]:
	var def := Catalog.get_def(id)
	return [float(def.speed), float(def.turn_deg), float(def.damage) + float(def.burn_total), float(def.ammo)]


func _set_model(viewport: SubViewport, id: String) -> void:
	var def := Catalog.get_def(id)
	# Placeholder geometry lives only in this preview scene, never in the weapon scene.
	var body := viewport.get_node("ModelRoot/Body") as MeshInstance3D
	(body.material_override as StandardMaterial3D).albedo_color = (def.color as Color).lerp(Color.WHITE, 0.45)
	body.scale = Vector3.ONE * float(def.get("scale", 1.0))
	(viewport.get_node("Camera") as Camera3D).look_at(Vector3.ZERO, Vector3.UP)


func _build_cards() -> void:
	for i in _ids.size():
		var id: String = _ids[i]
		var card := PhotoCard.instantiate() as Button
		card.name = id
		card.custom_minimum_size = Vector2(328, 174)
		card.set("title", Catalog.label(id))
		card.set("title_size", 35)
		cards_row.add_child(card)
		var thumbnail := PreviewScene.instantiate() as SubViewport
		thumbnail.size = Vector2i(656, 348)
		card.add_child(thumbnail)
		thumbnail.get_node("Floor").hide()
		(thumbnail.get_node("Camera") as Camera3D).fov = 34.0
		_set_model(thumbnail, id)
		thumbnail.render_target_update_mode = SubViewport.UPDATE_ONCE
		thumbnail.get_node("KeyLight").shadow_enabled = false
		card.set("photo", thumbnail.get_texture())
		var title := card.get_node("Title") as Label
		title.offset_left = 16
		title.offset_right = -16
		title.offset_top = -57
		title.offset_bottom = -12
		var badge := Label.new()
		badge.name = "Badge"
		badge.position = Vector2(16, 10)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 19)
		card.add_child(badge)
		card.focus_entered.connect(_preview.bind(i))
		card.mouse_entered.connect(_hover.bind(i))
		card.pressed.connect(_equip.bind(i))
		_cards.append(card)
	for i in _cards.size():
		var card := _cards[i]
		card.focus_neighbor_left = card.get_path_to(_cards[maxi(0, i - 1)])
		card.focus_neighbor_right = card.get_path_to(_cards[mini(_cards.size() - 1, i + 1)])
		card.focus_neighbor_top = card.get_path_to(slot_buttons[0])
		card.focus_neighbor_bottom = card.get_path_to(back_button)
		card.focus_next = card.get_path_to(_cards[i + 1] if i + 1 < _cards.size() else back_button)
		card.focus_previous = card.get_path_to(_cards[i - 1] if i > 0 else slot_buttons[1])
	for slot in 2:
		var button := slot_buttons[slot]
		button.focus_neighbor_left = button.get_path_to(slot_buttons[1 - slot])
		button.focus_neighbor_right = button.get_path_to(slot_buttons[1 - slot])
		button.focus_neighbor_top = NodePath(".")
		button.focus_next = button.get_path_to(slot_buttons[1] if slot == 0 else _cards[0])
		button.focus_previous = button.get_path_to(accept_button if slot == 0 else slot_buttons[0])
	accept_button.focus_next = accept_button.get_path_to(slot_buttons[0])


func _fit_layout() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	layout.scale = Vector2.ONE * factor
	layout.position = (size - DESIGN_SIZE * factor) * 0.5


func restore_selection() -> void:
	_using_mouse = false
	_select_slot(_active_slot)
	_cards[_preview_index].grab_focus()


func _select_slot(slot: int) -> void:
	_active_slot = slot
	for i in 2:
		slot_buttons[i].button_pressed = i == slot
		slot_buttons[i].modulate = ACCENT if i == slot else Color.WHITE
	_update_slots()
	_preview(_ids.find(_selected_missiles[slot]))


func _update_slots() -> void:
	for slot in 2:
		slot_buttons[slot].text = "%02d · %s  /  %s" % [
			slot + 1, "PRIMARIO" if slot == 0 else "SECONDARIO", Catalog.label(_selected_missiles[slot])
		]
	for i in _cards.size():
		var equipped: Array[String] = []
		for slot in 2:
			if _selected_missiles[slot] == _ids[i]:
				equipped.append("%02d" % (slot + 1))
		var badge := _cards[i].get_node("Badge") as Label
		badge.text = "DISPONIBILE" if equipped.is_empty() else "SLOT " + " + ".join(equipped)
		badge.modulate = Color.WHITE if equipped.is_empty() else ACCENT


func _hover(index: int) -> void:
	# Scroll/layout changes must not steal keyboard or gamepad focus.
	if _using_mouse:
		_cards[index].grab_focus()


func _preview(index: int) -> void:
	_preview_index = index
	var id: String = _ids[index]
	var def := Catalog.get_def(id)
	$Layout/Word.text = Catalog.label(id)
	$Layout/Stats/Margin/Column/Name.text = Catalog.full_name(id).to_upper()
	$Layout/Stats/Margin/Column/Status.text = (
		"EQUIPAGGIATO · SLOT %02d" if _selected_missiles[_active_slot] == id else "DISPONIBILE · SLOT %02d"
	) % (_active_slot + 1)
	$Layout/Stats/Margin/Column/Note.text = "PORTATA %.0f m\n%s" % [float(def.range), Catalog.description(id)]
	$Layout/Footer/Counter.text = "%02d / %02d" % [index + 1, _ids.size()]
	$Layout/Footer/Message.text = ""
	var values := _values(id)
	var labels := ["%.0f m/s" % values[0], "%.0f °/s" % values[1], "%.0f HP" % values[2], "%.0f" % values[3]]
	if float(def.burn_total) > 0.0:
		labels[2] = "%.0f + %.0f HP" % [float(def.damage), float(def.burn_total)]
	for s in STAT_NAMES.size():
		var row := $Layout/Stats/Margin/Column/Rows.get_node(STAT_NAMES[s])
		(row.get_node("Bar") as ProgressBar).value = values[s]
		(row.get_node("Header/Value") as Label).text = labels[s]
	for button: Button in slot_buttons:
		button.focus_neighbor_bottom = button.get_path_to(_cards[index])
	for button: Button in [back_button, accept_button]:
		button.focus_neighbor_top = button.get_path_to(_cards[index])
		button.focus_neighbor_bottom = button.get_path_to(_cards[index])
	_set_model(preview, id)


func _equip(index: int) -> void:
	if not is_visible_in_tree():
		return
	_cards[index].grab_focus()
	_selected_missiles[_active_slot] = _ids[index]
	Session.selected_missiles = _selected_missiles.duplicate()
	_update_slots()
	_preview(index)


func fade(show_ui: bool) -> Signal:
	if show_ui:
		layout.modulate.a = 0.0
	return create_tween().tween_property(layout, "modulate:a", 1.0 if show_ui else 0.0, 0.22).finished


func _process(delta: float) -> void:
	_clock += delta
	preview.get_node("ModelRoot").rotation.y = -0.25 + sin(_clock * 0.32) * 0.055


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_using_mouse = true
	elif (
		event is InputEventKey or event is InputEventJoypadButton
		or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.2)
	):
		_using_mouse = false
		$Layout/Footer/Hint.text = Bindings.menu_hint()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if get_viewport().gui_get_focus_owner() == null and (
		event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
		or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")
		or event.is_action_pressed("ui_accept")
	):
		_cards[_preview_index].grab_focus()
		get_viewport().set_input_as_handled()
