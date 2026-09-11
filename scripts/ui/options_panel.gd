extends VBoxContainer
class_name OptionsPanel

## Reusable settings panel shared by the main menu and the in-game pause overlay. Loads and
## applies the persisted settings on _ready; call save() when leaving the panel.

const Settings = preload("res://scripts/ui/settings_manager.gd")

const WINDOW_MODE_LABELS: Array[String] = ["FINESTRA", "BORDERLESS", "FULLSCREEN"]
const UPSCALER_LABELS: Array[String] = ["NATIVO", "FSR 1.0", "FSR 2.2"]
const AA_LABELS: Array[String] = ["OFF", "FXAA", "TAA"]
const QUALITY_LABELS: Array[String] = ["PERSONALIZZATO", "BASSO", "MEDIO", "ALTO", "ULTRA"]
const CLOUDS_LABELS: Array[String] = ["SPENTE", "BASSE", "MEDIE", "ALTE", "ULTRA"]
const SHADOWS_LABELS: Array[String] = ["SPENTE", "BASSE", "MEDIE", "ALTE", "ULTRA"]
const TONEMAP_LABELS: Array[String] = ["LINEARE", "REINHARDT", "FILMIC", "ACES", "AGX"]

## Keys driven by the master quality preset; touching one demotes the preset to CUSTOM.
const PRESET_MANAGED: Array[String] = ["clouds_quality", "shadows", "ssao", "ssil", "ssr",
	"glow", "volumetric_fog", "sky_cirrus", "sky_cumulus", "sky_fog"]

var settings: Dictionary = {}
var dirty := false
var _updating := false
var _applying_preset := false
var _resolutions: Array[Vector2i] = []
var _horizon_blur := false

@onready var preset_btn: Button = $Scroll/Sections/PresetBox/PresetBtn
@onready var clouds_btn: Button = $Scroll/Sections/CloudBox/CloudsBtn
@onready var coverage_slider: HSlider = $Scroll/Sections/CloudBox/CoverageRow/CoverageSlider
@onready var coverage_val_label: Label = $Scroll/Sections/CloudBox/CoverageRow/CoverageVal
@onready var cirrus_btn: Button = $Scroll/Sections/SkyBox/CirrusBtn
@onready var cumulus_btn: Button = $Scroll/Sections/SkyBox/CumulusBtn
@onready var sky_fog_btn: Button = $Scroll/Sections/SkyBox/SkyFogBtn
@onready var shadows_btn: Button = $Scroll/Sections/ShadowBox/ShadowsBtn
@onready var ssao_btn: Button = $Scroll/Sections/EffectsBox/SsaoBtn
@onready var ssil_btn: Button = $Scroll/Sections/EffectsBox/SsilBtn
@onready var ssr_btn: Button = $Scroll/Sections/EffectsBox/SsrBtn
@onready var glow_btn: Button = $Scroll/Sections/EffectsBox/GlowBtn
@onready var vol_fog_btn: Button = $Scroll/Sections/EffectsBox/VolFogBtn
@onready var horizon_btn: Button = $Scroll/Sections/EffectsBox/HorizonBtn
@onready var tonemap_btn: Button = $Scroll/Sections/EffectsBox/TonemapBtn
@onready var exposure_slider: HSlider = $Scroll/Sections/EffectsBox/ExposureRow/ExposureSlider
@onready var exposure_val_label: Label = $Scroll/Sections/EffectsBox/ExposureRow/ExposureVal
@onready var upscaler_btn: Button = $Scroll/Sections/RenderBox/UpscalerBtn
@onready var render_scale_btn: Button = $Scroll/Sections/RenderBox/RenderScaleBtn
@onready var aa_btn: Button = $Scroll/Sections/RenderBox/AntiAliasingBtn
@onready var sharpness_slider: HSlider = $Scroll/Sections/RenderBox/SharpnessRow/SharpnessSlider
@onready var sharpness_val_label: Label = $Scroll/Sections/RenderBox/SharpnessRow/SharpnessVal
@onready var window_mode_btn: Button = $Scroll/Sections/DisplayBox/WindowModeBtn
@onready var resolution_btn: Button = $Scroll/Sections/DisplayBox/ResolutionBtn
@onready var vsync_btn: Button = $Scroll/Sections/DisplayBox/VSyncBtn
@onready var fps_limit_btn: Button = $Scroll/Sections/DisplayBox/FpsLimitBtn
@onready var master_slider: HSlider = $Scroll/Sections/AudioBox/MasterRow/MasterSlider
@onready var master_val_label: Label = $Scroll/Sections/AudioBox/MasterRow/MasterVal
@onready var music_slider: HSlider = $Scroll/Sections/AudioBox/MusicRow/MusicSlider
@onready var music_val_label: Label = $Scroll/Sections/AudioBox/MusicRow/MusicVal
@onready var sfx_slider: HSlider = $Scroll/Sections/AudioBox/SFXRow/SFXSlider
@onready var sfx_val_label: Label = $Scroll/Sections/AudioBox/SFXRow/SFXVal
@onready var invert_y_btn: Button = $Scroll/Sections/ControlsBox/InvertYBtn
@onready var sens_slider: HSlider = $Scroll/Sections/ControlsBox/SensRow/SensSlider
@onready var sens_val_label: Label = $Scroll/Sections/ControlsBox/SensRow/SensVal


