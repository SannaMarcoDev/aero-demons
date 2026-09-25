extends Node

const Settings = preload("res://scripts/ui/settings_manager.gd")


func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)
	Settings.apply_settings(Settings.fixed_settings())


func _on_scene_changed(_scene: Node) -> void:
	Settings.apply_settings(Settings.fixed_settings())
