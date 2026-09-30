extends CanvasLayer

const Session = preload("res://scripts/core/game_session.gd")
const Bindings = preload("res://scripts/input/controller_bindings.gd")
const BOARD_SIZE := Vector2(1660, 680)

@onready var screen: Control = $Screen
@onready var menu_ui: Control = $Screen/Board
@onready var root_menu: Control = $Screen/Board/RootMenu
@onready var storia_menu: Control = $Screen/Board/StoriaMenu
@onready var storia_btn: Button = $Screen/Board/RootMenu/StoriaButton
@onready var free_flight_btn: Button = $Screen/Board/RootMenu/FreeFlightButton
@onready var arena_btn: Button = $Screen/Board/RootMenu/ArenaButton
@onready var options_btn: Button = $Screen/Board/RootMenu/OptionsButton
@onready var replay_btn: Button = $Screen/Board/RootMenu/ReplayButton
@onready var benchmark_btn: Button = $Screen/Board/RootMenu/BenchmarkButton
@onready var quit_btn: Button = $Screen/Board/RootMenu/QuitButton
@onready var alps_btn: Button = $Screen/Board/StoriaMenu/GardaButton
@onready var storia_back_btn: Button = $Screen/Board/StoriaMenu/StoriaBackButton
@onready var dialog: Control = $Screen/Dialog
@onready var dialog_cancel: Button = $Screen/Dialog/Center/Panel/Margin/Column/Actions/Cancel
@onready var dialog_confirm: Button = $Screen/Dialog/Center/Panel/Margin/Column/Actions/Confirm

var _transitioning := false
var _dialog_return_focus: Button
var _board_origin := Vector2.ZERO
var _layout_scale := 1.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	storia_btn.pressed.connect(_on_storia_pressed)
	free_flight_btn.pressed.connect(_on_free_flight_pressed)
	arena_btn.pressed.connect(_select_storia_map.bind(Session.ARENA))
	options_btn.pressed.connect(func():
		if not _transitioning:
			_play_sfx()
			_show_dialog("OPZIONI", "Opzioni non ancora disponibili."))
	replay_btn.pressed.connect(_on_replay_pressed)
	benchmark_btn.pressed.connect(_launch_scene.bind(Session.BENCHMARK))
	quit_btn.pressed.connect(_on_quit_pressed)
	alps_btn.pressed.connect(_select_storia_map.bind(Session.DOGFIGHT))
	storia_back_btn.pressed.connect(_on_storia_back_pressed)
	dialog_cancel.pressed.connect(_hide_dialog)
	dialog_confirm.pressed.connect(func(): get_tree().quit())
	for button: Button in _cards():
		button.mouse_entered.connect(_focus_card.bind(button))
	screen.resized.connect(_layout)
	_layout()
	_refresh_prompts()
	if Session.menu_section == "sorties":
		_show_storia_menu()
	else:
		var returning_free_flight := Session.menu_section == "free_flight"
		_show_root_menu()
		if returning_free_flight:
			free_flight_btn.grab_focus()
	_transitioning = true
	menu_ui.modulate.a = 0.0
	await _fade_board(true).finished
	_transitioning = false


func _cards() -> Array[Button]:
	return [storia_btn, arena_btn, free_flight_btn, replay_btn, options_btn,
		benchmark_btn, quit_btn, alps_btn, storia_back_btn]


func _layout() -> void:
	var view := screen.size
	_layout_scale = minf(view.x / 1920.0, view.y / 1080.0)
	menu_ui.size = BOARD_SIZE
	menu_ui.pivot_offset = BOARD_SIZE * 0.5
	menu_ui.scale = Vector2.ONE * _layout_scale
	_board_origin = view * 0.5 - BOARD_SIZE * 0.5 + Vector2(0, 34) * _layout_scale
	menu_ui.position = _board_origin
	$Screen/Chrome.scale = Vector2.ONE * _layout_scale
	$Screen/Chrome.position = (view - Vector2(1920, 1080) * _layout_scale) * 0.5
	$Screen/Background.position = Vector2(-80, -60)
	$Screen/Background.size = view + Vector2(160, 120)


func _process(delta: float) -> void:
	var parallax_offset := Vector2.ZERO
	var focus := get_viewport().gui_get_focus_owner()
	if focus is Button and focus.get_parent() in [root_menu, storia_menu] and not dialog.visible:
		parallax_offset = (
			((focus.position + focus.size * 0.5) / BOARD_SIZE - Vector2(0.5, 0.5))
			* Vector2(20, 12) * _layout_scale
		)
	var weight := 1.0 - exp(-delta * 7.0)
	menu_ui.position = menu_ui.position.lerp(_board_origin - parallax_offset, weight)
	$Screen/Background.position = $Screen/Background.position.lerp(
		Vector2(-80, -60) + parallax_offset * 0.3, weight
	)