func _ready() -> void:
	settings = Settings.load_settings()
	_horizon_blur = _load_horizon_blur()
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
	preset_btn.pressed.connect(_on_cycle_preset)
	clouds_btn.pressed.connect(func(): _cycle_enum("clouds_quality", Settings.CLOUDS_COUNT, clouds_btn, "NUVOLE", CLOUDS_LABELS))
	coverage_slider.value_changed.connect(_on_coverage_changed)
	cirrus_btn.pressed.connect(func(): _toggle_bool("sky_cirrus", cirrus_btn, "CIRRI", "ATTIVI", "DISATTIVI"))
	cumulus_btn.pressed.connect(func(): _toggle_bool("sky_cumulus", cumulus_btn, "CUMULI", "ATTIVI", "DISATTIVI"))
	sky_fog_btn.pressed.connect(func(): _toggle_bool("sky_fog", sky_fog_btn, "FOSCHIA", "ATTIVA", "DISATTIVA"))
	shadows_btn.pressed.connect(func(): _cycle_enum("shadows", Settings.SHADOWS_COUNT, shadows_btn, "OMBRE", SHADOWS_LABELS))
	ssao_btn.pressed.connect(func(): _toggle_bool("ssao", ssao_btn, "SSAO"))
	ssil_btn.pressed.connect(func(): _toggle_bool("ssil", ssil_btn, "SSIL"))
	ssr_btn.pressed.connect(func(): _toggle_bool("ssr", ssr_btn, "RIFLESSI SSR", "ATTIVI", "DISATTIVI"))
	glow_btn.pressed.connect(func(): _toggle_bool("glow", glow_btn, "BLOOM"))
	vol_fog_btn.pressed.connect(func(): _toggle_bool("volumetric_fog", vol_fog_btn, "FOG VOLUMETRICA", "ATTIVA", "DISATTIVA"))
	horizon_btn.pressed.connect(_on_toggle_horizon_blur)
	tonemap_btn.pressed.connect(func(): _cycle_enum("tonemap", Settings.TONEMAP_COUNT, tonemap_btn, "TONEMAP", TONEMAP_LABELS))
	exposure_slider.value_changed.connect(_on_exposure_changed)
	upscaler_btn.pressed.connect(_on_cycle_upscaler)
	render_scale_btn.pressed.connect(_on_cycle_render_scale)
	aa_btn.pressed.connect(func(): _cycle_enum("aa_mode", Settings.AA_COUNT, aa_btn, "ANTI-ALIASING", AA_LABELS))
	sharpness_slider.value_changed.connect(_on_sharpness_changed)
	master_slider.value_changed.connect(func(v): _on_volume_slider("master_volume", v, master_val_label))
	music_slider.value_changed.connect(func(v): _on_volume_slider("music_volume", v, music_val_label))
	sfx_slider.value_changed.connect(func(v): _on_volume_slider("sfx_volume", v, sfx_val_label))
	window_mode_btn.pressed.connect(_on_cycle_window_mode)
	resolution_btn.pressed.connect(_on_cycle_resolution)
	vsync_btn.pressed.connect(_on_toggle_vsync)
	fps_limit_btn.pressed.connect(_on_cycle_fps_limit)
	invert_y_btn.pressed.connect(_on_toggle_invert_y)
	sens_slider.value_changed.connect(_on_sens_slider_changed)


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
	preset_btn.text = "PRESET: %s" % QUALITY_LABELS[int(settings["quality_preset"])]
	clouds_btn.text = "NUVOLE: %s" % CLOUDS_LABELS[int(settings["clouds_quality"])]
	coverage_slider.value = float(settings["clouds_coverage"]) * 100.0
	coverage_val_label.text = "%3d%%" % roundi(coverage_slider.value)
	cirrus_btn.text = "CIRRI: ATTIVI" if bool(settings["sky_cirrus"]) else "CIRRI: DISATTIVI"
	cumulus_btn.text = "CUMULI: ATTIVI" if bool(settings["sky_cumulus"]) else "CUMULI: DISATTIVI"
	sky_fog_btn.text = "FOSCHIA: ATTIVA" if bool(settings["sky_fog"]) else "FOSCHIA: DISATTIVA"
	shadows_btn.text = "OMBRE: %s" % SHADOWS_LABELS[int(settings["shadows"])]
	ssao_btn.text = "SSAO: ATTIVO" if bool(settings["ssao"]) else "SSAO: DISATTIVO"
	ssil_btn.text = "SSIL: ATTIVO" if bool(settings["ssil"]) else "SSIL: DISATTIVO"
	ssr_btn.text = "RIFLESSI SSR: ATTIVI" if bool(settings["ssr"]) else "RIFLESSI SSR: DISATTIVI"
	glow_btn.text = "BLOOM: ATTIVO" if bool(settings["glow"]) else "BLOOM: DISATTIVO"
	vol_fog_btn.text = "FOG VOLUMETRICA: ATTIVA" if bool(settings["volumetric_fog"]) else "FOG VOLUMETRICA: DISATTIVA"
	horizon_btn.text = "SFOCATURA ORIZZONTE: ATTIVA" if _horizon_blur else "SFOCATURA ORIZZONTE: DISATTIVA"
	tonemap_btn.text = "TONEMAP: %s" % TONEMAP_LABELS[int(settings["tonemap"])]
	exposure_slider.value = float(settings["exposure"]) * 100.0
	exposure_val_label.text = "%3d%%" % roundi(exposure_slider.value)
	upscaler_btn.text = "UPSCALER: %s" % UPSCALER_LABELS[int(settings["upscaler"])]
	render_scale_btn.text = _render_scale_label(float(settings["render_scale"]))
	aa_btn.text = "ANTI-ALIASING: %s" % AA_LABELS[int(settings["aa_mode"])]
	sharpness_slider.value = float(settings["fsr_sharpness"]) * 100.0
	sharpness_val_label.text = "%.2f" % (sharpness_slider.value / 100.0)
	window_mode_btn.text = "SCHERMO: %s" % WINDOW_MODE_LABELS[int(settings["window_mode"])]
	resolution_btn.text = "RISOLUZIONE: %s" % str(settings["resolution"])
	vsync_btn.text = "V-SYNC: ATTIVO" if bool(settings["vsync"]) else "V-SYNC: DISATTIVO"
	fps_limit_btn.text = "LIMITE FPS: ILLIMITATO" if int(settings["fps_limit"]) == 0 \
		else "LIMITE FPS: %d" % int(settings["fps_limit"])
	master_slider.value = float(settings["master_volume"]) * 100.0
	master_val_label.text = "%3d%%" % roundi(master_slider.value)
	music_slider.value = float(settings["music_volume"]) * 100.0
	music_val_label.text = "%3d%%" % roundi(music_slider.value)
	sfx_slider.value = float(settings["sfx_volume"]) * 100.0
	sfx_val_label.text = "%3d%%" % roundi(sfx_slider.value)
	invert_y_btn.text = "INVERTI ASSE Y: SI'" if bool(settings["controls_invert_y"]) else "INVERTI ASSE Y: NO"
	sens_slider.value = float(settings["controls_sensitivity"]) * 100.0
	sens_val_label.text = "%3d%%" % roundi(sens_slider.value)


