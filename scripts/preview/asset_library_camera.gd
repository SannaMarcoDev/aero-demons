extends "res://scripts/camera/free_fly_camera.gd"
## Review-only navigation. Production scenes never reference this script.

# The first ten entries are the urban catalog (four residential, six functional).
# Landmarks and the road sample are deliberately not counted as buildings.
const ASSETS := ["ResidenceGabled", "ResidenceCourtyard", "ResidenceL", "ResidenceTerraced",
	"IndustrialShed", "OfficesTwins", "OfficeSpire", "ResearchCenter", "CivicCanopy",
	"WarehouseVault", "ControlTower", "SatelliteDish", "RoadManager"]
const TITLES := ["01 / PALAZZINA A FALDE", "02 / RESIDENZA A CORTE", "03 / RESIDENZA A L",
	"04 / TORRE RESIDENZIALE A TERRAZZE — 107 m", "05 / CAPANNONE A SHED",
	"06 / TORRI DIREZIONALI COLLEGATE — 116 m", "07 / TORRE A CORONA OBLIQUA — 132 m",
	"08 / CENTRO RICERCA A GRADONI", "09 / CENTRO CIVICO", "10 / DEPOSITO A VOLTA",
	"11 / TORRE DI CONTROLLO — 70 m", "12 / PARABOLA — Ø 70 m", "13 / INCROCIO — ROADMANAGER"]
const HEIGHTS := [8.0, 10.0, 15.0, 53.0, 6.0, 57.0, 65.0, 18.0, 14.0, 10.0, 35.0, 33.0, 0.0]
var selected := 0


func _ready() -> void:
	super._ready()
	focus_asset(0)


func focus_asset(index: int) -> void:
	assert(index >= 0 and index <= ASSETS.size())
	selected = index
	if index == 0:
		position = Vector3(680, 500, 870)
		look_at(Vector3(0, 28, -105))
		get_node("../HUD/Margin/VBox/Selection").text = "10 EDIFICI / 4 RESIDENZIALI + 6 FUNZIONALI / TORRE, PARABOLA E STRADE"
	else:
		var target: Vector3 = get_parent().get_node(ASSETS[index - 1]).position + Vector3.UP * HEIGHTS[index - 1]
		var offset := Vector3(95, 65, 130) * (1.5 if HEIGHTS[index - 1] > 45.0 else 1.0)
		position = target + offset
		look_at(target)
		get_node("../HUD/Margin/VBox/Selection").text = TITLES[index - 1] + " / vista a circa %d m" % roundi(offset.length())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			focus_asset(event.keycode - KEY_0)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT:
			focus_asset(posmod(selected + (1 if event.keycode == KEY_RIGHT else -1), ASSETS.size() + 1))
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_HOME:
			focus_asset(0)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)
