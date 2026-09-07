extends RefCounted
class_name GameSession
## Stato cross-scena minimal: mappa + missile scelti. Static var persiste finché il processo vive.

static var selected_map: String = "res://scenes/maps/flight_playground.tscn"
static var selected_missiles: Array[String] = ["STDM", "HSSTDM"]
static var free_flight: bool = true
static var selected_missile_id: String:
	get:
		return selected_missiles[0] if not selected_missiles.is_empty() else "STDM"
	set(value):
		if selected_missiles.is_empty():
			selected_missiles = [value, "HSSTDM"]
		else:
			selected_missiles[0] = value