func _changed() -> void:
	dirty = true
	if not _updating:
		Settings.apply_settings(settings)


func _mark_custom() -> void:
	if _updating or _applying_preset:
		return
	if int(settings["quality_preset"]) != Settings.QUALITY_CUSTOM:
		settings["quality_preset"] = Settings.QUALITY_CUSTOM
		preset_btn.text = "PRESET: PERSONALIZZATO"


func _cycle_enum(key: String, count: int, btn: Button, prefix: String, labels: Array[String]) -> void:
	settings[key] = wrapi(int(settings[key]) + 1, 0, count)
	btn.text = "%s: %s" % [prefix, labels[int(settings[key])]]
	if key in PRESET_MANAGED:
		_mark_custom()
	_changed()


func _toggle_bool(key: String, btn: Button, prefix: String, on := "ATTIVO", off := "DISATTIVO") -> void:
	settings[key] = not bool(settings[key])
	btn.text = "%s: %s" % [prefix, on if settings[key] else off]
	if key in PRESET_MANAGED:
		_mark_custom()
	_changed()


func _on_cycle_preset() -> void:
	settings["quality_preset"] = wrapi(int(settings["quality_preset"]) + 1, 0, Settings.QUALITY_COUNT)
	var preset := int(settings["quality_preset"])
	if preset == Settings.QUALITY_CUSTOM:
		preset_btn.text = "PRESET: PERSONALIZZATO"
	else:
		_applying_preset = true
		_updating = true
		for key in Settings.QUALITY_PRESETS[preset]:
			settings[key] = Settings.QUALITY_PRESETS[preset][key]
		_refresh_ui()
		_updating = false
		_applying_preset = false
	_changed()


