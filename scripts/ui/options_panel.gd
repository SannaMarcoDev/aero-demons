extends VBoxContainer
class_name OptionsPanel

## Reusable settings panel shared by the main menu and the in-game pause overlay. Loads and
## applies the persisted settings on _ready; call save() when leaving the panel.

const Settings = preload("res://scripts/ui/settings_manager.gd")

const WINDOW_MODE_LABELS: Array[String] = ["FINESTRA", "BORDERLESS", "FULLSCREEN"]
const UPSCALER_LABELS: Array[String] = ["NATIVO", "FSR 1.0", "FSR 2.2"]
const AA_LABELS: Array[String] = ["OFF", "FXAA", "TAA"]

var settings: Dictionary = {}
var dirty := false
var _updating := false
var _resolutions: Array[Vector2i] = []

@onready var master_slider: HSlider = $Scroll/Sections/AudioBox/MasterRow/MasterSlider
@onready var master_val_label: Label = $Scroll/Sections/AudioBox/MasterRow/MasterVal
@onready var music_slider: HSlider = $Scroll/Sections/AudioBox/MusicRow/MusicSlider
@onready var music_val_label: Label = $Scroll/Sections/AudioBox/MusicRow/MusicVal
@onready var sfx_slider: HSlider = $Scroll/Sections/AudioBox/SFXRow/SFXSlider
@onready var sfx_val_label: Label = $Scroll/Sections/AudioBox/SFXRow/SFXVal
@onready var window_mode_btn: Button = $Scroll/Sections/DisplayBox/WindowModeBtn
@onready var resolution_btn: Button = $Scroll/Sections/DisplayBox/ResolutionBtn
@onready var vsync_btn: Button = $Scroll/Sections/DisplayBox/VSyncBtn
@onready var fps_limit_btn: Button = $Scroll/Sections/DisplayBox/FpsLimitBtn
@onready var upscaler_btn: Button = $Scroll/Sections/RenderBox/UpscalerBtn
@onready var render_scale_btn: Button = $Scroll/Sections/RenderBox/RenderScaleBtn
@onready var aa_btn: Button = $Scroll/Sections/RenderBox/AntiAliasingBtn
@onready var invert_y_btn: Button = $Scroll/Sections/ControlsBox/InvertYBtn
@onready var sens_slider: HSlider = $Scroll/Sections/ControlsBox/SensRow/SensSlider
@onready var sens_val_label: Label = $Scroll/Sections/ControlsBox/SensRow/SensVal


func _ready() -> void:
	settings = Settings.load_settings()
	_build_resolution_list()
	_wire_signals()
	_updating = true
	_refresh_ui()
	_updating = false
	Settings.apply_settings(settings)


func grab_first_focus() -> void:
	master_slider.grab_focus()


## Writes settings.cfg only when something actually changed since load/last save.
func save() -> Error:
	if not dirty:
		return OK
	var error := Settings.save_settings(settings)
	if error == OK:
		dirty = false
	return error


func _wire_signals() -> void:
	master_slider.value_changed.connect(func(v): _on_volume_slider("master_volume", v, master_val_label))
	music_slider.value_changed.connect(func(v): _on_volume_slider("music_volume", v, music_val_label))
	sfx_slider.value_changed.connect(func(v): _on_volume_slider("sfx_volume", v, sfx_val_label))
	sens_slider.value_changed.connect(_on_sens_slider_changed)
	window_mode_btn.pressed.connect(_on_cycle_window_mode)
	resolution_btn.pressed.connect(_on_cycle_resolution)
	vsync_btn.pressed.connect(_on_toggle_vsync)
	fps_limit_btn.pressed.connect(_on_cycle_fps_limit)
	upscaler_btn.pressed.connect(_on_cycle_upscaler)
	render_scale_btn.pressed.connect(_on_cycle_render_scale)
	aa_btn.pressed.connect(_on_cycle_aa)
	invert_y_btn.pressed.connect(_on_toggle_invert_y)


func _build_resolution_list() -> void:
	_resolutions.clear()
	var native := Vector2i.ZERO
	if DisplayServer.get_name() != "headless":
		native = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	for entry in Settings.RESOLUTIONS:
		if native == Vector2i.ZERO or (entry.x <= native.x and entry.y <= native.y):
			_resolutions.append(entry)
	var current := Settings.parse_resolution(str(settings.get("resolution", "1920x1080")))
	if not _resolutions.has(current):
		_resolutions.append(current)
	_resolutions.sort_custom(func(a, b): return a.x * a.y < b.x * b.y)


