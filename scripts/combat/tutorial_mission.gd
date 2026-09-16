extends "res://scripts/combat/sortie_controller.gd"
class_name TutorialMission
## Protected flight, informational weapon panels, then the authored 2/4/8 encounters.
signal flight_training_completed

enum Phase { OPENING, MOVEMENT_READING, MOVEMENT, CONTACT_RADIO, SPEED_READING, APPROACH,
	TARGET_READING, MISSILE_READING, GUN_READING, COMBAT, WAVE_RADIO, OUTRO }
const PRACTICE_SECONDS := 0.35
const CONTACT_DISTANCE := 6000.0
const HANDOFF_DISTANCE := 1800.0
const Bindings = preload("res://scripts/ui/controller_bindings.gd")

@export var dialogue: DialogueResource
@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_fighter.tscn")
var encounter_index := 0
var active_enemies: Array[EnemyFighter] = []
var phase := Phase.OPENING
var movement_practice := Vector3.ZERO
var acceleration_practice := 0.0
var _movement_armed := false
var _acceleration_armed := false

@onready var radio: RadioDialogue = get_node("../HudText/RadioDialogue")
@onready var director: CombatDirector = get_node("../../CombatDirector")
@onready var contact: Marker3D = get_node("../../FlightContact")
@onready var spawn_root: Node3D = get_node("../../SpawnedEnemies")
@onready var targeting: TargetLock = player.get_node("TargetLock")
@onready var weapons: WeaponController = player.get_node("WeaponController")


func _ready() -> void:
	super()
	process_mode = Node.PROCESS_MODE_PAUSABLE
	player.invulnerable = true
	weapons.firing_enabled = false
	targeting.auto_acquire = false
	director.set_physics_process(false)
	for wing: EnemyFighter in [get_node("../../Wingman1"), get_node("../../Wingman2")]:
		wing.get_node("WeaponController").firing_enabled = false
	radio.finished.connect(_on_radio_finished)
	_start.call_deferred()


func _start() -> void:
	if terminal:
		return
	for cue in ["intro", "contacts", "combat", "after_1", "after_2", "outro"]:
		if dialogue == null or not dialogue.cues.has(cue):
			push_error("Tutorial mission: missing dialogue " + cue)
			_finish("ERRORE MISSIONE", "Dialogo tutorial mancante: " + cue)
			return
	hud.tutorial_panel.confirmed.connect(_on_tutorial_confirmed)
	radio.play(dialogue, "intro")


func objectives_text() -> String:
	if terminal:
		return ">MISSIONE TERMINATA"
	match phase:
		Phase.MOVEMENT:
			var todo: Array[String] = []
			if movement_practice.x < PRACTICE_SECONDS:
				todo.append("beccheggio [%s / %s]" % [Bindings.action_label("pitch_up"), Bindings.action_label("pitch_down")])
			if movement_practice.y < PRACTICE_SECONDS:
				todo.append("rollio [%s / %s]" % [Bindings.action_label("roll_left"), Bindings.action_label("roll_right")])
			if movement_practice.z < PRACTICE_SECONDS:
				todo.append("imbardata [%s / %s]" % [Bindings.action_label("yaw_left"), Bindings.action_label("yaw_right")])
			return ">PROVA: " + "\n".join(todo)
		Phase.APPROACH:
			return ">ACCELERA [%s] E RAGGIUNGI I CONTATTI · %.1f KM" % [Bindings.action_label("accelerate"), player.global_position.distance_to(contact.global_position) / 1000.0]
		Phase.COMBAT, Phase.WAVE_RADIO:
			return ">GRUPPO %d/3 · NEMICI RIMASTI: %d" % [encounter_index + 1, remaining]
		Phase.OUTRO:
			return ">AREA LIBERA · RIENTRO ALLA BASE"
	return ">ASCOLTA LA RADIO / LEGGI LE ISTRUZIONI"


func tutorial_contact() -> Node3D:
	return contact if phase >= Phase.CONTACT_RADIO and phase <= Phase.APPROACH and not terminal else null


