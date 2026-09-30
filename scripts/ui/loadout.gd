extends CanvasLayer

const Session = preload("res://scripts/ui/game_session.gd")

@onready var aircraft_selection = $AircraftSelection
@onready var missile_selection = $MissileSelection
@onready var loading_screen: ColorRect = $LoadingScreen
@onready var loading_progress: ProgressBar = $LoadingScreen/Center/Column/Progress
@onready var loading_label: Label = $LoadingScreen/Center/Column/Status

var _aircraft_step := true
var _launching := false
var _transitioning := true


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	aircraft_selection.confirmed.connect(_on_aircraft_continue)
	aircraft_selection.back_requested.connect(_on_back_pressed)
	missile_selection.confirmed.connect(_on_avvia_pressed)
	missile_selection.back_requested.connect(_on_back_pressed)
	_set_aircraft_step(true)
	await aircraft_selection.fade(true)
	_transitioning = false


func _set_aircraft_step(enabled: bool) -> void:
	_aircraft_step = enabled
	aircraft_selection.visible = enabled
	aircraft_selection.set_process(enabled)
	missile_selection.visible = not enabled
	missile_selection.set_process(not enabled)
	if enabled:
		aircraft_selection.restore_selection()
	else:
		missile_selection.restore_selection()


func _on_aircraft_continue() -> void:
	if _launching or _transitioning:
		return
	_transitioning = true
	await aircraft_selection.fade(false)
	_set_aircraft_step(false)
	await missile_selection.fade(true)
	_transitioning = false


func _on_avvia_pressed() -> void:
	if _launching or _transitioning or _aircraft_step:
		return
	_launching = true
	Session.selected_missiles = missile_selection._selected_missiles.duplicate()
	missile_selection.accept_button.disabled = true
	missile_selection.back_button.disabled = true
	await missile_selection.fade(false)
	loading_progress.value = 0.0
	loading_label.text = "CARICAMENTO…"
	$LoadingScreen/Center/Column/Mission.text = Session.level_name()
	loading_screen.modulate.a = 0.0
	loading_screen.show()
	await create_tween().tween_property(loading_screen, "modulate:a", 1.0, 0.22).finished
	# Show the loading screen before requesting terrain/resources or instantiating the level.
	await get_tree().process_frame
	var path := Session.selected_map
	var error := ResourceLoader.load_threaded_request(path, "PackedScene")
	if error == OK:
		var progress: Array = []
		while true:
			var status := ResourceLoader.load_threaded_get_status(path, progress)
			if not progress.is_empty():
				loading_progress.value = float(progress[0]) * 100.0
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				loading_progress.value = 100.0
				loading_label.text = "AVVIO…"
				await get_tree().process_frame
				await get_tree().process_frame
				var scene := ResourceLoader.load_threaded_get(path) as PackedScene
				error = Session.change_scene(get_tree(), path, scene) if scene != null else ERR_CANT_OPEN
				break
			if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				error = ERR_CANT_OPEN
				break
			await get_tree().process_frame
	if error == OK:
		return
	await create_tween().tween_property(loading_screen, "modulate:a", 0.0, 0.22).finished
	loading_screen.hide()
	missile_selection.accept_button.disabled = false
	missile_selection.back_button.disabled = false
	missile_selection.accept_button.text = "RIPROVA →"
	missile_selection.restore_selection()
	missile_selection.get_node("Layout/Footer/Message").text = "CARICAMENTO FALLITO · RIPROVA"
	await missile_selection.fade(true)
	_launching = false
	missile_selection.accept_button.grab_focus()


func _on_back_pressed() -> void:
	if _launching or _transitioning:
		return
	_transitioning = true
	if not _aircraft_step:
		await missile_selection.fade(false)
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
