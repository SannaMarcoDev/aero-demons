@tool
extends EditorPlugin

const ImporterScene = preload("res://addons/wc_bridge/WorldCreatorBridge.tscn")

var importer_instance: Control

func _enter_tree() -> void:
	if ImporterScene == null:
		push_error("WC Bridge: Could not load WorldCreatorBridge.tscn! Plugin will not initialize.")
		return
	
	# Init
	importer_instance = ImporterScene.instantiate()
	
	# Add UI to screen
	add_control_to_bottom_panel(importer_instance, "WC Bridge")
	
func _exit_tree() -> void:
	# Cleanup
	if is_instance_valid(importer_instance):
		remove_control_from_bottom_panel(importer_instance)
		importer_instance.queue_free()
