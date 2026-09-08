extends Node3D
## Temporary F6 comparison. Runtime only; never saves resources or changes MSAA.

const MODES := ["Attuale", "TAA", "SSAA 1,25x", "SSAA 1,5x", "FSR2 nativo", "FXAA", "Terreno: blending a distanza", "Mipmap morbide a distanza"]
var mode := 0
var initial_taa: bool
var initial_blur: float
var initial_scale: float
var initial_scaling: int
var initial_screen_aa: int
var initial_shader: Shader
var initial_override: bool
var terrain_filter: Shader
var label: Label
@onready var terrain_material: Terrain3DMaterial = $GardaLake/WC_Terrain.material

func _ready() -> void:
	var viewport := get_viewport()
	initial_taa = viewport.use_taa
	initial_scale = viewport.scaling_3d_scale
	initial_scaling = viewport.scaling_3d_mode
	initial_screen_aa = viewport.screen_space_aa
	initial_shader = terrain_material.shader_override
	initial_override = terrain_material.shader_override_enabled
	var blur = terrain_material.get_shader_param("depth_blur")
	initial_blur = float(blur) if blur != null else 0.0
	if DisplayServer.get_name() != "headless":
		var code := initial_shader.code if initial_override and initial_shader else RenderingServer.shader_get_code(terrain_material.get_shader_rid())
		var condition := "region_mip < 0.0 && region_uv.z > -1."
		assert(code.count(condition) == 1, "Terrain shader changed: review distance blending probe")
		terrain_filter = Shader.new()
		# Keep four-cell material blending beyond the native minification cutoff.
		# ponytail: four neighboring cells only; footprint-aware filtering if this falls short.
		terrain_filter.code = code.replace(condition, "region_uv.z > -1.")
	var overlay := CanvasLayer.new()
	overlay.layer = 11
	add_child(overlay)
	label = Label.new()
	label.position = Vector2(24, 150)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	overlay.add_child(label)
	label.text = "F6 · Filtro: " + MODES[mode]

func apply_mode(index: int) -> void:
	mode = wrapi(index, 0, MODES.size())
	var viewport := get_viewport()
	# MSAA excluded: changing it caused D3D12 device loss with SunshineClouds.
	var scaling: int = initial_scaling if mode == 0 else (Viewport.SCALING_3D_MODE_FSR2 if mode == 4 else Viewport.SCALING_3D_MODE_BILINEAR)
	# Leave supersampling before selecting an algorithm that only accepts scale <= 1.
	if scaling != Viewport.SCALING_3D_MODE_BILINEAR and viewport.scaling_3d_scale > 1.0:
		viewport.scaling_3d_scale = 1.0
	viewport.scaling_3d_mode = scaling
	viewport.scaling_3d_scale = initial_scale if mode == 0 else (1.25 if mode == 2 else (1.5 if mode == 3 else 1.0))
	viewport.use_taa = initial_taa if mode == 0 else mode == 1
	viewport.screen_space_aa = initial_screen_aa if mode == 0 else (Viewport.SCREEN_SPACE_AA_FXAA if mode == 5 else Viewport.SCREEN_SPACE_AA_DISABLED)
	terrain_material.shader_override = terrain_filter if mode == 6 else initial_shader
	terrain_material.shader_override_enabled = true if mode == 6 else initial_override
	terrain_material.set_shader_param("depth_blur", 2.0 if mode == 7 else initial_blur)
	label.text = "F6 · Filtro: " + MODES[mode]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		apply_mode(mode + 1)
		get_viewport().set_input_as_handled()
