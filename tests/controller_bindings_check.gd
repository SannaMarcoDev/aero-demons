extends Node
## Run this scene headlessly with -- --write-profile <isolated.cfg>, then in a new
## process with -- --read-profile <isolated.cfg>. Without arguments, uses a temp
## file; graphical runs leave a controller probe visible after the assertions.

const Settings = preload("res://scripts/ui/settings_manager.gd")
const Bindings = preload("res://scripts/ui/controller_bindings.gd")

# Exercise the real player input reader, without a terrain, weapons or flight tick.
class InputProbe extends PlayerFlight:
	func _ready() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		_update_controls()

var _probe: InputProbe
var _status: Label
var _path := ""


func _ready() -> void:
	# This input-only fixture does not need the autoload's music playback.
	get_node("/root/AudioManager")._music_player.stop()
	get_node("/root/AudioManager")._music_player.stream = null
	var args := OS.get_cmdline_user_args()
	var read_phase := args.size() == 2 and args[0] == "--read-profile"
	var write_phase := args.size() == 2 and args[0] == "--write-profile"
	_path = args[1] if read_phase or write_phase else OS.get_cache_dir().path_join(
		"aero-demons-bindings-%d.cfg" % OS.get_process_id())
	# Never use the production settings path, even when invoked incorrectly.
	assert(ProjectSettings.globalize_path(_path) != ProjectSettings.globalize_path(Settings.CONFIG_PATH))
	if read_phase:
		assert(FileAccess.file_exists(_path), "Persistence check needs the previous process's file")
	else:
		assert(not FileAccess.file_exists(_path), "Do not overwrite existing test/user data")
		var initial := ConfigFile.new()
		initial.set_value("audio", "master_volume", 0.37)
		initial.set_value("controls", "invert_y", true)
		initial.set_value("controls", "sensitivity", 1.25)
		initial.set_value("unrelated", "sentinel", "keep")
		assert(initial.save(_path) == OK)

	var defaults := Bindings.defaults()
	var custom := defaults.duplicate(true)
	custom.fire_gun.events = [{"button": JOY_BUTTON_B}]
	# Move and invert pitch/look Y as complete pairs, without leaving axis conflicts.
	custom.pitch_up.events = [{"axis": JOY_AXIS_RIGHT_Y, "direction": -1}]
	custom.pitch_down.events = [{"axis": JOY_AXIS_RIGHT_Y, "direction": 1}]
	custom.look_up.events = [{"axis": JOY_AXIS_LEFT_Y, "direction": 1}]
	custom.look_down.events = [{"axis": JOY_AXIS_LEFT_Y, "direction": -1}]
	custom.pitch_up.deadzone = 0.3
	custom.pitch_down.deadzone = 0.3
	custom.yaw_left.events = [{"axis": JOY_AXIS_TRIGGER_RIGHT, "direction": 1}]
	custom.yaw_right.events = [{"axis": JOY_AXIS_TRIGGER_LEFT, "direction": 1}]
	assert(Bindings.validated(custom) == custom)
	var keyboard := _non_controller_events()
	if read_phase:
		assert(Settings.load_settings(_path).controls_bindings == custom, "Profile must survive process restart")
	else:
		assert(Settings.load_settings(_path).controls_bindings == defaults, "Legacy config uses defaults")
		assert(Settings.save_controller_bindings(custom, _path) == OK)
	Settings.apply_controls(Settings.load_settings(_path))
	assert(Settings.controls_invert_y and is_equal_approx(Settings.controls_sensitivity, 1.25))
	assert(_non_controller_events() == keyboard, "Keyboard/mouse debugging must survive rebinding")
	var before := FileAccess.get_file_as_bytes(_path)
	var invalid_profiles: Array = [null, [], {"unknown": {}}, {"fire_gun": {}},
		{"fire_gun": {"events": [], "deadzone": 0.5}}]
	for bad_event in [{"button": -1}, {"button": 999}, {"button": "1"},
			{"axis": 6, "direction": 1}, {"axis": 0, "direction": 0},
			{"axis": JOY_AXIS_TRIGGER_LEFT, "direction": -1}]:
		invalid_profiles.append({"fire_gun": {"events": [bad_event], "deadzone": 0.5}})
	for deadzone in [NAN, INF, -0.1, 1.0, "bad"]:
		invalid_profiles.append({"fire_gun": {"events": [{"button": JOY_BUTTON_B}], "deadzone": deadzone}})
	var conflict := custom.duplicate(true)
	conflict.fire_gun.events = [{"button": JOY_BUTTON_A}]
	invalid_profiles.append(conflict)
	for invalid in invalid_profiles:
		assert(Bindings.normalized(invalid) == defaults)
		assert(Settings.save_controller_bindings(invalid, _path) == ERR_INVALID_DATA)
		assert(FileAccess.get_file_as_bytes(_path) == before, "Rejected profiles must not touch the file")
	assert(Settings.save_controller_bindings(custom, _path + "/missing/config.cfg") != OK)
	assert(FileAccess.get_file_as_bytes(_path) == before)

	_probe = InputProbe.new()
	var exhaust := Afterburner.new()
	exhaust.name = "Afterburners"
	_probe.add_child(exhaust)
	add_child(_probe)
	await _button(JOY_BUTTON_X, true)
	assert(not _probe.gun_trigger, "Old gun button must no longer fire")
	await _button(JOY_BUTTON_X, false)
	await _button(JOY_BUTTON_B, true)
	assert(_probe.gun_trigger, "New gun button must drive PlayerFlight, not only InputMap metadata")
	assert(Input.is_action_pressed("ui_cancel"), "Same button is allowed across UI/flight contexts")
	# Re-applying graphics/audio settings must not release held controller actions.
	Settings.apply_controls(Settings.load_settings(_path))
	assert(Input.is_action_pressed("fire_gun"))
	await _button(JOY_BUTTON_B, false)
	await _axis(JOY_AXIS_RIGHT_Y, -0.2)
	assert(is_zero_approx(Input.get_axis("pitch_up", "pitch_down")), "Deadzone filters small input")
	await _axis(JOY_AXIS_RIGHT_Y, -0.65)
	assert(is_equal_approx(Input.get_action_strength("pitch_up"), 0.5), "Analog strength is preserved")
	await _axis(JOY_AXIS_RIGHT_Y, 1.0)
	assert(is_equal_approx(Input.get_axis("pitch_up", "pitch_down"), 1.0))
	await _axis(JOY_AXIS_RIGHT_Y, 0.0)
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.55)
	assert(is_equal_approx(Input.get_action_strength("yaw_left"), 0.5), "Trigger remains analog after swapping")
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	assert(is_equal_approx(Input.get_action_strength("yaw_right"), 1.0))
	await _axis(JOY_AXIS_TRIGGER_LEFT, 0.0)

	await _button(JOY_BUTTON_B, true)
	assert(_probe.gun_trigger)
	assert(Settings.reset_controller_bindings(_path) == OK)
	assert(not Input.is_action_pressed("fire_gun"), "Removing a held binding must release its action")
	assert(Settings.load_settings(_path).controls_bindings == defaults)
	assert(Settings.controls_invert_y and is_equal_approx(Settings.controls_sensitivity, 1.25))
	await _button(JOY_BUTTON_B, false)
	await _button(JOY_BUTTON_B, true)
	assert(not _probe.gun_trigger)
	await _button(JOY_BUTTON_B, false)
	await _button(JOY_BUTTON_X, true)
	assert(_probe.gun_trigger, "Reset restores the project binding")
	await _button(JOY_BUTTON_X, false)
	var saved := ConfigFile.new()
	assert(saved.load(_path) == OK)
	assert(saved.get_value("unrelated", "sentinel") == "keep")
	assert(is_equal_approx(saved.get_value("audio", "master_volume"), 0.37))
	assert(saved.get_value("controls", "invert_y") == true)
	assert(is_equal_approx(saved.get_value("controls", "sensitivity"), 1.25))
	# Invalid data on disk falls back without rewriting it or disabling any action.
	saved.set_value("controls", "bindings", conflict)
	assert(saved.save(_path) == OK)
	assert(Settings.load_settings(_path).controls_bindings == defaults)
	# Run the intentionally malformed INI only headlessly: ConfigFile sends its
	# expected engine errors to the editor debugger even with printing disabled.
	if DisplayServer.get_name() == "headless":
		var corrupt := FileAccess.open(_path, FileAccess.WRITE)
		assert(corrupt != null)
		corrupt.store_string("[broken")
		corrupt.close()
		before = FileAccess.get_file_as_bytes(_path)
		# Silence only these synchronous negative probes, never their assertions.
		var print_errors := Engine.print_error_messages
		Engine.print_error_messages = false
		var fallback := Settings.load_settings(_path)
		var corrupt_error := Settings.save_controller_bindings(custom, _path)
		Engine.print_error_messages = print_errors
		assert(fallback.controls_bindings == defaults)
		assert(corrupt_error != OK)
		assert(FileAccess.get_file_as_bytes(_path) == before, "Do not overwrite a corrupt settings file")
	assert(DirAccess.remove_absolute(_path) == OK)
	assert(Settings.load_settings(_path).controls_bindings == defaults)
	assert(saved.save(_path) == OK)
	assert(Settings.save_controller_bindings(custom, _path) == OK)
	# The existing options writer preserves the separately-owned binding section.
	assert(Settings.save_settings(Settings.load_settings(_path), _path) == OK)
	assert(Settings.load_settings(_path).controls_bindings == custom)
	print("PASS: controller bindings ", "restart" if read_phase else "write", "; input, analog, reset, validation, isolation")
	if not write_phase:
		assert(DirAccess.remove_absolute(_path) == OK)
	if DisplayServer.get_name() == "headless":
		_probe.queue_free()
		await get_tree().process_frame
		get_tree().quit.call_deferred(0)
	else:
		_status = Label.new()
		_status.position = Vector2(40, 40)
		_status.add_theme_font_size_override("font_size", 24)
		add_child(_status)


func _process(_delta: float) -> void:
	if _status != null:
		_status.text = "CONTROLLER CHECK — profilo temporaneo, nessun salvataggio personale\n\n" \
			+ "Cannone rimappato X → B: tieni B, poi prova X.\n" \
			+ "Lettura reale PlayerFlight.gun_trigger: %s\n\n" % str(_probe.gun_trigger) \
			+ "Test automatici PASS. Chiudere la finestra per terminare."


func _button(index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	await get_tree().physics_frame
	await get_tree().process_frame


func _axis(index: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = index
	event.axis_value = value
	Input.parse_input_event(event)
	await get_tree().physics_frame
	await get_tree().process_frame


func _non_controller_events() -> Dictionary:
	var result := {}
	for action: String in Bindings.defaults():
		result[action] = []
		for event in InputMap.action_get_events(action):
			if not event is InputEventJoypadButton and not event is InputEventJoypadMotion:
				result[action].append(event)
	return result
