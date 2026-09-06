extends Area3D
class_name AircraftHitbox

## Bullets look for an Area3D that can take damage; the health lives on the aircraft above it.


func apply_damage(amount: float) -> void:
	get_parent().apply_damage(amount)
