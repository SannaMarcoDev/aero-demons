extends RefCounted
## One immutable map for distant terrain, local trees and lake depth. No visited-area state.
## RG: woodland/cultivation; BA: unsigned 16-bit height in -128..4096 metres.
const IMAGE: Image = preload("res://resources/terrain/garda_landcover.res")
const EXTENT := 250000.0

static func sample(point: Vector3) -> Color:
	var uv := (Vector2(point.x, point.z) / EXTENT + Vector2(0.5, 0.5)) * IMAGE.get_width() - Vector2(0.5, 0.5)
	if not point.is_finite() or uv.x < 0.0 or uv.y < 0.0 or uv.x >= IMAGE.get_width() - 1 or uv.y >= IMAGE.get_height() - 1:
		return Color(0, 0, 0, 0)
	var p := Vector2i(uv.floor())
	var f := uv - Vector2(p)
	return IMAGE.get_pixelv(p).lerp(IMAGE.get_pixelv(p + Vector2i.RIGHT), f.x).lerp(
		IMAGE.get_pixelv(p + Vector2i.DOWN).lerp(IMAGE.get_pixelv(p + Vector2i.ONE), f.x), f.y)
