extends RefCounted
## Per-scene immutable map. CPU samples use R; the original RGBA image backs GPU shading.
## RG: woodland/cultivation; BA: unsigned 16-bit height in -128..4096 metres.
const SOURCE := "res://resources/terrain/garda_landcover.res"
const EXTENT := 250000.0

var cpu_image: Image
var gpu_texture: ImageTexture

func _init() -> void:
	var rgba_image := ResourceLoader.load(SOURCE, "Image", ResourceLoader.CACHE_MODE_IGNORE) as Image
	assert(rgba_image != null and rgba_image.get_format() == Image.FORMAT_RGBA8)
	assert(rgba_image.has_mipmaps())
	gpu_texture = ImageTexture.create_from_image(rgba_image)
	cpu_image = rgba_image.duplicate() as Image
	cpu_image.convert(Image.FORMAT_R8)
	assert(cpu_image.get_format() == Image.FORMAT_R8 and cpu_image.has_mipmaps())

func sample(point: Vector3) -> Color:
	var uv := (Vector2(point.x, point.z) / EXTENT + Vector2(0.5, 0.5)) * cpu_image.get_width() - Vector2(0.5, 0.5)
	if not point.is_finite() or uv.x < 0.0 or uv.y < 0.0 or uv.x >= cpu_image.get_width() - 1 or uv.y >= cpu_image.get_height() - 1:
		return Color(0, 0, 0, 0)
	var p := Vector2i(uv.floor())
	var f := uv - Vector2(p)
	return cpu_image.get_pixelv(p).lerp(cpu_image.get_pixelv(p + Vector2i.RIGHT), f.x).lerp(
		cpu_image.get_pixelv(p + Vector2i.DOWN).lerp(cpu_image.get_pixelv(p + Vector2i.ONE), f.x), f.y)
