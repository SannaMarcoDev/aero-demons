@tool
extends Node3D
## Bind across the city scene boundary without changing the user's map or roads.

func _ready() -> void:
	var terrain := get_node_or_null("../GardaTerrain") as Terrain3D
	if terrain != null:
		$RoadTerrain.terrain = terrain
		_connect_user_road.call_deferred()

func _connect_user_road() -> void:
	var target := get_node_or_null("../RoadManager/TwoLaneRoads/WestEnd") as RoadPoint
	var point := $RoadManager/Ground/UserRoadLink as RoadPoint
	if target == null or point.is_prior_connected() or target.is_next_connected():
		return # Never replace a connection the user has authored.
	point.global_transform = target.global_transform
	point.container.update_edges()
	target.container.update_edges()
	point.connect_container(RoadPoint.PointInit.PRIOR, target, RoadPoint.PointInit.NEXT)
