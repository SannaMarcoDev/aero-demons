extends Node3D
## Temporary visual comparison: F6 cycles exclusive runtime presets, never saves resources.

# MSAA excluded: switching it triggers GPU device loss in SunshineClouds on D3D12.
const MODES := ["Attuale", "TAA", "Mipmap morbide a distanza"]
var mode := 0
var initial_taa: bool
var initial_blur: float
var label: Label
@onready var terrain_material: Terrain3DMaterial = $TutorialMap/WC_Terrain.material

func _ready() -> void:
	initial_taa = get_viewport().use_taa
	var blur = terrain_material.get_shader_param("depth_blur")
	initial_blur = float(blur) if blur != null else 0.0
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		mode = (mode + 1) % MODES.size()
		get_viewport().use_taa = true if mode == 1 else (initial_taa if mode == 0 else false)
		terrain_material.set_shader_param("depth_blur", 2.0 if mode == 2 else initial_blur)
		label.text = "F6 · Filtro: " + MODES[mode]
		get_viewport().set_input_as_handled()
