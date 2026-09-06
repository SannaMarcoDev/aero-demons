extends Node3D

## Demo Showcase Controller for the Fighter Jet Thruster / Afterburner VFX.
## Features automated throttle showcase cycle, manual keyboard & mouse controls,
## multi-angle camera transitions, and inspector parameter switching.

@export var engine_assembly: Node3D
@export var camera: Camera3D

# Camera preset positions: [position, look_at_target, fov]
const CAM_PRESETS := {
	"hero": [Vector3(4.8, 2.4, 5.8), Vector3(0.0, 1.6, 2.5), 50.0],
	"rear": [Vector3(0.0, 1.6, 9.2), Vector3(0.0, 1.6, 0.0), 45.0],
	"side": [Vector3(8.2, 1.6, 2.8), Vector3(0.0, 1.6, 2.8), 50.0],
	"close": [Vector3(1.6, 1.8, 1.2), Vector3(0.0, 1.6, 0.2), 52.0],
	"top": [Vector3(0.0, 7.5, 3.0), Vector3(0.0, 1.6, 3.0), 55.0],
}

var _current_cam_preset := "hero"
var _target_cam_pos := Vector3(4.8, 2.4, 5.8)
var _target_cam_look := Vector3(0.0, 1.6, 2.5)
var _target_cam_fov := 50.0

# Automated showcase state machine
var auto_showcase := true
var _showcase_time := 0.0
var _manual_throttle := 1.0

# Mouse orbit controls
var _mouse_orbiting := false
var _orbit_yaw := 40.0
var _orbit_pitch := 15.0
var _orbit_distance := 7.0
var _orbit_center := Vector3(0.0, 1.6, 2.2)

# UI Node references
var _lbl_throttle: Label
var _lbl_mode: Label
var _slider_throttle: HSlider
var _btn_auto: Button


func _ready() -> void:
	if not engine_assembly:
		engine_assembly = get_node_or_null("JetEngineAssembly")
	if not camera:
		camera = get_node_or_null("Camera3D") as Camera3D

	_setup_ui()
	set_camera_preset("hero")


func _input(event: InputEvent) -> void:
	# Camera shortcuts: 1, 2, 3, 4, 5
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				set_camera_preset("hero")
			KEY_2:
				set_camera_preset("rear")
			KEY_3:
				set_camera_preset("side")
			KEY_4:
				set_camera_preset("close")
			KEY_5:
				set_camera_preset("top")
			KEY_SPACE:
				toggle_auto_showcase()
			KEY_I:
				set_manual_throttle(0.05)
			KEY_M:
				set_manual_throttle(0.6)
			KEY_A:
				set_manual_throttle(1.0)
			KEY_C:
				_cycle_color_theme()

	# Mouse orbit
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = clampf(_orbit_distance - 0.4, 2.0, 18.0)
			_current_cam_preset = "custom"
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = clampf(_orbit_distance + 0.4, 2.0, 18.0)
			_current_cam_preset = "custom"

	if event is InputEventMouseMotion and _mouse_orbiting:
		_orbit_yaw -= event.relative.x * 0.4
		_orbit_pitch = clampf(_orbit_pitch + event.relative.y * 0.4, -30.0, 80.0)
		_current_cam_preset = "custom"


func _process(delta: float) -> void:
	# Manual keyboard throttle adjustment
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		set_manual_throttle(_manual_throttle + delta * 0.4)
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		set_manual_throttle(_manual_throttle - delta * 0.4)

	# Run automated showcase cycle if active
	if auto_showcase:
		_process_showcase(delta)
	else:
		if engine_assembly:
			engine_assembly.throttle = _manual_throttle

	_update_environment_lighting()
	_update_camera(delta)
	_update_ui()


func _update_environment_lighting() -> void:
	var deflector_light := get_node_or_null("ExhaustDeflectorLight") as OmniLight3D
	if deflector_light and engine_assembly:
		var cur_t: float = engine_assembly.throttle
		deflector_light.visible = (cur_t > 0.25)
		deflector_light.light_energy = lerpf(0.0, 3.2, clamp((cur_t - 0.25) / 0.75, 0.0, 1.0))
		if "thruster_vfx" in engine_assembly and engine_assembly.thruster_vfx:
			deflector_light.light_color = engine_assembly.thruster_vfx.color_shock


