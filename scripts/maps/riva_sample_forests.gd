extends "res://scripts/maps/garda_forests.gd"
## Garda woodland streaming over the Riva sample: trees stand where the real land-use
## mask (masks_a.r, OpenStreetMap + ESA WorldCover) has forest, not on noise.

const LAKE_LEVEL := 65.0

@export var forest_mask: Texture2D
## masks_b.r: OSM building footprints. No trees through the building meshes.
@export var building_mask: Texture2D
@export var mask_rect := Rect2(-20480, -20480, 40960, 40960)
var buildings: MaskCover


class MaskCover:
	var image: Image
	var rect: Rect2

	func _init(texture: Texture2D, area: Rect2) -> void:
		image = texture.get_image()
		image.decompress()
		image.clear_mipmaps()
		image.convert(Image.FORMAT_R8)
		rect = area

	func sample(point: Vector3) -> Color:
		var uv := (Vector2(point.x, point.z) - rect.position) / rect.size * Vector2(image.get_size()) - Vector2(0.5, 0.5)
		if not point.is_finite() or uv.x < 0.0 or uv.y < 0.0 or uv.x >= image.get_width() - 1 or uv.y >= image.get_height() - 1:
			return Color(0, 0, 0, 0)
		var p := Vector2i(uv.floor())
		var f := uv - Vector2(p)
		return image.get_pixelv(p).lerp(image.get_pixelv(p + Vector2i.RIGHT), f.x).lerp(
			image.get_pixelv(p + Vector2i.DOWN).lerp(image.get_pixelv(p + Vector2i.ONE), f.x), f.y)


func _ready() -> void:
	noise.seed = seed_value
	noise.frequency = 0.0025
	noise.fractal_octaves = 3
	landcover = MaskCover.new(forest_mask, mask_rect)
	if building_mask != null:
		buildings = MaskCover.new(building_mask, mask_rect)
	terrain.visibility_changed.connect(func():
		for tile: Node3D in tiles.values(): tile.visible = terrain.visible)
	built = not enabled
	set_process(enabled)


func suitable_position(position: Vector3, _check_development: bool = true) -> bool:
	return position.is_finite() and position.y >= LAKE_LEVEL + 2.0 and position.y <= MAX_HEIGHT \
		and mask_rect.has_point(Vector2(position.x, position.z)) \
		and (buildings == null or buildings.sample(position).r < 0.05)
