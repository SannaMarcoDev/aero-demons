extends SceneTree
## godot --headless --path . --script tests/controller_remap_check.gd
## All writes target a disposable file, never the player's settings.
const Settings = preload("res://scripts/ui/settings_manager.gd")
const Bindings = preload("res://scripts/ui/controller_bindings.gd")
var panel: OptionsPanel
var remap: Window
var path := "user://remap_check_%d.cfg" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("AudioManager")._music_player.stop()
	root.get_node("AudioManager")._music_player.stream = null
	root.gui_embed_subwindows = true
	panel = load("res://scenes/ui/options_panel.tscn").instantiate()
	root.add_child(panel)
	panel.size = Vector2(900, 700)
	remap = panel.get_node("ControllerRemap")
	remap.config_path = path
	assert(not FileAccess.file_exists(path))
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", 0.37)
	assert(config.save(path) == OK)
	Bindings.apply({})
	panel.settings.controls_bindings = Bindings.defaults()
	panel.grab_first_focus()
	assert(panel.get_node("RemapButton").has_focus())
	panel.get_node("RemapButton").pressed.emit()
	await process_frame
	assert(remap.visible and remap._rows[0].has_focus())
	# Native controller UI navigation, not just signal calls.
	await _button(JOY_BUTTON_DPAD_DOWN)
	assert(remap._rows[1].has_focus())
	await _button(JOY_BUTTON_A)
	assert(remap._capture == remap._rows[1], "Accept opens capture without assigning itself")
	assert(remap.draft == Bindings.defaults())
	await _button(JOY_BUTTON_B)
	assert(remap.visible and remap._capture == null, "B can be bound without closing either menu")
	assert(remap.draft.pitch_down.events == [{"button": JOY_BUTTON_B}])
	assert(Settings.load_settings(path).controls_bindings == Bindings.defaults(), "Draft is not persisted")
	# Swap an occupied input without unbinding the other action.
	remap._begin_capture(_row("fire_gun"))
	await _button(JOY_BUTTON_A)
	assert(remap.draft.fire_gun.events == [{"button": JOY_BUTTON_A}])
	assert(remap.draft.fire_missile.events == [{"button": JOY_BUTTON_X}])
	assert(not Bindings.validated(remap.draft).is_empty())
	# Axis drift is ignored; capture commits only after returning to neutral.
	remap._begin_capture(_row("roll_left"))
	await _axis(JOY_AXIS_RIGHT_X, -0.2)
	assert(remap._candidate.is_empty())
	await _axis(JOY_AXIS_RIGHT_X, -0.9)
	assert(remap._capture != null)
	await _axis(JOY_AXIS_RIGHT_X, 0.0)
	assert(remap._capture == null)
	assert(remap.draft.roll_left.events == [{"axis": JOY_AXIS_RIGHT_X, "direction": -1}])
	assert(remap.draft.look_left.events == [{"axis": JOY_AXIS_LEFT_X, "direction": -1}])
	# Menu alternatives are preserved, and menu conflicts swap only in that context.
	remap._begin_capture(_row("ui_up"))
	await _button(JOY_BUTTON_DPAD_DOWN)
	assert(remap.draft.ui_up.events.size() == Bindings.defaults().ui_up.events.size())
	assert(not Bindings.validated(remap.draft).is_empty())
	# Put menu navigation back before the rest of the controller-driven checks.
	for action: String in Bindings.CONTEXTS[0]:
		remap.draft[action] = Bindings.defaults()[action]
	remap._refresh_rows()
	# Existing held axes must return to neutral before capture can begin.
	remap._begin_capture(_row("yaw_left"))
	remap._blocked_axes[Vector2i(0, JOY_AXIS_TRIGGER_RIGHT)] = true
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	assert(remap._candidate.is_empty())
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert(remap._capture == null)
	assert(remap.draft.yaw_left.events == [{"axis": JOY_AXIS_TRIGGER_RIGHT, "direction": 1}])
	var before: Dictionary = remap.draft.duplicate(true)
	remap._begin_capture(_row("brake"))
	remap._process(9.0)
	assert(remap._capture == null and remap.draft == before)
	remap._begin_capture(_row("brake"))
	remap._on_connection_changed(0, false)
	assert(remap._capture == null and remap.draft == before)
	# Save failure keeps the modal and draft, with no InputMap changes.
	remap.config_path = path + "/missing/file.cfg"
	remap._save_profile()
	assert(remap.visible and remap.draft == before)
	assert(panel.settings.controls_bindings == Bindings.defaults())
	remap.config_path = path
	remap._save_profile()
	await process_frame
	assert(not remap.visible and panel.get_node("RemapButton").has_focus())
	assert(panel.settings.controls_bindings == before, "Options snapshot must track saved bindings")
	Settings.apply_controls(panel.settings)
	assert(Settings.load_settings(path).controls_bindings == before)
	assert(InputMap.action_get_events("fire_gun").any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A))
	assert(config.load(path) == OK and is_equal_approx(config.get_value("audio", "master_volume"), 0.37))
	# Paused-tree capture, reset/rollback and explicit focus wrap.
	paused = true
	remap.open(panel.get_node("RemapButton"))
	await process_frame
	assert(remap._rows[0].has_focus())
	await _button(JOY_BUTTON_DPAD_UP)
	assert(remap._back.has_focus())
	remap._begin_capture(_row("fire_gun"))
	await _button(JOY_BUTTON_B)
	assert(remap._capture == null and paused)
	remap._reset_profile()
	assert(remap.draft == Bindings.defaults())
	assert(Settings.load_settings(path).controls_bindings == before)
	await _button(JOY_BUTTON_B)
	assert(not remap.visible and paused)
	remap.open(panel.get_node("RemapButton"))
	await process_frame
	assert(remap.draft == before)
	remap._reset_profile()
	remap._save_profile()
	assert(Settings.load_settings(path).controls_bindings == Bindings.defaults())
	paused = false
	panel.queue_free()
	await process_frame
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	print("PASS: controller remap navigation, capture, swap, axes, timeout, disconnect, persistence, rollback, pause, focus")
	quit(0)


func _row(action: String) -> Button:
	for button: Button in remap._rows:
		if button.get_meta("action") == action:
			return button
	assert(false, "Missing action row")
	return null


func _button(index: int) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = index
		event.pressed = pressed
		remap.push_input(event)
		await process_frame


func _axis(index: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = index
	event.axis_value = value
	remap.push_input(event)
	await process_frame
