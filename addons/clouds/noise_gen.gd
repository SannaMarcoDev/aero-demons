class_name CloudNoiseGen
extends RefCounted

## One-time CPU generation of the seamless billow/detail volume
## and the 2D weather map (coverage / wetness / type). Static deck: these
## are built once at startup and never touched again.

const NOISE_3D_SIZE := 128
const WEATHER_SIZE := 1024
const WEATHER_WORLD_M := 100000.0

# Mild fixed elongation of the broad weather formations only.
# The 3D billows remain isotropic in the horizontal plane.
const WIND_DIR := Vector2(0.928, 0.371)
const WIND_PERP := Vector2(-0.371, 0.928)
const WIND_STRETCH := 1.25


static func _remap(v: float, lo: float, hi: float, out_lo: float, out_hi: float) -> float:
	return out_lo + (out_hi - out_lo) * clampf((v - lo) / maxf(hi - lo, 1e-5), 0.0, 1.0)


## RG: rounded cellular billows. BA: subordinate smooth turbulence.
## Use the native seamless generator: repeat-wrapping arbitrary samples
## cut vertical planes through the old clouds at every texture boundary.
static func make_noise_3d() -> PackedByteArray:
	var n := NOISE_3D_SIZE
	var data := PackedByteArray()
	data.resize(n * n * n * 4)
	for ch in 4:
		var noise := FastNoiseLite.new()
		noise.seed = 555 + ch * 137
		noise.frequency = [3.0, 7.0, 16.0, 32.0][ch] / n
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR if ch < 2 else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		var slices := noise.get_seamless_image_3d(n, n, n, ch < 2, 0.25)
		for z in n:
			slices[z].convert(Image.FORMAT_L8)
			var pixels := slices[z].get_data()
			for xy in n * n:
				data[(z * n * n + xy) * 4 + ch] = pixels[xy]
	return data


## Full mip chain for the 3D noise volume: array of RGBA8 byte arrays,
## level 0 first, each level a 2x2x2 box downsample of the previous.
static func make_noise_3d_mips() -> Array:
	var levels: Array = [make_noise_3d()]
	var size := NOISE_3D_SIZE
	while size > 1:
		var prev: PackedByteArray = levels.back()
		size /= 2
		var next := PackedByteArray()
		next.resize(size * size * size * 4)
		var i := 0
		for z in size:
			for y in size:
				for x in size:
					for ch in 4:
						var acc := 0
						for dz in 2:
							for dy in 2:
								for dx in 2:
									var pi := (((z * 2 + dz) * size * 2 + (y * 2 + dy)) * size * 2 + (x * 2 + dx)) * 4 + ch
									acc += prev[pi]
						next[i] = acc / 8
						i += 1
		levels.append(next)
	return levels


