extends RefCounted
## Baked from the city footprints, roads and airfield safety strips; CPU-only Image.
## Shared by forest and grass so neither can grow through the delivered development.
const ORIGIN := Vector2(-36418.484, 413.42773)
const MINIMUM := Vector2(-4000, -3300)
const PIXEL_METRES := 7.0
const MASK: Image = preload("res://resources/terrain/garda_development.res")

static func contains(point: Vector3) -> bool:
	if not point.is_finite():
		return false
	var pixel := Vector2i(((Vector2(point.x, point.z) - ORIGIN - MINIMUM) / PIXEL_METRES).floor())
	return Rect2i(Vector2i.ZERO, MASK.get_size()).has_point(pixel) and MASK.get_pixelv(pixel).r > 0.5
