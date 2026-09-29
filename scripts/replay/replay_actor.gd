extends Node3D
## A visual proxy, never an active combatant. Scene paths come from ReplayData's allowlist.
const Data = preload("res://scripts/replay/replay_data.gd")

var track: Dictionary
var visual: Node3D
var bindings: Array = []
var particles: Array[GPUParticles3D] = []
var exhausts: Array[Node] = []
var clock_materials: Array[ShaderMaterial] = []
var sound: AudioStreamPlayer3D
var _last_position := Vector3.ZERO
var _last_time := -1.0
var _smoke_budgets := [0.0, 0.0]
static var _clock_shaders: Dictionary = {}

func setup(description: Dictionary) -> void:
	track = description
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if track.scene == "audio":
		sound = AudioStreamPlayer3D.new()
		sound.stream = load(track.sound) as AudioStream
		sound.bus = &"SFX"
		sound.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		sound.max_distance = 30000.0
		visual = sound
	else:
		visual = (load(track.scene) as PackedScene).instantiate() as Node3D
		if not track.model.is_empty():
			var old_model := visual.get_node_or_null("AircraftModel")
			if old_model != null:
				visual.remove_child(old_model)
				old_model.free()
			var model := (load(track.model) as PackedScene).instantiate()
			model.name = "AircraftModel"
			visual.add_child(model)
		for property in track.settings:
			if visual.get(property) != null:
				visual.set(property, track.settings[property])
		if visual.get("autoplay") != null:
			visual.set("autoplay", false)
		_strip_gameplay(visual)
	add_child(visual)
	if track.scene == "res://scenes/weapons/missile.tscn":
		visual.set("audio_enabled", false)
		visual.call("_apply_visual")
	_freeze(visual)
	visual.transform = Transform3D.IDENTITY
	for exhaust in exhausts:
		exhaust.set("_material", exhaust.get_node("Volume").material_override)
	for channel in track.channels:
		var node := visual.get_node_or_null(NodePath(channel.path))
		if node == null:
			continue
		var property: String = channel.property
		if property == "alpha_multiplier" and node is GeometryInstance3D and node.material_override is ShaderMaterial:
			bindings.append({"node": node, "channel": channel})
		elif property == "playback" and node is AudioStreamPlayer3D:
			bindings.append({"node": node, "channel": channel})
		elif node.get(property) != null and typeof(node.get(property)) == typeof(channel.keys[0][1]):
			bindings.append({"node": node, "channel": channel})
	_last_position = Data.value_at(track.poses, track.born).origin

func _strip_gameplay(node: Node) -> void:
	for group in node.get_groups():
		node.remove_from_group(group)
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is CollisionShape3D:
		node.disabled = true
	if not Data.script_path(node) in Data.VISUAL_SCRIPTS:
		node.set_script(null)
	for child in node.get_children():
		if child is Camera3D or (Data.is_actor(child) and not child is AudioStreamPlayer3D):
			node.remove_child(child)
			child.free()
		else:
			_strip_gameplay(child)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	if node is AudioStreamPlayer3D or node is AudioStreamPlayer:
		node.stop()
		node.stream_paused = true
	if node is Timer:
		node.stop()
	if node is AnimationPlayer:
		node.stop(true)
		node.active = false
	if node is GPUParticles3D:
		node.use_fixed_seed = true
		node.seed = absi(hash(track.label + str(visual.get_path_to(node)))) % 2147483647
		node.speed_scale = 0.0
		node.restart(true)
		node.emitting = false
		node.visibility_aabb = AABB(Vector3.ONE * -20000.0, Vector3.ONE * 40000.0)
		particles.append(node)
		for index in node.draw_passes:
			var mesh: Mesh = node.get_draw_pass_mesh(index)
			if mesh is PrimitiveMesh and mesh.material is ShaderMaterial:
				mesh = mesh.duplicate()
				mesh.material = _clock_material(mesh.material)
				node.set_draw_pass_mesh(index, mesh)
	if node is GeometryInstance3D and node.material_override is ShaderMaterial:
		node.material_override = _clock_material(node.material_override)
	if Data.script_path(node) == "res://scripts/vfx/jet_exhaust.gd":
		exhausts.append(node)
	for child in node.get_children():
		_freeze(child)

