extends Control
class_name TacticalRadarWidget

var _mode: String = "storia"
var _sweep_angle: float = 0.0
var _font: Font = null

# Authentic Military Avionics Palette
const COLOR_BG := Color(0.02, 0.04, 0.08, 0.75)
const COLOR_GRID := Color(0.15, 0.28, 0.4, 0.5)
const COLOR_GRID_BOLD := Color(0.2, 0.45, 0.65, 0.7)
const COLOR_HUD_CYAN := Color(0.3, 0.8, 1.0, 0.9)
const COLOR_HUD_GREEN := Color(0.2, 0.9, 0.4, 0.9)
const COLOR_HUD_AMBER := Color(1.0, 0.68, 0.1, 0.95)
const COLOR_HUD_RED := Color(0.95, 0.25, 0.2, 0.95)
const COLOR_TEXT_MUTED := Color(0.45, 0.62, 0.78, 0.8)


func _ready() -> void:
	_font = load("res://assets/fonts/Michroma-Regular.ttf")


func set_mode(new_mode: String) -> void:
	_mode = new_mode
	queue_redraw()


func _draw() -> void:
	var rect := get_rect()
	var center := rect.size * 0.5
	var radius := minf(rect.size.x, rect.size.y) * 0.42
	var time_sec: float = Time.get_ticks_msec() / 1000.0

	# Tactical HUD background frame
	draw_rect(Rect2(Vector2.ZERO, rect.size), COLOR_BG, true)
	draw_rect(Rect2(Vector2.ZERO, rect.size), COLOR_GRID, false, 1.0)
	_draw_corner_ticks(rect.size)

	# In Options mode: display clean professional audio VU meters
	if _mode == "options":
		_draw_audio_vu_meters(center, radius, time_sec)
		return

	# Circular military radar scope
	draw_circle(center, radius, Color(0.01, 0.03, 0.06, 0.6))
	draw_arc(center, radius, 0.0, TAU, 64, COLOR_GRID_BOLD, 1.5, true)

	# Concentric range rings
	for r_ratio in [0.33, 0.66]:
		draw_arc(center, radius * r_ratio, 0.0, TAU, 48, COLOR_GRID, 1.0, true)

	# Crosshair axes with range tick marks
	draw_line(Vector2(center.x - radius, center.y), Vector2(center.x + radius, center.y), COLOR_GRID, 1.0)
	draw_line(Vector2(center.x, center.y - radius), Vector2(center.x, center.y + radius), COLOR_GRID, 1.0)

	var ratios: Array[float] = [0.33, 0.66, 1.0]
	for r_ratio in ratios:
		var tick_d: float = radius * r_ratio
		draw_line(Vector2(center.x + tick_d, center.y - 3), Vector2(center.x + tick_d, center.y + 3), COLOR_GRID_BOLD, 1.0)
		draw_line(Vector2(center.x - tick_d, center.y - 3), Vector2(center.x - tick_d, center.y + 3), COLOR_GRID_BOLD, 1.0)
		draw_line(Vector2(center.x - 3, center.y + tick_d), Vector2(center.x + 3, center.y + tick_d), COLOR_GRID_BOLD, 1.0)
		draw_line(Vector2(center.x - 3, center.y - tick_d), Vector2(center.x + 3, center.y - tick_d), COLOR_GRID_BOLD, 1.0)

	# Cardinal compass indicators
	if _font != null:
		draw_string(_font, Vector2(center.x - 4, center.y - radius - 6), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, COLOR_HUD_CYAN)
		draw_string(_font, Vector2(center.x - 4, center.y + radius + 14), "S", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, COLOR_TEXT_MUTED)
		draw_string(_font, Vector2(center.x + radius + 6, center.y + 4), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_MUTED)
		draw_string(_font, Vector2(center.x - radius - 18, center.y + 4), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_MUTED)
		draw_string(_font, Vector2(center.x + radius * 0.33 + 4, center.y - 4), "10 KM", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_TEXT_MUTED)
		draw_string(_font, Vector2(center.x + radius * 0.66 + 4, center.y - 4), "20 KM", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_TEXT_MUTED)

	# Center aircraft reticle
	draw_line(center - Vector2(10, 0), center + Vector2(10, 0), COLOR_HUD_CYAN, 1.5)
	draw_line(center - Vector2(0, 7), center + Vector2(0, 7), COLOR_HUD_CYAN, 1.5)
	draw_arc(center, 4.0, 0.0, TAU, 16, COLOR_HUD_CYAN, 1.5)

	# Rotating radar sweep line with realistic phosphor fading trail
	_sweep_angle = fmod(time_sec * 1.8, TAU)
	var sweep_vec := Vector2(cos(_sweep_angle), sin(_sweep_angle)) * radius
	draw_line(center, center + sweep_vec, COLOR_HUD_CYAN, 1.5)
	for i in range(1, 10):
		var t_angle := _sweep_angle - float(i) * 0.04
		var t_vec := Vector2(cos(t_angle), sin(t_angle)) * radius
		var a := 0.25 * (1.0 - float(i) / 10.0)
		draw_line(center, center + t_vec, Color(COLOR_HUD_CYAN.r, COLOR_HUD_CYAN.g, COLOR_HUD_CYAN.b, a), 1.0)

	# Mode-specific tactical contacts and topography
	match _mode:
		"storia":
			_draw_storia_contacts(center, radius)
		"free_flight", "map_alps":
			_draw_alps_vector(center, radius)
		"map_coast":
			_draw_coast_vector(center, radius)
		"quit":
			_draw_quit_vector(center, radius)


