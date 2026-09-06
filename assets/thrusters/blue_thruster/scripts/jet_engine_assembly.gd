@tool
class_name JetEngineAssembly
extends Node3D

## High-fidelity jet engine test assembly with articulated nozzle petals,
## titanium nacelle casing, heat-shielded interior, and integrated JetThrusterVFX.

const JetThrusterVFXScript = preload("res://assets/thrusters/blue_thruster/scripts/jet_thruster_vfx.gd")

@export_range(0.0, 1.0, 0.01) var throttle: float = 1.0:
	set(value):
		throttle = clampf(value, 0.0, 1.0)
		_update_engine()

@export var thruster_vfx: Node3D

var _petals_root: Node3D
var _petals: Array[Node3D] = []
const PETAL_COUNT := 20
const NOZZLE_RADIUS := 0.52


func _ready() -> void:
	_setup_geometry()
	if not thruster_vfx:
		thruster_vfx = get_node_or_null("JetThrusterVFX")
	_update_engine()


func _process(delta: float) -> void:
	if thruster_vfx and not is_equal_approx(thruster_vfx.throttle, throttle):
		thruster_vfx.throttle = throttle
	# Animate petals opening smoothly
	var target_scale := lerpf(0.92, 1.12, throttle)
	if _petals_root:
		_petals_root.scale = _petals_root.scale.lerp(Vector3(target_scale, target_scale, 1.0), 5.0 * delta)


func _setup_geometry() -> void:
	_petals_root = get_node_or_null("Petals") as Node3D
	if not _petals_root:
		_petals_root = Node3D.new()
		_petals_root.name = "Petals"
		add_child(_petals_root)
		_create_petals()


func _create_petals() -> void:
	_petals.clear()
	var petal_mat := StandardMaterial3D.new()
	petal_mat.albedo_color = Color(0.22, 0.23, 0.25)
	petal_mat.metallic = 0.88
	petal_mat.roughness = 0.32

	var petal_mesh := BoxMesh.new()
	petal_mesh.size = Vector3(0.12, 0.03, 0.45)
	petal_mesh.material = petal_mat

	for i in range(PETAL_COUNT):
		var angle := (float(i) / float(PETAL_COUNT)) * TAU
		var p_node := Node3D.new()
		p_node.name = "Petal_%02d" % i
		_petals_root.add_child(p_node)

		var r := NOZZLE_RADIUS
		p_node.position = Vector3(cos(angle) * r, sin(angle) * r, -0.22)
		p_node.rotation = Vector3(0, 0, angle + PI * 0.5)

		var mi := MeshInstance3D.new()
		mi.mesh = petal_mesh
		mi.rotation.x = deg_to_rad(-6.0) # Slight convergent tilt toward nozzle exit
		p_node.add_child(mi)
		_petals.append(p_node)


func _update_engine() -> void:
	if thruster_vfx:
		thruster_vfx.throttle = throttle