func _on_coverage_changed(value: float) -> void:
	settings["clouds_coverage"] = value / 100.0
	coverage_val_label.text = "%3d%%" % roundi(value)
	_changed()


func _on_exposure_changed(value: float) -> void:
	settings["exposure"] = value / 100.0
	exposure_val_label.text = "%3d%%" % roundi(value)
	_changed()


func _on_sharpness_changed(value: float) -> void:
	settings["fsr_sharpness"] = value / 100.0
	sharpness_val_label.text = "%.2f" % (value / 100.0)
	_changed()


func _load_horizon_blur() -> bool:
	var config := ConfigFile.new()
	if config.load(Settings.GRAPHICS_CFG_PATH) == OK:
		var saved = config.get_value("graphics", "horizon_blur", false)
		if saved is bool:
			return saved
	return false


## Horizon DOF lives in graphics.cfg, owned by HorizonGraphics (F7). The button mirrors it:
## saves the file and nudges any live HorizonGraphics so the change is visible at once.
func _on_toggle_horizon_blur() -> void:
	_horizon_blur = not _horizon_blur
	var config := ConfigFile.new()
	var error := config.load(Settings.GRAPHICS_CFG_PATH)
	if error == OK or error == ERR_FILE_NOT_FOUND:
		config.set_value("graphics", "horizon_blur", _horizon_blur)
		if config.save(Settings.GRAPHICS_CFG_PATH) != OK:
			push_warning("Cannot save horizon_blur to %s" % Settings.GRAPHICS_CFG_PATH)
	for node in get_tree().root.find_children("HorizonGraphics", "CanvasLayer", true, false):
		node.call("apply_blur", _horizon_blur)
	horizon_btn.text = "SFOCATURA ORIZZONTE: ATTIVA" if _horizon_blur else "SFOCATURA ORIZZONTE: DISATTIVA"


func _render_scale_label(scale: float) -> String:
	var text := "SCALA RENDER: %d%%" % roundi(scale * 100.0)
	if scale > 1.0:
		text += " (SSAA)"
	return text


## Supersampling (>100%) is a native-only option; FSR modes reject scale > 1.
func _render_scale_options() -> Array[float]:
	var options: Array[float] = []
	var native := int(settings["upscaler"]) == Settings.UPSCALER_OFF
	for scale in Settings.RENDER_SCALES:
		if native or scale <= 1.0:
			options.append(scale)
	return options


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
	if int(settings["upscaler"]) != Settings.UPSCALER_OFF and float(settings["render_scale"]) > 1.0:
		settings["render_scale"] = 1.0
		render_scale_btn.text = _render_scale_label(1.0)
	_changed()


func _on_cycle_render_scale() -> void:
	var options := _render_scale_options()
	var index := options.find(float(settings["render_scale"]))
	if index < 0:
		index = options.size() - 1
	index = wrapi(index + 1, 0, options.size())
	settings["render_scale"] = options[index]
	render_scale_btn.text = _render_scale_label(options[index])
	_changed()


func _on_toggle_invert_y() -> void:
	settings["controls_invert_y"] = not bool(settings["controls_invert_y"])
	invert_y_btn.text = "INVERTI ASSE Y: SI'" if settings["controls_invert_y"] else "INVERTI ASSE Y: NO"
	_changed()
