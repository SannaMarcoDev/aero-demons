extends Node3D
class_name Explosion
## Explosion assembled from layered particle emitters. `blast_kind` picks the family (warhead,
## heavy warhead, napalm, aircraft kill, wreck cook-off in the air; ground impact) and `effect_seed`
## one of that family's hand-tuned variants plus a jitter on every layer, so no two blasts look the same.
## The replay records both (with `drift_velocity`) and rebuilds the identical blast from them.

signal finished

enum QualityLevel { LOW, MEDIUM, HIGH }
enum Kind { MISSILE, HEAVY, NAPALM, AIRCRAFT, COOK_OFF, GROUND }

const FIRE_SHADER := preload("res://resources/shaders/vfx/explosion_fire.gdshader")
const BILLOW_SHADER := preload("res://resources/shaders/vfx/explosion_smoke.gdshader")
const STREAK_SHADER := preload("res://resources/shaders/vfx/explosion_streak.gdshader")
const SHOCKWAVE_SHADER := preload("res://resources/shaders/vfx/explosion_shockwave.gdshader")
const MISSILE_HIT_SOUND: AudioStream = preload("res://assets/audio/sfx/weapons/missile-hit.mp3")

## Every look starts here; the family overrides some keys and the variant more. Plain numbers are
## multipliers on the base layer setup, `heat` and `soot` are 0..1 looks (cool..hot, grey..black),
## Vector2i values are min/max counts.
const BASE_LOOK := {
	"fire": 1.0, "lobes": 1.0, "burn": 1.0, "heat": 0.5, "flash": 1.0, "light": 1.0,
	"smoke": 1.0, "smoke_life": 1.0, "soot": 0.55, "sparks": 1.0, "shock": 0.0,
	"fragments": Vector2i(0, 0), "frag_speed": 1.0, "frag_fire": 0.2, "frag_trail": 1.0, "frag_drop": 1.0,
	"chain": Vector2i(0, 0), "volume_db": -3.0,
	"dust": 0.0, "scorch": 0.0,
}
const FAMILIES := {
	Kind.MISSILE: {},
	Kind.HEAVY: {"fire": 1.15, "flash": 1.3, "light": 1.5, "smoke": 1.3, "smoke_life": 1.3, "shock": 1.0,
		"sparks": 1.3, "chain": Vector2i(1, 2), "volume_db": -1.0},
	Kind.NAPALM: {"heat": 0.35, "burn": 1.4, "soot": 0.95, "smoke": 1.2, "smoke_life": 1.4, "sparks": 0.5,
		"fragments": Vector2i(9, 13), "frag_speed": 0.75, "frag_fire": 0.8, "frag_trail": 0.45, "frag_drop": 1.6},
	Kind.AIRCRAFT: {"soot": 0.9, "smoke": 1.3, "smoke_life": 1.8, "shock": 0.6, "light": 1.3,
		"fragments": Vector2i(4, 7), "frag_fire": 0.25, "volume_db": -1.0},
	Kind.COOK_OFF: {"fire": 0.8, "flash": 0.7, "smoke_life": 0.6, "sparks": 0.8, "soot": 0.75, "volume_db": -9.0},
	# Off the ground: a blinding dome of fire that shoots up into a tall burning pillar under a
	# rolling head, a black column behind it, smoking debris and sparks flung high, a low dust
	# skirt and a scorch mark that outlives the smoke.
	Kind.GROUND: {"fire": 1.4, "burn": 1.5, "heat": 0.7, "flash": 2.0, "light": 2.0, "smoke": 1.3,
		"smoke_life": 2.4, "soot": 0.95, "sparks": 1.8, "shock": 1.0, "fragments": Vector2i(8, 11),
		"frag_speed": 2.0, "frag_fire": 0.3, "frag_trail": 1.0, "frag_drop": 1.5, "volume_db": -1.0,
		"dust": 1.0, "scorch": 1.0},
}
const VARIANTS := {
	Kind.MISSILE: [
		{"name": "burst", "weight": 3.0},
		{"name": "flak", "weight": 2.0, "fire": 0.75, "burn": 0.7, "heat": 0.4, "smoke": 1.45, "soot": 0.85, "sparks": 1.7},
		{"name": "flare", "weight": 1.5, "fire": 1.15, "burn": 0.85, "heat": 0.9, "flash": 1.6, "smoke": 0.6, "soot": 0.3, "sparks": 0.7},
	],
	Kind.HEAVY: [
		{"name": "double", "weight": 2.0},
		{"name": "ripple", "weight": 2.0, "fire": 0.9, "chain": Vector2i(2, 3), "shock": 0.8},
		{"name": "dome", "weight": 1.5, "fire": 1.35, "burn": 1.3, "heat": 0.65, "shock": 1.3, "chain": Vector2i(0, 1)},
	],
	Kind.NAPALM: [
		{"name": "splash", "weight": 2.0},
		{"name": "drape", "weight": 1.5, "fire": 0.85, "fragments": Vector2i(12, 16), "frag_speed": 0.55, "frag_drop": 2.0},
	],
	Kind.AIRCRAFT: [
		{"name": "breakup", "weight": 3.0, "fragments": Vector2i(5, 8)},
		{"name": "fuel", "weight": 2.0, "fire": 1.4, "burn": 1.5, "heat": 0.6, "smoke": 1.4, "soot": 1.0, "shock": 1.0,
			"fragments": Vector2i(2, 4)},
		{"name": "chain", "weight": 2.0, "fire": 0.85, "chain": Vector2i(2, 3), "fragments": Vector2i(3, 5)},
	],
	Kind.COOK_OFF: [
		{"name": "pop", "weight": 3.0},
		{"name": "sputter", "weight": 2.0, "fire": 0.6, "smoke": 1.5, "soot": 1.0, "sparks": 0.4},
		{"name": "sparkle", "weight": 1.5, "fire": 0.7, "heat": 0.8, "sparks": 2.0},
	],
	Kind.GROUND: [
		{"name": "strike", "weight": 1.0},
	],
}
const JITTER_KEYS := ["fire", "lobes", "burn", "flash", "light", "smoke", "smoke_life", "sparks", "shock", "frag_speed", "frag_trail"]

