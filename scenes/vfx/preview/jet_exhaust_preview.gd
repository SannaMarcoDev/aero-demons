extends Node3D
## Isolated look-development scene. All geometry is new, procedural test-fixture geometry.
const EXHAUST = preload("res://scenes/vfx/jet_exhaust.tscn")
const VIEWS = ["Rear", "Side", "Rear quarter", "Close", "Gameplay", "Twin engines"]
var engine: Node3D
var twin: Node3D
var camera: Camera3D
var slider: HSlider
var caption: Label
var ui: CanvasLayer
var view_picker: OptionButton
var view_index: int = 2
var time: float = 0.0
var auto_sweep: bool = false

func material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = 0.65
	return result

func mesh_node(mesh: Mesh, mat: Material, at: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	parent.add_child(node)
	node.position = at
	return node

func box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_node(mesh, mat, at)

func nozzle(at: Vector3) -> Node3D:
	var rig := Node3D.new()
	add_child(rig)
	rig.position = at
	var metal := material(Color(0.18, 0.19, 0.20), 0.8)
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.48
	barrel.bottom_radius = 0.64
	barrel.height = 1.4
	barrel.radial_segments = 48
	barrel.cap_top = false
	barrel.cap_bottom = false
	mesh_node(barrel, metal, Vector3(0, 0, -0.7), rig).rotation.x = PI / 2.0
	var back := CylinderMesh.new()
	back.top_radius = 0.6
	back.bottom_radius = 0.6
	back.height = 0.04
	mesh_node(back, material(Color(0.018, 0.021, 0.025)), Vector3(0, 0, -1.3), rig).rotation.x = PI / 2.0
	var rim := TorusMesh.new()
	rim.inner_radius = 0.452
	rim.outer_radius = 0.49
	mesh_node(rim, metal, Vector3.ZERO, rig).rotation.x = PI / 2.0
	for i in 18:
		var angle := i * TAU / 18.0
		var petal := BoxMesh.new()
		petal.size = Vector3(0.035, 0.025, 1.1)
		var rib := mesh_node(petal, metal, Vector3(sin(angle) * 0.548, cos(angle) * 0.548, -0.63), rig)
		rib.rotation = Vector3(cos(angle) * -0.11, sin(angle) * 0.11, -angle)
	var effect := EXHAUST.instantiate()
	effect.name = "JetExhaust"
	rig.add_child(effect)
	return rig

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.30, 0.39, 0.48)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.77, 0.9)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mat := material(Color(0.22, 0.25, 0.28))
	var wall_mat := material(Color(0.39, 0.43, 0.46))
	var stripe_mat := material(Color(0.15, 0.19, 0.22))
	box(Vector3(100, 0.2, 100), Vector3(0, -0.11, 0), floor_mat)
	box(Vector3(0.15, 10, 60), Vector3(-8, 4.9, 0), wall_mat)
	box(Vector3(25, 10, 0.15), Vector3(0, 4.9, -7), wall_mat)
	for i in range(-28, 29):
		box(Vector3(0.03, 0.006, 60), Vector3(i, 0, 0), stripe_mat)
		box(Vector3(60, 0.006, 0.03), Vector3(0, 0, i), stripe_mat)
		box(Vector3(0.025, 9, 0.055), Vector3(-7.9, 4.5, i), stripe_mat)
	for i in range(-12, 13):
		box(Vector3(0.055, 9, 0.025), Vector3(i, 4.5, -6.9), stripe_mat)
	for i in range(1, 10):
		box(Vector3(0.025, 0.03, 60), Vector3(-7.9, i, 0), stripe_mat)
		box(Vector3(25, 0.03, 0.025), Vector3(0, i, -6.9), stripe_mat)
	box(Vector3(0.35, 1.15, 0.5), Vector3(0, 0.575, -0.7), stripe_mat)
	engine = nozzle(Vector3(0, 1.9, 0))
	twin = nozzle(Vector3(1.65, 1.9, 0))
	twin.visible = false
	camera = Camera3D.new()
	camera.fov = 48
	camera.near = 0.05
	add_child(camera)
	camera.make_current()
	_build_ui()
	set_view(2)
	slider.value = 1.0

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.037, 0.05, 0.90)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.text = "JET EXHAUST  /  REAL-TIME STUDY"
	column.add_child(title)
	caption = Label.new()
	column.add_child(caption)
	slider = HSlider.new()
	slider.custom_minimum_size = Vector2(410, 28)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	column.add_child(slider)
	var presets := HBoxContainer.new()
	column.add_child(presets)
	for value in [0.0, 0.2, 0.55, 0.8, 1.0]:
		var button := Button.new()
		button.text = "%d%%" % (value * 100)
		button.pressed.connect(func(): slider.value = value)
		presets.add_child(button)
	view_picker = OptionButton.new()
	for label in VIEWS:
		view_picker.add_item(label)
	view_picker.select(view_index)
	view_picker.item_selected.connect(set_view)
	column.add_child(view_picker)
	var hint := Label.new()
	hint.text = "1–6: views   T: throttle sweep   H: hide UI
B: afterburner on/off   D: distortion on/off"
	column.add_child(hint)

func set_view(index: int) -> void:
	view_index = clampi(index, 0, 5)
	view_picker.select(view_index)
	twin.visible = view_index == 5
	var positions := [Vector3(0, 2.0, 11), Vector3(11, 2.8, 3.0), Vector3(7, 4.3, 10), Vector3(2.0, 2.65, 4.3), Vector3(28, 12, 43), Vector3(5, 3.8, 11)]
	var target := Vector3(0, 1.9, 2.0)
	if view_index == 0:
		target = Vector3(0, 1.9, 0)
	elif view_index == 1:
		target.z = 3.0
	elif view_index == 3:
		target.z = 0.7
	elif view_index == 5:
		target.x = 0.8
	camera.position = positions[view_index]
	camera.look_at(target)

func _process(delta: float) -> void:
	time += delta
	if auto_sweep:
		slider.value = 0.5 - 0.5 * cos(time * 0.45)
	engine.get_node("JetExhaust").throttle = slider.value
	twin.get_node("JetExhaust").throttle = slider.value * 0.65 if twin.visible else 0.0
	caption.text = "%s   |   Throttle %3.0f%%   |   %.0f FPS" % [VIEWS[view_index], slider.value * 100, Engine.get_frames_per_second()]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_6:
		set_view(event.keycode - KEY_1)
	elif event.keycode == KEY_T:
		auto_sweep = not auto_sweep
	elif event.keycode == KEY_H:
		ui.visible = not ui.visible
	elif event.keycode == KEY_B:
		var effect := engine.get_node("JetExhaust")
		effect.afterburner_enabled = not effect.afterburner_enabled
	elif event.keycode == KEY_D:
		var effect := engine.get_node("JetExhaust")
		effect.heat_distortion = 12.0 if effect.heat_distortion == 0.0 else 0.0
