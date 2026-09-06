extends RefCounted
## Catalogo unico dei tipi. Nessuna Resource, solo dizionario statico.
## I valori qui sono la verità per WeaponController, debug rig e HUD.

const DEFS := {
	"STDM": {
		"label": "STDM",
		"full_name": "Standard Missile",
		"description": "Standard — equilibrato.",
		"speed": 450.0,
		"acceleration": 900.0,
		"turn_deg": 40.0,
		"seeker_fov": 55.0,
		"range": 5000.0,
		"damage": 60.0,
		"lifetime": 11.0,
		"proximity": 25.0,
		"burn_total": 0.0,
		"burn_duration": 0.0,
		"ammo": 240,
		"color": Color(0.22, 0.28, 0.35, 1),
	},
	"HSSTDM": {
		"label": "HSSTDM",
		"full_name": "High-Speed Standard Missile",
		"description": "High Speed — 700 m/s, metà danni, alta velocità.",
		"speed": 700.0,
		"acceleration": 1500.0,
		"turn_deg": 30.0,
		"seeker_fov": 50.0,
		"range": 5000.0,
		"damage": 30.0,
		"lifetime": 8.0,
		"proximity": 25.0,
		"burn_total": 0.0,
		"burn_duration": 0.0,
		"ammo": 210,
		"color": Color(0.3, 0.72, 0.95, 1),
	},
	"BAHM": {
		"label": "BAHM",
		"full_name": "Big Ass Heavy Missile",
		"description": "Heavy — 400 m/s, danni doppi, esplosione 1.7×.",
		"speed": 400.0,
		"acceleration": 800.0,
		"turn_deg": 30.0,
		"seeker_fov": 45.0,
		"range": 5000.0,
		"damage": 120.0,
		"lifetime": 12.0,
		"proximity": 32.0,
		"burn_total": 0.0,
		"burn_duration": 0.0,
		"ammo": 120,
		"color": Color(0.18, 0.2, 0.22, 1),
		"scale": 1.35,
	},
	"NCGBM": {
		"label": "NCGBM",
		"full_name": "Napalm Charged Geneva Banned Missile",
		"description": "Napalm — infiamma 75 danni in 10s (DoT).",
		"speed": 450.0,
		"acceleration": 900.0,
		"turn_deg": 30.0,
		"seeker_fov": 55.0,
		"range": 5000.0,
		"damage": 5.0,
		"lifetime": 11.0,
		"proximity": 25.0,
		"burn_total": 75.0,
		"burn_duration": 10.0,
		"ammo": 165,
		"color": Color(0.92, 0.28, 0.12, 1),
	},
	"MTSM": {
		"label": "MTSM",
		"full_name": "Multi-Target Split Missile",
		"description": "Multi-lock — due portanti, fino a 6 sub-missili ciascuno dopo 0,4 secondi.",
		"speed": 400.0,
		"acceleration": 800.0,
		"turn_deg": 45.0,
		"seeker_fov": 65.0,
		"range": 10000.0,
		"damage": 60.0,
		"lifetime": 12.0,
		"proximity": 25.0,
		"burn_total": 0.0,
		"burn_duration": 0.0,
		"ammo": 40,
		"color": Color(0.38, 0.28, 0.52, 1),
		"salvo_size": 2,
		"max_locks": 6,
		"split_delay": 0.4,
		"split_spread_degrees": 13.0,
		"split_straight_time": 0.38,
	},
}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["STDM"])

static func ids() -> Array:
	return DEFS.keys()

static func label(id: String) -> String:
	return get_def(id).get("label", id)

static func full_name(id: String) -> String:
	return get_def(id).get("full_name", id)

static func description(id: String) -> String:
	return get_def(id)["description"]

static func range_m(id: String) -> float:
	return float(get_def(id).get("range", 5000.0))
