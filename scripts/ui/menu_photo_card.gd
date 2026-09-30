@tool
extends Button

@export var title := "":
	set(value):
		title = value
		text = value
		if is_node_ready():
			$Title.text = value
@export var photo: Texture2D:
	set(value):
		photo = value
		if is_node_ready():
			$Photo.texture = value
@export var title_size := 44:
	set(value):
		title_size = value
		if is_node_ready():
			$Title.add_theme_font_size_override("font_size", value)

var _highlight: Tween


func _ready() -> void:
	$Title.text = title
	$Title.add_theme_font_size_override("font_size", title_size)
	$Photo.texture = photo
	pivot_offset = size * 0.5
	resized.connect(func(): pivot_offset = size * 0.5)
	if Engine.is_editor_hint():
		return
	focus_entered.connect(_highlight_selection.bind(true))
	focus_exited.connect(_highlight_selection.bind(false))


func _highlight_selection(selected: bool) -> void:
	if _highlight != null:
		_highlight.kill()
	z_index = 10 if selected else 0
	_highlight = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_highlight.tween_property(self, "scale", Vector2.ONE * (1.035 if selected else 1.0), 0.16)
	_highlight.tween_property($Photo, "modulate", Color.WHITE if selected else Color(0.68, 0.72, 0.76), 0.16)
	_highlight.tween_property($Frame, "modulate:a", 1.0 if selected else 0.15, 0.16)
	_highlight.tween_property($Title, "modulate:a", 1.0 if selected else 0.8, 0.16)
