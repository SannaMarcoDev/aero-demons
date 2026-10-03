@tool
class_name CloudLayer3D
extends Node3D

## Global volumetric cloud layer. Position, rotation and scale do not move the
## field: altitudes are world-space Y in meters. Requires a RenderingDevice.
## Noise/weather are generated at startup; altitude, coverage, density and sun
## direction changes rebuild the existing shape/light caches, not the weather.

@export_group("Editor")
## Render the actual clouds in the 3D editor. Initial generation takes a few
## seconds. Disable to release preview resources; runtime is unaffected.
@export var editor_preview := false:
	set(value):
		editor_preview = value
		_queue_editor_update()

@export_group("Scene")
@export var world_environment: WorldEnvironment:
	set(value):
		world_environment = value
		_queue_editor_update()
@export var sun: DirectionalLight3D:
	set(value):
		sun = value
		_apply_settings()

@export_group("Clouds")
## Original, sparse banks, a nearly continuous sea, or isolated tall cumuli.
## Switching rebuilds shape/light caches; it does not change altitude or light.
@export var preset: CloudNoiseGen.Preset = CloudNoiseGen.Preset.ORIGINAL:
	set(value):
		preset = value
		_apply_settings()
@export var clouds_enabled := true:
	set(value):
		clouds_enabled = value
		_apply_settings()
## Lower bake bound, not a shared cloud-base altitude.
@export var deck_base := 2000.0:
	set(value):
		deck_base = value
		_apply_settings()
## Upper bake bound, not a shared cloud-top altitude. Must exceed deck_base.
@export var deck_top := 15000.0:
	set(value):
		deck_top = value
		_apply_settings()
@export_range(0.0, 2.0, 0.01, "or_greater") var coverage := 1.18:
	set(value):
		coverage = maxf(0.0, value)
		_apply_settings()
@export_range(0.0, 0.02, 0.0001, "or_greater") var density_scale := 0.0035:
	set(value):
		density_scale = maxf(0.0, value)
		_apply_settings()
## Darker, more contrasted cloud bases: the cloud above hides the sky and
## scattered sunlight fades faster with depth. 0 = original look, 1 = physical
## occlusion, above 1 = stylized. Runtime and editor preview.
@export_range(0.0, 1.0, 0.01, "or_greater") var base_darkening := 0.0:
	set(value):
		base_darkening = maxf(0.0, value)
		_apply_settings()
@export_range(1, 4096, 1, "or_greater") var max_steps := 1024:
	set(value):
		max_steps = maxi(1, value)
		_apply_settings()

@export_group("Atmosphere")
## Aerial perspective on terrain, water and clouds: one shared air model.
## Disabled: clouds fall back to their original distance haze, ground is clear.
@export var atmosphere_enabled := true:
	set(value):
		atmosphere_enabled = value
		_apply_settings()
## Distance at which haze veils 63% of the scene at the base altitude.
@export_range(1000.0, 500000.0, 100.0, "or_greater", "suffix:m") var haze_distance := 45000.0:
	set(value):
		haze_distance = maxf(1.0, value)
		_apply_settings()
## World Y of the densest haze (valley floor / lake level).
@export var haze_base_altitude := 0.0:
	set(value):
		haze_base_altitude = value
		_apply_settings()
## Haze thins by 63% every this many meters above the base.
@export_range(100.0, 10000.0, 10.0, "or_greater", "suffix:m") var haze_height := 1500.0:
	set(value):
		haze_height = maxf(1.0, value)
		_apply_settings()
## Rayleigh air giving distance its blue cast. 1 = physical sea-level density.
@export_range(0.0, 4.0, 0.01, "or_greater") var air_density := 1.0:
	set(value):
		air_density = maxf(0.0, value)
		_apply_settings()
## Sky light scattered by the air; multiplied by the sun color and energy.
@export var haze_color := Color(0.50, 0.57, 0.64):
	set(value):
		haze_color = value
		_apply_settings()
## Extra brightening of the haze looking toward the sun.
@export_range(0.0, 2.0, 0.01, "or_greater") var haze_sun_scattering := 0.30:
	set(value):
		haze_sun_scattering = maxf(0.0, value)
		_apply_settings()
## Share of the haze light coming from the whole sky. The rest is direct sun,
## which the clouds can shadow. Lower = deeper shadows and stronger shafts.
@export_range(0.0, 1.0, 0.01) var haze_sky_light := 0.35:
	set(value):
		haze_sky_light = clampf(value, 0.0, 1.0)
		_apply_settings()
