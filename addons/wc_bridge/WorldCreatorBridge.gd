@tool
extends Control

# References to the UI nodes
# Terrain tab (the Sync XML path lives here; the Objects sync reuses its value)
@onready var path_line_edit: LineEdit = $VBoxContainer/ControlsContainer/TabContainer/Terrain/HBoxContainer_XML/XMLLineEdit
@onready var browse_button: Button = $VBoxContainer/ControlsContainer/TabContainer/Terrain/HBoxContainer_XML/BrowseButton
@onready var name_line_edit: LineEdit = $VBoxContainer/ControlsContainer/TabContainer/Terrain/HBoxContainer_Name/NameLineEdit
@onready var auto_vertex_spacing: Button = $VBoxContainer/ControlsContainer/TabContainer/Terrain/HBoxContainer_VertexSpacing/AutoVertexSpacingButton
@onready var sync_terrain_button: Button = $VBoxContainer/ControlsContainer/TabContainer/Terrain/SyncTerrainButton
@onready var vertex_spacing_spinbox: SpinBox = $VBoxContainer/ControlsContainer/TabContainer/Terrain/HBoxContainer_VertexSpacing/SpinBox
@onready var height_scale_spinbox: SpinBox = $VBoxContainer/ControlsContainer/TabContainer/Terrain/HBoxContainer_Scales/HBox_Height/SpinBox
@onready var world_scale_spinbox: SpinBox = $VBoxContainer/ControlsContainer/TabContainer/Terrain/HBoxContainer_Scales/HBox_World/SpinBox
@onready var enable_triplanar_projection_checkbox: CheckBox = $VBoxContainer/ControlsContainer/TabContainer/Terrain/HBoxContainer_TriplanarProjection/CheckBox
# Objects tab
@onready var reset_objects_checkbox: CheckBox = $VBoxContainer/ControlsContainer/TabContainer/Objects/HBoxContainer_ResetObjects/CheckBox
@onready var sync_objects_button: Button = $VBoxContainer/ControlsContainer/TabContainer/Objects/SyncObjectsButton
# Common
@onready var error_label: Label = $VBoxContainer/ErrorLabel
@onready var controls_container: Control = $VBoxContainer/ControlsContainer

var file_dialog: FileDialog
var terrain3d_available: bool = false

# --- WC object-import transform (ported from the Blender bridge) ---
# The Blender bridge consumes WC instance data in a left-handed, Z-up frame: it uses
# (tx,ty,tz) directly as position, applies the WC quaternion directly (just reordered
# to w,x,y,z), and pre-rotates each model +90 deg about its up axis. We reproduce that
# here, converted into Godot's Y-up world and aligned to the transposed/flipped
# heightmap the terrain import produces. WC_TO_GODOT drives BOTH position and rotation
# so they stay consistent; its columns are the Godot images of WC's tx/ty/tz axes:
#   WC tx (east) -> Godot +Z ,  WC ty (north) -> Godot +X ,  WC tz (up) -> Godot +Y
const WC_TO_GODOT := Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))
const WC_MODEL_YAW_DEG: float = 0.0    # extra model-facing yaw about up. Blender needs +90 (its glTF import pre-rotates models); Godot keeps models Y-up, so none is needed.
const WC_SCALE_CONST: float = 1000.0   # size_m ~= |scale| * WC_SCALE_CONST * ModelScale (10x obj * 100x point scale)
const WC_POSITION_SCALE: float = 1024.0 # WC normalizes instance positions so 1.0 = this many meters (FIXED reference, not the terrain size; matches the Blender bridge's *1024)
const WC_OVERRIDE_SHADER := "res://resources/terrain/terrain_wc_override.gdshader" # shared patched Terrain3D shader, built by tools/build_terrain_override.gd

func _enter_tree():
	# Signals are connected in _ready()
	pass

func _exit_tree():
	# Clean up resources
	_terrain3d_util = null
	if file_dialog and is_instance_valid(file_dialog):
		file_dialog.queue_free()
		file_dialog = null

func _ready(): 
	# Check if Terrain3D plugin is enabled by checking the project settings
	var enabled_plugins = ProjectSettings.get_setting("editor_plugins/enabled", [])
	terrain3d_available = "res://addons/terrain_3d/plugin.cfg" in enabled_plugins
	
	if not terrain3d_available:
		_show_error_message()
		return
	
	# Hide error label if Terrain3D is available
	if error_label:
		error_label.visible = false
	
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Select World Creator Sync XML"
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.xml ; XML Metadata"]
	file_dialog.file_selected.connect(_on_xml_selected)
	# Add dialog as child so it's managed properly
	add_child(file_dialog)
	
	# Connect buttons
	browse_button.pressed.connect(show_file_dialog)
	auto_vertex_spacing.pressed.connect(_on_auto_vertex_spacing_pressed)
	sync_terrain_button.pressed.connect(_on_sync_terrain_button_pressed)
	sync_objects_button.pressed.connect(_on_sync_objects_pressed)
	
	# Default Values
	var defaultXmlPath = OS.get_system_dir(OS.SystemDir.SYSTEM_DIR_DOCUMENTS).path_join("World Creator/Sync/bridge.xml")
	path_line_edit.text = defaultXmlPath
	name_line_edit.text = "WC_Terrain"
	
	world_scale_spinbox.value = 1
	height_scale_spinbox.value = 1
	vertex_spacing_spinbox.value = 1
	if FileAccess.file_exists(defaultXmlPath):
		_on_auto_vertex_spacing_pressed()

func _show_error_message():
	# Hide all controls
	if controls_container:
		controls_container.visible = false
	
	# Show error message
	if error_label:
		error_label.visible = true
		error_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	
# ----------------------------------------------------------------------
# --- EXISTING UI AND IMPORT FUNCTIONS ---

func show_file_dialog():
	file_dialog.popup_centered()
	
func _on_xml_selected(path: String):
	path_line_edit.text = path
	_on_auto_vertex_spacing_pressed()

func _on_auto_vertex_spacing_pressed():
	var xml_path = path_line_edit.text
	if not FileAccess.file_exists(xml_path):
		push_error("XML file not found: " + xml_path)
		return
	
	var parser = XMLParser.new()
	if parser.open(xml_path) != OK:
		push_error("Failed to parse XML: " + xml_path)
		return
	
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "Surface":
			var width = parser.get_named_attribute_value("Width").to_float()
			var length = parser.get_named_attribute_value("Length").to_float()
			var res_x = parser.get_named_attribute_value("ResolutionX").to_float()
			var res_y = parser.get_named_attribute_value("ResolutionY").to_float()
			
			if res_x > 0 and res_y > 0:
				var meters_per_px = max(width / res_x, length / res_y)
				vertex_spacing_spinbox.value = meters_per_px
				print("Auto-set vertex_spacing to %.2f (%.0fm terrain / %d px = %.2f m/px)" % [
					meters_per_px, width, int(res_x), meters_per_px
				])
			break

func _on_sync_terrain_button_pressed() -> void:
	if not terrain3d_available:
		_warn("Terrain3D is not available.\nPlease install and enable the Terrain3D plugin.")
		return

	var xml_path: String = path_line_edit.text
	if not FileAccess.file_exists(xml_path):
		_warn("Sync XML not found:\n%s" % xml_path)
		return

	var metadata = _parse_wc_xml(xml_path)
	if metadata.is_empty():
		_warn("Failed to parse required metadata from:\n%s" % xml_path)
		return

	# Warn if Vertex Spacing differs from the ideal for this heightmap's resolution
	# (the value the Auto button would set). Let the user keep theirs or switch.
	var ideal_vs: float = _ideal_vertex_spacing(metadata)
	if ideal_vs > 0.0 and not is_equal_approx(vertex_spacing_spinbox.value, ideal_vs):
		if await _confirm_use_ideal(vertex_spacing_spinbox.value, ideal_vs):
			vertex_spacing_spinbox.value = ideal_vs

	var terrain_name: String = name_line_edit.text
	var vertex_spacing: float = vertex_spacing_spinbox.value
	var height_scale: float = height_scale_spinbox.value
	var world_scale: float = world_scale_spinbox.value
	var enable_triplanar_projection: bool = enable_triplanar_projection_checkbox.button_pressed

	print("=== Starting Terrain Import === \n%s (spacing: %.1f)" % [terrain_name, vertex_spacing])

	var resource_dir = "res://wc_data/%s" % terrain_name
	_create_resource_directory(resource_dir)

	await _import_heightmap_tiles(xml_path, metadata, terrain_name, resource_dir, vertex_spacing, world_scale, height_scale, enable_triplanar_projection)

	print("=== IMPORT COMPLETE ===\n")

# The vertex spacing that exactly matches the heightmap resolution (what the Auto
# button sets): meters-per-pixel = max(width/resX, length/resY).
func _ideal_vertex_spacing(metadata: Dictionary) -> float:
	var rx: float = float(metadata.get("resolution_x", 0))
	var ry: float = float(metadata.get("resolution_y", 0))
	if rx <= 0.0 or ry <= 0.0:
		return 0.0
	return max(float(metadata.get("width", 0)) / rx, float(metadata.get("length", 0)) / ry)

# Asks whether to switch Vertex Spacing to the ideal value. Returns true for "use
# ideal", false to keep the current setting. Blocks (via await) until the user picks.
func _confirm_use_ideal(current_vs: float, ideal_vs: float) -> bool:
	var dlg := ConfirmationDialog.new()
	dlg.title = "WC Bridge — Vertex Spacing"
	dlg.dialog_text = "Vertex Spacing is %.3f, but the ideal for this terrain's heightmap resolution is %.3f.\n\nA non-ideal value resamples the heightmap (lower detail or wasted resolution). Use the ideal value, or keep your current setting?" % [current_vs, ideal_vs]
	dlg.ok_button_text = "Use ideal (%.3f)" % ideal_vs
	add_child(dlg)
	dlg.get_cancel_button().text = "Keep %.3f" % current_vs
	var result := {"ideal": false}
	dlg.confirmed.connect(func() -> void: result["ideal"] = true)
	dlg.popup_centered()
	while dlg.visible:
		await get_tree().process_frame
	dlg.queue_free()
	return result["ideal"]

