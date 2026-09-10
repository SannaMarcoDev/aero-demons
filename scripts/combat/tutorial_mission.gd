extends "res://scripts/combat/sortie_controller.gd"
class_name TutorialMission
## Three authored encounters. The inherited controller owns defeat/result UI, not wave progression.

enum Phase { RADIO, COMBAT, OUTRO }
const BRIEFINGS := ["intro", "after_1", "after_2"]

@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_fighter.tscn")
@export var dialogue: DialogueResource
@export var encounter_paths: Array[NodePath] = [
	NodePath("../../EnemySpawnMarkers/Encounter1"),
	NodePath("../../EnemySpawnMarkers/Encounter2"),
	NodePath("../../EnemySpawnMarkers/Encounter3"),
]

var phase := Phase.RADIO
var encounter_index := 0
var active_enemies: Array[EnemyFighter] = []
var _encounters: Array[Node3D] = []

@onready var radio: RadioDialogue = get_node("../HudText/RadioDialogue")
@onready var director: CombatDirector = get_node("../../CombatDirector")
@onready var spawn_root: Node3D = get_node("../../SpawnedEnemies")


func _ready() -> void:
	super()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	radio.line_shown.connect(_on_radio_line)
	radio.finished.connect(_on_radio_finished)
	_start.call_deferred()


func _start() -> void:
	if terminal:
		return
	if dialogue == null or enemy_scene == null or encounter_paths.size() != BRIEFINGS.size():
		_configuration_error("Servono dialoghi, scena nemica e tre gruppi di marker.")
		return
	for cue in BRIEFINGS + ["outro"]:
		if not dialogue.cues.has(cue):
			_configuration_error("Dialogo mancante: " + cue)
			return
	for path in encounter_paths:
		var group := get_node_or_null(path) as Node3D
		if group == null or group.get_child_count() == 0:
			_configuration_error("Gruppo di spawn mancante o vuoto: " + str(path))
			return
		for marker in group.get_children():
			if not marker is Marker3D or not marker.transform.is_finite():
				_configuration_error("Ogni punto di spawn deve essere un Marker3D valido: " + str(path))
				return
		_encounters.append(group)
	_play_briefing()


func objectives_text() -> String:
	if terminal:
		return ">MISSIONE TERMINATA"
	if phase == Phase.OUTRO:
		return ">AREA LIBERA · ASCOLTA LA SQUADRA"
	if phase == Phase.RADIO or remaining == 0:
		return ">ASCOLTA LA SQUADRA ALLA RADIO"
	return ">GRUPPO %d/3 · NEMICI RIMASTI: %d" % [encounter_index + 1, remaining]


func wing_alive(number: int) -> bool:
	return CombatDirector.alive(get_node_or_null("../../Wingman%d" % number))


func _play_briefing() -> void:
	phase = Phase.RADIO
	radio.play(dialogue, BRIEFINGS[encounter_index], [self])


func _on_radio_line(line: DialogueLine) -> void:
	if terminal or phase != Phase.RADIO or not line.has_tag("spawn"):
		return
	if line.get_tag_value("spawn") != str(encounter_index + 1):
		_configuration_error("Avvistamento fuori sequenza: " + line.get_tag_value("spawn"))
		return
	# Latch before instantiating: duplicated radio events cannot spawn the same wave twice.
	phase = Phase.COMBAT
	for marker: Marker3D in _encounters[encounter_index].get_children():
		var instance := enemy_scene.instantiate()
		if not instance is EnemyFighter:
			instance.free()
			_configuration_error("La scena di spawn deve contenere un EnemyFighter.")
			return
		var enemy := instance as EnemyFighter
		enemy.name = marker.name
		enemy.label = str(marker.name).replace("Bandit", "BANDIT ")
		# Ready stores the spawn and builds the initial maneuver, so place it BEFORE add_child.
		enemy.transform = spawn_root.global_transform.affine_inverse() * marker.global_transform
		enemy.director = director
		enemy.destroyed.connect(_on_enemy_destroyed)
		active_enemies.append(enemy)
		spawn_root.add_child(enemy)
		enemy.reset_physics_interpolation()
	remaining = active_enemies.size()
	director._refresh_pilots()
	director._assign_roles()


func _on_enemy_destroyed(aircraft: Node3D) -> void:
	if terminal or not active_enemies.has(aircraft):
		return
	active_enemies.erase(aircraft)
	remaining = active_enemies.size()
	_try_advance.call_deferred()


func _on_radio_finished() -> void:
	if terminal:
		return
	if phase == Phase.OUTRO:
		_finish("MISSIONE COMPLETATA", "TUTTI I NEMICI ABBATTUTI · AREA LIBERA")
	elif phase == Phase.RADIO:
		_configuration_error("Il dialogo non contiene l'avvistamento dell'incontro.")
	else:
		_try_advance.call_deferred()


func _try_advance() -> void:
	if terminal or phase != Phase.COMBAT or remaining > 0 or radio.playing or get_tree().paused:
		return
	encounter_index += 1
	if encounter_index == _encounters.size():
		phase = Phase.OUTRO
		radio.play(dialogue, "outro", [self])
	else:
		_play_briefing()


func _process(_delta: float) -> void:
	# Also catches the last kill being reported just before the pause menu opens.
	if phase == Phase.COMBAT and remaining == 0:
		_try_advance()


func _finish(title: String, detail: String) -> void:
	if terminal:
		return
	radio.stop()
	super(title, detail)


func _configuration_error(detail: String) -> void:
	push_error("Tutorial mission: " + detail)
	_finish("ERRORE MISSIONE", detail)
