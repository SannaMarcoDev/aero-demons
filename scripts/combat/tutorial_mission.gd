extends "res://scripts/combat/sortie_controller.gd"
class_name TutorialMission
## Formation showcase → controls popup → collaudo → radio banter → convoy reveal → four interceptors.
signal flight_training_completed

enum Phase { OPENING, CONTROLS_READING, FLIGHT, BANTER, REVEAL, TARGET_READING, MISSILE_READING, GUN_READING, COMBAT }
const PRACTICE_SECONDS := 0.35
const BANTER_SILENCE := 3.0 # Nova's non-answer to Ubris's question.
const Bindings = preload("res://scripts/input/controller_bindings.gd")
const Cinematic = preload("res://scripts/combat/tutorial_cinematic.gd")

@export var safety_height := 120.0
@export var dialogue: DialogueResource
@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_fighter.tscn")
var active_enemies: Array[EnemyFighter] = []
var phase := Phase.OPENING
var movement_practice := Vector3.ZERO
var _formation_time := 0.0
var _wings_joined := false
var _half_call_pending := false
var _movement_armed := false
var cinematic: Cinematic

@onready var radio: RadioDialogue = get_node_or_null("../HudText/RadioDialogue")
@onready var director: CombatDirector = get_node("../../CombatDirector")
@onready var spawn_root: Node3D = get_node("../../SpawnedEnemies")
@onready var targeting: TargetLock = player.get_node("TargetLock")
@onready var weapons: WeaponController = player.get_node("WeaponController")
@onready var wings: Array[EnemyFighter] = [get_node("../../Wingman1"), get_node("../../Wingman2")]


func _ready() -> void:
	super()
	if radio == null:
		radio = preload("res://scenes/ui/radio_dialogue.tscn").instantiate()
		hud.get_node("HudText").add_child(radio)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	player.controls_enabled = false
	player.invulnerable = true
	weapons.firing_enabled = false
	targeting.auto_acquire = false
	director.set_physics_process(false)
	for wing in wings:
		wing.hide()
		wing.set_physics_process(false)
		wing.get_node("WeaponController").firing_enabled = false
	_start.call_deferred()


func _start() -> void:
	for cue in ["collaudo", "collaudo_comandi", "banter", "banter_reply", "sphere", "interceptors", "combat", "half"]:
		if dialogue == null or not dialogue.cues.has(cue):
			push_error("Tutorial mission: missing dialogue " + cue)
			_finish("ERRORE MISSIONE", "Dialogo tutorial mancante: " + cue)
			return
	hud.tutorial_panel.confirmed.connect(_on_tutorial_confirmed)
	cinematic = Cinematic.new()
	cinematic.name = "TutorialCinematic"
	hud.get_parent().add_child(cinematic)
	_begin_flight()


func objectives_text() -> String:
	if terminal:
		return ">MISSIONE TERMINATA"
	match phase:
		Phase.OPENING, Phase.CONTROLS_READING, Phase.REVEAL:
			return ""
		Phase.FLIGHT:
			var todo: Array[String] = []
			if movement_practice.x < PRACTICE_SECONDS:
				todo.append("Beccheggio [%s / %s]" % [Bindings.action_label("pitch_up"), Bindings.action_label("pitch_down")])
			if movement_practice.y < PRACTICE_SECONDS:
				todo.append("Rollio [%s / %s]: inclina le ali, poi alza il muso per virare" % [Bindings.action_label("roll_left"), Bindings.action_label("roll_right")])
			if movement_practice.z < PRACTICE_SECONDS:
				todo.append("Imbardata [%s / %s]: correggi la direzione" % [Bindings.action_label("yaw_left"), Bindings.action_label("yaw_right")])
			if not player.landing_gear_retracted():
				todo.append("Retrai il carrello [%s]" % Bindings.action_label("landing_gear"))
			if not todo.is_empty():
				return ">COLLAUDO · PROVA I COMANDI\n" + "\n".join(todo)
			return ">COLLAUDO · RISALI IN QUOTA\nVolo livellato: tieni [%s + %s]" % [Bindings.action_label("accelerate"), Bindings.action_label("brake")]
		Phase.BANTER:
			return ">COLLAUDO COMPLETATO"
		Phase.COMBAT:
			return ">INTERCETTORI RIMASTI: %d / 4" % remaining
	return ">LEGGI LE ISTRUZIONI ARMI"


func _begin_flight() -> void:
	director.player = player
	for wing in wings:
		wing.director = director
		wing.formation_spacing = 40.0
		wing.formation_forward = 30.0
		wing.invulnerable = true
		wing.get_node("WeaponController").firing_enabled = false
	_wings_joined = true
	# The showcase plays `collaudo` and hands over in close formation while `collaudo_comandi` asks for the controls.
	await cinematic.play_formation(radio, dialogue, wings)
	if terminal:
		return
	# Let Aegis finish handing over before the controls popup pauses the game.
	if radio.playing:
		await radio.finished
	if terminal:
		return
	phase = Phase.CONTROLS_READING
	hud.tutorial_panel.open("VOLO · COMANDI DI BASE", "Il gioco è in pausa: puoi leggere senza pericolo.\n\nBeccheggio [{pitch_up} / {pitch_down}]: alza o abbassa il muso.\nRollio [{roll_left} / {roll_right}]: inclina le ali. Per virare, inclina e poi alza il muso.\nImbardata [{yaw_left} / {yaw_right}]: piccole correzioni di direzione.\n\nSpinta [{accelerate}] · Freno [{brake}]\nCarrello [{landing_gear}]: retrailo per volare pulito.")


