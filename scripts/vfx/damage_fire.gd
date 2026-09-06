extends Node3D
class_name DamageFire

## Fire, soot trail and debris for one damaged section of an airframe. The jet points along
## local +Y, so rotate the node to aim it at whatever the damage is meant to be venting from.
##
## Fire, smoke and debris run in world space: at flight speed the aircraft leaves particles
## behind. At rest they all emit at the damage point.

@export_range(0.0, 1.0, 0.01) var intensity := 1.0 : set = set_intensity
## How much the flame is allowed to wander off its axis. At 0 every lick leaves on the same
## vector at the same speed and only the shader's noise animates it, which is the difference
## between a jet of fire and a thrashing worm.
@export_range(0.0, 1.0, 0.01) var movement_randomness := 0.35 : set = set_movement_randomness
@export var light_energy := 3.2
@export var light_range := 7.0
@export var flicker_depth := 0.35

@onready var _emitters: Array[GPUParticles3D] = [$Flame, $Smoke, $Embers]
@onready var _glow: OmniLight3D = $Glow
@onready var _flame_process: ParticleProcessMaterial = $Flame.process_material
@onready var _smoke_process: ParticleProcessMaterial = $Smoke.process_material

var _phase := 0.0
var _travel := Vector3.ZERO
var _last_position := Vector3.ZERO


func _ready() -> void:
	_last_position = global_position
	set_intensity(intensity)
	set_movement_randomness(movement_randomness)


func _process(delta: float) -> void:
	_phase += delta
	# Two incommensurate rates, so the flicker never settles into a visible loop.
	var flicker := 0.5 * sin(_phase * 17.0) + 0.5 * sin(_phase * 6.3 + 1.7)
	_glow.light_energy = light_energy * intensity * (1.0 - flicker_depth * (0.5 - 0.5 * flicker))

	# A frame's worth of particles all spawn at the emitter's current point, so at flight
	# speed the trail comes out as beads one frame of travel apart. Sizing the emission box
	# to one frame of travel spreads that batch into a continuous column instead. The box is
	# axis-aligned in emitter space and the node is meant to be aimed freely, so the travel
	# is measured per local axis. Physics interpolation reports no travel at all on frames
	# between ticks, hence the decaying maximum: averaging lets the gaps reopen.
	var travel := global_basis.inverse() * (global_position - _last_position)
	_last_position = global_position
	_travel = (_travel * 0.9).max(travel.abs())
	var emission_box_extents := (_travel * 0.75).clampf(0.14, 4.0)
	_flame_process.emission_box_extents = emission_box_extents
	_smoke_process.emission_box_extents = emission_box_extents


func set_movement_randomness(value: float) -> void:
	movement_randomness = clampf(value, 0.0, 1.0)
	if not is_node_ready():
		return
	# Only lateral wander is scaled. The spread in launch speed stays: a frame emits some
	# forty particles at once, and if they all fly at the same speed that batch never mixes
	# with its neighbours and the jet bands into visible cards one frame of travel apart.
	_flame_process.spread = 1.0 + 14.0 * movement_randomness
	_flame_process.turbulence_enabled = movement_randomness > 0.0
	_flame_process.turbulence_noise_strength = 2.4 * movement_randomness
	_flame_process.turbulence_influence_max = 0.7 * movement_randomness


func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)
	if not is_node_ready():
		return
	for emitter in _emitters:
		emitter.emitting = intensity > 0.0
		emitter.amount_ratio = intensity
	_glow.visible = intensity > 0.0
	_glow.omni_range = light_range * (0.6 + 0.4 * intensity)
