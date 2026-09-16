extends RefCounted
## Controller-only profiles. Keyboard/mouse events stay in InputMap unchanged.
## A profile maps actions to {events: [{button: int} or {axis: int, direction: -1|1}],
## deadzone: float}. Submit both halves together to move/invert an analog pair.

const CONTEXTS := [
	["ui_accept", "ui_cancel", "ui_left", "ui_right", "ui_up", "ui_down"],
	["pitch_up", "pitch_down", "roll_left", "roll_right", "yaw_left", "yaw_right",
		"accelerate", "brake", "fire_gun", "fire_missile", "cycle_target",
		"switch_missile", "pause_menu", "look_left", "look_right", "look_up", "look_down"],
]


const BUTTON_LABELS := ["A", "B", "X", "Y", "View", "Xbox", "Menu", "LS", "RS", "LB", "RB",
	"D-pad su", "D-pad giù", "D-pad sinistra", "D-pad destra"]
const AXIS_LABELS := ["Stick SX ←", "Stick SX →", "Stick SX ↑", "Stick SX ↓",
	"Stick DX ←", "Stick DX →", "Stick DX ↑", "Stick DX ↓", "LT", "RT"]


static func binding_label(binding: Dictionary) -> String:
	if binding.has("button"):
		return BUTTON_LABELS[binding.button]
	if binding.axis >= JOY_AXIS_TRIGGER_LEFT:
		return AXIS_LABELS[8 + binding.axis - JOY_AXIS_TRIGGER_LEFT]
	return AXIS_LABELS[binding.axis * 2 + (1 if binding.direction > 0 else 0)]


## Prompts read the live map, not defaults or an unsaved remapping draft.
## Show the first controller alternative to keep hints short; desktop-only actions
## (e.g. the debugging retry key) fall back to their actual key/mouse event.
static func action_label(action: String) -> String:
	var events := InputMap.action_get_events(action)
	for event in events:
		if event is InputEventJoypadButton:
			return binding_label({"button": event.button_index})
		if event is InputEventJoypadMotion:
			return binding_label({"axis": event.axis, "direction": int(signf(event.axis_value))})
	return events[0].as_text() if not events.is_empty() else "Non assegnato"


static func menu_hint() -> String:
	return "[%s / %s] Naviga · [%s] Conferma · [%s] Indietro" % [
		action_label("ui_up"), action_label("ui_down"), action_label("ui_accept"), action_label("ui_cancel")]


static func weapons_hint() -> String:
	return "[%s] Cannone · [%s] Lancia missile\n[%s] Cambia missile · [%s] Cambia bersaglio (tieni: insegui)\n[%s] Pausa / opzioni" % [
		action_label("fire_gun"), action_label("fire_missile"), action_label("switch_missile"),
		action_label("cycle_target"), action_label("pause_menu")]


static func defaults() -> Dictionary:
	var profile := {}
	for context in CONTEXTS:
		for action: String in context:
			var definition: Dictionary = ProjectSettings.get_setting("input/" + action)
			var events: Array = []
			for event: InputEvent in definition.events:
				if event is InputEventJoypadButton:
					events.append({"button": event.button_index})
				elif event is InputEventJoypadMotion:
					events.append({"axis": event.axis, "direction": int(signf(event.axis_value))})
			profile[action] = {"events": events, "deadzone": definition.deadzone}
	return profile


## Missing actions inherit project defaults. Invalid/conflicting profiles are rejected
## as a unit: partial fallback could steal another action's only usable binding.
## An empty dictionary returned here means invalid, not "reset"; {} as input resets.
static func validated(overrides: Variant) -> Dictionary:
	if not overrides is Dictionary:
		return {}
	var profile := defaults()
	for action in overrides:
		if not profile.has(action):
			return {}
		var entry: Variant = overrides[action]
		if not entry is Dictionary or entry.size() != 2 \
				or not entry.has("events") or not entry.has("deadzone"):
			return {}
		var deadzone: Variant = entry.deadzone
		if not (deadzone is float or deadzone is int) or not is_finite(float(deadzone)) \
				or deadzone < 0.0 or deadzone >= 1.0:
			return {}
		if not entry.events is Array or entry.events.is_empty():
			return {}
		for event: Variant in entry.events:
			if not event is Dictionary:
				return {}
			if event.has("button"):
				if event.size() != 1 or not event.button is int \
						or event.button < JOY_BUTTON_A or event.button > JOY_BUTTON_DPAD_RIGHT:
					return {}
			elif event.has("axis") and event.has("direction"):
				if event.size() != 2 or not event.axis is int \
						or event.axis < JOY_AXIS_LEFT_X or event.axis > JOY_AXIS_TRIGGER_RIGHT \
						or not event.direction is int or event.direction not in [-1, 1]:
					return {}
				# Xbox triggers are unipolar: the negative half cannot be actuated.
				if event.axis >= JOY_AXIS_TRIGGER_LEFT and event.direction != 1:
					return {}
			else:
				return {}
		profile[action] = entry.duplicate(true)
	for context in CONTEXTS:
		var occupied := {}
		for action: String in context:
			for event: Dictionary in profile[action].events:
				var key := "button:%d" % event.button if event.has("button") \
						else "axis:%d:%d" % [event.axis, event.direction]
				if occupied.has(key):
					return {}
				occupied[key] = action
	return profile


static func normalized(overrides: Variant) -> Dictionary:
	var profile := validated(overrides)
	return defaults() if profile.is_empty() else profile


static func apply(overrides: Variant) -> void:
	var profile := normalized(overrides)
	for action: String in profile:
		var replacement: Array[InputEvent] = []
		for binding: Dictionary in profile[action].events:
			var event: InputEvent
			if binding.has("button"):
				var button := InputEventJoypadButton.new()
				button.button_index = binding.button
				event = button
			else:
				var motion := InputEventJoypadMotion.new()
				motion.axis = binding.axis
				motion.axis_value = binding.direction
				event = motion
			# Match the gamepad-independent gameplay bindings, including UI directions.
			event.device = -1
			replacement.append(event)
		var current: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				current.append(event)
		var changed := current.size() != replacement.size() \
				or not is_equal_approx(InputMap.action_get_deadzone(action), profile[action].deadzone)
		if not changed:
			for i in current.size():
				if current[i].device != -1 or not current[i].is_match(replacement[i], true):
					changed = true
					break
		if not changed:
			continue
		# A held input removed from the map must not leave its old action latched.
		Input.action_release(action)
		for event in current:
			InputMap.action_erase_event(action, event)
		for event in replacement:
			InputMap.action_add_event(action, event)
		InputMap.action_set_deadzone(action, profile[action].deadzone)
