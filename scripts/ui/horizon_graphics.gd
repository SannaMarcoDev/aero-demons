extends CanvasLayer
## C is authored in tutorial_clouds.tres. D adds only camera-local far DOF.
## F7 is independent of the temporary F6 filters. No scene/resource saves.

var settings_path := "user://graphics.cfg"
var settings := ConfigFile.new()
var can_save := true
var attributes: CameraAttributesPractical
var label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	var camera: Camera3D = get_node("../Player/FlightCamera")
	var source: CameraAttributes = camera.attributes
	if source == null:
		source = get_node("../GardaLake/Sky3D").camera_attributes
	# Preserve exposure without modifying the shared WorldEnvironment resource.
	attributes = source.duplicate()
	attributes.dof_blur_far_distance = 35000.0
	attributes.dof_blur_far_transition = 45000.0
	attributes.dof_blur_amount = 0.08
	camera.attributes = attributes
	label = Label.new()
	label.position = Vector2(24, 180)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	var error := settings.load(settings_path)
	can_save = error == OK or error == ERR_FILE_NOT_FOUND
	if not can_save:
		push_warning("Cannot read %s (%s); leaving the file untouched" % [settings_path, error_string(error)])
	var saved = settings.get_value("graphics", "horizon_blur", false) if error == OK else false
	apply_blur(saved if saved is bool else false)

func apply_blur(enabled: bool) -> void:
	attributes.dof_blur_far_enabled = enabled
	label.text = "F7 · Orizzonte: " + ("D · C + blur lontano" if enabled else "C · Standard")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		apply_blur(not attributes.dof_blur_far_enabled)
		settings.set_value("graphics", "horizon_blur", attributes.dof_blur_far_enabled)
		var error := settings.save(settings_path) if can_save else ERR_FILE_CANT_WRITE
		if error != OK:
			label.text += " · non salvato"
			push_warning("Cannot save horizon setting to %s: %s" % [settings_path, error_string(error)])
		get_viewport().set_input_as_handled()