# Velocity a layer keeps from the blast's drift over its life: fast fire sheds it at once, the
# cloud a little later, burning fragments carry it the whole way down.
const DRIFT_FIRE := [Vector2(0.0, 1.0), Vector2(0.08, 0.55), Vector2(0.25, 0.15), Vector2(0.5, 0.03), Vector2(1.0, 0.0)]
const DRIFT_SMOKE := [Vector2(0.0, 1.0), Vector2(0.1, 0.5), Vector2(0.35, 0.12), Vector2(1.0, 0.0)]
const DRIFT_FRAGMENT := [Vector2(0.0, 1.0), Vector2(0.4, 0.75), Vector2(1.0, 0.45)]
# Smoke puffs per second each burning fragment leaves behind (capped by its 60 Hz process rate).
const TRAIL_PUFF_RATE := 40.0
# Seconds the scorch mark stays before fading, and how long the fade takes.
const SCORCH_HOLD := 20.0
const SCORCH_FADE := 8.0

const SCENE: PackedScene = preload("res://scenes/vfx/explosion_fx.tscn")

@export var blast_kind: Kind = Kind.MISSILE:
	set(value):
		blast_kind = value
		if is_node_ready():
			_configure()

@export var effect_seed := 0:
	set(value):
		effect_seed = value
		if is_node_ready():
			_configure()

## World-space velocity (m/s) the blast inherits from whatever blew up; smears fire and smoke
## along the flight path and carries the burning fragments forward.
@export var drift_velocity := Vector3.ZERO:
	set(value):
		drift_velocity = value
		if is_node_ready():
			_configure()

@export_range(0.1, 8.0, 0.05) var overall_scale := 1.0:
	set(value):
		overall_scale = maxf(value, 0.1)
		if is_node_ready():
			_apply_scale()
			_configure()

@export_range(0.0, 4.0, 0.05) var intensity := 1.0:
	set(value):
		intensity = clampf(value, 0.0, 4.0)
		if is_node_ready():
			_apply_appearance()

@export_range(0.0, 2.0, 0.05) var smoke_amount := 1.0:
	set(value):
		smoke_amount = clampf(value, 0.0, 2.0)
		if is_node_ready():
			_configure()

@export_range(0.0, 2.0, 0.05) var sparks_amount := 1.0:
	set(value):
		sparks_amount = clampf(value, 0.0, 2.0)
		if is_node_ready():
			_configure()

@export_range(0.0, 32.0, 0.1) var light_energy := 10.0:
	set(value):
		light_energy = maxf(value, 0.0)

@export_range(0.5, 40.0, 0.5) var light_range := 16.0:
	set(value):
		light_range = maxf(value, 0.5)
		if is_node_ready():
			_configure()

@export var auto_free := true
@export var quality_level: QualityLevel = QualityLevel.HIGH:
	set(value):
		quality_level = clampi(value, QualityLevel.LOW, QualityLevel.HIGH)
		if is_node_ready():
			_configure()

## Name of the variant `effect_seed` picked, for previews and debugging.
var variant_name := ""

@onready var _emitters: Array[GPUParticles3D] = [
	$Flash, $Glare, $FireCore, $FireLobes, $SecondaryLobes, $Smoke, $Pillar, $Cap, $DustRing, $Sparks,
	$Fragments, $FragmentSmoke, $Shockwave,
]
@onready var _billows: Array[GPUParticles3D] = [
	$FireLobes, $SecondaryLobes, $Smoke, $Pillar, $Cap, $DustRing, $FragmentSmoke,
]