func _process_showcase(delta: float) -> void:
	_showcase_time += delta
	var cycle_length := 18.0
	var t_mod := fmod(_showcase_time, cycle_length)
	var target_t: float

	if t_mod < 3.5:
		# Idle engine warm-up (0.05)
		target_t = 0.05
	elif t_mod < 6.5:
		# Spool up to Military Thrust (0.05 -> 0.6)
		var p := (t_mod - 3.5) / 3.0
		target_t = lerpf(0.05, 0.6, smoothstep(0.0, 1.0, p))
	elif t_mod < 10.0:
		# Steady Military Thrust (0.6)
		target_t = 0.6
	elif t_mod < 11.5:
		# Punch into Full Afterburner! (0.6 -> 1.0)
		var p := (t_mod - 10.0) / 1.5
		target_t = lerpf(0.6, 1.0, smoothstep(0.0, 1.0, p))
	elif t_mod < 15.5:
		# Maximum Afterburner (1.0)
		target_t = 1.0
	else:
		# Throttle down to Idle (1.0 -> 0.05)
		var p := (t_mod - 15.5) / 2.5
		target_t = lerpf(1.0, 0.05, smoothstep(0.0, 1.0, p))

	if engine_assembly:
		engine_assembly.throttle = target_t
	_manual_throttle = target_t


func set_manual_throttle(val: float) -> void:
	auto_showcase = false
	_manual_throttle = clampf(val, 0.0, 1.0)
	if engine_assembly:
		engine_assembly.throttle = _manual_throttle


func toggle_auto_showcase() -> void:
	auto_showcase = not auto_showcase
	if auto_showcase:
		_showcase_time = 0.0


func set_camera_preset(p_name: String) -> void:
	if not CAM_PRESETS.has(p_name):
		return
	_current_cam_preset = p_name
	var cfg: Array = CAM_PRESETS[p_name]
	_target_cam_pos = cfg[0]
	_target_cam_look = cfg[1]
	_target_cam_fov = cfg[2]

	# Synchronize orbit angles
	var offset: Vector3 = _target_cam_pos - _orbit_center
	_orbit_distance = offset.length()
	_orbit_yaw = rad_to_deg(atan2(offset.x, offset.z))
	_orbit_pitch = rad_to_deg(asin(clampf(offset.y / maxf(_orbit_distance, 0.001), -1.0, 1.0)))


func _update_camera(delta: float) -> void:
	if not camera:
		return

	if _current_cam_preset == "custom":
		var yaw_rad := deg_to_rad(_orbit_yaw)
		var pitch_rad := deg_to_rad(_orbit_pitch)
		var dir := Vector3(
			sin(yaw_rad) * cos(pitch_rad),
			sin(pitch_rad),
			cos(yaw_rad) * cos(pitch_rad)
		)
		_target_cam_pos = _orbit_center + dir * _orbit_distance
		_target_cam_look = _orbit_center

	camera.position = camera.position.lerp(_target_cam_pos, 6.0 * delta)
	var cur_rot := camera.transform.basis.orthonormalized()
	var target_xform := Transform3D.IDENTITY.looking_at(_target_cam_look - camera.position, Vector3.UP)
	camera.transform.basis = cur_rot.slerp(target_xform.basis.orthonormalized(), 6.0 * delta).orthonormalized()
	camera.fov = lerpf(camera.fov, _target_cam_fov, 6.0 * delta)


