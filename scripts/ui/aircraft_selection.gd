extends Control

signal confirmed
signal back_requested

const Session = preload("res://scripts/core/game_session.gd")
const AircraftCatalog = preload("res://scripts/aircraft/aircraft_catalog.gd")
const Bindings = preload("res://scripts/input/controller_bindings.gd")
const PhotoCard = preload("res://scenes/ui/menu_photo_card.tscn")
const PlayerScene = preload("res://scenes/player/player.tscn")
const DESIGN_SIZE := Vector2(1920, 1080)
# Presentation only: these locked entries never enter AircraftCatalog or GameSession.
# ponytail: placeholder stats are UI-only; use catalog data when these aircraft become playable.
const AIRCRAFT := [
	{"name": "SAAB JA 37 · VIGGEN", "short": "VIGGEN", "photo": preload("res://assets/ui/aircraft_selection/viggen.jpg")},
	{"name": "F-16 · FIGHTING FALCON", "short": "F-16", "photo": preload("res://assets/ui/aircraft_selection/f16.jpg"), "stats": [1080.0, 28.0, 62.0, 85.0]},
	{"name": "F/A-18 · HORNET", "short": "F/A-18", "photo": preload("res://assets/ui/aircraft_selection/fa18.jpg"), "stats": [910.0, 25.0, 58.0, 110.0]},
	{"name": "F-22 · RAPTOR", "short": "F-22", "photo": preload("res://assets/ui/aircraft_selection/f22.jpg"), "stats": [1190.0, 34.0, 70.0, 95.0]},
	{"name": "SU-27 · FLANKER", "short": "SU-27", "photo": preload("res://assets/ui/aircraft_selection/su27.jpg"), "stats": [1130.0, 26.0, 66.0, 105.0]},
	{"name": "MIG-29 · FULCRUM", "short": "MIG-29", "photo": preload("res://assets/ui/aircraft_selection/mig29.jpg"), "stats": [1100.0, 30.0, 72.0, 80.0]},
	{"name": "MIRAGE 2000", "short": "MIRAGE 2000", "photo": preload("res://assets/ui/aircraft_selection/mirage2000.jpg"), "stats": [1060.0, 29.0, 64.0, 90.0]},
]
const STAT_NAMES := ["Speed", "Acceleration", "Handling", "Health"]
const STAT_FORMATS := ["%.0f km/h", "%.1f m/s²", "%.0f °/s", "%.0f HP"]

@onready var layout: Control = $Layout
@onready var cards_row: HBoxContainer = $Layout/Carousel/Margin/Cards
@onready var scroll: ScrollContainer = $Layout/Carousel
@onready var studio: SubViewportContainer = $Layout/Studio
@onready var photo: TextureRect = $Layout/Photo
@onready var model_root: Node3D = $Layout/Studio/Viewport/ModelRoot
@onready var accept_button: Button = $Layout/Footer/Accept
@onready var back_button: Button = $Layout/Footer/Back

var _cards: Array[Button] = []
var _stats: Array = []
var _preview_index := 0
var _using_mouse := false
var _clock := 0.0
var _notice_until := 0
var _preview_fade: Tween


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$Layout/Header/Mission.text = Session.level_name()
	$Layout/Footer/Hint.text = Bindings.menu_hint()
	# Instantiation reads the scene's actual overrides as well as script defaults;
	# without adding it to the tree, no flight, audio or weapon logic runs.
	var player := PlayerScene.instantiate()
	_stats.append([
		float(player.get("max_speed")) * 3.6,
		float(player.get("acceleration")),
		float(player.get("pitch_speed")),
		float(player.get("max_health")),
	])
	player.free()
	for i in range(1, AIRCRAFT.size()):
		_stats.append(AIRCRAFT[i].stats)
	for s in STAT_NAMES.size():
		var maximum := 1.0
		for values in _stats:
			maximum = maxf(maximum, float(values[s]))
		($Layout/Stats/Margin/Column/Rows.get_node(STAT_NAMES[s] + "/Bar") as ProgressBar).max_value = maximum

	var model := AircraftCatalog.create_model(AircraftCatalog.DEFAULT_ID)
	model.get_node("Afterburners").hide()
	model_root.add_child(model)
	$Layout/Studio/Viewport/Camera.look_at(Vector3(0, -0.8, 0.4), Vector3.UP)
	_build_cards()
	accept_button.pressed.connect(_accept)
	back_button.pressed.connect(func(): back_requested.emit())
	resized.connect(_fit_layout)
	_fit_layout()
	restore_selection()