## How much cloud shadows darken the air: light shafts, shadowed haze under
## cloud banks and toward the horizon. Uses the Cloud Shadows cache: needs
## shadows enabled and at least one registered receiver.
@export_range(0.0, 1.0, 0.01) var haze_cloud_shadows := 1.0:
	set(value):
		haze_cloud_shadows = clampf(value, 0.0, 1.0)
		_apply_settings()
## How high the haze climbs over the sky above the horizon, blending it into
## the ground haze below. 0 = sky untouched, 1 = physical haze, higher = wider.
@export_range(0.0, 8.0, 0.01, "or_greater") var horizon_haze := 1.0:
	set(value):
		horizon_haze = maxf(0.0, value)
		_apply_settings()

@export_group("Cloud Shadows")
## Receivers must use cloud_receiver.gdshader or include cloud_shadow.gdshaderinc.
## Register each material once; moving/spawned objects need no per-frame updates.
@export var shadow_materials: Array[ShaderMaterial] = []:
	set(value):
		shadow_materials = value
		_sync_shadows()
@export var shadows_enabled := true:
	set(value):
		shadows_enabled = value
		_sync_shadows()
## Horizontal resolution over the 100 km tile. 512 + mipmaps uses 86 MiB VRAM.
@export_enum("256:256", "512:512", "1024:1024") var shadow_resolution := 512:
	set(value):
		shadow_resolution = value if value in [256, 512, 1024] else 512
		_sync_shadows()
## How much darker everything under the clouds is than in the open: the
## cloud also hides the sky, so the shadow removes that share of ambient light
## and reflections on receivers and of skylight in the air (haze in front of
## terrain and clouds). 0 = only direct sun is shadowed, 1 = darkest.
@export_range(0.0, 1.0, 0.01) var shadow_darkness := 0.0:
	set(value):
		shadow_darkness = clampf(value, 0.0, 1.0)
		_sync_shadows()
		_apply_settings()

var _shadow_pass: CloudShadowPass
var _runtime_shadow_materials: Array[Resource] = []
var _transparency: CloudTransparency
var _msaa_copy: MeshInstance3D


# Godot's later MSAA resolve otherwise overwrites compute edits made POST_SKY.
# Restore the resolved back buffer before VFX, not their rendering priorities.
func _create_msaa_copy() -> void:
	_msaa_copy = MeshInstance3D.new()
	_msaa_copy.name = "CloudMSAAResolve"
	_msaa_copy.visible = false
	_msaa_copy.extra_cull_margin = 1000000.0
	_msaa_copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_msaa_copy.mesh = quad
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled;
uniform sampler2D scene_color : hint_screen_texture, filter_nearest;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
	ALBEDO = textureLod(scene_color, SCREEN_UV, 0.0).rgb;
	ALPHA = 1.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = -128
	_msaa_copy.material_override = material
	add_child(_msaa_copy)


## Optional hook for materials assigned after a node's initial setup.
## Returns a viewport-local copy for shared assets; keep the returned material.
func register_transparent_material(material: Material) -> Material:
	return _transparency.register_material(material) if _transparency != null else material


func _queue_transparent_bind(node: Node) -> void:
	if node is GeometryInstance3D:
		# One extra deferred turn lets existing material/clock/shadow adapters finish.
		_bind_transparent_geometry.call_deferred(node)


func _bind_transparent_geometry(node: GeometryInstance3D) -> void:
	if _transparency != null and is_instance_valid(node) and node.is_inside_tree() and node.get_viewport() == get_viewport():
		_transparency.bind_geometry(node)


func _queue_transparent_scan() -> void:
	_bind_transparents.call_deferred()


func _bind_transparents() -> void:
	if _transparency == null or not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_tree().root
	for node in scene.find_children("*", "GeometryInstance3D", true, false):
		_bind_transparent_geometry(node)


## Opt-in binding for a spawned receiver. Do not share a material across layers.
func register_shadow_material(material: Resource) -> bool:
	if not _is_shadow_material(material):
		return false
	if not _runtime_shadow_materials.has(material) and not (material is ShaderMaterial and shadow_materials.has(material)):
		_runtime_shadow_materials.append(material)
	_sync_shadows()
	return true


func unregister_shadow_material(material: Resource) -> void:
	_runtime_shadow_materials.erase(material)
	if material is ShaderMaterial:
		shadow_materials.erase(material)
	_sync_shadows()


