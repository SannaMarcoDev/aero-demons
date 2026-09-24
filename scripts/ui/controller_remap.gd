extends Window
## Draft edits keep menu navigation unchanged until Save. The exclusive window
## isolates capture from both the main menu and the paused HUD.
signal bindings_saved(profile: Dictionary)

const Settings = preload("res://scripts/ui/settings_manager.gd")
const Bindings = preload("res://scripts/ui/controller_bindings.gd")
const LABELS := {
	"pitch_up": "Beccheggio su", "pitch_down": "Beccheggio giù",
	"roll_left": "Rollio sinistra", "roll_right": "Rollio destra",
	"yaw_left": "Imbardata sinistra", "yaw_right": "Imbardata destra",
	"accelerate": "Accelera", "brake": "Frena", "fire_gun": "Cannone",
	"fire_missile": "Lancia missile", "cycle_target": "Bersaglio / freno a terra",
	"landing_gear": "Carrello", "switch_missile": "Cambia missile", "pause_menu": "Pausa",
	"reset_camera": "Centra visuale",
	"look_left": "Visuale sinistra", "look_right": "Visuale destra",
	"look_up": "Visuale su", "look_down": "Visuale giù",
	"ui_accept": "Conferma", "ui_cancel": "Indietro",
	"ui_left": "Menu sinistra", "ui_right": "Menu destra",
	"ui_up": "Menu su", "ui_down": "Menu giù",
}
const HELP := "Seleziona un comando. I conflitti scambiano le due assegnazioni.\nLe modifiche, incluso il ripristino, si applicano solo con SALVA."

var config_path := Settings.CONFIG_PATH
var draft: Dictionary = {}
var _rows: Array[Button] = []
var _capture: Button
var _remaining := 0.0
var _candidate: Dictionary = {}
var _device := -1
var _blocked_axes := {}
var _blocked_buttons := {}
var _return_focus: Control

@onready var _list: VBoxContainer = $Panel/Margin/Layout/Scroll/List
@onready var _status: Label = $Panel/Margin/Layout/Status
@onready var _save: Button = $Panel/Margin/Layout/Save
@onready var _reset: Button = $Panel/Margin/Layout/Reset
@onready var _back: Button = $Panel/Margin/Layout/Back


func _ready() -> void:
	close_requested.connect(_close)
	_save.pressed.connect(_save_profile)
	_reset.pressed.connect(_reset_profile)
	_back.pressed.connect(_close)
	Input.joy_connection_changed.connect(_on_connection_changed)


func open(from: Control) -> void:
	_return_focus = from
	draft = Settings.load_settings(config_path).controls_bindings.duplicate(true)
	_status.text = HELP
	_rebuild_rows()
	popup_centered_clamped(Vector2i(760, 660), 0.9)
	_rows[0].grab_focus.call_deferred()


func _rebuild_rows() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	# Flight first, then menu controls. Every existing alternative stays editable.
	for context in [Bindings.CONTEXTS[1], Bindings.CONTEXTS[0]]:
		var heading := Label.new()
		heading.text = "// VOLO" if context == Bindings.CONTEXTS[1] else "// MENU"
		_list.add_child(heading)
		for action: String in context:
			for slot in draft[action].events.size():
				var button := Button.new()
				button.custom_minimum_size.y = 40
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.set_meta("action", action)
				button.set_meta("slot", slot)
				button.pressed.connect(_begin_capture.bind(button))
				_list.add_child(button)
				_rows.append(button)
	_refresh_rows()
	var focusable: Array[Button] = _rows.duplicate()
	focusable.append_array([_save, _reset, _back])
	for i in focusable.size():
		var button := focusable[i]
		button.focus_neighbor_top = button.get_path_to(focusable[posmod(i - 1, focusable.size())])
		button.focus_neighbor_bottom = button.get_path_to(focusable[(i + 1) % focusable.size()])
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom


func _refresh_rows() -> void:
	for button in _rows:
		var action: String = button.get_meta("action")
		var slot: int = button.get_meta("slot")
		var suffix := " (%d)" % (slot + 1) if draft[action].events.size() > 1 else ""
		button.text = "%s%s:  %s" % [LABELS[action], suffix, Bindings.binding_label(draft[action].events[slot])]