static var _last_variant := {}
# Meshes and materials of freed blasts, handed to new ones: creating ParticleProcessMaterials costs
# milliseconds per spawn, reassigning existing ones next to nothing.
static var _resource_pool: Array[Dictionary] = []
const _POOL_LIMIT := 12
var _resources := {}

var _materials: Array[ShaderMaterial] = []
var _chain: Array[Dictionary] = []
var _delays := {}
var _duration := 5.0
var _light_gain := 1.0
var _light_decay := 10.0
var _scorch_glow := 0.0
var _elapsed := 0.0
var _generation := 0
var _playing := false


const _QUALITY_COUNT := [0.5, 0.75, 1.0]
const _QUALITY_LIGHT := [0.55, 0.8, 1.0]
# Shader, fixed uniforms and depth-sort nudge (m) of every layer: shockwave first so the others
# draw over its refraction, then cloud, fireball and the additive fire, flash on top.
const _LAYERS := {
	"Flash": [FIRE_SHADER, {"flash_mode": 1.0, "min_view_size": 0.006}, 3.0],
	"Glare": [FIRE_SHADER, {"flash_mode": 2.0, "min_view_size": 0.02}, 3.0],
	"FireCore": [FIRE_SHADER, {"flash_mode": 0.0}, 1.0],
	"FireLobes": [BILLOW_SHADER, {}, 0.5],
	"SecondaryLobes": [BILLOW_SHADER, {}, 0.3],
	"Smoke": [BILLOW_SHADER, {}, 0.0],
	"Pillar": [BILLOW_SHADER, {}, 0.6],
	"Cap": [BILLOW_SHADER, {}, 0.2],
	"DustRing": [BILLOW_SHADER, {}, -0.2],
	"Sparks": [STREAK_SHADER, {}, 2.0],
	"Fragments": [FIRE_SHADER, {"flash_mode": 0.0}, 1.0],
	"FragmentSmoke": [BILLOW_SHADER, {}, 0.2],
	"Shockwave": [SHOCKWAVE_SHADER, {}, -1.0],
}


static func spawn(parent: Node, pos: Vector3, p_scale: float = 1.0, kind: Kind = Kind.MISSILE,
		velocity := Vector3.ZERO, p_seed := -1) -> Explosion:
	if parent == null:
		return null
	var instance: Explosion = SCENE.instantiate()
	instance.overall_scale = p_scale
	instance.blast_kind = kind
	instance.drift_velocity = velocity
	instance.effect_seed = p_seed if p_seed >= 0 else _fresh_seed(kind)
	parent.add_child(instance)
	instance.global_position = pos
	instance.play()
	return instance


static func spawn_aircraft(parent: Node, pos: Vector3, p_scale: float = 3.0, velocity := Vector3.ZERO) -> Explosion:
	return spawn(parent, pos, p_scale, Kind.AIRCRAFT, velocity)