# ----------------------------------------------------------------------
# --- OBJECT IMPORT (instance_info.xml / detail_info.xml) ---
# Scene objects (e.g. the castle) are placed as real GLB nodes under "WC_SceneObjects".
# Biome instances (trees/bushes/logs) become GPU-instanced foliage via the Terrain3D
# instancer. Detail objects (density heatmaps) are not handled yet.

# Shows a modal warning dialog in the editor (and logs it), used to cancel the object
# sync with a visible reason — e.g. no terrain present — rather than a silent error.
func _warn(message: String) -> void:
	push_warning(message)
	var dlg := AcceptDialog.new()
	dlg.title = "WC Bridge"
	dlg.dialog_text = message
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)

func _on_sync_objects_pressed() -> void:
	if not terrain3d_available:
		_warn("Terrain3D is not available.\nPlease install and enable the Terrain3D plugin.")
		return

	var xml_path: String = path_line_edit.text
	if not FileAccess.file_exists(xml_path):
		_warn("Sync XML not found:\n%s" % xml_path)
		return

	var base_dir: String = xml_path.get_base_dir()
	var instance_info_path: String = base_dir.path_join("instance_info.xml")
	var detail_info_path: String = base_dir.path_join("detail_info.xml")
	var has_instance: bool = FileAccess.file_exists(instance_info_path)
	var has_detail: bool = FileAccess.file_exists(detail_info_path)
	if not has_instance and not has_detail:
		_warn("No instance_info.xml or detail_info.xml found next to:\n%s" % xml_path)
		return

	# Need the edited scene + the Terrain3D node the terrain was synced into.
	if not Engine.has_singleton("EditorInterface"):
		push_error("Could not access EditorInterface. Is the script running as a @tool?")
		return
	var editor_interface = Engine.get_singleton("EditorInterface")
	var scene_root = editor_interface.get_edited_scene_root()
	if not scene_root:
		_warn("No scene is open.\nOpen the scene with your terrain, then Sync Objects.")
		return

	var terrain_name: String = name_line_edit.text
	var terrain_node = scene_root.find_child(terrain_name, false, false)
	if not (terrain_node is Terrain3D):
		_warn("No Terrain3D node named \"%s\" found in the scene.\n\nSync a terrain first (Terrain tab), then Sync Objects." % terrain_name)
		return

	# Terrain dimensions come from bridge.xml's <Surface>.
	var metadata: Dictionary = _parse_wc_xml(xml_path)
	if metadata.is_empty():
		_warn("Could not read terrain metadata from:\n%s" % xml_path)
		return

	var world_scale: float = world_scale_spinbox.value
	var height_scale: float = height_scale_spinbox.value

	print("=== Sync Objects ===")

	# Free any previously-placed instances first (scene objects are re-placed
	# wholesale each sync), before touching the imported files they reference.
	var objects_root: Node3D = _recreate_objects_root(scene_root)

	# Imported object models live alongside the terrain data.
	var resource_dir: String = "res://wc_data/%s" % terrain_name
	var objects_dir: String = resource_dir.path_join("objects")
	if reset_objects_checkbox.button_pressed:
		print("Reset Objects: ON — re-importing object models (instancer clear comes with biome placement)")
		_delete_dir_recursive(objects_dir)
	_create_resource_directory(objects_dir)

	# Parse object metadata. Scene objects become real GLB nodes; biome objects
	# (trees/bushes/logs) become GPU-instanced foliage; detail objects become
	# density-scattered GPU foliage from their heatmap.
	var scene_objs: Array = []
	var biome_objs: Array = []
	var detail_objs: Array = []
	if has_instance:
		var objs: Array = _parse_object_info(instance_info_path)
		print("instance_info.xml -> %d object(s):" % objs.size())
		for o in objs:
			if o.kind == "scene":
				scene_objs.append(o)
			else:
				biome_objs.append(o)
	if has_detail:
		detail_objs = _parse_object_info(detail_info_path)
		print("detail_info.xml -> %d object(s)" % detail_objs.size())

	# Copy any not-yet-imported model GLBs into the project, then let Godot's glTF
	# importer process them (same pipeline as dragging a .glb into the FileSystem).
	var fs = editor_interface.get_resource_filesystem()
	var pending := PackedStringArray()
	for o in (scene_objs + biome_objs + detail_objs):
		if String(o.glb_path) == "":
			continue
		var glb_abs: String = base_dir.path_join(String(o.glb_path).replace("\\", "/"))
		var res_path: String = objects_dir.path_join(glb_abs.get_file())
		if ResourceLoader.exists(res_path):
			continue
		if not FileAccess.file_exists(glb_abs):
			push_error("Model file not found: %s" % glb_abs)
			continue
		if DirAccess.copy_absolute(glb_abs, ProjectSettings.globalize_path(res_path)) == OK:
			pending.append(res_path)
		else:
			push_error("Failed to copy GLB into project: %s" % res_path)
	if not pending.is_empty():
		fs.scan()
		# is_scanning() goes false before the IMPORT step finishes, so poll until the
		# resources are actually loadable (with a timeout) rather than just the scan.
		var frames: int = 0
		while frames < 1800:
			await get_tree().process_frame
			frames += 1
			var all_ready: bool = true
			for rp in pending:
				if not ResourceLoader.exists(rp):
					all_ready = false
					break
			if all_ready:
				break
		if frames >= 1800:
			push_warning("Timed out waiting for model import; some biome models may be missing.")

	# Place scene objects as real GLB nodes.
	var scene_placed: int = 0
	for o in scene_objs:
		scene_placed += _place_scene_object(o, base_dir, terrain_node, metadata, world_scale, height_scale, objects_root, scene_root, objects_dir)
	if objects_root.get_child_count() == 0:
		scene_root.remove_child(objects_root)
		objects_root.queue_free()
	else:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(objects_root)

	# Place biome + detail objects via the Terrain3D instancer (GPU-instanced foliage).
	# Clear previously-instanced WC meshes first so re-syncing replaces, not stacks.
	var biome_placed: int = 0
	var detail_placed: int = 0
	if not biome_objs.is_empty() or not detail_objs.is_empty():
		_clear_instancer(terrain_node)
		var mesh_id: int = 0
		for o in biome_objs:
			biome_placed += _place_biome_object(o, base_dir, terrain_node, metadata, world_scale, height_scale, objects_dir, mesh_id)
			mesh_id += 1
		for o in detail_objs:
			detail_placed += _place_detail_object(o, base_dir, terrain_node, metadata, world_scale, height_scale, objects_dir, mesh_id)
			mesh_id += 1
		if terrain_node.assets and terrain_node.data_directory:
			var assets_path = terrain_node.data_directory.path_join("wc_terrain_assets.tres")
			ResourceSaver.save(terrain_node.assets, assets_path)
			terrain_node.assets = load(assets_path)

	print("=== Sync Objects complete: %d scene-object instance(s), %d biome + %d detail instance(s) ===" % [scene_placed, biome_placed, detail_placed])

# Places every instance of a SceneObjectList entry as a real GLB node. Returns the
# number of instances placed.
func _place_scene_object(obj: Dictionary, base_dir: String, terrain_node, metadata: Dictionary, world_scale: float, height_scale: float, objects_root: Node3D, scene_root: Node, objects_dir: String) -> int:
	if obj.glb_path == "" or obj.instance_files.is_empty():
		push_warning("Scene object '%s' has no model or instance data; skipping." % obj.name)
		return 0

	# Load the model that was imported into the project by the copy/scan pass in
	# _on_sync_objects_pressed. Instances reference this on-disk .glb scene, so they
	# render reliably and save compactly, and the same asset feeds the instancer later.
	var glb_file: String = String(obj.glb_path).replace("\\", "/").get_file()
	var res_path: String = objects_dir.path_join(glb_file)
	if not ResourceLoader.exists(res_path):
		push_error("Model was not imported into the project: %s" % res_path)
		return 0
	var packed = ResourceLoader.load(res_path)
	if not (packed is PackedScene):
		push_error("Imported model is not a scene: %s" % res_path)
		return 0

	# Normalize against the model's largest dimension (matches the Blender bridge,
	# which normalizes every model to 1 m before applying WC's scale fields).
	var probe: Node = packed.instantiate()
	var mesh_dim: float = _scene_max_dimension(probe)
	probe.free()
	if mesh_dim <= 0.0:
		mesh_dim = 1.0

	var placed: int = 0
	for inst_file in obj.instance_files:
		var csv_path: String = base_dir.path_join(String(inst_file.file_name))
		var rows: Array = _read_instance_csv(csv_path)
		if rows.is_empty():
			push_warning("No instance rows read from: %s" % csv_path)
			continue
		for row in rows:
			var xform: Transform3D = _wc_instance_transform(row, terrain_node, metadata, world_scale, height_scale, float(obj.model_scale), mesh_dim)
			var inst: Node = packed.instantiate()
			inst.name = "%s_%d" % [obj.name, placed]
			objects_root.add_child(inst)
			inst.owner = scene_root
			if inst is Node3D:
				(inst as Node3D).transform = xform
			placed += 1
			if placed <= 8:
				var pos := xform.origin
				var scl := xform.basis.get_scale()
				print("    %s[%d] pos=(%.1f, %.1f, %.1f) size~%.1fm" % [obj.name, placed - 1, pos.x, pos.y, pos.z, maxf(scl.x, maxf(scl.y, scl.z)) * mesh_dim])

	print("  - [scene] \"%s\": placed %d instance(s) (model ~%.2fm, ModelScale %s)" % [obj.name, placed, mesh_dim, str(obj.model_scale)])
	return placed