## RGBA8 2D weather map covering WEATHER_WORLD_M. R = coverage 0..1,
## G = wetness (density multiplier), B = cluster height potential,
## A = footprint mask. Coverage fades to a low mean at the borders.
static func make_weather() -> PackedByteArray:
	var n := WEATHER_SIZE
	# Cumulus massifs ~9 km: real cumulus formations are several km
	# across — 30/1024 cells gave ~1.7 km lumps (the popcorn field).
	var cells := FastNoiseLite.new()
	cells.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cells.fractal_type = FastNoiseLite.FRACTAL_FBM
	cells.fractal_octaves = 2
	cells.frequency = 6.5 / n
	cells.seed = 1234
	# Smaller secondary formations fill the broad clear lanes without
	# turning every original massif into a continuous flat sheet.
	var small_cells := FastNoiseLite.new()
	small_cells.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	small_cells.fractal_type = FastNoiseLite.FRACTAL_FBM
	small_cells.fractal_octaves = 3
	small_cells.frequency = 10.0 / n
	small_cells.seed = 8123

	# Regional clustering ~17 km: massifs group into streets/patches
	# with wide clear lanes between groups.
	var region := FastNoiseLite.new()
	region.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	region.fractal_type = FastNoiseLite.FRACTAL_FBM
	region.fractal_octaves = 3
	region.frequency = 3.0 / n
	region.seed = 999

	# Per-cluster tower height: same scale as cells so a massif's top
	# altitude is coherent across its footprint — sub-peaks come from
	# crown erosion, not per-pixel height scatter.
	var hgt := FastNoiseLite.new()
	hgt.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hgt.fractal_type = FastNoiseLite.FRACTAL_FBM
	hgt.fractal_octaves = 3
	hgt.frequency = 8.0 / n
	hgt.seed = 4242

	# Per-cluster density/wetness, slightly finer for sub-peak variation.
	var wet := FastNoiseLite.new()
	wet.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wet.fractal_type = FastNoiseLite.FRACTAL_FBM
	wet.fractal_octaves = 3
	wet.frequency = 9.0 / n
	wet.seed = 777

	var data := PackedByteArray()
	data.resize(n * n * 4)
	var i := 0
	for y in n:
		for x in n:
			# Wind frame: compress the along-wind axis so footprints
			# elongate 1.25x downwind instead of staying round.
			var along := (float(x) * WIND_DIR.x + float(y) * WIND_DIR.y) / WIND_STRETCH
			var across := float(x) * WIND_PERP.x + float(y) * WIND_PERP.y
			var c := clampf(maxf(cells.get_noise_2d(along, across) * 0.5 + 0.5,
					(small_cells.get_noise_2d(along, across) * 0.5 + 0.5) * 0.83),
				0.0, 1.0)
			var r := clampf(region.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			# Sharp-edged massifs; the survival threshold drops where the
			# regional field is dense — sparse regions scatter isolated
			# towers, dense regions pack clustered streets.
			var w := clampf(wet.get_noise_2d(along, across) * 0.5 + 0.5, 0.0, 1.0)
			var cov := _remap(c, lerpf(0.32, 0.27, r), 0.82, 0.0, 1.0)
			# Do not carve 2D tower slots: they shred one coherent formation
			# into disconnected columns. The 3D field supplies the billows.
			# Alpha retains the footprint for the weather diagnostic tool.
			var foot := _remap(c, lerpf(0.45, 0.31, r), 0.55, 0.0, 1.0)
			# Border fade — to the MEAN coverage, not zero. A zero border
			# is a transparent ring around the map: grazing rays sample it
			# past 50 km and see straight through to the sky — a bright
			# razor line at the deck's silhouette edge.
			var fx := minf(x, n - 1 - x) / (n * 0.08)
			var fy := minf(y, n - 1 - y) / (n * 0.08)
			var bf := clampf(minf(fx, fy), 0.0, 1.0)
			cov = lerpf(0.22, cov, bf)
			# Stronger cells tower higher: height correlates with cell
			# strength plus a coherent per-cluster noise term.
			var t := clampf(c * 0.20
					+ (hgt.get_noise_2d(along, across) * 0.5 + 0.5) * 0.90
					- 0.15, 0.0, 1.0)
			data[i] = int(cov * 255.0)
			data[i + 1] = int(w * 255.0)
			data[i + 2] = int(t * 255.0)
			data[i + 3] = int(foot * 255.0)
			i += 4
	return data


## Full mip chain for the weather map: array of RGBA8 byte arrays, level
## 0 (1024^2) first, each level a 2x2 box downsample. textureLod() in the
## shader needs real mip levels — a mipless texture silently clamps to 0
## and every smoothed-coverage gate reads full-res speckle instead.
static func make_weather_mips() -> Array:
	var levels: Array = [make_weather()]
	var size := WEATHER_SIZE
	while size > 4:
		var prev: PackedByteArray = levels.back()
		size /= 2
		var next := PackedByteArray()
		next.resize(size * size * 4)
		var i := 0
		for y in size:
			for x in size:
				for ch in 4:
					var acc := 0
					for dy in 2:
						for dx in 2:
							acc += prev[((y * 2 + dy) * size * 2 + (x * 2 + dx)) * 4 + ch]
					next[i] = acc / 4
					i += 1
		levels.append(next)
	return levels


# The 10x10 grid only accelerates the bake. The denser morphology samples
# follow the weather locally, merging into broken banks and emergent crowns.
const CLOUD_CELLS := 10
const FIELD_CLAMP := 4000.0
const SHAPE_BLEND := 250.0

# Fixed, repeatable compositions. Reuse the existing weather/noise assets;
# only the macro bodies and their baked lighting change when switching.
enum Preset { ORIGINAL, SPARSE, CLOUD_SEA, TALL_CUMULUS }
const PRESET_SETTINGS := {
	Preset.ORIGINAL: {"seed": 0, "coverage": 1.0, "regional": 0.80, "width": 1.0, "height": 1.0, "rise": 0.0},
	Preset.SPARSE: {"seed": 137, "coverage": 0.77, "regional": 0.90, "width": 0.85, "height": 0.85, "rise": 0.0},
	Preset.CLOUD_SEA: {"seed": 281, "coverage": 1.85, "regional": 0.15, "width": 1.05, "height": 0.60, "rise": 0.07},
	Preset.TALL_CUMULUS: {"seed": 419, "coverage": 0.76, "regional": 1.0, "width": 0.72, "height": 1.0, "rise": 0.20},
}


static func make_cloud_lobes(base: float, top: float, coverage: float,
		weather: PackedByteArray, preset: Preset = Preset.ORIGINAL) -> PackedFloat32Array:
	var style: Dictionary = PRESET_SETTINGS.get(preset, PRESET_SETTINGS[Preset.ORIGINAL])
	var data := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	var region := FastNoiseLite.new()
	region.seed = 999 + style.seed
	region.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	region.fractal_type = FastNoiseLite.FRACTAL_NONE
	region.frequency = 2.7 / WEATHER_WORLD_M
	var vertical_scale := (top - base) / 13000.0
	var add := func(center: Vector3, radius: Vector3, angle: float) -> void:
		var ry := radius.y * vertical_scale
		# Clearance in conservative-distance units, including tall ellipsoids.
		var clearance := 650.0 * vertical_scale * ry / minf(radius.x, minf(ry, radius.z))
		var y := maxf(base + center.y * vertical_scale, base + clearance + ry)
		data.append_array([center.x, y, center.z, cos(angle),
			radius.x, ry, radius.z, sin(angle)])
	# Sample the weather across the whole footprint, not just once per
	# branching tower group. Neighbors overlap into banks; weak margins
	# shrink into small clouds and clear regions stay genuinely empty.
	# ponytail: 2.5km morphology samples; refine if regional contours alias.
	for z in 40:
		for x in 40:
			# Local detail edits must not reshuffle unrelated formations.
			rng.seed = 73191 + (z * 40 + x) * 15731 + style.seed
			var center := Vector3((x + rng.randf_range(0.12, 0.88)) * WEATHER_WORLD_M / 40.0,
				0.0, (z + rng.randf_range(0.12, 0.88)) * WEATHER_WORLD_M / 40.0)
			var regional := smoothstep(0.30, 0.70, region.get_noise_2d(center.x, center.z) * 0.5 + 0.5)
			var wx := clampi(int(center.x / WEATHER_WORLD_M * WEATHER_SIZE), 0, WEATHER_SIZE - 1)
			var wz := clampi(int(center.z / WEATHER_WORLD_M * WEATHER_SIZE), 0, WEATHER_SIZE - 1)
			var wi := (wz * WEATHER_SIZE + wx) * 4
			var local_coverage: float = weather[wi] / 255.0 * coverage * style.coverage
			var strength := smoothstep(0.32, 0.78, local_coverage + (regional - 0.5) * style.regional)
			strength *= smoothstep(0.0, 0.20, local_coverage)
			if strength < (0.55 if preset == Preset.TALL_CUMULUS else 0.08):
				continue
			var rise := smoothstep(0.40, 0.72, weather[wi + 2] / 255.0 + style.rise) * smoothstep(0.12, 0.75, strength)
			var height: float = (950.0 + 7200.0 * pow(rise, 1.5) + weather[wi + 1] * 2.0) * style.height
			var width: float = lerpf(400.0, 3400.0, strength) * style.width
			var radius := Vector3(width * rng.randf_range(0.90, 1.25), height * 0.5,
				width * rng.randf_range(0.80, 1.15))
			var angle := rng.randf() * TAU
			center.y = 1000.0 + height * 0.5
			add.call(center - Vector3(0.0, radius.y * 0.45, 0.0),
				Vector3(radius.x, radius.y * 0.55, radius.z), angle)
			add.call(center, radius * 0.70, angle)
			# The core is buried beneath unequal overlapping shoulders,
			# rather than exposing a smooth oval dressed in tiny satellites.
			for lobe in 5 + int(rise * 10.0):
				var y := rng.randf_range(-0.35, 0.95)
				var a := rng.randf() * TAU
				var dir := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y))
				var c := center + (dir * radius * rng.randf_range(0.52, 0.65)).rotated(Vector3.UP, -angle)
				var r := minf(radius.x, minf(radius.y, radius.z)) * rng.randf_range(0.45, 0.72)
				var shoulder := Vector3(r * rng.randf_range(0.9, 1.4), r * rng.randf_range(0.85, 1.15), r)
				add.call(c, shoulder, a)
				# Sub-voxel satellites contribute no useful contour at 195m.
				for detail in (rng.randi_range(3, 6) if r > 650.0 else 0):
					var dy := rng.randf_range(0.10, 0.95)
					var da := rng.randf() * TAU
					var d := Vector3(cos(da) * sqrt(1.0 - dy * dy), dy, sin(da) * sqrt(1.0 - dy * dy))
					var dc := c + (d * shoulder * 0.78).rotated(Vector3.UP, -a)
					var dr := r * rng.randf_range(0.30, 0.48)
					add.call(dc, Vector3(dr, dr * 0.85, dr * 1.15), da)
	return data