func _physics_process(delta: float) -> void:
	if terminal:
		return
	if _wings_joined and phase != Phase.COMBAT:
		_formation_time += delta
	match phase:
		Phase.FLIGHT:
			var axes := Vector3(Input.get_axis("pitch_up", "pitch_down"), Input.get_axis("roll_left", "roll_right"), Input.get_axis("yaw_left", "yaw_right"))
			if not _movement_armed:
				_movement_armed = axes.is_zero_approx()
			else:
				for axis in 3:
					if absf(axes[axis]) > 0.2:
						movement_practice[axis] += delta
			if _safe_airborne() and player.landing_gear_retracted() and movement_practice.x >= PRACTICE_SECONDS and movement_practice.y >= PRACTICE_SECONDS and movement_practice.z >= PRACTICE_SECONDS:
				phase = Phase.BANTER
				_banter.call_deferred()
		Phase.COMBAT:
			if _half_call_pending and not radio.playing:
				_half_call_pending = false
				if remaining == 2:
					radio.play(dialogue, "half")


func _safe_airborne() -> bool:
	return not player.grounded and player.global_position.y >= player.min_altitude + safety_height


func _banter() -> void:
	radio.play(dialogue, "banter")
	await radio.finished
	if terminal:
		return
	await get_tree().create_timer(BANTER_SILENCE, false).timeout
	if terminal:
		return
	radio.play(dialogue, "banter_reply")
	await radio.finished
	if terminal:
		return
	phase = Phase.REVEAL
	_reveal()


func _reveal() -> void:
	await cinematic.play_reveal(radio, dialogue, enemy_scene)
	if terminal:
		return
	for i in wings.size():
		var side := -1.0 if i == 0 else 1.0
		wings[i].global_position = player.global_position + player.global_basis.x * (side * wings[i].formation_spacing) - player.global_basis.z * wings[i].formation_forward
		wings[i].global_basis = player.global_basis
		wings[i].speed = player.speed
		wings[i].reset_physics_interpolation()
	active_enemies = cinematic.release_interceptors(spawn_root)
	remaining = active_enemies.size()
	for enemy in active_enemies:
		enemy.destroyed.connect(_on_enemy_destroyed)
	phase = Phase.TARGET_READING
	flight_training_completed.emit()
	hud.tutorial_panel.open("ARMI · BERSAGLIO E AGGANCIO", "Quattro intercettori in avvicinamento. Il gioco è in pausa: puoi leggere senza pericolo.\n\nPremi e rilascia [{cycle_target}] per selezionare un bersaglio; tienilo premuto per seguirlo con la visuale.\n\nMantieni il bersaglio sullo schermo e nel raggio del missile. Attendi il segnale di aggancio prima del lancio.")


func _on_tutorial_confirmed() -> void:
	if terminal:
		return
	match phase:
		Phase.CONTROLS_READING:
			phase = Phase.FLIGHT
		Phase.TARGET_READING:
			phase = Phase.MISSILE_READING
			hud.tutorial_panel.open("ARMI · MISSILI", "Lancia con [{fire_missile}] dopo l'aggancio.\nCambia armamento con [{switch_missile}]; il tipo attivo è indicato nell'HUD.\n\nMTSM aggancia più contatti validi a schermo. Gli altri missili richiedono un aggancio sul bersaglio selezionato.")
		Phase.MISSILE_READING:
			phase = Phase.GUN_READING
			hud.tutorial_panel.open("ARMI · CANNONE", "Spara con [{fire_gun}]. Il cannone non richiede aggancio.\n\nAvvicinati al bersaglio e porta il mirino sul cerchio che anticipa il nemico. Usa raffiche brevi.\n\nCon la prossima conferma inizia il combattimento.")
		Phase.GUN_READING:
			phase = Phase.COMBAT
			player.invulnerable = false
			weapons.firing_enabled = true
			targeting.auto_acquire = true
			for aircraft in wings + active_enemies:
				aircraft.director = director
				aircraft.get_node("WeaponController").firing_enabled = true
				aircraft.set_physics_process(true)
				director.release_attack(aircraft)
			director.allow_player_attacks = true
			director._refresh_pilots()
			director._assign_roles()
			director.set_physics_process(true)
			radio.play(dialogue, "combat")


func _on_enemy_destroyed(aircraft: Node3D) -> void:
	if terminal or phase != Phase.COMBAT or not active_enemies.has(aircraft):
		return
	active_enemies.erase(aircraft)
	remaining = active_enemies.size()
	if remaining == 2:
		_half_call_pending = true
	if remaining == 0:
		_finish("MISSIONE COMPLETATA", "QUATTRO INTERCETTORI ABBATTUTI · DATI REGISTRATI")


func _finish(title: String, detail: String) -> void:
	if terminal:
		return
	radio.stop()
	super(title, detail)