## Variant index `p_seed` selects for `kind`; the first draw of the seeded generator, exactly as
## `_configure` makes it.
static func pick_variant(kind: Kind, p_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return _weighted_index(VARIANTS[kind], rng.randf())


# A fresh seed that, when possible, does not repeat the variant the last blast of this kind used.
static func _fresh_seed(kind: Kind) -> int:
	var candidate := randi()
	for attempt in 4:
		if pick_variant(kind, candidate) != _last_variant.get(kind, -1):
			break
		candidate = randi()
	_last_variant[kind] = pick_variant(kind, candidate)
	return candidate


static func _weighted_index(variants: Array, roll: float) -> int:
	var total := 0.0
	for variant in variants:
		total += float(variant.weight)
	var target := roll * total
	for index in variants.size():
		target -= float(variants[index].weight)
		if target < 0.0:
			return index
	return variants.size() - 1


func _ready() -> void:
	$AudioPlayer.stream = MISSILE_HIT_SOUND
	_build_resources()
	_apply_scale()
	_configure()
	$BlastLight.visible = false
	$Scorch.visible = false


func play() -> void:
	stop_immediately()
	_generation += 1
	_playing = true
	_elapsed = 0.0
	$BlastLight.visible = light_energy > 0.0 and intensity > 0.0
	$Scorch.visible = _scorch_glow > 0.0
	$Scorch.modulate.a = 1.0
	$AudioPlayer.play()
	for emitter in _emitters:
		var delay: float = _delays.get(emitter, 0.0)
		if delay > 0.0:
			_start_delayed(emitter, delay, _generation)
		else:
			_burst(emitter)
	for link in _chain:
		_spawn_link(link, _generation)
	$LifetimeTimer.start(_duration)


func stop_immediately() -> void:
	_generation += 1
	_playing = false
	$LifetimeTimer.stop()
	$AudioPlayer.stop()
	$BlastLight.visible = false
	$Scorch.visible = false
	for emitter in _emitters:
		# restart clears particles already in flight; disabling immediately prevents a new burst.
		emitter.restart()
		emitter.emitting = false


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var flicker := 0.8 + 0.2 * sin(_elapsed * 41.0 + float(effect_seed % 97))
	var pulse := exp(-_elapsed * _light_decay) + 0.12 * exp(-_elapsed * 1.8) * flicker
	$BlastLight.light_energy = light_energy * intensity * _light_gain * pulse
	$BlastLight.light_color = Color(1.0, 0.86, 0.62).lerp(Color(1.0, 0.42, 0.14), 1.0 - exp(-_elapsed * 4.0))
	$BlastLight.visible = $BlastLight.light_energy > 0.01
	if $Scorch.visible:
		$Scorch.emission_energy = _scorch_glow * exp(-_elapsed * 0.45)
		$Scorch.modulate.a = 1.0 - smoothstep(SCORCH_HOLD, SCORCH_HOLD + SCORCH_FADE, _elapsed)


func _on_lifetime_timer_timeout() -> void:
	if not _playing:
		return
	_playing = false
	$BlastLight.visible = false
	$Scorch.visible = false
	for emitter in _emitters:
		emitter.emitting = false
	finished.emit()
	if auto_free:
		queue_free()


func _start_delayed(emitter: GPUParticles3D, delay: float, generation: int) -> void:
	await get_tree().create_timer(delay).timeout
	if _playing and generation == _generation:
		_burst(emitter)


func _burst(emitter: GPUParticles3D) -> void:
	if emitter.visible and emitter.amount > 0:
		emitter.emitting = true
		emitter.restart()


## Secondary detonations are separate cook-off blasts in the world, so the replay records them
## like any other explosion.
func _spawn_link(link: Dictionary, generation: int) -> void:
	await get_tree().create_timer(link.delay).timeout
	if not _playing or generation != _generation or get_parent() == null:
		return
	var origin: Vector3 = global_position + link.offset + drift_velocity * float(link.delay) * 0.5
	spawn(get_parent(), origin, link.scale, Kind.COOK_OFF, drift_velocity * 0.5, link.seed)


func _apply_scale() -> void:
	scale = Vector3.ONE * overall_scale


func _apply_appearance() -> void:
	var seed_offset := float(effect_seed % 10007) * 0.173
	for material in _materials:
		material.set_shader_parameter("intensity", intensity)
		material.set_shader_parameter("seed_offset", seed_offset)


# Turns kind + seed into the look of this blast and pushes it onto every layer. Deterministic:
# the same exported settings always rebuild the same explosion.
func _configure() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = effect_seed
	var variants: Array = VARIANTS[blast_kind]
	var variant: Dictionary = variants[_weighted_index(variants, rng.randf())]
	variant_name = variant.name
	var look := BASE_LOOK.duplicate()
	look.merge(FAMILIES[blast_kind], true)
	look.merge(variant, true)
	for key in JITTER_KEYS:
		look[key] *= rng.randf_range(0.85, 1.15)
	look.heat = clampf(look.heat + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	look.soot = clampf(look.soot + rng.randf_range(-0.08, 0.08), 0.0, 1.0)

	var q: float = _QUALITY_COUNT[quality_level]
	var s := overall_scale
	# Fireball size in local units: about 15 m across at overall_scale 1.
	var fire: float = 1.5 * look.fire
	var burn_scale := sqrt(look.burn)
	# Off the ground everything launches upwards from just above the impact instead of all round.
	var ground := blast_kind == Kind.GROUND
	if ground:
		look.dust *= rng.randf_range(0.85, 1.15)
	var lift := fire if ground else 0.0
	_delays.clear()

	# Flash and glare: the first frames, readable from far away.
	_set_amount($Flash, 1)
	$Flash.lifetime = 0.09 * rng.randf_range(0.85, 1.2)
	_shape($Flash, 4.6 * look.flash, 5.8 * look.flash, [Vector2(0.0, 0.3), Vector2(0.25, 1.0), Vector2(1.0, 1.2)])
	_aim($Flash, 180.0, lift)
	_set_amount($Glare, 1)
	$Glare.lifetime = 0.5 * sqrt(look.flash)
	_shape($Glare, 12.0 * look.flash, 14.0 * look.flash, [Vector2(0.0, 0.6), Vector2(0.15, 1.0), Vector2(1.0, 1.3)])
	_aim($Glare, 180.0, lift)

	# White-hot core.
	_set_amount($FireCore, maxi(roundi(7.0 * q * look.lobes), 3))
	$FireCore.lifetime = 0.45 * look.burn
	_motion($FireCore, 0.45 * fire, 1.0 * fire, 3.5 * fire, 6.0, 0.0)
	_shape($FireCore, 2.0 * fire, 3.4 * fire, [Vector2(0.0, 0.25), Vector2(0.15, 1.0), Vector2(0.6, 1.2), Vector2(1.0, 0.75)])
	_drift($FireCore, 0.15, 0.5, DRIFT_FIRE)
	_aim($FireCore, 70.0 if ground else 180.0, 0.3 * lift)

	# Main fireball: lobes born as fire that roll over into smoke; a dome on the ground.
	_set_amount($FireLobes, maxi(roundi(22.0 * q * look.lobes), 6))
	$FireLobes.lifetime = 1.9 * burn_scale
	_motion($FireLobes, 0.6 * fire, 5.0 * fire, 13.0 * fire, 8.0, 2.2 if ground else 1.2)
	_aim($FireLobes, 75.0 if ground else 180.0, 0.5 * lift)
	_shape($FireLobes, 2.4 * fire, 4.8 * fire, [Vector2(0.0, 0.3), Vector2(0.1, 0.85), Vector2(0.4, 1.2), Vector2(1.0, 1.7)])
	_spin($FireLobes, 35.0)
	_drift($FireLobes, 0.15, 0.6, DRIFT_FIRE)
	_billow($FireLobes, 0.45 * burn_scale, 1.0, 1.15)

	# In the air a second, later burst; on the ground a skirt of fire racing out along the surface.
	_set_amount($SecondaryLobes, roundi(12.0 * look.lobes) if quality_level != QualityLevel.LOW else 0)
	$SecondaryLobes.lifetime = 1.4 * burn_scale
	if ground:
		_motion($SecondaryLobes, 0.5 * fire, 8.0 * fire, 16.0 * fire, 9.0, 1.0)
		_aim($SecondaryLobes, 180.0, 0.3 * lift, Vector3.BACK, 0.85)
	else:
		_motion($SecondaryLobes, 0.8 * fire, 2.0 * fire, 6.0 * fire, 8.0, 1.0)
		_aim($SecondaryLobes, 180.0, 0.0)
	_shape($SecondaryLobes, 1.8 * fire, 3.4 * fire, [Vector2(0.0, 0.3), Vector2(0.12, 0.9), Vector2(1.0, 1.5)])
	_spin($SecondaryLobes, 45.0)
	_drift($SecondaryLobes, 0.2, 0.65, DRIFT_FIRE)
	_billow($SecondaryLobes, 0.42 * burn_scale, 0.9, 1.15)
	_delays[$SecondaryLobes] = 0.0 if ground else 0.07 * rng.randf_range(0.7, 1.4)

	# The ground blast's pillar: burning lobes shot straight up at a wide range of speeds, so they
	# string out into a column from the dome to the head, then keep climbing on their own heat.
	_set_amount($Pillar, roundi(44.0 * q * look.lobes) if ground else 0)
	$Pillar.lifetime = 3.4 * burn_scale
	_motion($Pillar, 0.5 * fire, 1.5 * fire, 24.0 * fire, 1.0, 2.5)
	_aim($Pillar, 9.0, 0.5 * lift)
	_shape($Pillar, 2.4 * fire, 4.0 * fire, [Vector2(0.0, 0.4), Vector2(0.12, 1.0), Vector2(1.0, 1.7)])
	_spin($Pillar, 30.0)
	_drift($Pillar, 0.0, 0.1, DRIFT_FIRE)
	_billow($Pillar, 0.7, 1.6, 1.4)

	# Its head: big lobes thrown up hardest, slowed by the air into a rolling, burning cap.
	_set_amount($Cap, roundi(20.0 * q * look.lobes) if ground else 0)
	$Cap.lifetime = 3.6 * burn_scale
	_motion($Cap, 0.6 * fire, 21.0 * fire, 26.0 * fire, 1.3, 3.0)
	_aim($Cap, 22.0, 0.5 * lift)
	_shape($Cap, 4.0 * fire, 6.0 * fire, [Vector2(0.0, 0.3), Vector2(0.15, 0.9), Vector2(1.0, 2.0)])
	_spin($Cap, 20.0)
	_drift($Cap, 0.0, 0.1, DRIFT_SMOKE)
	_billow($Cap, 0.7, 1.4, 1.3)

	# The cloud the blast leaves hanging in the sky, or the black column climbing off the ground.
	var smoke_size := fire * sqrt(look.smoke)
	_set_amount($Smoke, roundi(30.0 * q * look.smoke * smoke_amount))
	$Smoke.lifetime = 4.2 * look.smoke_life
	if ground:
		_motion($Smoke, 0.8 * fire, 0.5 * fire, 16.0 * fire, 1.3, 1.0)
		_aim($Smoke, 14.0, 0.3 * lift)
	else:
		_motion($Smoke, 2.0 * fire, 1.5 * fire, 5.0 * fire, 3.0, 0.4)
		_aim($Smoke, 180.0, 0.0)
	_shape($Smoke, 2.2 * smoke_size, 4.6 * smoke_size, [Vector2(0.0, 0.45), Vector2(0.15, 1.0), Vector2(0.6, 1.7), Vector2(1.0, 2.3)])
	_spin($Smoke, 18.0)
	_drift($Smoke, 0.04, 0.25, DRIFT_SMOKE)
	_billow($Smoke, 0.07, 0.6, 1.6 if ground else 1.1)
	_delays[$Smoke] = 0.16 * rng.randf_range(0.8, 1.3)

	# Dust skirt: a thin, fast ring the shock kicks up along the ground, gone in seconds.
	_set_amount($DustRing, roundi(16.0 * q * look.dust * smoke_amount) if ground else 0)
	$DustRing.lifetime = 3.0
	_motion($DustRing, 0.6 * fire, 10.0 * fire, 24.0 * fire, 4.0, 0.4)
	_shape($DustRing, 1.0 * fire, 1.8 * fire, [Vector2(0.0, 0.4), Vector2(0.2, 1.0), Vector2(1.0, 2.2)])
	_spin($DustRing, 15.0)
	_aim($DustRing, 180.0, 0.3 * lift, Vector3.BACK, 0.92)
	_drift($DustRing, 0.0, 0.1, DRIFT_SMOKE)
	_billow($DustRing, 0.0, 0.0, 0.5)
	_delays[$DustRing] = 0.03

	# Incandescent streaks; off the ground they arc high and rain back down.
	_set_amount($Sparks, roundi(56.0 * q * look.sparks * sparks_amount))
	$Sparks.lifetime = 1.6 if ground else 0.85
	var sparks: ParticleProcessMaterial = $Sparks.process_material
	sparks.initial_velocity_min = (24.0 if ground else 16.0) * sqrt(fire)
	sparks.initial_velocity_max = (60.0 if ground else 40.0) * sqrt(fire)
	sparks.particle_flag_damping_as_friction = false
	sparks.damping_min = (5.0 if ground else 10.0) * s
	sparks.damping_max = (9.0 if ground else 18.0) * s
	sparks.gravity = Vector3(0.0, -9.8, 0.0)
	_aim($Sparks, 45.0 if ground else 180.0, 0.3 * lift)
	_shape($Sparks, 0.5, 1.1, [Vector2(0.0, 1.0), Vector2(1.0, 0.6)])
	_drift($Sparks, 0.1, 0.5, DRIFT_SMOKE)

	# Burning fragments (aircraft kills), napalm gel or, off the ground, debris flung out of the
	# blast. Each one is a small fire that drops puffs into FragmentSmoke as it flies: born burning,
	# cooling into its trail.
	var fragment_count := roundi(rng.randi_range(look.fragments.x, look.fragments.y) * (1.0 if quality_level == QualityLevel.HIGH else q))
	_set_amount($Fragments, fragment_count)
	$Fragments.lifetime = 1.6 + 1.8 * look.frag_trail
	var fragments: ParticleProcessMaterial = $Fragments.process_material
	fragments.direction = Vector3.UP
	fragments.spread = 50.0 if ground else 100.0
	fragments.initial_velocity_min = 10.0 * look.frag_speed
	fragments.initial_velocity_max = 22.0 * look.frag_speed
	fragments.particle_flag_damping_as_friction = true
	fragments.damping_min = 0.12
	fragments.damping_max = 0.2
	fragments.gravity = Vector3(0.0, -9.8 * look.frag_drop, 0.0)
	fragments.sub_emitter_frequency = TRAIL_PUFF_RATE
	var debris := 0.8 if ground else 1.0
	_shape($Fragments, 1.6 * debris, 2.6 * debris, [Vector2(0.0, 1.0), Vector2(0.7, 0.8), Vector2(1.0, 0.0)])
	_drift($Fragments, 0.25, 0.6, DRIFT_FRAGMENT)

	_set_amount($FragmentSmoke, ceili(fragment_count * TRAIL_PUFF_RATE * 1.8 * look.frag_trail * 1.15) if fragment_count > 0 else 0)
	$FragmentSmoke.lifetime = 1.8 * look.frag_trail
	# Puffs are emitted from each fragment's own transform, so they take explicit world sizes.
	_motion($FragmentSmoke, 0.05, 0.1, 0.4, 2.0, 0.3)
	_shape($FragmentSmoke, 1.2 * s * debris, 2.0 * s * debris, [Vector2(0.0, 0.5), Vector2(0.2, 1.0), Vector2(1.0, 2.2)])
	_spin($FragmentSmoke, 25.0)
	_drift($FragmentSmoke, 0.0, 0.0, DRIFT_SMOKE)
	_billow($FragmentSmoke, 0.12 + 0.5 * look.frag_fire, 1.2, 1.2)

	# Pressure shell on the bigger blasts.
	_set_amount($Shockwave, 1 if look.shock > 0.05 else 0)
	$Shockwave.lifetime = 0.42
	_shape($Shockwave, 22.0 * fire, 22.0 * fire, [Vector2(0.0, 0.12), Vector2(1.0, 1.0)])
	($Shockwave.draw_pass_1.surface_get_material(0) as ShaderMaterial).set_shader_parameter("strength", minf(look.shock, 2.0))

	for material in _materials:
		if material.shader != SHOCKWAVE_SHADER:
			material.set_shader_parameter("heat_bias", look.heat)
	for emitter in _billows:
		_billow_set(emitter, "soot", look.soot)
		_billow_set(emitter, "dirt", 0.0)
	# The dust skirt is soil; a ground blast's column picks up a little of it.
	_billow_set($DustRing, "dirt", 1.0)
	_billow_set($DustRing, "soot", 0.5)
	_billow_set($Smoke, "dirt", 0.12 if ground else 0.0)

	# Scorch mark burnt into the ground, glowing with embers before it cools.
	_scorch_glow = 3.0 * look.scorch
	var scorch_size := 13.0 * fire * maxf(look.scorch, 0.1)
	$Scorch.size = Vector3(scorch_size, 8.0 * fire, scorch_size)
	$Scorch.rotation.y = rng.randf() * TAU if ground else 0.0
	$Scorch.emission_energy = _scorch_glow
	$BlastLight.position = Vector3(0.0, 3.0 * lift, 0.0)

	# Light, sound and the secondary detonations.
	_light_gain = look.light * look.fire * _QUALITY_LIGHT[quality_level]
	_light_decay = 9.0 / sqrt(look.burn)
	$BlastLight.omni_range = light_range * s * fire
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("setup_sfx_3d"):
		audio_manager.setup_sfx_3d($AudioPlayer, look.volume_db)
	else:
		$AudioPlayer.bus = &"SFX"
		$AudioPlayer.volume_db = look.volume_db
	$AudioPlayer.pitch_scale = clampf(1.12 - 0.11 * s, 0.7, 1.25) * rng.randf_range(0.93, 1.07)

	_chain.clear()
	var chain_time := 0.0
	for link in rng.randi_range(look.chain.x, look.chain.y):
		chain_time += rng.randf_range(0.1, 0.32)
		var direction := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		_chain.append({
			"delay": chain_time,
			"offset": direction * rng.randf_range(2.5, 5.0) * fire * s,
			"scale": s * rng.randf_range(0.4, 0.6),
			"seed": rng.randi(),
		})

	_duration = maxf(
		maxf(_delays[$Smoke] + $Smoke.lifetime, $FireLobes.lifetime),
		maxf($Fragments.lifetime + $FragmentSmoke.lifetime if $Fragments.visible else 0.0, chain_time)
	) + 0.3
	if ground:
		_duration = maxf(_duration, maxf($Cap.lifetime, $Pillar.lifetime) + 0.3)
	if _scorch_glow > 0.0:
		_duration = maxf(_duration, SCORCH_HOLD + SCORCH_FADE)
	_apply_appearance()
	_apply_visibility()


func _set_amount(emitter: GPUParticles3D, amount: int) -> void:
	# GPUParticles3D requires an allocated slot even for a disabled layer.
	if emitter.amount != maxi(amount, 1):
		emitter.amount = maxi(amount, 1)
	emitter.visible = amount > 0


# Spawn sphere radius, launch speed and quadratic air drag, all in local units so a blast at any
# `overall_scale` is the same shape. Drag acts on world speed, which grows with the scale.
func _motion(emitter: GPUParticles3D, radius: float, speed_min: float, speed_max: float, drag: float, rise: float) -> void:
	var process: ParticleProcessMaterial = emitter.process_material
	process.emission_sphere_radius = radius
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.particle_flag_damping_as_friction = true
	process.damping_min = drag * 0.8 / overall_scale
	process.damping_max = drag * 1.2 / overall_scale
	process.gravity = Vector3(0.0, rise * overall_scale, 0.0)


func _shape(emitter: GPUParticles3D, size_min: float, size_max: float, curve: Array) -> void:
	var process: ParticleProcessMaterial = emitter.process_material
	process.scale_min = size_min
	process.scale_max = size_max
	process.scale_curve = _curve_texture(curve) if not curve.is_empty() else null


func _spin(emitter: GPUParticles3D, degrees_per_second: float) -> void:
	var process: ParticleProcessMaterial = emitter.process_material
	process.angular_velocity_min = -degrees_per_second
	process.angular_velocity_max = degrees_per_second


# Launch direction (local, UP unless given), spread cone and the height above the blast origin
# particles start from: a sphere in the air, a dome or a column off the ground.
func _aim(emitter: GPUParticles3D, spread: float, lift: float, direction := Vector3.UP, flatness := 0.0) -> void:
	var process: ParticleProcessMaterial = emitter.process_material
	process.direction = direction
	process.spread = spread
	process.flatness = flatness
	process.emission_shape_offset = Vector3(0.0, lift, 0.0)


func _billow(emitter: GPUParticles3D, burn: float, glow: float, density: float) -> void:
	_billow_set(emitter, "burn", burn)
	_billow_set(emitter, "glow", glow)
	_billow_set(emitter, "density", density)


func _billow_set(emitter: GPUParticles3D, parameter: StringName, value: float) -> void:
	((emitter.draw_pass_1 as Mesh).surface_get_material(0) as ShaderMaterial).set_shader_parameter(parameter, value)


# Directional velocity is applied in world space by ParticleProcessMaterial, so the curve carries
# the drift direction and the min/max carry a random share of its speed per particle.
func _drift(emitter: GPUParticles3D, share_min: float, share_max: float, decay: Array) -> void:
	var process: ParticleProcessMaterial = emitter.process_material
	var speed := drift_velocity.length()
	var direction := drift_velocity / speed if speed > 0.01 else Vector3.ZERO
	var texture := CurveXYZTexture.new()
	texture.curve_x = _axis_curve(direction.x, decay)
	texture.curve_y = _axis_curve(direction.y, decay)
	texture.curve_z = _axis_curve(direction.z, decay)
	process.directional_velocity_curve = texture
	process.directional_velocity_min = speed * share_min
	process.directional_velocity_max = speed * share_max


func _axis_curve(component: float, decay: Array) -> Curve:
	var curve := Curve.new()
	curve.min_value = -1.0
	curve.max_value = 1.0
	for point in decay:
		curve.add_point(Vector2(point.x, point.y * component))
	return curve


func _apply_visibility() -> void:
	# World-space particles are culled by this box in local units; it must hold the drift too.
	var reach := 60.0 + drift_velocity.length() * 3.5 / overall_scale
	for emitter in _emitters:
		emitter.visibility_aabb = AABB(Vector3.ONE * -reach, Vector3.ONE * reach * 2.0)


func _build_resources() -> void:
	for emitter in _emitters:
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.sorting_offset = _LAYERS[emitter.name][2]
	for emitter in _billows:
		emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	$Scorch.normal_fade = 0.35
	# Fragments feed their trail through the sub-emitter; it must stay active (emitting, not
	# one-shot) to take the puffs, but never emits on its own while it is a sub-emitter.
	$Fragments.sub_emitter = $Fragments.get_path_to($FragmentSmoke)
	$Fragments.fixed_fps = 60
	$FragmentSmoke.one_shot = false
	$FragmentSmoke.explosiveness = 0.0

	_resources = _resource_pool.pop_back() if not _resource_pool.is_empty() else _create_resources()
	_materials = _resources.materials
	for emitter in _emitters:
		emitter.draw_pass_1 = _resources.meshes[emitter.name]
		emitter.process_material = _resources.processes[emitter.name]


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _resources.is_empty() and _resource_pool.size() < _POOL_LIMIT:
		_resource_pool.append(_resources)


func _create_resources() -> Dictionary:
	var materials: Array[ShaderMaterial] = []
	var meshes := {}
	var processes := {}
	for layer in _LAYERS:
		var material := ShaderMaterial.new()
		material.shader = _LAYERS[layer][0]
		for parameter in _LAYERS[layer][1]:
			material.set_shader_parameter(parameter, _LAYERS[layer][1][parameter])
		materials.append(material)
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		mesh.material = material
		meshes[layer] = mesh
		var process := ParticleProcessMaterial.new()
		process.direction = Vector3.UP
		process.spread = 180.0
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.35
		process.angle_min = -180.0
		process.angle_max = 180.0
		process.lifetime_randomness = 0.3
		process.particle_flag_inherit_emitter_scale = true
		processes[layer] = process

	processes.Fragments.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_CONSTANT
	processes.FragmentSmoke.particle_flag_inherit_emitter_scale = false
	processes.Sparks.particle_flag_align_y = true
	for layer in ["Flash", "Glare", "Shockwave"]:
		var process: ParticleProcessMaterial = processes[layer]
		process.angle_min = 0.0 if layer == "Shockwave" else -180.0
		process.angle_max = 0.0 if layer == "Shockwave" else 180.0
		process.initial_velocity_min = 0.0
		process.initial_velocity_max = 0.0
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		process.gravity = Vector3.ZERO
	return {"materials": materials, "meshes": meshes, "processes": processes}


func _curve(points: Array) -> Curve:
	var curve := Curve.new()
	curve.max_value = 4.0
	for point in points:
		curve.add_point(point)
	return curve


func _curve_texture(points: Array) -> CurveTexture:
	var texture := CurveTexture.new()
	texture.curve = _curve(points)
	return texture