static func make_cloud_cells(base: float, top: float, coverage: float,
		weather: PackedByteArray, preset: Preset = Preset.ORIGINAL) -> PackedFloat32Array:
	var lobes := make_cloud_lobes(base, top, coverage, weather, preset)
	var bins: Array[PackedFloat32Array] = []
	bins.resize(CLOUD_CELLS * CLOUD_CELLS)
	var cell_m := WEATHER_WORLD_M / CLOUD_CELLS
	for i in range(0, lobes.size(), 8):
		var c := Vector3(lobes[i], lobes[i + 1], lobes[i + 2])
		var r := Vector3(lobes[i + 4], lobes[i + 5], lobes[i + 6])
		var co := lobes[i + 3]
		var si := lobes[i + 7]
		# Any omitted primitive has distance > clamp + blend everywhere
		# in this bin, so cannot affect either density OR distance skipping.
		var expanded := r * (1.0 + (FIELD_CLAMP + SHAPE_BLEND) / minf(r.x, minf(r.y, r.z)))
		var reach := Vector2(Vector2(expanded.x * co, expanded.z * si).length(),
			Vector2(expanded.x * si, expanded.z * co).length())
		for z in range(floori((c.z - reach.y) / cell_m), floori((c.z + reach.y) / cell_m) + 1):
			for x in range(floori((c.x - reach.x) / cell_m), floori((c.x + reach.x) / cell_m) + 1):
				var bx := posmod(x, CLOUD_CELLS)
				var bz := posmod(z, CLOUD_CELLS)
				bins[bz * CLOUD_CELLS + bx].append_array([
					c.x + (bx - x) * cell_m, c.y, c.z + (bz - z) * cell_m, co,
					r.x, r.y, r.z, si])
	# One vec4 range per bin, followed by its contiguous ellipsoid pairs.
	# Keep CPU order in every bin: smooth union must not change at bin edges.
	var data := PackedFloat32Array()
	data.resize(CLOUD_CELLS * CLOUD_CELLS * 4)
	for bin in bins.size():
		data[bin * 4] = data.size() / 4
		data.append_array(bins[bin])
		data[bin * 4 + 1] = data.size() / 4
	return data


## Heavily downsampled weather map for distant samples: grazing rays
## stretch the full-res map into radial streaks, so beyond ~12 km we read
## this smooth 128^2 version instead. Alpha carries the cluster footprint
## mask — already soft-edged from its wider remap — straight through the
## box downsample.
static func make_weather_lo(hi: PackedByteArray) -> PackedByteArray:
	var n := WEATHER_SIZE
	var out_n := 128
	var box := n / out_n
	var data := PackedByteArray()
	data.resize(out_n * out_n * 4)
	var i := 0
	for y in out_n:
		for x in out_n:
			for ch in 4:
				var acc := 0
				for dy in box:
					for dx in box:
						acc += hi[((y * box + dy) * n + (x * box + dx)) * 4 + ch]
				data[i] = acc / (box * box)
				i += 1
	return data