func _clock_material(source: ShaderMaterial) -> ShaderMaterial:
	var result := source.duplicate() as ShaderMaterial
	if source.shader == null or not "TIME" in source.shader.code:
		return result
	var id := source.shader.get_instance_id()
	if not _clock_shaders.has(id):
		var regex := RegEx.new()
		regex.compile("\\bTIME\\b")
		var code := regex.sub(source.shader.code, "replay_clock", true)
		var declaration := code.find(";") + 1
		code = code.insert(declaration, "\nuniform float replay_clock = 0.0;\n")
		var shader := Shader.new()
		shader.code = code
		_clock_shaders[id] = shader
	result.shader = _clock_shaders[id]
	clock_materials.append(result)
	return result

func render_at(time: float, step: float, speed: float, audible: bool) -> void:
	var present: bool = time >= track.born and time <= track.end + 0.00001
	visible = present
	if not present:
		if sound != null:
			sound.stop()
		return
	global_transform = Data.value_at(track.poses, time, true, true)
	var expected_audio := 0.0
	var playing := false
	var pitch := 1.0
	for binding in bindings:
		var node: Node = binding.node
		var channel: Dictionary = binding.channel
		var property: String = channel.property
		var value: Variant = Data.value_at(channel.keys, time)
		if property == "alpha_multiplier":
			node.material_override.set_shader_parameter("alpha_multiplier", value)
			continue
		if sound != null:
			match property:
				"playback":
					expected_audio = value
					continue
				"playing":
					playing = value
					continue
				"pitch_scale":
					pitch = value
					continue
		if property == "emitting" and node is GPUParticles3D:
			if value and not node.emitting:
				node.restart(true)
		node.set(property, value)
	# Jet visibility is camera-dependent: recompute it for the replay's camera.
	for exhaust in exhausts:
		exhaust.call("_process", 0.0)
	for material in clock_materials:
		material.set_shader_parameter("replay_clock", time)
	if track.scene == "res://scenes/weapons/missile.tscn":
		# Also maps old particle-flame recordings onto the new continuous plume.
		visual.call("_update_flame")
		if step > 0.0 and not visual.get("_ballistic"):
			_emit_missile_trail(step)
	for emitter in particles:
		if step > 0.0:
			emitter.request_particles_process(step if emitter.emitting else 0.0, 0.0 if emitter.emitting else step)
	if sound != null:
		if not audible or not playing:
			sound.stop()
		else:
			sound.pitch_scale = clampf(pitch * maxf(speed, 0.01), 0.01, 4.0)
			sound.stream_paused = speed <= 0.0
			if speed > 0.0 and (not sound.playing or absf(sound.get_playback_position() - expected_audio) > 0.2):
				sound.play(maxf(expected_audio, 0.0))
	_last_position = visual.call("_flame_origin") if track.scene == "res://scenes/weapons/missile.tscn" else global_position
	_last_time = time

func _emit_missile_trail(step: float) -> void:
	var to: Vector3 = visual.call("_flame_origin")
	var from := _last_position if _last_time >= 0.0 else to
	for index in 2:
		var emitter := visual.get_node_or_null("SmokeCore" if index == 0 else "SmokeTrail") as GPUParticles3D
		_smoke_budgets[index] = visual.call("_emit_particle_segment", emitter, from, to, step, _smoke_budgets[index], float(visual.get("_smoke_intensity")))

func reset_effects() -> void:
	_last_time = -1.0
	_smoke_budgets = [0.0, 0.0]
	for emitter in particles:
		emitter.restart(true)
		emitter.emitting = false
	if sound != null:
		sound.stop()
