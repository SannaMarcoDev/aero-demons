extends Node
## Autoload: visual state capture at 30 Hz, independent of the player's camera.
const Data = preload("res://scripts/replay/replay_data.gd")
const SAMPLE_STEP := 1.0 / 30.0

var recording := false
var data: Dictionary = {}
var recording_path := ""
var selected_path := ""
var message := ""
var _clock := 0.0
var _next_sample := 0.0
var _bytes := 0
var _live: Dictionary = {}
var _hint: Label
var _notice_until := 0
var _confirm: ConfirmationDialog
var _was_paused := false
var _mouse_mode_before_dialog := Input.MOUSE_MODE_VISIBLE
var _unsaved := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	process_physics_priority = 100000
	get_tree().scene_changed.connect(_scene_changed)
	get_tree().node_added.connect(_node_added)
	_scene_changed.call_deferred() # The initial scene does not emit scene_changed.
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	_hint = Label.new()
	_hint.position = Vector2(20, 12)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0))
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_x", 1)
	_hint.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_hint)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Apri replay"
	_confirm.dialog_text = "Salvare la registrazione e aprire il replay?\nLa missione corrente verrà chiusa."
	_confirm.confirmed.connect(_open_confirmed)
	_confirm.canceled.connect(func():
		get_tree().paused = _was_paused
		Input.mouse_mode = _mouse_mode_before_dialog)
	layer.add_child(_confirm)

func _scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path in Data.LEVELS:
		start_recording()

func start_recording() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path in Data.LEVELS or recording:
		return
	if _unsaved and not save_recording().is_empty():
		return # Keep the previous take if disk writes failed.
	_clock = 0.0
	_next_sample = SAMPLE_STEP
	_bytes = 0
	_live.clear()
	var map_transform := Transform3D.IDENTITY
	for child in scene.get_children():
		if child is Node3D and child.scene_file_path == Data.LEVELS[scene.scene_file_path]:
			map_transform = child.global_transform
	data = {"version": Data.VERSION, "engine": Engine.get_version_info().string,
		"level": scene.scene_file_path, "map_transform": map_transform,
		"duration": 0.0, "actors": [], "camera": [], "fov": [], "shot": [], "shot_fov": []}
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	recording_path = Data.DIRECTORY.path_join("%s_%s_%d.aeroreplay" % [stamp, scene.name, Time.get_ticks_msec()])
	recording = true
	if not scene.tree_exiting.is_connected(_finish_scene):
		scene.tree_exiting.connect(_finish_scene, CONNECT_ONE_SHOT)
	_scan(scene)
	_sample_camera()
	notify("Registrazione avviata · tutti gli attori")
	print("REPLAY_RECORDING_STARTED ", recording_path)

func _scan(node: Node) -> void:
	if Data.is_actor(node):
		_register(node)
	for child in node.get_children():
		_scan(child)

func _node_added(node: Node) -> void:
	if recording and Data.is_actor(node):
		# Launch/configuration normally happens immediately after add_child().
		_register.call_deferred(node)

func _register(node) -> void:
	if not recording or not is_instance_valid(node) or not node.is_inside_tree() or _live.has(node.get_instance_id()):
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.is_ancestor_of(node):
		return
	if node is AudioStreamPlayer3D and (node.stream == null or not Data.sound_allowed(node.stream.resource_path)):
		return
	var actor := {"scene": "audio" if node is AudioStreamPlayer3D else node.scene_file_path,
		"label": str(node.get("label")) if node.get("label") != null else str(node.name),
		"model": "", "born": _clock, "end": _clock, "poses": [], "channels": [], "settings": {}}
	if node is AudioStreamPlayer3D:
		actor.sound = node.stream.resource_path
	var model: Node = node.get_node_or_null("AircraftModel")
	if model != null and model.scene_file_path in Data.MODELS:
		actor.model = model.scene_file_path
	for property in ["missile_id", "overall_scale", "intensity", "smoke_amount", "sparks_amount", "effect_seed", "autoplay", "local_coords", "light_enable"]:
		var value: Variant = node.get(property)
		if value != null:
			actor.settings[property] = value
	var bindings: Array = []
	_collect_channels(node, node, actor.channels, bindings)
	var index: int = data.actors.size()
	data.actors.append(actor)
	_live[node.get_instance_id()] = {"node": node, "index": index, "bindings": bindings}
	var on_exit := _actor_exiting.bind(node.get_instance_id())
	if not node.tree_exiting.is_connected(on_exit):
		node.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	_capture(_live[node.get_instance_id()])

func _collect_channels(root: Node, node: Node, channels: Array, bindings: Array) -> void:
	if node != root and (Data.is_actor(node) or node is Camera3D or node is CollisionObject3D or node is CollisionShape3D):
		return
	var properties: Array[String] = []
	if node is Node3D:
		if node != root:
			properties.append("transform")
		properties.append("visible")
	if node is GPUParticles3D:
		# Rendering outside the original camera must not depend on its culling.
		properties.append_array(["emitting", "amount_ratio"])
	if node is GeometryInstance3D and node.material_override is ShaderMaterial and node.material_override.get_shader_parameter("alpha_multiplier") != null:
		properties.append("alpha_multiplier")
	if node is Light3D:
		properties.append_array(["light_energy", "light_color"])
		if node is OmniLight3D:
			properties.append("omni_range")
	var script := Data.script_path(node)
	if script == "res://scenes/vfx/jet_exhaust.gd":
		properties.append_array(["_power", "_clock", "throttle"])
	if script == "res://scripts/vfx/damage_fire.gd":
		properties.append("intensity")
	if script == "res://scripts/weapons/missile.gd":
		properties.append_array(["_ballistic", "_flame_emission_scale", "_smoke_intensity"])
	if node is AudioStreamPlayer3D:
		properties.append_array(["playing", "pitch_scale", "volume_db", "playback"])
	for property in properties:
		channels.append({"path": str(root.get_path_to(node)), "property": property, "keys": []})
		bindings.append({"node": node, "property": property})
	for child in node.get_children():
		_collect_channels(root, child, channels, bindings)