func _on_radio_finished() -> void:
	if terminal or radio.playing:
		return
	match phase:
		Phase.OPENING:
			phase = Phase.MOVEMENT_READING
			hud.tutorial_panel.open("COLLAUDO · MOVIMENTO", "L'aereo è già in volo. Prova i comandi con piccoli movimenti.\n\nBeccheggio [{pitch_up} / {pitch_down}]: alza o abbassa il muso.\nRollio [{roll_left} / {roll_right}]: inclina le ali; poi usa il beccheggio per virare.\nImbardata [{yaw_left} / {yaw_right}]: correggi la direzione lateralmente.\n\nDopo la conferma, prova ciascun asse senza fretta.")
		Phase.CONTACT_RADIO:
			phase = Phase.SPEED_READING
			hud.tutorial_panel.open("COLLAUDO · VELOCITÀ", "Contatti nemici ancora lontani: nessun attacco in corso.\n\nAccelerazione [{accelerate}]: tieni premuto per aumentare la velocità.\nFreno [{brake}]: rallenta per controllare meglio l'avvicinamento.\nRilasciando i comandi torni gradualmente alla velocità di crociera.\n\nAccelera e vola verso l'indicatore CONTATTI.")
		Phase.WAVE_RADIO:
			phase = Phase.COMBAT
			_spawn_encounter()
		Phase.OUTRO:
			_finish("MISSIONE COMPLETATA", "TUTTI I NEMICI ABBATTUTI · RIENTRO ALLA BASE")


func _on_tutorial_confirmed() -> void:
	if terminal or get_tree().paused:
		return
	match phase:
		Phase.MOVEMENT_READING:
			phase = Phase.MOVEMENT
			_movement_armed = false
		Phase.SPEED_READING:
			phase = Phase.APPROACH
			_acceleration_armed = false
		Phase.TARGET_READING:
			phase = Phase.MISSILE_READING
			hud.tutorial_panel.open("ARMI · MISSILI", _missile_instructions())
		Phase.MISSILE_READING:
			phase = Phase.GUN_READING
			hud.tutorial_panel.open("ARMI · MITRAGLIATRICE", "Spara con [{fire_gun}]. La mitragliatrice non richiede aggancio.\n\nAvvicinati al bersaglio e sovrapponi il piccolo mirino di tiro al cerchio che anticipa il nemico. Usa raffiche brevi.")
		Phase.GUN_READING:
			phase = Phase.COMBAT
			radio.play(dialogue, "combat")


func _physics_process(delta: float) -> void:
	if terminal or get_tree().paused:
		return
	match phase:
		Phase.MOVEMENT:
			var axes := Vector3(Input.get_axis("pitch_up", "pitch_down"), Input.get_axis("roll_left", "roll_right"), Input.get_axis("yaw_left", "yaw_right"))
			if not _movement_armed:
				_movement_armed = axes.is_zero_approx()
				return
			for axis in 3:
				if absf(axes[axis]) > 0.2:
					movement_practice[axis] += delta
			if movement_practice.x >= PRACTICE_SECONDS and movement_practice.y >= PRACTICE_SECONDS and movement_practice.z >= PRACTICE_SECONDS:
				phase = Phase.CONTACT_RADIO
				# Narrative destination, not an active encounter. Keep it reachable inside the arena,
				# regardless of how long/direction the player used to practice.
				var forward := -player.global_basis.z
				forward.y = 0.0
				if forward.length_squared() < 0.01:
					forward = Vector3.FORWARD
				var origin := player.global_position
				var destination := origin + forward.normalized() * CONTACT_DISTANCE
				if Vector2(destination.x, destination.z).length() > player.return_distance - 1000.0:
					destination = origin - Vector3(origin.x, 0.0, origin.z).normalized() * CONTACT_DISTANCE
				contact.global_position = destination
				radio.play(dialogue, "contacts")
		Phase.APPROACH:
			if not _acceleration_armed:
				_acceleration_armed = not Input.is_action_pressed("accelerate")
				return
			if player.throttle_input > 0.2 and player.throttle_input * player.acceleration > player.brake_input * player.deceleration:
				acceleration_practice += delta
			if acceleration_practice >= PRACTICE_SECONDS and player.global_position.distance_to(contact.global_position) <= HANDOFF_DISTANCE:
				_show_weapons_instructions()
		Phase.COMBAT:
			_try_advance()


