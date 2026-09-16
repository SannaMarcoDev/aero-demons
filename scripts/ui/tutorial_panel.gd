extends PanelContainer
## Reusable reading pause. CombatHUD arbitrates input with pause/options/disconnect UI.
signal confirmed

const Bindings = preload("res://scripts/ui/controller_bindings.gd")
var hud: CombatHUD
var _title: Label
var _body: Label
var _hint: Label
var _template := ""
var _accept_armed := false
var _resume_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -420
	offset_right = 420
	offset_top = -200
	offset_bottom = 200
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 24)
	margin.add_child(lines)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	lines.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lines.add_child(_body)
	_hint = Label.new()
	lines.add_child(_hint)
	hide()


func open(title: String, template: String) -> void:
	if visible:
		return
	_title.text = title
	_template = template
	_accept_armed = false
	_resume_pending = false
	hud.player.clear_player_controls()
	get_tree().paused = true
	refresh_text()
	show()


func refresh_text() -> void:
	var labels := {}
	for context in Bindings.CONTEXTS:
		for action: String in context:
			labels[action] = Bindings.action_label(action)
	_body.text = _template.format(labels)
	_hint.text = "Rilascia i comandi per riprendere" if _resume_pending else "[%s] Conferma" % labels.ui_accept


func handle_input(event: InputEvent) -> bool:
	if not visible or not event.is_action("ui_accept"):
		return false
	if _accept_armed and event.is_action_pressed("ui_accept") and not event.is_echo():
		_resume_pending = true
		refresh_text()
	return true


func _process(_delta: float) -> void:
	if not visible or hud._pause_overlay.visible:
		return
	refresh_text()
	if not Input.is_action_pressed("ui_accept"):
		_accept_armed = true
	if _resume_pending and hud._controls_released():
		hide()
		_resume_pending = false
		hud.player.clear_player_controls()
		get_tree().paused = false
		confirmed.emit()


func cancel() -> void:
	# The result/scene transition owns the tree's pause state, not this cleanup.
	hide()
	_accept_armed = false
	_resume_pending = false