# Registers a biome object's model as a Terrain3DMeshAsset and instances every CSV
# row through the Terrain3D instancer (GPU-instanced foliage). Returns instance count.
func _place_biome_object(obj: Dictionary, base_dir: String, terrain_node, metadata: Dictionary, world_scale: float, height_scale: float, objects_dir: String, mesh_id: int) -> int:
	if obj.glb_path == "" or obj.instance_files.is_empty():
		push_warning("Biome object '%s' has no model or instance data; skipping." % obj.name)
		return 0

	var glb_file: String = String(obj.glb_path).replace("\\", "/").get_file()
	var res_path: String = objects_dir.path_join(glb_file)
	if not ResourceLoader.exists(res_path):
		push_error("Model was not imported into the project: %s" % res_path)
		return 0
	var packed = ResourceLoader.load(res_path)
	if not (packed is PackedScene):
		push_error("Imported model is not a scene: %s" % res_path)
		return 0

	# Register the model as a mesh asset in the terrain's asset list.
	if terrain_node.assets == null:
		var assets_path = terrain_node.data_directory.path_join("wc_terrain_assets.tres") if terrain_node.data_directory else ""
		if assets_path != "" and ResourceLoader.exists(assets_path):
			terrain_node.assets = load(assets_path)
		else:
			terrain_node.assets = Terrain3DAssets.new()
	var asset := Terrain3DMeshAsset.new()
	asset.set_id(mesh_id)
	asset.set_name(obj.name)
	asset.set_scene_file(packed)
	asset.set_enabled(true)
	terrain_node.assets.set_mesh_asset(mesh_id, asset)

	# Normalize against the asset mesh's own AABB. The instancer renders the raw mesh
	# and ignores the source node's unit-conversion scale (e.g. mm->m or inch->m), so
	# the visual scene size would be the wrong normalizer here.
	var mesh_dim: float = _mesh_asset_max_dimension(asset)
	if mesh_dim <= 0.0:
		mesh_dim = 1.0

	# Build a Transform3D per instance and hand them to the instancer in one batch.
	var transforms: Array[Transform3D] = []
	for inst_file in obj.instance_files:
		var csv_path: String = base_dir.path_join(String(inst_file.file_name))
		for row in _read_instance_csv(csv_path):
			transforms.append(_wc_instance_transform(row, terrain_node, metadata, world_scale, height_scale, float(obj.model_scale), mesh_dim))

	if not transforms.is_empty():
		# DEBUG: report placed world-space bounds to compare against the terrain extents.
		var mn: Vector3 = transforms[0].origin
		var mx: Vector3 = transforms[0].origin
		for t in transforms:
			mn = mn.min(t.origin)
			mx = mx.max(t.origin)
		print("    [debug] \"%s\" world bounds: X[%.0f .. %.0f]  Z[%.0f .. %.0f]" % [obj.name, mn.x, mx.x, mn.z, mx.z])
		terrain_node.instancer.add_transforms(mesh_id, transforms)

	var sample_m: float = 0.0
	if not transforms.is_empty():
		var sc: Vector3 = transforms[0].basis.get_scale()
		sample_m = maxf(sc.x, maxf(sc.y, sc.z)) * mesh_dim
	print("  - [biome] \"%s\": %d instance(s) via instancer (mesh_id %d, ~%.1fm each)" % [obj.name, transforms.size(), mesh_id, sample_m])
	return transforms.size()

# The Terrain3D instancer renders the asset's raw mesh (it does NOT bake the source
# MeshInstance3D node scale, which carries glTF unit conversion like mm->m). Normalize
# biome scale against this raw mesh AABB so instances come out the right size.
func _mesh_asset_max_dimension(asset) -> float:
	if not asset.has_method("get_mesh"):
		return 0.0
	var m = asset.get_mesh(0)
	if not (m is Mesh):
		return 0.0
	var s: Vector3 = (m as Mesh).get_aabb().size
	return maxf(s.x, maxf(s.y, s.z))

# Clears all Terrain3D instancer instances for meshes the WC bridge manages, so an
# object re-sync replaces rather than stacks. (This bridge owns the terrain's foliage.)
func _clear_instancer(terrain_node) -> void:
	var assets = terrain_node.assets
	if assets == null:
		return
	for i in range(assets.get_mesh_count()):
		terrain_node.instancer.clear_by_mesh(i)

# Density-scatters a detail object across the terrain from its heatmap PNG (brighter
# = denser), with random scale/rotation per the WC procedural params, into the
# Terrain3D instancer. NOTE: an approximation of WC's scatter — tune as needed.
func _place_detail_object(obj: Dictionary, base_dir: String, terrain_node, metadata: Dictionary, world_scale: float, height_scale: float, objects_dir: String, mesh_id: int) -> int:
	if obj.glb_path == "" or obj.heatmap_files.is_empty():
		push_warning("Detail object '%s' has no model or heatmap; skipping." % obj.name)
		return 0

	var glb_file: String = String(obj.glb_path).replace("\\", "/").get_file()
	var res_path: String = objects_dir.path_join(glb_file)
	if not ResourceLoader.exists(res_path):
		push_error("Model was not imported into the project: %s" % res_path)
		return 0
	var packed = ResourceLoader.load(res_path)
	if not (packed is PackedScene):
		return 0

	if terrain_node.assets == null:
		var assets_path = terrain_node.data_directory.path_join("wc_terrain_assets.tres") if terrain_node.data_directory else ""
		if assets_path != "" and ResourceLoader.exists(assets_path):
			terrain_node.assets = load(assets_path)
		else:
			terrain_node.assets = Terrain3DAssets.new()
	var asset := Terrain3DMeshAsset.new()
	asset.set_id(mesh_id)
	asset.set_name(obj.name)
	asset.set_scene_file(packed)
	asset.set_enabled(true)
	terrain_node.assets.set_mesh_asset(mesh_id, asset)
	var mesh_dim: float = _mesh_asset_max_dimension(asset)
	if mesh_dim <= 0.0:
		mesh_dim = 1.0

	# Density heatmap (grayscale; use the red channel as density 0..1).
	var heatmap_path: String = base_dir.path_join(String(obj.heatmap_files[0].file_name))
	var img := Image.load_from_file(heatmap_path)
	if img == null:
		push_error("Could not load detail heatmap: %s" % heatmap_path)
		return 0
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var hw: int = img.get_width()
	var hh: int = img.get_height()

	var width_m: float = float(metadata.width) * world_scale
	var length_m: float = float(metadata.length) * world_scale
	var inst_dist: float = maxf(float(obj.instance_distance), 1.0)
	var density: float = clampf(float(obj.density), 0.0, 1.0)

	# Jittered candidate grid in WC normalized space, ~one cell per InstanceDistance.
	var step_x: float = inst_dist / width_m
	var step_y: float = inst_dist / length_m
	var nx_count: int = max(1, int(1.0 / step_x))
	var ny_count: int = max(1, int(1.0 / step_y))

	var rng := RandomNumberGenerator.new()
	rng.seed = int(obj.seed)

	var transforms: Array[Transform3D] = []
	for iy in range(ny_count):
		for ix in range(nx_count):
			var nx: float = (float(ix) + rng.randf()) * step_x
			var ny: float = (float(iy) + rng.randf()) * step_y
			if nx >= 1.0 or ny >= 1.0:
				continue
			# Probabilistic density mask from the heatmap. World X is driven by ny (the
			# heatmap's row), and it reads mirrored along that axis, so flip the row.
			var px: int = clampi(int(nx * hw), 0, hw - 1)
			var py: int = clampi(int((1.0 - ny) * hh), 0, hh - 1)
			if rng.randf() > img.get_pixel(px, py).r * density:
				continue
			var pos: Vector3 = _wc_world_pos(nx, ny, terrain_node, metadata, world_scale, height_scale)
			pos.y += float(obj.height_offset)
			var yaw: float = deg_to_rad(rng.randf_range(float(obj.rot_y_min), float(obj.rot_y_max)))
			var basis := Basis(Vector3(0, 1, 0), yaw)
			if obj.align_to_normal:
				basis = _align_up(_terrain_normal(terrain_node, pos.x, pos.z)) * basis
			# Scale: ScaleRange * ModelScale * 0.01 (meters), normalized to the raw mesh.
			var size_m: float = rng.randf_range(float(obj.scale_min), float(obj.scale_max)) * float(obj.model_scale) * 0.01
			basis = basis.scaled_local(Vector3.ONE * (size_m / mesh_dim))
			transforms.append(Transform3D(basis, pos))

	if not transforms.is_empty():
		terrain_node.instancer.add_transforms(mesh_id, transforms)
	print("  - [detail] \"%s\": %d instance(s) via instancer (mesh_id %d, ~%.1f-%.1fm)" % [
		obj.name, transforms.size(), mesh_id,
		float(obj.scale_min) * float(obj.model_scale) * 0.01, float(obj.scale_max) * float(obj.model_scale) * 0.01])
	return transforms.size()

# WC normalized (nx,ny) -> Godot world position on the terrain surface.
func _wc_world_pos(nx: float, ny: float, terrain_node, metadata: Dictionary, world_scale: float, height_scale: float) -> Vector3:
	var width_m: float = float(metadata.width) * world_scale
	var length_m: float = float(metadata.length) * world_scale
	var g: Vector3 = WC_TO_GODOT * Vector3((nx - 0.5) * width_m, (ny - 0.5) * length_m, 0.0)
	var wy: float = terrain_node.data.get_height(Vector3(g.x, 0.0, g.z))
	if is_nan(wy):
		wy = float(metadata.min_height) + 0.5 * (float(metadata.max_height) - float(metadata.min_height)) * height_scale
	return Vector3(g.x, wy, g.z)