func _begin_capture(button: Button) -> void:
	_capture = button
	_remaining = 8.0
	_candidate = {}
	_blocked_axes.clear()
	_blocked_buttons.clear()
	for device in Input.get_connected_joypads():
		for axis in range(JOY_AXIS_TRIGGER_RIGHT + 1):
			if absf(Input.get_joy_axis(device, axis)) > 0.25:
				_blocked_axes[Vector2i(device, axis)] = true
		for index in range(JOY_BUTTON_DPAD_RIGHT + 1):
			if Input.is_joy_button_pressed(device, index):
				_blocked_buttons[Vector2i(device, index)] = true
	_status.text = "Premi e rilascia un pulsante (anche B), oppure muovi e ricentra un asse.\nPer annullare: attendi 8 secondi senza input, oppure premi Esc."
	button.text = "%s:  IN ATTESA…" % LABELS[button.get_meta("action")]


func _process(delta: float) -> void:
	if _capture == null:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_finish_capture("Acquisizione annullata. Nessuna modifica.")


func _input(event: InputEvent) -> void:
	if not visible or _capture == null:
		return
	set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_finish_capture("Acquisizione annullata.")
		return
	if event is InputEventJoypadButton:
		var key := Vector2i(event.device, event.button_index)
		if _blocked_buttons.has(key):
			if not event.pressed:
				_blocked_buttons.erase(key)
			return
		if event.button_index < JOY_BUTTON_A or event.button_index > JOY_BUTTON_DPAD_RIGHT:
			return
		if event.pressed and _candidate.is_empty():
			_candidate = {"button": event.button_index}
			_device = event.device
		elif not event.pressed and _device == event.device and _candidate.get("button", -1) == event.button_index:
			_assign_candidate()
	elif event is InputEventJoypadMotion:
		var key := Vector2i(event.device, event.axis)
		if _blocked_axes.has(key):
			if absf(event.axis_value) < 0.25:
				_blocked_axes.erase(key)
			return
		if event.axis < JOY_AXIS_LEFT_X or event.axis > JOY_AXIS_TRIGGER_RIGHT:
			return
		if _candidate.is_empty() and absf(event.axis_value) >= 0.7:
			if event.axis >= JOY_AXIS_TRIGGER_LEFT and event.axis_value < 0.0:
				return
			_candidate = {"axis": event.axis, "direction": int(signf(event.axis_value))}
			_device = event.device
		elif _device == event.device and _candidate.get("axis", -1) == event.axis and absf(event.axis_value) < 0.25:
			_assign_candidate()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		_close()


func _assign_candidate() -> void:
	var action: String = _capture.get_meta("action")
	var slot: int = _capture.get_meta("slot")
	var updated := draft.duplicate(true)
	var previous: Dictionary = updated[action].events[slot]
	var message := "Assegnato: %s. Premi SALVA per applicare." % Bindings.binding_label(_candidate)
	for context in Bindings.CONTEXTS:
		if action not in context:
			continue
		for other: String in context:
			for index in updated[other].events.size():
				if updated[other].events[index] == _candidate and (other != action or index != slot):
					updated[other].events[index] = previous.duplicate()
					message = "Scambio con %s. Premi SALVA per applicare." % LABELS[other]
	updated[action].events[slot] = _candidate.duplicate()
	if Bindings.validated(updated).is_empty():
		_finish_capture("Assegnazione non valida. Nessuna modifica.")
		return
	draft = updated
	_finish_capture(message)


func _finish_capture(message: String) -> void:
	var button := _capture
	_capture = null
	_candidate = {}
	_refresh_rows()
	_status.text = message
	if is_instance_valid(button):
		button.grab_focus()


func _reset_profile() -> void:
	draft = Bindings.defaults()
	_rebuild_rows()
	_status.text = "Predefiniti ripristinati nella bozza. SALVA per confermare, INDIETRO per annullare."
	_reset.grab_focus()


func _save_profile() -> void:
	var error := Settings.save_controller_bindings(draft, config_path)
	if error != OK:
		_status.text = "Impossibile salvare: %s. Le assegnazioni attive non sono cambiate." % error_string(error)
		return
	bindings_saved.emit(draft.duplicate(true))
	_close()


func _close() -> void:
	_capture = null
	hide()
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus.call_deferred()


func _on_connection_changed(_device_id: int, connected: bool) -> void:
	if visible and not connected:
		_finish_capture("Controller scollegato. Ricollegalo per continuare; la bozza è conservata.")