func _refresh_ui() -> void:
	master_slider.value = float(settings["master_volume"]) * 100.0
	master_val_label.text = "%3d%%" % roundi(master_slider.value)
	music_slider.value = float(settings["music_volume"]) * 100.0
	music_val_label.text = "%3d%%" % roundi(music_slider.value)
	sfx_slider.value = float(settings["sfx_volume"]) * 100.0
	sfx_val_label.text = "%3d%%" % roundi(sfx_slider.value)
	sens_slider.value = float(settings["controls_sensitivity"]) * 100.0
	sens_val_label.text = "%3d%%" % roundi(sens_slider.value)
	window_mode_btn.text = "SCHERMO: %s" % WINDOW_MODE_LABELS[int(settings["window_mode"])]
	resolution_btn.text = "RISOLUZIONE: %s" % str(settings["resolution"])
	vsync_btn.text = "V-SYNC: ATTIVO" if bool(settings["vsync"]) else "V-SYNC: DISATTIVO"
	fps_limit_btn.text = "LIMITE FPS: ILLIMITATO" if int(settings["fps_limit"]) == 0 \
		else "LIMITE FPS: %d" % int(settings["fps_limit"])
	upscaler_btn.text = "UPSCALER: %s" % UPSCALER_LABELS[int(settings["upscaler"])]
	render_scale_btn.text = "SCALA RENDER: %d%%" % roundi(float(settings["render_scale"]) * 100.0)
	aa_btn.text = "ANTI-ALIASING: %s" % AA_LABELS[int(settings["aa_mode"])]
	invert_y_btn.text = "INVERTI ASSE Y: SI'" if bool(settings["controls_invert_y"]) else "INVERTI ASSE Y: NO"


func _changed() -> void:
	dirty = true
	if not _updating:
		Settings.apply_settings(settings)


func _on_volume_slider(key: String, value: float, label: Label) -> void:
	settings[key] = value / 100.0
	label.text = "%3d%%" % roundi(value)
	_changed()


func _on_sens_slider_changed(value: float) -> void:
	settings["controls_sensitivity"] = value / 100.0
	sens_val_label.text = "%3d%%" % roundi(value)
	_changed()


func _on_cycle_window_mode() -> void:
	settings["window_mode"] = wrapi(int(settings["window_mode"]) + 1, 0, Settings.WINDOW_MODE_COUNT)
	settings["fullscreen"] = settings["window_mode"] != Settings.WINDOW_MODE_WINDOWED
	window_mode_btn.text = "SCHERMO: %s" % WINDOW_MODE_LABELS[int(settings["window_mode"])]
	_changed()


func _on_cycle_resolution() -> void:
	var current := Settings.parse_resolution(str(settings["resolution"]))
	var index := _resolutions.find(current)
	index = wrapi(index + 1, 0, _resolutions.size())
	settings["resolution"] = Settings.resolution_to_string(_resolutions[index])
	resolution_btn.text = "RISOLUZIONE: %s" % settings["resolution"]
	_changed()


func _on_toggle_vsync() -> void:
	settings["vsync"] = not bool(settings["vsync"])
	vsync_btn.text = "V-SYNC: ATTIVO" if settings["vsync"] else "V-SYNC: DISATTIVO"
	_changed()


func _on_cycle_fps_limit() -> void:
	var index := Settings.FPS_LIMITS.find(int(settings["fps_limit"]))
	index = wrapi(index + 1, 0, Settings.FPS_LIMITS.size())
	settings["fps_limit"] = Settings.FPS_LIMITS[index]
	fps_limit_btn.text = "LIMITE FPS: ILLIMITATO" if settings["fps_limit"] == 0 \
		else "LIMITE FPS: %d" % int(settings["fps_limit"])
	_changed()


func _on_cycle_upscaler() -> void:
	settings["upscaler"] = wrapi(int(settings["upscaler"]) + 1, 0, Settings.UPSCALER_COUNT)
	upscaler_btn.text = "UPSCALER: %s" % UPSCALER_LABELS[int(settings["upscaler"])]
	_changed()


func _on_cycle_render_scale() -> void:
	var index := Settings.RENDER_SCALES.find(float(settings["render_scale"]))
	index = wrapi(index + 1, 0, Settings.RENDER_SCALES.size())
	settings["render_scale"] = Settings.RENDER_SCALES[index]
	render_scale_btn.text = "SCALA RENDER: %d%%" % roundi(float(settings["render_scale"]) * 100.0)
	_changed()


func _on_cycle_aa() -> void:
	settings["aa_mode"] = wrapi(int(settings["aa_mode"]) + 1, 0, Settings.AA_COUNT)
	aa_btn.text = "ANTI-ALIASING: %s" % AA_LABELS[int(settings["aa_mode"])]
	_changed()


func _on_toggle_invert_y() -> void:
	settings["controls_invert_y"] = not bool(settings["controls_invert_y"])
	invert_y_btn.text = "INVERTI ASSE Y: SI'" if settings["controls_invert_y"] else "INVERTI ASSE Y: NO"
	_changed()