func _show_weapons_instructions() -> void:
	if terminal or phase != Phase.APPROACH:
		return
	phase = Phase.TARGET_READING
	player.invulnerable = false
	weapons.firing_enabled = true
	targeting.auto_acquire = true
	for wing: EnemyFighter in [get_node("../../Wingman1"), get_node("../../Wingman2")]:
		wing.get_node("WeaponController").firing_enabled = true
	director.allow_player_attacks = true
	director.set_physics_process(true)
	_spawn_encounter()
	if terminal:
		return
	flight_training_completed.emit()
	hud.tutorial_panel.open("ARMI · BERSAGLIO E AGGANCIO", "Premi e rilascia [{cycle_target}] per selezionare o cambiare bersaglio. Tieni premuto per seguirlo con la visuale.\n\nMantieni il bersaglio sullo schermo e nel raggio del missile: il mirino rosso indica che puoi agganciare. Attendi il segnale di aggancio prima del lancio.\n\nCon MTSM l'aggancio multiplo è immediato sui contatti validi a schermo.")


func _missile_instructions() -> String:
	var slots: Array[String] = []
	for index in weapons.equipped_missile_ids.size():
		var id := weapons.equipped_missile_ids[index]
		slots.append("Slot %d · %s: %s" % [index + 1, id, weapons.Catalog.description(id)])
	return "Lancia con [{fire_missile}] solo con un aggancio valido.\nCambia slot con [{switch_missile}]; il tipo attivo è indicato nell'HUD.\n\n%s\n\nSTDM, HSSTDM, BAHM e NCGBM richiedono il lock sul bersaglio selezionato. MTSM aggancia più contatti a schermo e lancia due portanti." % "\n".join(slots)


func _spawn_encounter() -> void:
	var markers := get_node("../../EnemySpawnMarkers/Encounter%d" % (encounter_index + 1))
	for marker: Marker3D in markers.get_children():
		var enemy := enemy_scene.instantiate() as EnemyFighter
		if enemy == null:
			_finish("ERRORE MISSIONE", "Scena nemica non valida")
			return
		enemy.name = marker.name
		enemy.label = str(marker.name).replace("Bandit", "BANDIT ")
		var start := marker.global_transform
		if encounter_index == 0:
			# Present the first group ahead of the player's actual approach heading.
			start = player.global_transform * Transform3D(Basis.IDENTITY, marker.position + Vector3(0, 0, -1000))
		enemy.transform = spawn_root.global_transform.affine_inverse() * start
		enemy.director = director
		enemy.destroyed.connect(_on_enemy_destroyed)
		active_enemies.append(enemy)
		spawn_root.add_child(enemy)
		enemy.reset_physics_interpolation()
	remaining = active_enemies.size()
	director._refresh_pilots()
	director._assign_roles()


func _on_enemy_destroyed(aircraft: Node3D) -> void:
	if terminal or phase != Phase.COMBAT or not active_enemies.has(aircraft):
		return
	active_enemies.erase(aircraft)
	remaining = active_enemies.size()
	_try_advance.call_deferred()


func _try_advance() -> void:
	if terminal or phase != Phase.COMBAT or remaining > 0 or radio.playing or get_tree().paused:
		return
	encounter_index += 1
	if encounter_index == 3:
		phase = Phase.OUTRO
		radio.play(dialogue, "outro")
	else:
		phase = Phase.WAVE_RADIO
		radio.play(dialogue, "after_%d" % encounter_index)


func _finish(title: String, detail: String) -> void:
	if terminal:
		return
	radio.stop()
	super(title, detail)