static func _is_shadow_material(material: Resource) -> bool:
	var uniforms: Array = []
	if material is ShaderMaterial and material.shader != null:
		uniforms = material.shader.get_shader_uniform_list()
	elif material != null and material.has_method("get_material_rid") and material.has_method("get_shader_rid"):
		# Terrain3DMaterial owns its RenderingServer material instead of a ShaderMaterial.
		var shader_rid: RID = material.get_shader_rid()
		if not shader_rid.is_valid():
			return false
		uniforms = RenderingServer.get_shader_parameter_list(shader_rid)
	else:
		return false
	var names: Array[StringName] = []
	for uniform in uniforms:
		names.append(uniform.name)
	return names.has(&"cloud_shadow_texture") and names.has(&"cloud_shadow_enabled") \
		and names.has(&"cloud_shadow_deck") and names.has(&"cloud_shadow_sun_direction")


func _sync_shadows() -> void:
	if _compositor == null or effect == null:
		return
	var receivers: Array[Resource] = []
	for material in shadow_materials + _runtime_shadow_materials:
		if _is_shadow_material(material):
			if not receivers.has(material):
				receivers.append(material)
		elif material != null:
			push_warning("CloudLayer3D: shadow material must include cloud_shadow.gdshaderinc.")
	if receivers.is_empty():
		_shadow_pass = null # No receivers: release the cache, not just its bindings.
		if _atmosphere != null:
			_atmosphere.shadows = null
		effect.shadows = null
		return
	if _shadow_pass == null:
		_shadow_pass = CloudShadowPass.new()
		_shadow_pass.source = effect
	if _atmosphere != null:
		_atmosphere.shadows = _shadow_pass # the air reuses the receivers' cache
	effect.shadows = _shadow_pass # and so does the haze in front of the clouds
	_shadow_pass.materials = receivers
	_shadow_pass.shadows_enabled = shadows_enabled
	_shadow_pass.resolution = shadow_resolution
	_shadow_pass.ambient_dimming = shadow_darkness


func _process(_delta: float) -> void:
	if _msaa_copy != null:
		_msaa_copy.visible = get_viewport().msaa_3d != Viewport.MSAA_DISABLED and effect != null and (effect.enabled or _atmosphere.enabled)
	if _transparency != null and effect != null:
		_transparency.set_active(effect.enabled and effect.clouds_enabled and effect.view_ready)
	if _shadow_pass != null:
		# Runs before RenderingServer prepares material descriptor sets. WeakRef
		# prevents queued updates from retaining a detached scene at shutdown.
		RenderingServer.call_on_render_thread(_update_shadow_pass.bind(weakref(_shadow_pass)))


static func _update_shadow_pass(target: WeakRef) -> void:
	var pass_: CloudShadowPass = target.get_ref()
	if pass_ != null:
		pass_.update()


## The existing renderer, available after this node enters the scene.
var effect: CloudSystem
var _atmosphere: CloudAtmosphere
var _previous_compositor: Compositor
var _compositor: Compositor
var _attached_environment: WorldEnvironment
var _saving_preview := false
var _density_revision := 0


## Request local extinction in 1/meters. Callback(float) runs on the main thread
## a few rendered frames later. False means busy/unavailable/invalid: retry later.
## Zero means clear air. For a 0..1 artistic immersion, use 1.0 - exp(-density *
## distance_in_meters), e.g. 600m. This is NOT a wind or precipitation simulation.
## One outstanding query per layer; the node does not track players or cameras.
func request_density(world_position: Vector3, callback: Callable) -> bool:
	if effect == null or not effect.enabled or not is_inside_tree() \
			or not world_position.is_finite() or not callback.is_valid():
		return false
	return effect.request_density(world_position,
		_deliver_density.bind(callback, _density_revision))


func _deliver_density(density: float, callback: Callable, revision: int) -> void:
	if callback.is_valid():
		# Discard samples from before settings changes, disable or tree re-entry.
		callback.call(density if revision == _density_revision and clouds_enabled and effect != null else 0.0)


func _queue_editor_update() -> void:
	if Engine.is_editor_hint() and is_node_ready():
		_update_editor_preview.call_deferred()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(world_environment):
		warnings.append("Assign a WorldEnvironment to render the cloud layer.")
	if not is_finite(deck_base) or not is_finite(deck_top) or deck_top <= deck_base:
		warnings.append("Deck Top must be greater than Deck Base (finite meters).")
	if RenderingServer.get_rendering_device() == null:
		warnings.append("Clouds require a RenderingDevice; use Forward+.")
	return warnings


func _update_editor_preview() -> void:
	if not is_inside_tree():
		return
	update_configuration_warnings()
	if effect != null and (not editor_preview or _attached_environment != world_environment):
		_stop_effect()
	if editor_preview and effect == null and _get_configuration_warnings().is_empty():
		_start_effect()


