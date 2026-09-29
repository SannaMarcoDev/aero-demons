extends RefCounted
## Data-only recordings. Never deserialize objects, scripts or arbitrary scene paths.

const VERSION := 1
const MAGIC := "AERODEMONS-REPLAY\n"
const DIRECTORY := "user://replays"
const MAX_BYTES := 256 * 1024 * 1024
const MAX_SECONDS := 7200.0
const VIEWER := "res://scenes/replay/replay_viewer.tscn"
const LEVELS := {
	"res://scenes/levels/freeroam.tscn": "res://scenes/maps/garda_final.tscn",
	"res://scenes/levels/tutorial.tscn": "res://scenes/maps/garda_final.tscn",
	"res://scenes/levels/freeroam_utah.tscn": "res://scenes/maps/utah_final.tscn",
	"res://scenes/levels/tutorial_utah.tscn": "res://scenes/maps/utah_final.tscn",
}
const SCENES := [
	"res://scenes/player/player.tscn", "res://scenes/enemies/enemy_fighter.tscn",
	"res://scenes/weapons/missile.tscn", "res://scenes/weapons/bullet.tscn",
	"res://scenes/vfx/explosion_fx.tscn", "res://scenes/vfx/energy_sphere.tscn",
	"res://assets/BinbunVFX/muzzle_flash/effects/short_flash/short_flash_02.tscn",
	"res://assets/BinbunVFX/impact_explosions/effects/hit/vfx_hit_02.tscn",
]
const MODELS := ["res://scenes/aircraft/saab_ja37.tscn", "res://scenes/aircraft/su27.tscn", "res://assets/aircraft/mig29/mig29.glb"]
const VISUAL_SCRIPTS := [
	"res://scripts/aircraft/saab_controls.gd", "res://scripts/aircraft/su27_controls.gd",
	"res://scripts/vfx/afterburner.gd", "res://scenes/vfx/jet_exhaust.gd",
	"res://scripts/vfx/damage_fire.gd", "res://scripts/vfx/explosion_fx.gd",
	"res://scripts/vfx/energy_sphere.gd", "res://scripts/weapons/missile.gd",
	"res://assets/BinbunVFX/shared/script/vfx_controller.gd",
	"res://assets/BinbunVFX/shared/script/vfx_light.gd",
]
const PROPERTIES := ["transform", "visible", "emitting", "amount_ratio", "light_energy", "light_color", "omni_range", "_power", "_clock", "throttle", "intensity", "_ballistic", "_flame_emission_scale", "_smoke_intensity", "playing", "pitch_scale", "volume_db", "playback", "alpha_multiplier"]

static func script_path(node: Node) -> String:
	var script: Script = node.get_script()
	return script.resource_path if script != null else ""

static func is_actor(node: Node) -> bool:
	return node is Node3D and (node.scene_file_path in SCENES or node is AudioStreamPlayer3D)

static func sound_allowed(path: String) -> bool:
	return path.begins_with("res://assets/audio/") and not ".." in path and path.get_extension().to_lower() in ["mp3", "wav", "ogg"] and ResourceLoader.exists(path)

static func lower_key(keys: Array, time: float) -> int:
	var low := 0
	var high := keys.size()
	while low < high:
		var mid := (low + high) >> 1
		if float(keys[mid][0]) <= time:
			low = mid + 1
		else:
			high = mid
	return maxi(low - 1, 0)

static func value_at(keys: Array, time: float, interpolate := true, cut_teleports := false) -> Variant:
	var index := lower_key(keys, time)
	var a: Array = keys[index]
	if not interpolate or index + 1 >= keys.size():
		return a[1]
	var b: Array = keys[index + 1]
	var weight := clampf((time - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.000001), 0.0, 1.0)
	if a[1] is Transform3D:
		# Teleports (intro/handoff/respawn) are cuts, not flights through the map.
		if cut_teleports and a[1].origin.distance_to(b[1].origin) > maxf(100.0, (float(b[0]) - float(a[0])) * 3000.0):
			return a[1]
		if absf(a[1].basis.determinant()) < 0.0000001 or absf(b[1].basis.determinant()) < 0.0000001:
			return a[1]
		return a[1].interpolate_with(b[1], weight)
	if a[1] is float:
		return lerpf(a[1], b[1], weight)
	if a[1] is Color:
		return a[1].lerp(b[1], weight)
	return a[1]

