extends PanelContainer
class_name RadioDialogue
## Linear radio subtitles: no focus, input handling, voice requirement or global dialogue-end listener.

signal line_shown(line: DialogueLine)
signal finished

@export var minimum_line_seconds := 3.0
@export var seconds_per_character := 0.05

var playing := false
var current_line: DialogueLine
var _resource: DialogueResource
var _states: Array = []
var _generation := 0
var _loading := false
var _pending := false
var _pending_line: DialogueLine
var _remaining := 0.0

@onready var _speaker: Label = $Lines/Speaker
@onready var _text: RichTextLabel = $Lines/Text


func _ready() -> void:
	# CombatHUD runs during pause; the radio must not inherit that behavior.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	hide()


func play(resource: DialogueResource, cue: String, states: Array = []) -> void:
	stop()
	_resource = resource
	_states = states
	playing = true
	_next_line(cue, _generation)


func stop() -> void:
	_generation += 1
	playing = false
	_pending = false
	_loading = false
	_pending_line = null
	current_line = null
	_states = []
	_remaining = 0.0
	hide()


func _next_line(key: String, generation: int) -> void:
	_loading = true
	var line := await _resource.get_next_dialogue_line(key, _states)
	if generation != _generation or not is_inside_tree():
		return
	# Publish only from the pausable process, even if loading finishes during a pause.
	_pending_line = line
	_pending = true
	_loading = false


func _process(delta: float) -> void:
	if not playing or get_tree().paused or _loading:
		return
	if _pending:
		_pending = false
		current_line = _pending_line
		_pending_line = null
		if current_line == null:
			stop()
			finished.emit()
			return
		_speaker.text = "RADIO  /  " + current_line.character
		_text.text = current_line.text
		_remaining = maxf(minimum_line_seconds, _text.get_parsed_text().length() * seconds_per_character)
		if current_line.time.is_valid_float():
			_remaining = maxf(current_line.time.to_float(), 0.1)
		show()
		line_shown.emit(current_line)
		return
	_remaining -= delta
	if _remaining <= 0.0 and current_line != null:
		_next_line(current_line.next_id, _generation)
