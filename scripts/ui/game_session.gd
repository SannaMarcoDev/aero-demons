extends RefCounted
class_name GameSession
## Stato cross-scena minimal: mappa + missile scelti. Static var persiste finché il processo vive.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const LOADOUT := "res://scenes/ui/loadout.tscn"
const DOGFIGHT := "res://scenes/levels/tutorial.tscn"
const FREE_FLIGHT := "res://scenes/levels/freeroam.tscn"

static var selected_map: String = FREE_FLIGHT
static var menu_section := ""
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


static func level_name() -> String:
	return "GARDA · VOLO LIBERO" if free_flight else "GARDA · DOGFIGHT"


static func change_scene(tree: SceneTree, path: String) -> Error:
	var was_paused := tree.paused
	tree.paused = false
	var error := tree.change_scene_to_file(path)
	if error != OK:
		tree.paused = was_paused
		push_error("Cannot open %s: %s" % [path, error_string(error)])
	else:
		var audio := tree.root.get_node_or_null("AudioManager")
		if audio != null:
			audio.stop_alarm()
	return error