func _focus_card(button: Button) -> void:
	if not _transitioning and not dialog.visible and not button.disabled:
		button.grab_focus()


func _refresh_prompts() -> void:
	$Screen/Chrome/NavHints.text = Bindings.menu_hint()


func _show_root_menu() -> void:
	Session.menu_section = ""
	root_menu.show()
	storia_menu.hide()
	$Screen/Chrome/Section.hide()
	$Screen/Chrome/Status.hide()
	storia_btn.grab_focus()


func _show_storia_menu() -> void:
	Session.menu_section = "sorties"
	root_menu.hide()
	storia_menu.show()
	$Screen/Chrome/Section.show()
	$Screen/Chrome/Status.hide()
	alps_btn.grab_focus()


func _fade_board(show_board: bool) -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(menu_ui, "modulate:a", 1.0 if show_board else 0.0, 0.22)
	return tween


func _on_storia_pressed() -> void:
	await _switch_section(true)


func _on_storia_back_pressed() -> void:
	await _switch_section(false)


func _switch_section(campaign: bool) -> void:
	if _transitioning:
		return
	_transitioning = true
	_play_sfx()
	await _fade_board(false).finished
	if campaign:
		_show_storia_menu()
	else:
		_show_root_menu()
	await _fade_board(true).finished
	_transitioning = false


func _select_storia_map(map_path: String) -> void:
	if _transitioning:
		return
	Session.free_flight = false
	Session.selected_map = map_path
	await _launch_scene(Session.LOADOUT)


func _on_replay_pressed() -> void:
	if _transitioning:
		return
	get_node("/root/ReplayRecorder").selected_path = ""
	await _launch_scene("res://scenes/replay/replay_viewer.tscn")


func _launch_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	_play_sfx()
	await _fade_board(false).finished
	if Session.change_scene(get_tree(), path) != OK:
		_show_error("Impossibile aprire la schermata. Riprova.")
		await _fade_board(true).finished
		_transitioning = false


func _on_free_flight_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	_play_sfx()
	Session.free_flight = true
	Session.menu_section = ""
	Session.selected_map = Session.FREE_FLIGHT
	free_flight_btn.set("title", "CARICAMENTO…")
	free_flight_btn.disabled = true
	await get_tree().process_frame
	var path := Session.FREE_FLIGHT
	var status := ResourceLoader.load_threaded_get_status(path)
	var error := OK
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		error = ResourceLoader.load_threaded_request(path)
	while error == OK and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if error == OK and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if scene != null:
			await _fade_board(false).finished
			error = Session.change_scene(get_tree(), path, scene)
		else:
			error = ERR_FILE_CANT_OPEN
	elif error == OK:
		error = ERR_FILE_CANT_OPEN
	if error != OK:
		free_flight_btn.set("title", "FREE FLIGHT")
		free_flight_btn.disabled = false
		free_flight_btn.grab_focus()
		_show_error("Impossibile avviare il volo libero. Riprova.")
		await _fade_board(true).finished
		_transitioning = false


func _show_error(message: String) -> void:
	$Screen/Chrome/Status.text = message
	$Screen/Chrome/Status.show()


func _on_quit_pressed() -> void:
	if not _transitioning:
		_play_sfx()
		_show_dialog("VUOI USCIRE?", "La sessione di Aero Demons verrà chiusa.", true)


func _show_dialog(title: String, message: String, confirm_quit := false) -> void:
	_dialog_return_focus = get_viewport().gui_get_focus_owner() as Button
	$Screen/Dialog/Center/Panel/Margin/Column/Title.text = title
	$Screen/Dialog/Center/Panel/Margin/Column/Message.text = message
	dialog_confirm.visible = confirm_quit
	dialog_cancel.text = "ANNULLA" if confirm_quit else "INDIETRO"
	dialog_cancel.focus_neighbor_left = dialog_confirm.get_path() if confirm_quit else dialog_cancel.get_path()
	dialog_cancel.focus_neighbor_right = dialog_cancel.focus_neighbor_left
	for button: Button in _cards():
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
	dialog.show()
	dialog_cancel.grab_focus()


func _hide_dialog() -> void:
	dialog.hide()
	for button: Button in _cards():
		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL
	if is_instance_valid(_dialog_return_focus):
		_dialog_return_focus.grab_focus()


func _input(_event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if dialog.visible:
			_hide_dialog()
		elif storia_menu.visible:
			_on_storia_back_pressed()
		else:
			quit_btn.grab_focus()
	elif get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
				or event.is_action_pressed("ui_accept"):
			var button := dialog_cancel if dialog.visible else (alps_btn if storia_menu.visible else storia_btn)
			button.grab_focus()
			get_viewport().set_input_as_handled()


func _play_sfx() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr != null and audio_mgr.has_method("play_weapon_switch"):
		audio_mgr.play_weapon_switch()
