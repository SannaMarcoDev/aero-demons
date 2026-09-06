extends Node

const TARGET_LOCK_SOUND: AudioStream = preload("res://assets/audio/sfx/ui/target-lock.mp3")
const ALARM_SOUND: AudioStream = preload("res://assets/audio/sfx/ui/alarm.mp3")
const BULLET_HIT_SOUND: AudioStream = preload("res://assets/audio/sfx/weapons/bullet-hit.mp3")
const MISSILE_LAUNCH_SOUND: AudioStream = preload("res://assets/audio/sfx/weapons/fire-missile.mp3")
const MISSILE_HIT_SOUND: AudioStream = preload("res://assets/audio/sfx/weapons/missile-hit.mp3")
const WEAPON_SWITCH_SOUND: AudioStream = preload("res://assets/audio/sfx/ui/weapon-switch.wav")

var _ui_player: AudioStreamPlayer
var _alarm_player: AudioStreamPlayer
var _alarm_active := false


func _ready() -> void:
	_ui_player = _make_2d_player(&"SFX", -20.0)
	_alarm_player = _make_2d_player(&"SFX", -20.0)
	_alarm_player.finished.connect(_on_alarm_finished)


func _on_alarm_finished() -> void:
	if _alarm_active and _alarm_player != null:
		_play_2d(_alarm_player, ALARM_SOUND)


func play_atoll_cutscene_music() -> void:
	pass


func play_target_lock() -> void:
	if _ui_player != null and not _ui_player.playing:
		_play_2d(_ui_player, TARGET_LOCK_SOUND)


func play_alarm() -> void:
	_alarm_active = true
	if _alarm_player != null and not _alarm_player.playing:
		_play_2d(_alarm_player, ALARM_SOUND)


func stop_alarm() -> void:
	_alarm_active = false
	if _alarm_player != null and _alarm_player.playing:
		_alarm_player.stop()


func play_weapon_switch() -> void:
	if _ui_player != null:
		_play_2d(_ui_player, WEAPON_SWITCH_SOUND)


func play_bullet_hit(parent: Node, position: Vector3) -> void:
	_play_spatial(BULLET_HIT_SOUND, parent, position, -13.5)


func play_missile_launch(parent: Node, position: Vector3, volume_db: float = -4.0) -> void:
	_play_spatial(MISSILE_LAUNCH_SOUND, parent, position, volume_db)


func play_missile_hit(parent: Node, position: Vector3, volume_db: float = -7.5) -> void:
	_play_spatial(MISSILE_HIT_SOUND, parent, position, volume_db)


func _make_2d_player(bus: StringName, volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.volume_db = volume_db
	add_child(player)
	return player


func _play_2d(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if player == null:
		return
	player.stream = stream
	player.play()


func _play_spatial(stream: AudioStream, parent: Node, position: Vector3, volume_db: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	setup_sfx_3d(player, volume_db)
	parent.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


func setup_sfx_3d(player: AudioStreamPlayer3D, volume_db: float) -> void:
	player.bus = &"SFX"
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_db = 24.0
	player.volume_db = volume_db
	player.max_distance = 30000.0