# Surface normal at a world XZ, via finite differences of terrain height.
func _terrain_normal(terrain_node, x: float, z: float) -> Vector3:
	var e: float = 1.0
	var h: float = terrain_node.data.get_height(Vector3(x, 0.0, z))
	var hx: float = terrain_node.data.get_height(Vector3(x + e, 0.0, z))
	var hz: float = terrain_node.data.get_height(Vector3(x, 0.0, z + e))
	if is_nan(h) or is_nan(hx) or is_nan(hz):
		return Vector3.UP
	return Vector3(h - hx, e, h - hz).normalized()

# A proper rotation (det +1) whose +Y points along n, for align-to-normal placement.
# Uses the shortest-arc rotation from +Y to the normal. A hand-built orthonormal basis
# here is easy to get left-handed (det -1), which mirrors the mesh and inverts its
# normals/winding (the stone's normal map then looks flipped).
func _align_up(n: Vector3) -> Basis:
	var up: Vector3 = n.normalized()
	if up.length() < 0.001:
		return Basis()
	return Basis(Quaternion(Vector3.UP, up))

# Builds a Godot Transform3D for one WC instance row. Position is normalized [0,1]
# over the terrain; Y is sampled from the live terrain surface. See the WC_* consts.
func _wc_instance_transform(row: Dictionary, terrain_node, metadata: Dictionary, world_scale: float, height_scale: float, model_scale: float, mesh_dim: float) -> Transform3D:
	# Position: WC normalized [0,1] -> centered meters in WC's own axes (tx=width,
	# ty=length, tz=up), then mapped to Godot via WC_TO_GODOT. Height (Y) is sampled
	# from the live terrain surface, so we leave WC "up" at 0 here.
	# WC normalizes instance positions so 1.0 = WC_POSITION_SCALE meters (a FIXED
	# reference, not the terrain size — matches the Blender bridge's *1024). Convert to
	# meters and center over the actual terrain extent. For a 1024 m terrain this equals
	# (t-0.5)*size, which is why square terrains worked even with the old (wrong) code.
	var wc_x: float = (WC_POSITION_SCALE * row.tx - float(metadata.width) * 0.5) * world_scale
	var wc_y: float = (WC_POSITION_SCALE * row.ty - float(metadata.length) * 0.5) * world_scale
	var g: Vector3 = WC_TO_GODOT * Vector3(wc_x, wc_y, 0.0)
	var wx: float = g.x
	var wz: float = g.z

	var wy: float = terrain_node.data.get_height(Vector3(wx, 0.0, wz))
	if is_nan(wy):
		wy = float(metadata.min_height) + row.tz * (float(metadata.max_height) - float(metadata.min_height)) * height_scale

	# Rotation: apply the WC quaternion in WC space, convert to Godot via the same
	# basis, then any model-facing yaw (WC_MODEL_YAW_DEG, which is 0 for Godot).
	var r_wc := Basis(Quaternion(row.qx, row.qy, row.qz, row.qw).normalized())
	var r_godot: Basis = WC_TO_GODOT * r_wc * WC_TO_GODOT.inverse()
	var model_fix := Basis(Vector3(0, 1, 0), deg_to_rad(WC_MODEL_YAW_DEG))
	var basis := r_godot * model_fix

	# Scale: WC scale * 100 (point) * 10 (object) * ModelScale, on a 1 m-normalized
	# model. WC_TO_GODOT already carries the WC->Godot handedness flip, so use |scale|.
	var k: float = WC_SCALE_CONST * model_scale / mesh_dim
	# scaled_local: scale in the model's own frame (after rotation), so non-uniform
	# per-axis scale stretches the model's axes, not the world axes.
	basis = basis.scaled_local(Vector3(absf(row.sx), absf(row.sy), absf(row.sz)) * k)

	return Transform3D(basis, Vector3(wx, wy, wz))

# Reads a WC instance CSV: tx,ty,tz,sx,sy,sz,qx,qy,qz,qw,gradient,seed
func _read_instance_csv(path: String) -> Array:
	var rows: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return rows
	var is_header := true
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty():
			continue
		if is_header:
			is_header = false
			continue
		var p := line.split(",")
		if p.size() < 12:
			continue
		rows.append({
			"tx": p[0].to_float(), "ty": p[1].to_float(), "tz": p[2].to_float(),
			"sx": p[3].to_float(), "sy": p[4].to_float(), "sz": p[5].to_float(),
			"qx": p[6].to_float(), "qy": p[7].to_float(), "qz": p[8].to_float(), "qw": p[9].to_float(),
			"gradient": p[10].to_float(), "seed": p[11].to_float(),
		})
	f.close()
	return rows

# Removes any existing WC_SceneObjects node and returns a fresh empty one.
func _recreate_objects_root(scene_root: Node) -> Node3D:
	var existing = scene_root.find_child("WC_SceneObjects", false, false)
	if existing:
		scene_root.remove_child(existing)
		existing.queue_free()
	var n := Node3D.new()
	n.name = "WC_SceneObjects"
	scene_root.add_child(n)
	n.owner = scene_root
	return n

# Recursively deletes a res:// directory and its contents. Used by Reset Objects to
# force models to re-import.
func _delete_dir_recursive(dir_path: String) -> void:
	var gpath: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(gpath):
		return
	var d := DirAccess.open(gpath)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if d.current_is_dir():
			_delete_dir_recursive(dir_path.path_join(entry))
		else:
			DirAccess.remove_absolute(gpath.path_join(entry))
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(gpath)

# Largest dimension of a node tree's combined AABB, in the root's local space
# (the root's own transform is ignored — we overwrite it when placing).
func _scene_max_dimension(root: Node) -> float:
	var res: Array = _accumulate_aabb(root, Transform3D.IDENTITY, AABB(), false, true)
	var has: bool = res[1]
	if not has:
		return 0.0
	var aabb: AABB = res[0]
	return aabb.size[aabb.size.max_axis_index()]

func _accumulate_aabb(node: Node, xform: Transform3D, accum: AABB, has: bool, is_root: bool) -> Array:
	var t: Transform3D = xform
	if node is Node3D and not is_root:
		t = xform * (node as Node3D).transform
	var local_aabb := AABB()
	var has_local := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		# Use the mesh resource's AABB (vertex-derived, always valid) rather than
		# VisualInstance3D.get_aabb(), which can return a stale 1 m box on a freshly
		# instantiated node in the editor and wreck the size normalization.
		local_aabb = (node as MeshInstance3D).mesh.get_aabb()
		has_local = true
	elif node is VisualInstance3D:
		local_aabb = (node as VisualInstance3D).get_aabb()
		has_local = true
	if has_local:
		var world: AABB = t * local_aabb
		if has:
			accum = accum.merge(world)
		else:
			accum = world
			has = true
	for c in node.get_children():
		var r: Array = _accumulate_aabb(c, t, accum, has, false)
		accum = r[0]
		has = r[1]
	return [accum, has]

# Reads a WC object-metadata XML (instance_info.xml or detail_info.xml) and returns
# an Array of object Dictionaries (see _new_object_record for the shape).
# WC declares encoding="utf-16" but actually writes UTF-8, so we read the bytes
# ourselves, normalize the declaration, and feed open_buffer().
func _parse_object_info(path: String) -> Array:
	var objects: Array = []

	var content: String = _read_text_any_encoding(path)
	if content.is_empty():
		push_error("Could not read object XML: %s" % path)
		return objects
	content = content.replace("encoding=\"utf-16\"", "encoding=\"utf-8\"")

	var parser := XMLParser.new()
	if parser.open_buffer(content.to_utf8_buffer()) != OK:
		push_error("Failed to parse object XML: %s" % path)
		return objects

	var stack: Array[String] = []   # open element names, for parent/child context
	var cur: Dictionary = {}        # current object being built ({} = none)
	var cur_file: Dictionary = {}   # current InstanceDataFiles/HeatmapFiles entry
	var cur_file_kind: String = ""  # "instance" | "heatmap" | ""
	var in_model: bool = false      # inside <ObjectInfo>/<SubobjectInfo>

	while parser.read() == OK:
		var node_type := parser.get_node_type()

		if node_type == XMLParser.NODE_ELEMENT:
			var open_name := parser.get_node_name()
			match open_name:
				"BiomeObjectList", "SceneObjectList", "DetailList":
					var kind := "biome"
					if open_name == "SceneObjectList":
						kind = "scene"
					elif open_name == "DetailList":
						kind = "detail"
					cur = _new_object_record(kind)
				"ObjectInfo", "SubobjectInfo":
					in_model = true
				"InstanceDataFiles":
					cur_file = {"file_name": "", "tile_x": 0, "tile_y": 0, "data_count": 0}
					cur_file_kind = "instance"
				"HeatmapFiles":
					cur_file = {"file_name": "", "tile_x": 0, "tile_y": 0}
					cur_file_kind = "heatmap"
			# Self-closing elements have no end tag, so don't track them on the stack.
			if not parser.is_empty():
				stack.push_back(open_name)

		elif node_type == XMLParser.NODE_ELEMENT_END:
			var close_name := parser.get_node_name()
			match close_name:
				"BiomeObjectList", "SceneObjectList", "DetailList":
					if not cur.is_empty():
						objects.push_back(cur)
						cur = {}
				"ObjectInfo", "SubobjectInfo":
					in_model = false
				"InstanceDataFiles":
					if not cur.is_empty() and not cur_file.is_empty():
						cur.instance_files.push_back(cur_file)
						cur.instance_count += int(cur_file.get("data_count", 0))
					cur_file = {}
					cur_file_kind = ""
				"HeatmapFiles":
					if not cur.is_empty() and not cur_file.is_empty():
						cur.heatmap_files.push_back(cur_file)
					cur_file = {}
					cur_file_kind = ""
			if not stack.is_empty() and stack[stack.size() - 1] == close_name:
				stack.pop_back()

		elif node_type == XMLParser.NODE_TEXT:
			if cur.is_empty() or stack.is_empty():
				continue
			var text := parser.get_node_data().strip_edges()
			if text.is_empty():
				continue
			var elem := stack[stack.size() - 1]
			var parent: String = stack[stack.size() - 2] if stack.size() >= 2 else ""
			# Object Name is a direct child of the list element. This deliberately
			# excludes <MaterialInfos><Name>M_...</Name>, whose parent is MaterialInfos.
			if elem == "Name" and parent in ["BiomeObjectList", "SceneObjectList", "DetailList"]:
				cur.name = text
			elif cur_file_kind != "" and not cur_file.is_empty():
				match elem:
					"FileName": cur_file.file_name = text
					"TileX": cur_file.tile_x = int(text)
					"TileY": cur_file.tile_y = int(text)
					"DataCount": cur_file.data_count = int(text)
			elif in_model:
				# Path/ModelScale/ModelYAxis only exist on ObjectInfo/SubobjectInfo,
				# never on the nested MaterialInfos, so in_model is enough to scope them.
				# Range Min/Max are disambiguated by their parent element.
				match elem:
					"Path": cur.glb_path = text
					"ModelScale": cur.model_scale = text.to_float()
					"ModelYAxis": cur.model_y_axis = text
					"InstanceDistance": cur.instance_distance = text.to_float()
					"Density": cur.density = text.to_float()
					"AlignToNormal": cur.align_to_normal = (text.to_lower() == "true")
					"Seed": cur.seed = text.to_float()
					"HeightOffset": cur.height_offset = text.to_float()
					"Min":
						if parent == "ScaleRange": cur.scale_min = text.to_float()
						elif parent == "RotationRangeY": cur.rot_y_min = text.to_float()
					"Max":
						if parent == "ScaleRange": cur.scale_max = text.to_float()
						elif parent == "RotationRangeY": cur.rot_y_max = text.to_float()

	return objects