func _build_cards() -> void:
	for i in AIRCRAFT.size():
		var card := PhotoCard.instantiate() as Button
		card.name = "Aircraft%d" % i
		card.custom_minimum_size = Vector2(276, 174)
		card.set("title", AIRCRAFT[i].short)
		card.set("title_size", 35)
		card.set("photo", AIRCRAFT[i].photo)
		cards_row.add_child(card)
		var title := card.get_node("Title") as Label
		title.offset_left = 16
		title.offset_right = -16
		title.offset_top = -57
		title.offset_bottom = -12
		var badge := Label.new()
		badge.text = "SELEZIONATO" if i == 0 else "LOCKED"
		badge.position = Vector2(16, 10)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size", 19)
		badge.add_theme_color_override("font_color", Color(0.73, 1.0, 0.25) if i == 0 else Color.WHITE)
		badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("shadow_offset_y", 2)
		card.add_child(badge)
		card.focus_entered.connect(_preview.bind(i))
		card.mouse_entered.connect(_hover.bind(i))
		card.pressed.connect(_accept.bind(i))
		_cards.append(card)
	for i in _cards.size():
		var card := _cards[i]
		card.focus_neighbor_left = card.get_path_to(_cards[maxi(0, i - 1)])
		card.focus_neighbor_right = card.get_path_to(_cards[mini(_cards.size() - 1, i + 1)])
		card.focus_neighbor_top = NodePath(".")
		card.focus_neighbor_bottom = card.get_path_to(back_button)
		card.focus_next = card.get_path_to(_cards[i + 1] if i + 1 < _cards.size() else back_button)
		card.focus_previous = card.get_path_to(_cards[i - 1] if i > 0 else accept_button)


func _fit_layout() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	layout.scale = Vector2.ONE * factor
	layout.position = (size - DESIGN_SIZE * factor) * 0.5


func restore_selection() -> void:
	_using_mouse = false
	_preview(0)
	_cards[0].grab_focus()
	scroll.scroll_horizontal = 0


func _hover(index: int) -> void:
	# Layout/scroll changes must not steal focus from keyboard or controller.
	if _using_mouse:
		_cards[index].grab_focus()


func _preview(index: int) -> void:
	_preview_index = index
	$Layout/Footer/Message.text = ""
	_notice_until = 0
	var available := index == 0
	studio.visible = available
	photo.visible = not available
	photo.texture = AIRCRAFT[index].photo
	$Layout/Word.text = AIRCRAFT[index].short if available else "LOCKED"
	$Layout/LockedBands.visible = not available
	$Layout/Stats/Margin/Column/Name.text = AIRCRAFT[index].name.replace(" · ", "\n")
	$Layout/Stats/Margin/Column/Status.text = "DISPONIBILE" if available else "NON ANCORA DISPONIBILE"
	$Layout/Stats/Margin/Column/Status.modulate = Color(0.73, 1.0, 0.25) if available else Color(0.85, 0.88, 0.92)
	$Layout/Stats/Margin/Column/Note.text = "DATI DI GIOCO · VOLO STANDARD\nManovrabilità: beccheggio" if available else "VALORI PROVVISORI\nAereo non giocabile in questa build"
	$Layout/Footer/Counter.text = "%02d / %02d" % [index + 1, AIRCRAFT.size()]
	accept_button.text = "CONTINUA → ARMAMENTO" if available else "NON DISPONIBILE"
	for button: Button in [back_button, accept_button]:
		button.focus_neighbor_top = button.get_path_to(_cards[index])
		button.focus_neighbor_bottom = button.get_path_to(_cards[index])
	for s in STAT_NAMES.size():
		var row := $Layout/Stats/Margin/Column/Rows.get_node(STAT_NAMES[s])
		(row.get_node("Bar") as ProgressBar).value = float(_stats[index][s])
		(row.get_node("Header/Value") as Label).text = STAT_FORMATS[s] % float(_stats[index][s])
	if _preview_fade != null:
		_preview_fade.kill()
	var preview: CanvasItem = studio if available else photo
	preview.modulate.a = 0.0
	_preview_fade = create_tween()
	_preview_fade.tween_property(preview, "modulate:a", 1.0, 0.2)


func _accept(index: int = -1) -> void:
	if not is_visible_in_tree():
		return
	if index >= 0:
		_cards[index].grab_focus()
	if _preview_index != 0:
		$Layout/Footer/Message.text = "NON ANCORA DISPONIBILE"
		_notice_until = Time.get_ticks_msec() + 2200
		return
	Session.selected_aircraft_id = AircraftCatalog.DEFAULT_ID
	confirmed.emit()


func fade(show_ui: bool) -> Signal:
	if show_ui:
		layout.modulate.a = 0.0
	return create_tween().tween_property(layout, "modulate:a", 1.0 if show_ui else 0.0, 0.22).finished


func _process(delta: float) -> void:
	_clock += delta
	model_root.rotation.y = sin(_clock * 0.32) * 0.055
	if _notice_until != 0 and Time.get_ticks_msec() >= _notice_until:
		$Layout/Footer/Message.text = ""
		_notice_until = 0


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