func _draw_corner_ticks(size: Vector2) -> void:
	var t_len := 12.0
	var col := COLOR_GRID_BOLD
	draw_line(Vector2(4, 4), Vector2(4 + t_len, 4), col, 1.5)
	draw_line(Vector2(4, 4), Vector2(4, 4 + t_len), col, 1.5)
	draw_line(Vector2(size.x - 4, 4), Vector2(size.x - 4 - t_len, 4), col, 1.5)
	draw_line(Vector2(size.x - 4, 4), Vector2(size.x - 4, 4 + t_len), col, 1.5)
	draw_line(Vector2(4, size.y - 4), Vector2(4 + t_len, size.y - 4), col, 1.5)
	draw_line(Vector2(4, size.y - 4), Vector2(4, size.y - 4 - t_len), col, 1.5)
	draw_line(Vector2(size.x - 4, size.y - 4), Vector2(size.x - 4 - t_len, size.y - 4), col, 1.5)
	draw_line(Vector2(size.x - 4, size.y - 4), Vector2(size.x - 4, size.y - 4 - t_len), col, 1.5)


func _draw_storia_contacts(center: Vector2, radius: float) -> void:
	# Military target diamond contacts with callsign tags
	var targets: Array[Dictionary] = [
		{"pos": Vector2(0.48, -0.4), "id": "TGT-01", "alt": "3500M"},
		{"pos": Vector2(0.62, -0.22), "id": "TGT-02", "alt": "4100M"},
		{"pos": Vector2(-0.38, 0.45), "id": "TGT-03", "alt": "2800M"},
		{"pos": Vector2(-0.55, -0.35), "id": "TGT-04", "alt": "5200M"}
	]
	for t in targets:
		var p: Vector2 = center + (t["pos"] as Vector2) * radius
		_draw_diamond(p, 5.0, COLOR_HUD_AMBER)
		if _font != null:
			draw_string(_font, p + Vector2(8, 2), "%s  [%s]" % [t["id"], t["alt"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_HUD_AMBER)


func _draw_atoll_vector(center: Vector2, radius: float) -> void:
	# Precise vector contour of the coral atoll
	var points: Array[Vector2] = []
	var count := 32
	for i in range(count + 1):
		var a := float(i) / float(count) * TAU
		var n := 1.0 + sin(a * 3.0) * 0.15 + cos(a * 5.0) * 0.08
		points.append(center + Vector2(cos(a), sin(a)) * (radius * 0.5 * n))
	for i in range(count):
		draw_line(points[i], points[i + 1], COLOR_HUD_GREEN, 1.5)

	# Flight path arrow
	var p_start := center + Vector2(-radius * 0.65, radius * 0.4)
	var p_end := center + Vector2(radius * 0.65, -radius * 0.5)
	draw_line(p_start, p_end, COLOR_HUD_CYAN, 1.0)
	draw_circle(p_end, 3.5, COLOR_HUD_GREEN)
	if _font != null:
		draw_string(_font, p_end + Vector2(8, 4), "CORRIDOR // UNRESTRICTED", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_HUD_GREEN)


func _draw_alps_vector(center: Vector2, radius: float) -> void:
	# Clean alpine ridge contour lines
	var ridge: Array[Vector2] = [
		center + Vector2(-radius * 0.8, -radius * 0.1),
		center + Vector2(-radius * 0.4, -radius * 0.6),
		center + Vector2(0.0, -radius * 0.3),
		center + Vector2(radius * 0.45, -radius * 0.68),
		center + Vector2(radius * 0.8, -radius * 0.18)
	]
	for i in range(ridge.size() - 1):
		draw_line(ridge[i], ridge[i + 1], COLOR_HUD_CYAN, 1.5)

	if _font != null:
		draw_string(_font, ridge[1] + Vector2(-15, -8), "PEAK 4810M", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_HUD_CYAN)


func _draw_coast_vector(center: Vector2, radius: float) -> void:
	var coast: Array[Vector2] = []
	for i in range(21):
		var t := float(i) / 20.0
		var y := lerpf(-radius * 0.8, radius * 0.8, t)
		var x := center.x + sin(t * PI * 1.5) * (radius * 0.4) - radius * 0.1
		coast.append(Vector2(x, center.y + y))
	for i in range(coast.size() - 1):
		draw_line(coast[i], coast[i + 1], COLOR_HUD_CYAN, 1.5)
	if _font != null:
		draw_string(_font, center + Vector2(radius * 0.1, radius * 0.3), "SHORELINE // BARNEGAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_TEXT_MUTED)


func _draw_quit_vector(center: Vector2, radius: float) -> void:
	var sz := radius * 0.4
	draw_rect(Rect2(center - Vector2(sz, sz), Vector2(sz * 2.0, sz * 2.0)), COLOR_HUD_RED, false, 1.0)
	draw_line(center - Vector2(sz * 1.2, 0), center + Vector2(sz * 1.2, 0), COLOR_HUD_RED, 1.0)
	draw_line(center - Vector2(0, sz * 1.2), center + Vector2(0, sz * 1.2), COLOR_HUD_RED, 1.0)
	if _font != null:
		draw_string(_font, center + Vector2(-radius * 0.35, -sz - 8), "DISENGAGE SESSION", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_HUD_RED)


func _draw_audio_vu_meters(center: Vector2, radius: float, time_sec: float) -> void:
	# Clean military avionics VU meter channels: Master, Music, SFX
	var channels := ["MASTER", "MUSIC", "SFX"]
	var bar_w := radius * 0.35
	var bar_h := 18.0
	var start_y := center.y - 45.0

	for i in range(3):
		var y := start_y + float(i) * 36.0
		var label_pos := Vector2(center.x - radius * 0.8, y + 13.0)
		var bar_x := center.x - radius * 0.2

		if _font != null:
			draw_string(_font, label_pos, channels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_HUD_CYAN)

		# Meter frame
		draw_rect(Rect2(Vector2(bar_x, y), Vector2(bar_w * 2.0, bar_h)), Color(0.05, 0.09, 0.15, 0.8), true)
		draw_rect(Rect2(Vector2(bar_x, y), Vector2(bar_w * 2.0, bar_h)), COLOR_GRID, false, 1.0)

		# Discrete LED segments (12 segments per bar)
		var segs := 14
		var seg_w := (bar_w * 2.0 - 4.0) / float(segs) - 2.0
		var level := sin(time_sec * 4.0 + float(i) * 1.5) * 0.3 + 0.65

		for s in range(segs):
			var s_ratio := float(s) / float(segs)
			if s_ratio <= level:
				var sx := bar_x + 2.0 + float(s) * (seg_w + 2.0)
				var col := COLOR_HUD_GREEN if s_ratio < 0.7 else (COLOR_HUD_AMBER if s_ratio < 0.88 else COLOR_HUD_RED)
				draw_rect(Rect2(Vector2(sx, y + 2.0), Vector2(seg_w, bar_h - 4.0)), col, true)

	if _font != null:
		draw_string(_font, Vector2(center.x - radius * 0.7, start_y + 120.0), "AUDIO BUS TELEMETRY // CALIBRATED", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_TEXT_MUTED)


func _draw_diamond(pos: Vector2, size: float, color: Color) -> void:
	var pts := PackedVector2Array([
		pos + Vector2(0, -size),
		pos + Vector2(size, 0),
		pos + Vector2(0, size),
		pos + Vector2(-size, 0)
	])
	draw_polyline(pts, color, 1.5, true)