func _new_object_record(kind: String) -> Dictionary:
	return {
		"kind": kind,                # "biome" | "scene" | "detail"
		"name": "",
		"glb_path": "",              # relative to the Sync folder, e.g. "Assets\\tree.glb"
		"model_scale": 1.0,
		"model_y_axis": "YPos",
		"instance_files": [],        # [{file_name, tile_x, tile_y, data_count}]
		"instance_count": 0,         # sum of data_count across instance_files
		"heatmap_files": [],         # [{file_name, tile_x, tile_y}]
		# Procedural params (used by detail / density scatter):
		"scale_min": 1.0,
		"scale_max": 1.0,
		"rot_y_min": 0.0,
		"rot_y_max": 0.0,
		"align_to_normal": false,
		"instance_distance": 16.0,   # average spacing in meters
		"density": 1.0,
		"seed": 0.0,
		"height_offset": 0.0,
	}

# Reads a text file as a String, honoring a UTF-16 BOM if present. Defaults to
# UTF-8 (which is what WC actually writes, despite its encoding declaration).
func _read_text_any_encoding(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() >= 2 and ((bytes[0] == 0xFF and bytes[1] == 0xFE) or (bytes[0] == 0xFE and bytes[1] == 0xFF)):
		return bytes.get_string_from_utf16()
	return bytes.get_string_from_utf8()

# Helper function to read and parse the XML file
func _parse_wc_xml(path: String) -> Dictionary:
	var metadata = {}
	var parser = XMLParser.new()
	
	var error = parser.open(path)
	if error != OK:
		push_error("XMLParser Error: Could not open file: " + path)
		return metadata
	
	var textures = []
	
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			
			if parser.get_node_name() == "Surface":
				metadata.min_height = parser.get_named_attribute_value("MinHeight").to_float()
				metadata.max_height = parser.get_named_attribute_value("MaxHeight").to_float()
				
				# Terrain dimensions in METERS
				metadata.length = parser.get_named_attribute_value("Length").to_float()
				metadata.width = parser.get_named_attribute_value("Width").to_float()
				
				# Total resolution in PIXELS across entire terrain
				metadata.resolution_x = parser.get_named_attribute_value("ResolutionX").to_int()
				metadata.resolution_y = parser.get_named_attribute_value("ResolutionY").to_int()
				
				# Read tile count from XML (defaults to 1 for single-tile terrains)
				metadata.tiles_x = parser.get_named_attribute_value("TilesX").to_int() if parser.has_attribute("TilesX") else 1
				metadata.tiles_y = parser.get_named_attribute_value("TilesY").to_int() if parser.has_attribute("TilesY") else 1
				
				# TileResolution = pixels per tile file (e.g., 4096)
				# Tiles are sequential: tile 0 = pixels 0-4095, tile 1 = 4096-8191, etc.
				metadata.tile_resolution = parser.get_named_attribute_value("TileResolution").to_int() if parser.has_attribute("TileResolution") else metadata.resolution_x
				
				# For single-tile, tile_resolution equals full resolution
				if metadata.tiles_x == 1 and metadata.tiles_y == 1:
					metadata.tile_resolution = metadata.resolution_x
				
				# Calculate meters per pixel (native resolution)
				metadata.meters_per_px = metadata.width / float(metadata.resolution_x)
				
				# Calculate meters per tile (tile_resolution pixels * meters_per_px)
				metadata.tile_meters_x = metadata.tile_resolution * metadata.meters_per_px
				metadata.tile_meters_y = metadata.tile_resolution * metadata.meters_per_px
			
			if parser.get_node_name() == "TextureInfo":
				var albedo_file = ""
				if parser.has_attribute("AlbedoFile"):
					albedo_file = parser.get_named_attribute_value("AlbedoFile")
				
				var normal_file = ""
				if parser.has_attribute("NormalFile"):
					normal_file = parser.get_named_attribute_value("NormalFile")
				
				var roughness_file = ""
				if parser.has_attribute("RoughnessFile"):
					roughness_file = parser.get_named_attribute_value("RoughnessFile")
				
				var height_file = ""
				if parser.has_attribute("HeightFile"):
					height_file = parser.get_named_attribute_value("HeightFile")
				
				var tile_size = "1024,1024"  # Default tile size
				if parser.has_attribute("TileSize"):
					tile_size = parser.get_named_attribute_value("TileSize")
					
				var texture_info = {
					"name": parser.get_named_attribute_value("Name"),
					"albedo_file": albedo_file,
					"normal_file": normal_file,
					"roughness_file": roughness_file,
					"height_file": height_file,
					"tile_size": tile_size,
					"metallic": parser.get_named_attribute_value("Metallic").to_float(),
					"smoothness": parser.get_named_attribute_value("Smoothness").to_float(),
					"color": parser.get_named_attribute_value("Color")
				}
				textures.append(texture_info)

	metadata.textures = textures
	return metadata

# Helper function to create resource directory
func _create_resource_directory(dir_path: String) -> void:
	var global_path = ProjectSettings.globalize_path(dir_path)
	
	if not DirAccess.dir_exists_absolute(global_path):
		var err = DirAccess.make_dir_recursive_absolute(global_path)
		if err != OK:
			push_error("Failed to create directory: %s (Error: %d)" % [dir_path, err])

# Import heightmap tiles - uses tile data parsed from XML
func _import_heightmap_tiles(xml_path: String, data: Dictionary, terrain_name: String, resource_dir: String, vertex_spacing: float, world_scale: float, height_scale: float, enable_triplanar_projection: bool = false) -> void:
	var heightmap_path = xml_path.get_base_dir()
	
	# Tile dimensions from XML
	var tiles_x = data.tiles_x
	var tiles_y = data.tiles_y
	var tile_resolution = data.tile_resolution  # Pixels per tile file (e.g., 4096)
	var tile_meters = data.tile_meters_x * world_scale  # Meters per tile
	var total_res_x = data.resolution_x
	var total_res_y = data.resolution_y
	
	if not Engine.has_singleton("EditorInterface"):
		push_error("Could not access EditorInterface. Is the script running as an @tool?")
		return
	
	var editor_interface = Engine.get_singleton("EditorInterface")
	var scene_root = editor_interface.get_edited_scene_root()
	
	if not scene_root:
		push_error("Cannot create node: No scene is currently open.")
		return
	
	# Clean up any existing region files from previous syncs to avoid mixing region sizes
	var res_dir_access := DirAccess.open(resource_dir)
	if res_dir_access:
		for file in res_dir_access.get_files():
			if file.begins_with("terrain3d") and file.ends_with(".res"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(resource_dir.path_join(file)))

	# Check if terrain already exists and replace it
	var existing_terrain = scene_root.find_child(terrain_name, false, false)
	if existing_terrain and existing_terrain is Terrain3D:
		scene_root.remove_child(existing_terrain)
		existing_terrain.queue_free()
	
	# Create and add Terrain3D node
	var terrain_node = Terrain3D.new()
	terrain_node.name = terrain_name
	terrain_node.vertex_spacing = vertex_spacing
	
	# Configure material settings - set world background to none (value 0)
	var material = terrain_node.material
	if not material:
		material = Terrain3DMaterial.new()
		terrain_node.material = material
	material.set_world_background(0)  # 0 = None/Disabled

	var shader_params = material.get("_shader_parameters")
	if typeof(shader_params) != TYPE_DICTIONARY:
		shader_params = {}
	shader_params["blend_sharpness"] = 0.0
	shader_params["enable_projection"] = enable_triplanar_projection
	# The patched override shader samples noise_texture for its index-domain
	# warp; make sure one exists even on a fresh material.
	if shader_params.get("noise_texture") == null:
		var wc_noise := NoiseTexture2D.new()
		wc_noise.width = 512
		wc_noise.height = 512
		wc_noise.seamless = true
		wc_noise.noise = FastNoiseLite.new()
		shader_params["noise_texture"] = wc_noise
	material.set("_shader_parameters", shader_params)

	# Shared patched shader (sharper index blending + warp + colormap strength).
	var wc_shader: Shader = load(WC_OVERRIDE_SHADER)
	if wc_shader:
		material.shader_override = wc_shader
		material.shader_override_enabled = true

	scene_root.add_child(terrain_node)
	terrain_node.owner = scene_root

	# Wait a frame for Terrain3D to initialize internal data in the scene tree
	await get_tree().process_frame

	# Calculate required region_size based on terrain extent
	# Terrain3D has a 32×32 region grid (16 regions in each direction from center)
	# max_extent = 16 * region_size * vertex_spacing
	# So: region_size = max_extent / (16 * vertex_spacing)
	var max_extent = max(data.width, data.length) * world_scale / 2.0
	var min_region_size = int(ceil(max_extent / (16.0 * vertex_spacing)))
	
	# Round up to valid region_size (256, 512, 1024, 2048)
	var region_size = 256
	if min_region_size > 256:
		region_size = 512
	if min_region_size > 512:
		region_size = 1024
	if min_region_size > 1024:
		region_size = 2048
	
	terrain_node.change_region_size(region_size)
	terrain_node.data_directory = resource_dir

	var mat_rid: RID = material.get_material_rid()
	if mat_rid.is_valid():
		RenderingServer.material_set_param(mat_rid, "blend_sharpness", 0.0)
		RenderingServer.material_set_param(mat_rid, "enable_projection", enable_triplanar_projection)
	
	# Apply textures before importing heightmaps
	_apply_textures(terrain_node, data, heightmap_path, resource_dir)
	
	# Calculate total terrain size in meters
	var total_meters_x = data.width * world_scale
	var total_meters_y = data.length * world_scale
	
	# Height conversion factors
	var height_range = data.max_height - data.min_height
	var scale_factor = (height_range * height_scale) / 65535.0
	var base_height = data.min_height
	
	# Import each tile directly as a separate region
	# Tiles are sequential: tile 0 = pixels 0 to tile_resolution-1, tile 1 = tile_resolution to 2*tile_resolution-1, etc.
	# In Terrain3D: image_pixels * vertex_spacing = meters covered
	
	# Calculate how many output pixels per full tile for Terrain3D
	var output_tile_px = int(round(tile_meters / vertex_spacing))
	
	# Calculate offset to center the terrain. World X/Z are transposed vs WC
	# width/length (matching the heightmap transpose + the object WC_TO_GODOT
	# mapping), so X uses length and Z uses width. Equal for a square terrain.
	var offset_x = -total_meters_y / 2.0
	var offset_z = -total_meters_x / 2.0
	
	# Count total tiles to import (non-padding tiles)
	var total_tiles = 0
	for ty in range(tiles_y):
		for tx in range(tiles_x):
			var x_start = tx * tile_resolution
			var y_start = ty * tile_resolution
			if min(tile_resolution, total_res_x - x_start) > 0 and min(tile_resolution, total_res_y - y_start) > 0:
				total_tiles += 1
	
	var tiles_imported = 0
	
	print("Importing %d tiles (%dx%d px each -> %dx%d output)..." % [total_tiles, tile_resolution, tile_resolution, output_tile_px, output_tile_px])
	
	for ty in range(tiles_y):
		for tx in range(tiles_x):
			# Calculate which pixels this tile covers in the total resolution
			var x_start_px = tx * tile_resolution
			var y_start_px = ty * tile_resolution
			
			# How many pixels of actual data in this tile (may be less for edge tiles or 0 for padding tiles)
			var x_src_pixels = min(tile_resolution, total_res_x - x_start_px)
			var y_src_pixels = min(tile_resolution, total_res_y - y_start_px)
			
			# Skip tiles that are entirely padding (no actual data needed)
			if x_src_pixels <= 0 or y_src_pixels <= 0:
				continue
			
			var file_name = "heightmap_%d_%d.raw" % [tx, ty]
			var full_path = heightmap_path.path_join(file_name)
			
			if not FileAccess.file_exists(full_path):
				push_error("Heightmap tile not found: " + full_path)
				continue
			
			# Calculate OUTPUT pixels for this tile (resampled for vertex_spacing)
			# For partial tiles, scale proportionally
			var x_out_pixels = int(round(float(x_src_pixels) / float(tile_resolution) * output_tile_px))
			var y_out_pixels = int(round(float(y_src_pixels) / float(tile_resolution) * output_tile_px))
			
			if x_out_pixels <= 0 or y_out_pixels <= 0:
				continue
			
			# Read the raw 16-bit heightmap. A single tile holds the whole (possibly
			# non-square) terrain at resolution_x x resolution_y; multi-tile exports use
			# square tile_resolution tiles. tile_stride = the file's pixel row width.
			var tile_stride: int = total_res_x if (tiles_x == 1 and tiles_y == 1) else tile_resolution
			var tile_rows: int = total_res_y if (tiles_x == 1 and tiles_y == 1) else tile_resolution
			var file = FileAccess.open(full_path, FileAccess.READ)
			var file_data_size = tile_stride * tile_rows
			var raw_data = file.get_buffer(file_data_size * 2)
			file.close()
			
			if raw_data.size() < file_data_size * 2:
				push_error("Tile %d,%d: Only read %d bytes, expected %d" % [tx, ty, raw_data.size(), file_data_size * 2])
				continue
			
			# Convert raw 16-bit to float heights with resampling
			var float_data = PackedFloat32Array()
			float_data.resize(x_out_pixels * y_out_pixels)
			
			# Sample ratio: how many source pixels per output pixel
			var sample_x = float(x_src_pixels) / float(x_out_pixels)
			var sample_y = float(y_src_pixels) / float(y_out_pixels)
			
			for oy in range(y_out_pixels):
				for ox in range(x_out_pixels):
					# Map output to source coordinates
					var sx = int(ox * sample_x)
					var sy = int(oy * sample_y)
					sx = min(sx, x_src_pixels - 1)
					sy = min(sy, y_src_pixels - 1)
					
					# Read from file (row stride = tile_stride)
					var file_idx = (sy * tile_stride + sx) * 2
					var raw_value = raw_data.decode_u16(file_idx)
					
					# Y-flip for correct orientation
					var flipped_oy = (y_out_pixels - 1) - oy
					var out_idx = ox * y_out_pixels + flipped_oy
					float_data[out_idx] = base_height + raw_value * scale_factor
			
			# Create tile image at OUTPUT resolution. Dims are swapped (y_out, x_out)
			# because the data is written transposed (out_idx below); identical to
			# (x_out, y_out) on a square terrain.
			var tile_img = Image.create_from_data(y_out_pixels, x_out_pixels, false, Image.FORMAT_RF, float_data.to_byte_array())
			
			# Calculate world position using tile meters
			var pos_x = offset_x + (ty * tile_meters)
			var pos_z = offset_z + (tx * tile_meters)
			var pos := Vector3(pos_x, 0, pos_z)
			
			# Load control map (splatmap) for this tile
			var control_img = _load_splatmaps_for_tile(
				heightmap_path, tx, ty,
				data.textures.size(),
				x_out_pixels, y_out_pixels
			)
			
			# Load color map for this tile
			var color_img = _load_colormap_for_tile(
				heightmap_path, tx, ty,
				x_out_pixels, y_out_pixels
			)
			
			# Import this tile into Terrain3D
			var imported_images: Array[Image]
			imported_images.resize(Terrain3DRegion.TYPE_MAX)
			imported_images[Terrain3DRegion.TYPE_HEIGHT] = tile_img
			if control_img:
				imported_images[Terrain3DRegion.TYPE_CONTROL] = control_img
			if color_img:
				imported_images[Terrain3DRegion.TYPE_COLOR] = color_img
			
			terrain_node.data.import_images(imported_images, pos, 0.0, 1.0)
			tiles_imported += 1
			
			# Show what was imported for this tile
			var imported_types = ["height"]
			if control_img: imported_types.append("splatmap")
			if color_img: imported_types.append("colormap")
			print("  [%d/%d] Tile (%d,%d) - %dx%d px (%s)" % [tiles_imported, total_tiles, tx, ty, x_out_pixels, y_out_pixels, ", ".join(imported_types)])
			

	# Select the newly created terrain
	editor_interface.get_selection().add_node(terrain_node)
	
	print("Done - %s (%.0fx%.0fm)" % [terrain_name, total_meters_x, total_meters_y])

# Shared Terrain3DUtil instance - created once for encoding operations
var _terrain3d_util: Terrain3DUtil = null

func _get_terrain3d_util() -> Terrain3DUtil:
	if _terrain3d_util == null:
		_terrain3d_util = Terrain3DUtil.new()
	return _terrain3d_util

# Load and process splatmaps for a tile - OPTIMIZED with native resize
func _load_splatmaps_for_tile(base_path: String, tx: int, ty: int, texture_count: int,
	target_size_x: int, target_size_y: int) -> Image:
	
	var splatmap_count = int(ceil(texture_count / 4.0))
	if splatmap_count == 0:
		return null
	
	# Use shared Terrain3DUtil instance for encoding
	var util := _get_terrain3d_util()
	
	# Load and resize all splatmaps first (using fast native resize)
	var resized_splatmaps: Array[Image] = []
	for splatmap_idx in range(splatmap_count):
		var splatmap_file = "splatmap_%d_%d_%d.tga" % [splatmap_idx, tx, ty]
		var splatmap_path = base_path.path_join(splatmap_file)
		
		if not FileAccess.file_exists(splatmap_path):
			resized_splatmaps.append(null)
			continue
		
		var splatmap = Image.load_from_file(splatmap_path)
		if not splatmap:
			resized_splatmaps.append(null)
			continue
		
		# Convert and resize using native methods (MUCH faster than pixel loops)
		if splatmap.get_format() != Image.FORMAT_RGBA8:
			splatmap.convert(Image.FORMAT_RGBA8)
		
		if splatmap.get_width() != target_size_x or splatmap.get_height() != target_size_y:
			splatmap.resize(target_size_x, target_size_y, Image.INTERPOLATE_BILINEAR)
		
		# Rotate to match heightmap orientation (swap X/Y axes)
		splatmap.rotate_90(CLOCKWISE)
		
		resized_splatmaps.append(splatmap)
	
	# Hoist per-splatmap invariants out of the pixel loop and skip nulls entirely
	var active_data: Array[PackedByteArray] = []
	var active_base_idx := PackedInt32Array()
	var active_channels := PackedInt32Array()
	for splatmap_idx in range(splatmap_count):
		var splatmap: Image = resized_splatmaps[splatmap_idx]
		if splatmap == null:
			continue
		var data := splatmap.get_data()
		if data.is_empty():
			continue
		var base_texture_idx := splatmap_idx * 4
		active_data.append(data)
		active_base_idx.append(base_texture_idx)
		active_channels.append(min(4, texture_count - base_texture_idx))
	var active_count := active_data.size()

	# Pack control values as ints. FORMAT_RF reads these bytes as bit-reinterpreted
	# floats, so we skip util.as_float() and the per-pixel PackedFloat32Array alloc.
	var total_pixels := target_size_x * target_size_y
	var packed_ints := PackedInt32Array()
	packed_ints.resize(total_pixels)

	for pixel_idx in range(total_pixels):
		var data_idx := pixel_idx * 4
		var base_id := 0
		var overlay_id := 0
		var base_strength := 0
		var overlay_strength := 0

		for s in range(active_count):
			var data: PackedByteArray = active_data[s]
			var base_texture_idx: int = active_base_idx[s]
			var channel_count: int = active_channels[s]

			for ch in range(channel_count):
				var strength: int = data[data_idx + ch]
				if strength == 0:
					continue
				if strength > base_strength:
					overlay_id = base_id
					overlay_strength = base_strength
					base_id = base_texture_idx + ch
					base_strength = strength
				elif strength > overlay_strength:
					overlay_id = base_texture_idx + ch
					overlay_strength = strength

		var blend := 0
		if overlay_strength > 0 and base_strength > 0:
			blend = (overlay_strength * 255) / (base_strength + overlay_strength)

		packed_ints[pixel_idx] = util.enc_base(base_id) | util.enc_overlay(overlay_id) | util.enc_blend(blend) | util.enc_auto(false) | util.enc_hole(false)

	# Dims swapped (target_y, target_x) to match the rotate_90 above; no-op when square.
	var control_img = Image.create_from_data(target_size_y, target_size_x, false, Image.FORMAT_RF, packed_ints.to_byte_array())
	return control_img

# Load and process colormap for a tile - OPTIMIZED with native resize
func _load_colormap_for_tile(base_path: String, tx: int, ty: int,
	target_size_x: int, target_size_y: int) -> Image:
	
	var colormap_file = "colormap_%d_%d.png" % [tx, ty]
	var colormap_path = base_path.path_join(colormap_file)
	
	# Check if colormap exists
	if not FileAccess.file_exists(colormap_path):
		return null
	
	var colormap = Image.load_from_file(colormap_path)
	if not colormap:
		return null
	
	# Convert to RGBA8 if needed
	if colormap.get_format() != Image.FORMAT_RGBA8:
		colormap.convert(Image.FORMAT_RGBA8)
	
	# Use native resize (MUCH faster than pixel loops)
	if colormap.get_width() != target_size_x or colormap.get_height() != target_size_y:
		colormap.resize(target_size_x, target_size_y, Image.INTERPOLATE_BILINEAR)
	
	# Flip Y and rotate to match heightmap orientation (swap X/Y axes)
	colormap.rotate_90(CLOCKWISE)
	
	return colormap
	
	
# Apply textures from World Creator to Terrain3D
func _apply_textures(terrain_node: Terrain3D, data: Dictionary, base_path: String, resource_dir: String) -> void:
	if not data.has("textures") or data.textures.is_empty():
		return
	
	print("Applying %d texture(s)..." % data.textures.size())
	
	# Get or create the assets
	var assets_path = resource_dir.path_join("wc_terrain_assets.tres")
	var assets = terrain_node.assets
	if not assets and ResourceLoader.exists(assets_path):
		assets = load(assets_path)
	if not assets:
		assets = Terrain3DAssets.new()
	terrain_node.assets = assets

	var textures_dir = "res://wc_data/textures"
	_create_resource_directory(textures_dir)
	
	# First pass: determine the smallest texture size and load all textures
	var min_size = 99999
	var temp_images = []
	var texture_count = min(data.textures.size(), 32)
	
	print("  Loading texture files...")
	for i in range(texture_count):
		var tex_info = data.textures[i]
		
		# Skip textures without an albedo file (color-only materials)
		if tex_info.albedo_file == "" or tex_info.albedo_file == null:
			print("    [%d/%d] %s (color-only)" % [i + 1, texture_count, tex_info.name])
			temp_images.append(null)
			continue
		
		# Try both with and without Assets subfolder
		var source_path = base_path.path_join("Assets").path_join(tex_info.albedo_file)
		if not FileAccess.file_exists(source_path):
			source_path = base_path.path_join(tex_info.albedo_file)
		
		if not FileAccess.file_exists(source_path):
			push_warning("Texture file not found: %s" % tex_info.albedo_file)
			temp_images.append(null)
			continue
		
		# Load albedo image
		var albedo_img = Image.load_from_file(source_path)
		if not albedo_img:
			temp_images.append(null)
			continue
		
		min_size = min(min_size, min(albedo_img.get_width(), albedo_img.get_height()))
		
		# Try to load normal map (if exists)
		var normal_img: Image = null
		if tex_info.has("normal_file") and tex_info.normal_file != "" and tex_info.normal_file != null:
			var normal_path = base_path.path_join("Assets").path_join(tex_info.normal_file)
			if not FileAccess.file_exists(normal_path):
				normal_path = base_path.path_join(tex_info.normal_file)
			if FileAccess.file_exists(normal_path):
				normal_img = Image.load_from_file(normal_path)
		
		# Try to load roughness map (if exists)
		var roughness_img: Image = null
		if tex_info.has("roughness_file") and tex_info.roughness_file != "" and tex_info.roughness_file != null:
			var roughness_path = base_path.path_join("Assets").path_join(tex_info.roughness_file)
			if not FileAccess.file_exists(roughness_path):
				roughness_path = base_path.path_join(tex_info.roughness_file)
			if FileAccess.file_exists(roughness_path):
				roughness_img = Image.load_from_file(roughness_path)
		
		# Try to load height map (if exists)
		var height_img: Image = null
		if tex_info.has("height_file") and tex_info.height_file != "" and tex_info.height_file != null:
			var height_path = base_path.path_join("Assets").path_join(tex_info.height_file)
			if not FileAccess.file_exists(height_path):
				height_path = base_path.path_join(tex_info.height_file)
			if FileAccess.file_exists(height_path):
				height_img = Image.load_from_file(height_path)
		
		temp_images.append({
			"info": tex_info,
			"albedo": albedo_img,
			"normal": normal_img,
			"roughness": roughness_img,
			"height": height_img
		})
		
		# Show what was loaded
		var loaded_maps = ["albedo"]
		if normal_img: loaded_maps.append("normal")
		if roughness_img: loaded_maps.append("roughness")
		if height_img: loaded_maps.append("height")
		print("    [%d/%d] %s (%s)" % [i + 1, texture_count, tex_info.name, ", ".join(loaded_maps)])
	
	# Use default size if no textures with files were found
	if min_size == 99999:
		min_size = 2048
	
	print("  Processing textures at size: %dx%d" % [min_size, min_size])
	
	# Second pass: pack channels and create textures
	print("  Packing texture channels...")
	for i in range(data.textures.size()):
		var tex_info = data.textures[i]
		
		# Handle color-only materials (no texture file)
		if tex_info.albedo_file == "" or tex_info.albedo_file == null:
			# Parse color from XML
			var albedo_color = Color.WHITE
			if tex_info.has("color") and tex_info.color != "":
				var color_str = tex_info.color
				if color_str.begins_with("#") and color_str.length() == 9:
					# Convert ARGB to RGBA: #AARRGGBB -> #RRGGBBAA
					var a = color_str.substr(1, 2)
					var r = color_str.substr(3, 2)
					var g = color_str.substr(5, 2)
					var b = color_str.substr(7, 2)
					albedo_color = Color.html(r + g + b)
					albedo_color.a = float(("0x" + a).hex_to_int()) / 255.0
				else:
					albedo_color = Color.html(color_str)
			
			# Convert smoothness to roughness
			var roughness = 1.0 - tex_info.smoothness
			
			# Create 16x16 packed textures for color-only
			var albedo_packed = Image.create(16, 16, false, Image.FORMAT_RGBA8)
			albedo_packed.fill(Color(1.0, 1.0, 1.0, 0.5))  # White with mid-height
			albedo_packed.generate_mipmaps()
			
			var normal_packed = Image.create(16, 16, false, Image.FORMAT_RGBA8)
			normal_packed.fill(Color(0.5, 0.5, 1.0, roughness))  # Flat normal + roughness
			normal_packed.generate_mipmaps()

			var col_name: String = tex_info.name.validate_filename()
			var col_albedo_path = textures_dir.path_join("color_%s_albedo_packed.png" % col_name)
			var col_normal_path = textures_dir.path_join("color_%s_normal_packed.png" % col_name)
			albedo_packed.save_png(ProjectSettings.globalize_path(col_albedo_path))
			normal_packed.save_png(ProjectSettings.globalize_path(col_normal_path))

			var albedo_texture: Texture2D = null
			if ResourceLoader.exists(col_albedo_path):
				albedo_texture = load(col_albedo_path)
			if not albedo_texture:
				albedo_texture = ImageTexture.create_from_image(albedo_packed)
				albedo_texture.take_over_path(col_albedo_path)

			var normal_texture: Texture2D = null
			if ResourceLoader.exists(col_normal_path):
				normal_texture = load(col_normal_path)
			if not normal_texture:
				normal_texture = ImageTexture.create_from_image(normal_packed)
				normal_texture.take_over_path(col_normal_path)
			
			# Create a texture asset with color tint
			var texture_asset = Terrain3DTextureAsset.new()
			texture_asset.set_albedo_texture(albedo_texture)
			texture_asset.set_normal_texture(normal_texture)
			texture_asset.set_albedo_color(albedo_color)
			
			assets.set_texture(i, texture_asset)
			print("    [%d/%d] %s (color: %s)" % [i + 1, data.textures.size(), tex_info.name, albedo_color.to_html()])
			continue
		
		# Handle textured materials
		if i >= temp_images.size() or temp_images[i] == null:
			continue
		
		var tex_data = temp_images[i]
		var tex_info_data = tex_data.info
		var albedo_img: Image = tex_data.albedo
		var normal_img: Image = tex_data.normal
		var roughness_img: Image = tex_data.roughness
		var height_img: Image = tex_data.height
		
		# Resize all images to min_size if needed
		if albedo_img.get_width() != min_size or albedo_img.get_height() != min_size:
			albedo_img.resize(min_size, min_size, Image.INTERPOLATE_LANCZOS)
		
		if normal_img and (normal_img.get_width() != min_size or normal_img.get_height() != min_size):
			normal_img.resize(min_size, min_size, Image.INTERPOLATE_LANCZOS)
		
		if roughness_img and (roughness_img.get_width() != min_size or roughness_img.get_height() != min_size):
			roughness_img.resize(min_size, min_size, Image.INTERPOLATE_LANCZOS)
		
		if height_img and (height_img.get_width() != min_size or height_img.get_height() != min_size):
			height_img.resize(min_size, min_size, Image.INTERPOLATE_LANCZOS)
		
		# Convert albedo to RGBA8 for packing
		if albedo_img.get_format() != Image.FORMAT_RGBA8:
			albedo_img.convert(Image.FORMAT_RGBA8)
		
		# OPTIMIZED: Pack albedo texture using bulk byte array operations
		# RGB = Albedo, A = Height
		var albedo_data = albedo_img.get_data()
		var packed_albedo_data = PackedByteArray()
		packed_albedo_data.resize(min_size * min_size * 4)
		
		# Prepare height data if available
		var height_data: PackedByteArray
		if height_img:
			if height_img.get_format() != Image.FORMAT_RGBA8:
				height_img.convert(Image.FORMAT_RGBA8)
			height_data = height_img.get_data()
		
		for i_px in range(min_size * min_size):
			var idx = i_px * 4
			packed_albedo_data[idx] = albedo_data[idx]       # R
			packed_albedo_data[idx + 1] = albedo_data[idx + 1] # G
			packed_albedo_data[idx + 2] = albedo_data[idx + 2] # B
			# A = Height (default 0.5 = 128)
			packed_albedo_data[idx + 3] = height_data[idx] if height_img else 128
		
		var albedo_packed = Image.create_from_data(min_size, min_size, false, Image.FORMAT_RGBA8, packed_albedo_data)
		albedo_packed.generate_mipmaps()
		
		# OPTIMIZED: Pack normal texture using bulk byte array operations
		# RGB = Normal (OpenGL +Y), A = Roughness
		var roughness_value_byte = int((1.0 - tex_info_data.smoothness) * 255.0)
		
		var normal_data: PackedByteArray
		var roughness_data: PackedByteArray
		if normal_img:
			if normal_img.get_format() != Image.FORMAT_RGBA8:
				normal_img.convert(Image.FORMAT_RGBA8)
			normal_data = normal_img.get_data()
		if roughness_img:
			if roughness_img.get_format() != Image.FORMAT_RGBA8:
				roughness_img.convert(Image.FORMAT_RGBA8)
			roughness_data = roughness_img.get_data()
		
		var packed_normal_data = PackedByteArray()
		packed_normal_data.resize(min_size * min_size * 4)
		
		for i_px in range(min_size * min_size):
			var idx = i_px * 4
			# Default flat normal (128, 128, 255)
			packed_normal_data[idx] = normal_data[idx] if normal_img else 128       # R
			packed_normal_data[idx + 1] = normal_data[idx + 1] if normal_img else 128 # G
			packed_normal_data[idx + 2] = normal_data[idx + 2] if normal_img else 255 # B
			# A = Roughness
			packed_normal_data[idx + 3] = roughness_data[idx] if roughness_img else roughness_value_byte
		
		var normal_packed = Image.create_from_data(min_size, min_size, false, Image.FORMAT_RGBA8, packed_normal_data)
		normal_packed.generate_mipmaps()
		
		# Save packed textures to textures directory
		var albedo_dest_path = textures_dir.path_join(tex_info_data.albedo_file.get_basename() + "_packed.png")
		var normal_dest_path = textures_dir.path_join(tex_info_data.albedo_file.get_basename() + "_normal_packed.png")
		
		var albedo_dest_global = ProjectSettings.globalize_path(albedo_dest_path)
		var normal_dest_global = ProjectSettings.globalize_path(normal_dest_path)
		
		if not FileAccess.file_exists(albedo_dest_global):
			var err = albedo_packed.save_png(albedo_dest_global)
			if err != OK:
				push_error("Failed to save packed albedo texture: %s (Error: %d)" % [tex_info_data.albedo_file, err])
				continue
		
		if not FileAccess.file_exists(normal_dest_global):
			var err = normal_packed.save_png(normal_dest_global)
			if err != OK:
				push_error("Failed to save packed normal texture: %s (Error: %d)" % [tex_info_data.albedo_file, err])
				continue
		
		# Create textures from packed images and ensure resource_path is set
		var albedo_texture: Texture2D = null
		if ResourceLoader.exists(albedo_dest_path):
			albedo_texture = load(albedo_dest_path)
		if not albedo_texture:
			albedo_texture = ImageTexture.create_from_image(albedo_packed)
			albedo_texture.take_over_path(albedo_dest_path)

		var normal_texture: Texture2D = null
		if ResourceLoader.exists(normal_dest_path):
			normal_texture = load(normal_dest_path)
		if not normal_texture:
			normal_texture = ImageTexture.create_from_image(normal_packed)
			normal_texture.take_over_path(normal_dest_path)
		
		# Parse tile size (format is "1500,1500")
		# In WC: tile_size = how many meters one texture tile covers
		# In Terrain3D shader: id_scale = _texture_uv_scale_array[id] * 0.5
		# Then: id_uv = uv * id_scale
		# To make texture tile every X meters: uv_scale = 2.0 / tile_size_meters
		var tile_size_parts = tex_info_data.tile_size.split(",")
		var uv_scale = 1.0
		if tile_size_parts.size() >= 1:
			var tile_size_meters = tile_size_parts[0].to_float()
			if tile_size_meters > 0:
				uv_scale = 2.0 / tile_size_meters
		
		# Parse color tint from XML (format is "#ffffffff" - ARGB hex)
		var albedo_color = Color.WHITE
		if tex_info_data.has("color") and tex_info_data.color != "":
			var color_str = tex_info_data.color
			if color_str.begins_with("#") and color_str.length() == 9:
				# Convert ARGB to RGBA: #AARRGGBB -> #RRGGBBAA
				var a = color_str.substr(1, 2)
				var r = color_str.substr(3, 2)
				var g = color_str.substr(5, 2)
				var b = color_str.substr(7, 2)
				albedo_color = Color.html(r + g + b)
			else:
				albedo_color = Color.html(color_str)
		
		# Create a Terrain3DTextureAsset with packed textures
		var texture_asset = Terrain3DTextureAsset.new()
		texture_asset.set_albedo_texture(albedo_texture)
		texture_asset.set_normal_texture(normal_texture)
		texture_asset.set_albedo_color(albedo_color)
		texture_asset.set_uv_scale(uv_scale)
		
		# Set the texture asset in the slot
		assets.set_texture(i, texture_asset)
		print("    [%d/%d] %s (packed, uv_scale: %.4f)" % [i + 1, data.textures.size(), tex_info_data.name, uv_scale])
	
	print("  Applied %d texture(s) with channel packing" % assets.get_texture_count())

	# Save assets as external resource and assign back to terrain_node
	var err = ResourceSaver.save(assets, assets_path)
	if err == OK:
		terrain_node.assets = load(assets_path)
		print("  Saved terrain assets to: %s" % assets_path)
	else:
		push_error("Failed to save terrain assets to %s (Error: %d)" % [assets_path, err])

	if Engine.has_singleton("EditorInterface"):
		var efs = Engine.get_singleton("EditorInterface").get_resource_filesystem()
		if efs:
			efs.scan()
