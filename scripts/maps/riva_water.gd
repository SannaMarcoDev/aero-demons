@tool
extends MeshInstance3D
## Binds the Terrain3D height maps to the lake shader (resources/shaders/garda_water.gdshader): the
## lake bed gives the water its depth. RenderingServer-only, as Terrain3D's particle example.
@export var terrain: Terrain3D

func _ready() -> void:
	if terrain == null or terrain.data == null:
		return
	for changed in [terrain.data.region_map_changed, terrain.data.height_maps_changed, terrain.data.maps_changed]:
		if not changed.is_connected(_bind):
			changed.connect(_bind)
	_bind()

func _bind() -> void:
	var material := (mesh as PrimitiveMesh).material if mesh is PrimitiveMesh else null
	if material == null or terrain == null or terrain.data == null:
		return
	var rid := material.get_rid()
	RenderingServer.material_set_param(rid, "terrain_heights", terrain.data.get_height_maps_rid())
	RenderingServer.material_set_param(rid, "terrain_region_map", terrain.data.get_region_map())
	RenderingServer.material_set_param(rid, "terrain_region_size", terrain.region_size)
	RenderingServer.material_set_param(rid, "terrain_vertex_spacing", terrain.vertex_spacing)
