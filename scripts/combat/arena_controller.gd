extends "res://scripts/combat/sortie_controller.gd"
## Two unarmed moving targets; reuse the normal failure/restart/loadout flow.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy_fighter.tscn")

@onready var spawn_root: Node3D = get_node("../../SpawnedEnemies")
@onready var terrain: Terrain3D = get_node("../../GardaLake/GardaTerrain")
var _spawned := 0
var _destroyed := 0


func _ready() -> void:
	super()
	_spawn_enemies.call_deferred()


func _spawn_enemies() -> void:
	if terminal or not player.is_alive():
		return
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	while remaining < 2:
		var side := -1.0 if _spawned % 2 == 0 else 1.0
		var spawn_position := player.global_position + forward * 1500.0 + right * side * 250.0 + Vector3.UP * 100.0
		var ground := terrain.data.get_height(spawn_position)
		if not is_nan(ground):
			spawn_position.y = maxf(spawn_position.y, ground + 600.0)
		var enemy := ENEMY_SCENE.instantiate() as EnemyFighter
		_spawned += 1
		enemy.name = "ArenaTarget%d" % _spawned
		enemy.label = "ARENA %02d" % _spawned
		enemy.transform = spawn_root.global_transform.affine_inverse() * Transform3D(Basis.looking_at(forward), spawn_position)
		enemy.get_node("WeaponController").firing_enabled = false
		enemy.destroyed.connect(_on_enemy_destroyed)
		spawn_root.add_child(enemy)
		remaining += 1


func _on_enemy_destroyed(_aircraft: Node3D) -> void:
	remaining = maxi(remaining - 1, 0)
	_destroyed += 1


func objectives_text() -> String:
	return ">ARENA · BERSAGLI: %d/2 · ABBATTUTI: %d · NEMICI NON OFFENSIVI" % [remaining, _destroyed]