func _capture(entry: Dictionary) -> void:
	if not is_instance_valid(entry.node):
		return
	var node: Node3D = entry.node
	if not node.is_inside_tree():
		return
	var actor: Dictionary = data.actors[entry.index]
	_append_key(actor.poses, node.global_transform, false)
	actor.end = _clock
	for i in entry.bindings.size():
		var binding: Dictionary = entry.bindings[i]
		if not is_instance_valid(binding.node):
			continue
		var value: Variant
		match binding.property:
			"playback": value = binding.node.get_playback_position()
			"alpha_multiplier": value = binding.node.material_override.get_shader_parameter("alpha_multiplier")
			"visible": value = binding.node.is_visible_in_tree() if binding.node == node else binding.node.visible
			_: value = binding.node.get(binding.property)
		if value != null:
			_append_key(actor.channels[i].keys, value, true)

func _append_key(keys: Array, value: Variant, sparse: bool) -> void:
	_unsaved = true
	if not keys.is_empty() and is_equal_approx(float(keys.back()[0]), _clock):
		keys.back()[1] = value
		return
	if sparse and not keys.is_empty() and keys.back()[1] == value:
		return
	# Keep a hold key before a change: sparse interpolation must not animate early.
	if sparse and not keys.is_empty() and float(keys.back()[0]) < _clock - SAMPLE_STEP * 1.5:
		keys.append([maxf(0.0, _clock - SAMPLE_STEP), keys.back()[1]])
		_bytes += 128
	keys.append([_clock, value])
	_bytes += 128

func _actor_exiting(id: int) -> void:
	if not recording or not _live.has(id):
		return
	var entry: Dictionary = _live[id]
	_capture(entry)
	# Reparented tutorial interceptors keep their identity and history.
	if is_instance_valid(entry.node) and not entry.node.is_queued_for_deletion():
		_check_reparent.call_deferred(id)
		return
	_live.erase(id)

func _check_reparent(id: int) -> void:
	if not recording or not _live.has(id):
		return
	if not is_instance_valid(_live[id].node):
		_live.erase(id)
		return
	var node: Node = _live[id].node
	if node.is_inside_tree() and get_tree().current_scene.is_ancestor_of(node):
		node.tree_exiting.connect(_actor_exiting.bind(id), CONNECT_ONE_SHOT)
	else:
		data.actors[_live[id].index].end = _clock
		_live.erase(id)

func _sample_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_append_key(data.camera, camera.global_transform, false)
		_append_key(data.fov, camera.fov, true)

func _physics_process(delta: float) -> void:
	if not recording or get_tree().paused:
		return
	_clock += delta
	data.duration = _clock
	if _clock + 0.000001 < _next_sample:
		return
	_next_sample = _clock + SAMPLE_STEP
	for entry in _live.values():
		_capture(entry)
	_sample_camera()
	if _clock >= Data.MAX_SECONDS or _bytes >= (Data.MAX_BYTES >> 1):
		stop_recording()
		notify("Registrazione salvata e fermata: limite durata/memoria raggiunto.", 20)

func save_recording() -> String:
	if data.is_empty() or data.get("camera", []).is_empty():
		return "Nessuna registrazione da salvare."
	if recording:
		data.duration = _clock
		for entry in _live.values():
			_capture(entry)
		_sample_camera()
	var error := Data.save_file(recording_path, data)
	if error.is_empty():
		selected_path = recording_path
		_unsaved = false
		notify("Replay salvato: " + recording_path.get_file())
		print("REPLAY_SAVED ", recording_path, " actors=", data.actors.size(), " seconds=", _clock)
	else:
		notify(error, 20)
	return error

func stop_recording() -> String:
	if not recording:
		return ""
	var error := save_recording()
	recording = false
	_live.clear()
	return error

func _finish_scene() -> void:
	if recording:
		stop_recording()

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == Data.VIEWER:
		return # The viewer saves its camera edit before accepting a close.
	var error := stop_recording() if recording else save_recording() if _unsaved else ""
	if error.is_empty():
		get_tree().quit()

func notify(text: String, seconds := 5) -> void:
	message = text
	_notice_until = Time.get_ticks_msec() + seconds * 1000

func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	_hint.visible = scene != null and scene.scene_file_path in Data.LEVELS
	if not _hint.visible:
		return
	_hint.text = ("● REC %02d:%02d · %.1f MiB" % [floori(_clock / 60.0), int(_clock) % 60, _bytes / 1048576.0]) if recording else "REPLAY · registrazione ferma"
	_hint.text += "   F6 avvia/ferma · F9 salva · F7 rivedi"
	if Time.get_ticks_msec() < _notice_until:
		_hint.text += "\n" + message

func _input(event: InputEvent) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path in Data.LEVELS or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F6:
			if recording:
				stop_recording()
			else:
				start_recording()
		KEY_F9:
			save_recording()
		KEY_F7:
			if _confirm.visible:
				return
			_was_paused = get_tree().paused
			_mouse_mode_before_dialog = Input.mouse_mode
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_confirm.popup_centered()
		_:
			return
	get_viewport().set_input_as_handled()

func _open_confirmed() -> void:
	var error := stop_recording() if recording else save_recording() if _unsaved else ""
	if not error.is_empty():
		get_tree().paused = _was_paused
		Input.mouse_mode = _mouse_mode_before_dialog
		return
	get_tree().paused = false
	GameSession.change_scene(get_tree(), Data.VIEWER)