static func save_file(path: String, recording: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var bytes := var_to_bytes(recording)
	if bytes.size() > MAX_BYTES:
		return "Registrazione troppo grande (limite 256 MiB)."
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return "Impossibile scrivere il replay: " + error_string(FileAccess.get_open_error())
	file.store_buffer(MAGIC.to_utf8_buffer())
	file.store_32(bytes.size())
	file.store_buffer(bytes.compress(FileAccess.COMPRESSION_ZSTD))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return "Scrittura replay fallita: " + error_string(error)
	error = DirAccess.rename_absolute(path + ".tmp", path)
	return "" if error == OK else "Salvataggio replay fallito: " + error_string(error)

static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Replay non leggibile."}
	if file.get_length() > MAX_BYTES or file.get_length() < MAGIC.length() + 4:
		return {"error": "Dimensione replay non valida."}
	if file.get_buffer(MAGIC.length()).get_string_from_utf8() != MAGIC:
		return {"error": "Non è un replay Aero Demons."}
	var size := file.get_32()
	if size <= 0 or size > MAX_BYTES:
		return {"error": "Dimensione dati non valida."}
	var bytes := file.get_buffer(file.get_length() - file.get_position()).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if bytes.size() != size:
		return {"error": "Replay incompleto o danneggiato."}
	var value: Variant = bytes_to_var(bytes)
	var error := validate(value)
	return {"data": value} if error.is_empty() else {"error": error}

static func valid_value(value: Variant) -> bool:
	if value is Transform3D:
		return value.is_finite()
	if value is float:
		return is_finite(value)
	if value is Color:
		return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	return value is bool

static func valid_keys(keys: Variant, duration: float, value_type := -1) -> bool:
	if not keys is Array or keys.is_empty() or keys.size() > 500000:
		return false
	var previous := -1.0
	var type := typeof(keys[0][1]) if keys[0] is Array and keys[0].size() == 2 else -1
	for key in keys:
		if not key is Array or key.size() != 2 or not (key[0] is float or key[0] is int):
			return false
		var time := float(key[0])
		if not is_finite(time) or time < previous or time < 0.0 or time > duration + 0.1 or not valid_value(key[1]):
			return false
		if typeof(key[1]) != type or (value_type >= 0 and type != value_type):
			return false
		previous = time
	return true

static func validate(value: Variant) -> String:
	if not value is Dictionary or value.get("version") != VERSION:
		return "Versione replay non supportata."
	if not value.get("level", "") in LEVELS or not (value.get("duration") is float):
		return "Mappa o durata non valida."
	var duration: float = value.duration
	if not is_finite(duration) or duration < 0.0 or duration > MAX_SECONDS + 1.0:
		return "Durata replay non valida."
	if not value.get("map_transform") is Transform3D or not valid_value(value.map_transform):
		return "Trasformazione mappa non valida."
	if not value.get("actors") is Array or value.actors.size() > 100000:
		return "Elenco attori non valido."
	if not valid_keys(value.get("camera", []), duration, TYPE_TRANSFORM3D) or not valid_keys(value.get("fov", []), duration, TYPE_FLOAT):
		return "Traccia camera non valida."
	for field in ["shot", "shot_fov"]:
		if not value.get(field) is Array:
			return "Traccia regia non valida."
		if not value.get(field, []).is_empty() and not valid_keys(value[field], duration, TYPE_TRANSFORM3D if field == "shot" else TYPE_FLOAT):
			return "Traccia regia danneggiata."
	if value.get("shot", []).is_empty() != value.get("shot_fov", []).is_empty():
		return "Traccia regia incompleta."
	for actor in value.actors:
		if not actor is Dictionary or not actor.get("scene", "") in SCENES + ["audio"]:
			return "Attore non supportato."
		if not actor.get("born") is float or not actor.get("end") is float or not is_finite(actor.born) or not is_finite(actor.end) or actor.born < 0.0 or actor.end < actor.born or actor.end > duration + 0.1:
			return "Intervallo attore non valido."
		if not actor.get("label") is String or not actor.get("model") in MODELS + [""] or not actor.get("settings") is Dictionary:
			return "Descrizione attore non valida."
		for key in actor.get("settings", {}):
			var setting: Variant = actor.settings[key]
			match key:
				"missile_id":
					if not setting is String or not setting in ["STDM", "HSSTDM", "MTSM", "BAHM", "NCGBM"]:
						return "Tipo missile non supportato."
				"autoplay", "local_coords", "light_enable":
					if not setting is bool: return "Opzione effetto non valida."
				"effect_seed":
					if not setting is int: return "Seed non valido."
				"overall_scale", "intensity", "smoke_amount", "sparks_amount":
					if not setting is float or not is_finite(setting) or setting < 0.0 or setting > 8.0:
						return "Scala effetto non valida."
				_:
					return "Configurazione attore non supportata."
		if actor.scene == "audio":
			if not actor.get("sound") is String or not sound_allowed(actor.sound):
				return "Risorsa audio non supportata."
		if not valid_keys(actor.get("poses", []), duration, TYPE_TRANSFORM3D) or not actor.get("channels") is Array or actor.channels.size() > 4096:
			return "Tracce attore non valide."
		for channel in actor.channels:
			if not channel is Dictionary or not channel.get("path") is String or not channel.get("property", "") in PROPERTIES:
				return "Proprietà replay non supportata."
			var type := TYPE_FLOAT
			match channel.property:
				"transform": type = TYPE_TRANSFORM3D
				"visible", "emitting", "_ballistic", "playing": type = TYPE_BOOL
				"light_color": type = TYPE_COLOR
			var path: String = channel.path
			if path.begins_with("/") or ":" in path or ".." in path or not valid_keys(channel.get("keys", []), duration, type):
				return "Traccia proprietà non valida."
	return ""

## Runnable format/interpolation regression check, without a test framework.
## godot --headless --path . res://scenes/replay/replay_viewer.tscn -- --replay-self-check
static func self_check() -> Dictionary:
	var start := Transform3D.IDENTITY
	var finish := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(10, 0, 0))
	var keys := [[0.0, start], [2.0, finish]]
	assert(lower_key(keys, -1.0) == 0 and lower_key(keys, 3.0) == 1)
	assert(value_at(keys, 1.0).origin.is_equal_approx(Vector3(5, 0, 0)))
	assert(value_at([[0.0, true], [1.0, false]], 0.5) == true)
	var sample := {"version": VERSION, "level": LEVELS.keys()[0], "map_transform": start,
		"duration": 2.0, "camera": keys, "fov": [[0.0, 65.0]], "shot": [], "shot_fov": [], "actors": []}
	for scene in SCENES:
		sample.actors.append({"scene": scene, "label": "Self-check", "model": "", "settings": {},
			"born": 0.0, "end": 2.0, "poses": keys, "channels": [{"path": ".", "property": "visible", "keys": [[0.0, true]]}]})
	assert(validate(sample).is_empty())
	var path := DIRECTORY.path_join(".self-check-%d.tmp-replay" % Time.get_ticks_usec())
	assert(save_file(path, sample).is_empty())
	var loaded := load_file(path)
	assert(loaded.has("data") and loaded.data.actors.size() == SCENES.size())
	assert(DirAccess.remove_absolute(path) == OK)
	sample.version = -1
	assert(not validate(sample).is_empty())
	sample = loaded.data.duplicate(true)
	sample.erase("shot")
	assert(not validate(sample).is_empty())
	sample = loaded.data.duplicate(true)
	sample.actors[0].erase("settings")
	assert(not validate(sample).is_empty())
	sample = loaded.data.duplicate(true)
	sample.actors[0].channels[0].keys[0][1] = 1.0
	assert(not validate(sample).is_empty())
	return loaded.data