func _apply_settings() -> void:
	_queue_editor_update()
	if effect == null:
		return
	if not is_finite(deck_base) or not is_finite(deck_top) or deck_top <= deck_base:
		if not Engine.is_editor_hint():
			push_error("CloudLayer3D: deck_top must be greater than deck_base (finite meters).")
		return
	_density_revision += 1
	effect.clouds_enabled = clouds_enabled
	effect.deck_base = deck_base
	effect.deck_top = deck_top
	effect.coverage = coverage
	effect.preset = preset
	effect.density_scale = density_scale
	effect.base_darkening = base_darkening
	effect.max_steps = max_steps
	effect.sun = sun
	effect.atmosphere_enabled = atmosphere_enabled
	effect.haze_extinction = 1.0 / haze_distance
	effect.haze_base = haze_base_altitude
	effect.haze_height = haze_height
	effect.air_density = air_density
	var tint := haze_color.srgb_to_linear()
	effect.haze_tint = Vector3(tint.r, tint.g, tint.b)
	effect.haze_sun_scattering = haze_sun_scattering
	effect.haze_sky_light = haze_sky_light
	effect.haze_cloud_shadows = haze_cloud_shadows
	effect.horizon_haze = horizon_haze
	effect.shadow_darkness = shadow_darkness


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
	else:
		# Rendering continues while gameplay is paused, including receiver toggles.
		process_mode = Node.PROCESS_MODE_ALWAYS
		_start_effect()


func _start_effect() -> void:
	# Map tools and dedicated servers have no renderer; leave their scene intact.
	if DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(world_environment):
		push_error("CloudLayer3D: assign a WorldEnvironment in the Inspector.")
		return
	if RenderingServer.get_rendering_device() == null:
		push_error("CloudLayer3D: RenderingDevice unavailable; use Forward+.")
		return
	if not is_finite(deck_base) or not is_finite(deck_top) or deck_top <= deck_base:
		push_error("CloudLayer3D: deck_top must be greater than deck_base (finite meters).")
		return
	var noise := CloudNoiseGen.make_noise_3d_mips()
	var weather := CloudNoiseGen.make_weather_mips()
	effect = CloudSystem.new()
	_apply_settings()
	effect.set_noise_textures(noise, CloudNoiseGen.NOISE_3D_SIZE,
		weather, CloudNoiseGen.WEATHER_SIZE, CloudNoiseGen.make_weather_lo(weather[0]))
	# Preserve other effects without modifying a shared compositor resource.
	_attached_environment = world_environment
	_previous_compositor = world_environment.compositor
	_compositor = Compositor.new()
	var effects: Array[CompositorEffect] = []
	if _previous_compositor != null:
		effects.assign(_previous_compositor.compositor_effects)
	_atmosphere = CloudAtmosphere.new()
	_atmosphere.source = effect
	effects.append(_atmosphere)
	effects.append(effect) # same POST_SKY stage: atmosphere first, then clouds
	_compositor.compositor_effects = effects
	world_environment.compositor = _compositor
	_sync_shadows()
	if not Engine.is_editor_hint():
		_create_msaa_copy()
		_transparency = CloudTransparency.new()
		_transparency.texture = effect.view_texture
		get_tree().node_added.connect(_queue_transparent_bind, CONNECT_DEFERRED)
		_queue_transparent_scan.call_deferred()


func _stop_effect() -> void:
	_density_revision += 1
	if _msaa_copy != null:
		_msaa_copy.visible = false
		_msaa_copy.queue_free()
		_msaa_copy = null
	if get_tree() != null and get_tree().node_added.is_connected(_queue_transparent_bind):
		get_tree().node_added.disconnect(_queue_transparent_bind)
	if _transparency != null:
		_transparency.clear()
		_transparency = null
	if effect != null:
		effect.enabled = false
		effect.cancel_density_sample()
		effect.shadows = null
	if _atmosphere != null:
		_atmosphere.enabled = false
		_atmosphere.shadows = null
	if is_instance_valid(_attached_environment) and _attached_environment.compositor == _compositor:
		_attached_environment.compositor = _previous_compositor
	_shadow_pass = null
	_compositor = null
	_previous_compositor = null
	_attached_environment = null
	_atmosphere = null
	effect = null
	_saving_preview = false


func _notification(what: int) -> void:
	# The preview compositor is transient: never serialize it into the scene.
	# Keep its caches alive across saves, restoring the preview afterwards.
	if _compositor == null or not is_instance_valid(_attached_environment):
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_saving_preview = _attached_environment.compositor == _compositor
		if _saving_preview:
			_attached_environment.compositor = _previous_compositor
	elif what == NOTIFICATION_EDITOR_POST_SAVE and _saving_preview:
		if _attached_environment.compositor == _previous_compositor:
			_attached_environment.compositor = _compositor
		_saving_preview = false


func _exit_tree() -> void:
	_stop_effect()
	request_ready()
