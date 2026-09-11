extends SceneTree
## Headless probe: find steep high slopes where snow/rock/vegetation mix.
## Read-only terrain sampling; never saves. Run:
## Godot --headless --path . --script tools/terrain_view_probe.gd

const MAP := "res://scenes/maps/garda_final.tscn"
const STEP := 120.0
const MIX_RADIUS := 150.0
const SNOW := 4
const ROCK := [0, 1]
const VEG := [2, 3]

func _initialize() -> void:
	call_deferred("probe")

func probe() -> void:
	var map := load(MAP).instantiate() as Node3D
	root.add_child(map)
	var terrain = map.get_node("GardaTerrain")
	var data = terrain.data
	for method in ["get_height", "get_normal", "get_control", "get_control_base_id",
			"get_control_overlay_id", "get_control_blend", "get_color"]:
		print("Terrain3DData.", method, ": ", data.has_method(method))
	var spacing: float = terrain.vertex_spacing
	var regions := [Vector2i(-8, -8), Vector2i(-8, -7), Vector2i(-8, -6), Vector2i(-7, -8)]
	var candidates: Array[Dictionary] = []
	for region in regions:
		var corner := Vector2(region) * 1024.0 * spacing
		var z := corner.y
		while z < corner.y + 1024.0 * spacing:
			var x := corner.x
			while x < corner.x + 1024.0 * spacing:
				var pos := Vector3(x, 0, z)
				var h: float = data.get_height(pos)
				if is_finite(h) and h > 1100.0:
					var n: Vector3 = data.get_normal(pos)
					if is_finite(n.y) and n.y < 0.72:
						var ids := _texture_mix(data, pos)
						var kinds := _kinds(ids)
						if kinds.size() >= 3:
							pos.y = h
							candidates.append({"pos": pos, "normal": n, "ids": ids, "kinds": kinds,
								"steep": 1.0 - n.y})
				x += STEP
			z += STEP
	candidates.sort_custom(func(a, b): return _rank(a) > _rank(b))
	print("Candidates: ", candidates.size())
	for i in mini(20, candidates.size()):
		var c: Dictionary = candidates[i]
		print("  %d pos=%s h=%.0f n=%s ids=%s" % [i, c.pos, c.pos.y,
			Vector3(c.normal.x, c.normal.y, c.normal.z), c.ids])
	# Valley floor spots ringed by peaks for the wide view.
	var valley: Array[Dictionary] = []
	for region in regions:
		var corner := Vector2(region) * 1024.0 * spacing
		var z := corner.y
		while z < corner.y + 1024.0 * spacing:
			var x := corner.x
			while x < corner.x + 1024.0 * spacing:
				var pos := Vector3(x, 0, z)
				var h: float = data.get_height(pos)
				if is_finite(h) and h < 900.0:
					var peaks := 0
					for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
							Vector2(1, 1), Vector2(-1, -1)]:
						var hp: float = data.get_height(Vector3(pos.x + dir.x * 4000.0, 0,
							pos.z + dir.y * 4000.0))
						if is_finite(hp) and hp > 1700.0:
							peaks += 1
					if peaks >= 3:
						pos.y = h
						valley.append({"pos": pos, "peaks": peaks})
				x += STEP * 2.0
			z += STEP * 2.0
	print("Valley candidates: ", valley.size())
	for i in mini(10, valley.size()):
		print("  v%d pos=%s peaks=%d" % [i, valley[i].pos, valley[i].peaks])
	# Evaluate proposed eyes along the normal of candidate 0.
	var target: Vector3 = Vector3(-120920.0, 1876.0, -114800.0)
	var dir: Vector3 = Vector3(0.960731, 0.0, -0.170304).normalized()
	for dist in [800.0, 3000.0, 7000.0]:
		var eye: Vector3 = target + dir * dist
		eye.y = target.y + dist * 0.26
		var ground: float = data.get_height(eye)
		print("dist=%.0f eye=%s ground=%.0f clearance=%.0f" % [dist, eye, ground,
			eye.y - ground if is_finite(ground) else -1.0])
		# Ground heights between eye and target (occlusion check).
		for frac in [0.25, 0.5, 0.75]:
			var mid: Vector3 = eye.lerp(target, frac)
			print("   f=%.2f mid_ground=%.0f mid_sight=%.0f" % [frac,
				data.get_height(mid), mid.y])
	quit()

func _rank(c: Dictionary) -> float:
	return c.kinds.size() * 10.0 + c.steep

func _texture_mix(data, pos: Vector3) -> Array:
	var seen := {}
	for ring in [0.0, MIX_RADIUS]:
		var count := 1 if ring == 0.0 else 8
		for i in count:
			var angle := TAU * i / count
			var p := Vector3(pos.x + cos(angle) * ring, 0, pos.z + sin(angle) * ring)
			var base := -1
			var over := -1
			if data.has_method("get_control_base_id"):
				base = data.get_control_base_id(p)
				over = data.get_control_overlay_id(p)
			elif data.has_method("get_control"):
				var control: int = data.get_control(p)
				base = control & 0x1F
				over = (control >> 27) & 0x1F
			if base >= 0:
				seen[base] = true
			if over >= 0:
				seen[over] = true
	return seen.keys()

func _kinds(ids: Array) -> Array:
	var kinds := {}
	for id in ids:
		if id == SNOW:
			kinds["snow"] = true
		elif id in ROCK:
			kinds["rock"] = true
		elif id in VEG:
			kinds["veg"] = true
	return kinds.keys()
