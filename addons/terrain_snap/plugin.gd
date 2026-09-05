@tool
extends EditorPlugin

const MENU_ITEM := "Snap Selection to Terrain3D"

var _button: Button
var _snapping: bool = false


func _enter_tree() -> void:
	add_tool_menu_item(MENU_ITEM, _snap_selection)
	_button = Button.new()
	_button.text = "Snap to Terrain"
	_button.tooltip_text = "Drop the selection onto Terrain3D using the heightmap."
	var key := InputEventKey.new()
	key.keycode = KEY_PAGEDOWN
	var shortcut := Shortcut.new()
	shortcut.events = [key]
	_button.shortcut = shortcut
	_button.pressed.connect(_snap_selection)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)
	call_deferred("_take_page_down")


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if is_instance_valid(_button):
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _button)
		_button.queue_free()
	_button = null


func _take_page_down() -> void:
	if not is_instance_valid(_button):
		return
	var host := _button.get_parent()
	if host == null:
		return
	for sibling in host.get_children():
		if not (sibling is MenuButton):
			continue
		var popup: PopupMenu = (sibling as MenuButton).get_popup()
		for i in popup.item_count:
			if not _is_godot_floor_item(popup, i):
				continue
			popup.set_item_shortcut(i, Shortcut.new())
			return


func _is_godot_floor_item(popup: PopupMenu, i: int) -> bool:
	var sc: Shortcut = popup.get_item_shortcut(i)
	if sc:
		for ev in sc.events:
			if ev is InputEventKey and (ev as InputEventKey).keycode == KEY_PAGEDOWN:
				return true
	var text := popup.get_item_text(i).to_lower()
	return "floor" in text or "pavimento" in text


func _snap_selection() -> void:
	if _snapping:
		return
	_snapping = true
	_snap_selection_inner()
	_snapping = false


func _snap_selection_inner() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		_warn("No scene is open.")
		return
	var terrain := _find_terrain(scene_root)
	if terrain == null or terrain.get("data") == null:
		_warn("No Terrain3D node in this scene.")
		return
	var data = terrain.data
	var changes: Array[Dictionary] = []
	for node in _selected_node3ds():
		if node == terrain:
			continue
		var bottom := _aabb_bottom_center(node)
		var height: float = data.get_height(bottom)
		if is_nan(height):
			height = data.get_height(node.global_position)
		if is_nan(height):
			continue
		var delta := height - bottom.y
		if is_zero_approx(delta):
			continue
		var old_xf := node.global_transform
		var new_xf := old_xf
		new_xf.origin.y += delta
		changes.append({ "node": node, "old": old_xf, "new": new_xf })
	if changes.is_empty():
		_warn("Couldn't find Terrain3D height under the selection.")
		return
	var undo := get_undo_redo()
	undo.create_action("Snap Nodes to Terrain3D")
	for change in changes:
		var spatial: Node3D = change["node"]
		undo.add_do_method(spatial, "set_global_transform", change["new"])
		undo.add_undo_method(spatial, "set_global_transform", change["old"])
	undo.commit_action()


func _selected_node3ds() -> Array[Node3D]:
	var selection := EditorInterface.get_selection()
	var raw: Array = selection.get_transformable_selected_nodes()
	if raw.is_empty():
		raw = selection.get_selected_nodes()
	var out: Array[Node3D] = []
	for node in raw:
		if node is Node3D:
			out.append(node)
	return out


func _find_terrain(from: Node) -> Node:
	if from.is_class("Terrain3D"):
		return from
	var found := from.find_children("*", "Terrain3D", true, false)
	if found.is_empty():
		return null
	return found[0]


func _aabb_bottom_center(node: Node3D) -> Vector3:
	var aabb := AABB()
	var started := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is VisualInstance3D:
			var vis := current as VisualInstance3D
			var vis_aabb := vis.global_transform * vis.get_aabb()
			if started:
				aabb = aabb.merge(vis_aabb)
			else:
				aabb = vis_aabb
				started = true
		for child in current.get_children():
			stack.append(child)
	if not started:
		return node.global_position
	return Vector3(
		aabb.position.x + aabb.size.x * 0.5,
		aabb.position.y,
		aabb.position.z + aabb.size.z * 0.5
	)


func _warn(text: String) -> void:
	push_warning(text)
	var toaster = EditorInterface.get_editor_toaster()
	if toaster:
		toaster.push_toast(text, EditorToaster.SEVERITY_WARNING)