var _theme_index := 0
func _cycle_color_theme() -> void:
	if not engine_assembly or not ("thruster_vfx" in engine_assembly):
		return
	var vfx: Node3D = engine_assembly.thruster_vfx
	if not vfx:
		return
	_theme_index = (_theme_index + 1) % 3

	match _theme_index:
		0:
			# Modern Supersonic Blue (Ace Combat style)
			vfx.color_core = Color(1.0, 1.0, 1.0, 1.0)
			vfx.color_shock = Color(0.4, 0.82, 1.0, 1.0)
			vfx.color_plume = Color(0.18, 0.52, 1.0, 1.0)
			vfx.color_tail = Color(0.45, 0.15, 0.85, 1.0)
		1:
			# Intense Incandescent Orange (Russian Flanker / Titanium Fire style)
			vfx.color_core = Color(1.0, 0.95, 0.8, 1.0)
			vfx.color_shock = Color(1.0, 0.7, 0.2, 1.0)
			vfx.color_plume = Color(1.0, 0.35, 0.05, 1.0)
			vfx.color_tail = Color(0.7, 0.1, 0.02, 1.0)
		2:
			# Futuristic Sci-Fi Violet / Plasma
			vfx.color_core = Color(0.9, 0.95, 1.0, 1.0)
			vfx.color_shock = Color(0.75, 0.35, 1.0, 1.0)
			vfx.color_plume = Color(0.45, 0.1, 0.9, 1.0)
			vfx.color_tail = Color(0.2, 0.05, 0.6, 1.0)


# ==========================================
# UI SETUP & UPDATES
# ==========================================
func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 240)
	panel.position = Vector2(25, 25)

	# Transparent dark panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.82)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.25, 0.55, 0.9, 0.6)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "JET THRUSTER VFX SHOWCASE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	vbox.add_child(title)

	_lbl_throttle = Label.new()
	_lbl_throttle.text = "THROTTLE: 100%"
	vbox.add_child(_lbl_throttle)

	_slider_throttle = HSlider.new()
	_slider_throttle.min_value = 0.0
	_slider_throttle.max_value = 1.0
	_slider_throttle.step = 0.01
	_slider_throttle.value = 1.0
	_slider_throttle.value_changed.connect(func(v: float): set_manual_throttle(v))
	vbox.add_child(_slider_throttle)

	_btn_auto = Button.new()
	_btn_auto.text = "Auto Showcase: ON [Space]"
	_btn_auto.pressed.connect(toggle_auto_showcase)
	vbox.add_child(_btn_auto)

	var hbox_cam := HBoxContainer.new()
	hbox_cam.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox_cam)

	var btn_hero := Button.new()
	btn_hero.text = "Hero [1]"
	btn_hero.pressed.connect(func(): set_camera_preset("hero"))
	hbox_cam.add_child(btn_hero)

	var btn_rear := Button.new()
	btn_rear.text = "Rear [2]"
	btn_rear.pressed.connect(func(): set_camera_preset("rear"))
	hbox_cam.add_child(btn_rear)

	var btn_side := Button.new()
	btn_side.text = "Side [3]"
	btn_side.pressed.connect(func(): set_camera_preset("side"))
	hbox_cam.add_child(btn_side)

	var btn_close := Button.new()
	btn_close.text = "Close [4]"
	btn_close.pressed.connect(func(): set_camera_preset("close"))
	hbox_cam.add_child(btn_close)

	var btn_color := Button.new()
	btn_color.text = "Cycle Color Theme [C]"
	btn_color.pressed.connect(_cycle_color_theme)
	vbox.add_child(btn_color)

	var help := Label.new()
	help.text = "W/S: Throttle | I: Idle | M: Mil | A: Afterburner\nRMB + Drag: Orbit Camera | Wheel: Zoom"
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	vbox.add_child(help)


func _update_ui() -> void:
	if not engine_assembly:
		return
	var t: float = float(engine_assembly.throttle)
	if _lbl_throttle:
		var pct := int(round(t * 100.0))
		var state_str := " [IDLE]" if t < 0.2 else (" [MILITARY]" if t < 0.75 else " [AFTERBURNER!]")
		_lbl_throttle.text = "THROTTLE: %d%%%s" % [pct, state_str]
		if t >= 0.75:
			_lbl_throttle.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
		elif t >= 0.2:
			_lbl_throttle.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		else:
			_lbl_throttle.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))

	if _slider_throttle and not _slider_throttle.has_focus():
		_slider_throttle.set_value_no_signal(t)

	if _btn_auto:
		_btn_auto.text = "Auto Showcase: %s [Space]" % ("ON" if auto_showcase else "OFF")
