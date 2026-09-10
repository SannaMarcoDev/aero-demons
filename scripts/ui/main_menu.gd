extends CanvasLayer

const Session = preload("res://scripts/ui/game_session.gd")
const Settings = preload("res://scripts/ui/settings_manager.gd")

# Root Menu Buttons
@onready var root_menu: VBoxContainer = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/RootMenu
@onready var storia_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/RootMenu/StoriaButton
@onready var free_flight_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/RootMenu/FreeFlightButton
@onready var options_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/RootMenu/OptionsButton
@onready var quit_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/RootMenu/QuitButton

# Storia Submenu
@onready var storia_menu: VBoxContainer = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/StoriaMenu
@onready var alps_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/StoriaMenu/GardaButton
@onready var storia_back_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/StoriaMenu/StoriaBackButton

# Options Submenu
@onready var options_menu: VBoxContainer = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu
@onready var master_slider: HSlider = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/AudioBox/MasterRow/MasterSlider
@onready var master_val_label: Label = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/AudioBox/MasterRow/MasterVal
@onready var music_slider: HSlider = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/AudioBox/MusicRow/MusicSlider
@onready var music_val_label: Label = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/AudioBox/MusicRow/MusicVal
@onready var sfx_slider: HSlider = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/AudioBox/SFXRow/SFXSlider
@onready var sfx_val_label: Label = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/AudioBox/SFXRow/SFXVal
@onready var window_mode_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/DisplayBox/WindowModeBtn
@onready var vsync_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/DisplayBox/VSyncBtn
@onready var options_back_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/OptionsBackButton

# Dossier / Intel Panel
@onready var dossier_tag: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/HeaderRow/DossierTag
@onready var threat_badge: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/HeaderRow/ThreatBadge
@onready var dossier_title: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/DossierTitle
@onready var dossier_subtitle: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/DossierSubtitle
@onready var dossier_desc: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/DossierDesc
@onready var dossier_telemetry: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/TelemetryFooter/TelemetryLabel
@onready var radar_widget: Control = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/RadarContainer/TacticalRadarWidget
@onready var section_header: Label = $MarginContainer/MainLayout/ContentArea/LeftPanel/SectionHeader

var _current_settings: Dictionary = {}
var _focused_mode: String = "storia"


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_current_settings = Settings.load_settings()
	Settings.apply_settings(_current_settings)
	_init_options_ui()
	_wire_signals()
	if Session.menu_section == "sorties":
		_on_storia_pressed()
	else:
		_show_root_menu()


func _process(_delta: float) -> void:
	if is_instance_valid(radar_widget):
		radar_widget.queue_redraw()


func _wire_signals() -> void:
	# Root menu button signals
	storia_btn.pressed.connect(_on_storia_pressed)
	storia_btn.focus_entered.connect(func(): _set_dossier("storia"))
	storia_btn.mouse_entered.connect(func(): _set_dossier("storia"))

	free_flight_btn.pressed.connect(_on_free_flight_pressed)
	free_flight_btn.focus_entered.connect(func(): _set_dossier("free_flight"))
	free_flight_btn.mouse_entered.connect(func(): _set_dossier("free_flight"))

	options_btn.pressed.connect(_on_options_pressed)
	options_btn.focus_entered.connect(func(): _set_dossier("options"))
	options_btn.mouse_entered.connect(func(): _set_dossier("options"))

	quit_btn.pressed.connect(_on_quit_pressed)
	quit_btn.focus_entered.connect(func(): _set_dossier("quit"))
	quit_btn.mouse_entered.connect(func(): _set_dossier("quit"))

	# Storia submenu signals
	alps_btn.pressed.connect(func(): _select_storia_map(Session.DOGFIGHT))
	alps_btn.focus_entered.connect(func(): _set_dossier("map_alps"))
	alps_btn.mouse_entered.connect(func(): _set_dossier("map_alps"))

	storia_back_btn.pressed.connect(_on_storia_back_pressed)
	storia_back_btn.focus_entered.connect(func(): _set_dossier("storia"))

	# Options submenu signals
	master_slider.value_changed.connect(_on_master_slider_changed)
	music_slider.value_changed.connect(_on_music_slider_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	window_mode_btn.pressed.connect(_on_toggle_window_mode)
	vsync_btn.pressed.connect(_on_toggle_vsync)
	options_back_btn.pressed.connect(_on_options_back_pressed)


func _show_root_menu() -> void:
	Session.menu_section = ""
	root_menu.visible = true
	storia_menu.visible = false
	options_menu.visible = false
	section_header.text = "// OPERATIONAL DIRECTIVES"
	storia_btn.grab_focus()
	_set_dossier("storia")


func _on_storia_pressed() -> void:
	_play_sfx()
	Session.menu_section = "sorties"
	root_menu.visible = false
	options_menu.visible = false
	storia_menu.visible = true
	section_header.text = "// SELECT SORTIE SECTOR"
	alps_btn.grab_focus()
	_set_dossier("map_alps")


func _on_free_flight_pressed() -> void:
	_play_sfx()
	Session.free_flight = true
	Session.menu_section = ""
	Session.selected_map = Session.FREE_FLIGHT
	_open_loadout()


func _on_options_pressed() -> void:
	_play_sfx()
	root_menu.visible = false
	storia_menu.visible = false
	options_menu.visible = true
	section_header.text = "// AVIONICS CONFIGURATION"
	master_slider.grab_focus()
	_set_dossier("options")


func _on_quit_pressed() -> void:
	_play_sfx()
	get_tree().quit()


func _on_storia_back_pressed() -> void:
	_play_sfx()
	_show_root_menu()
	storia_btn.grab_focus()


func _on_options_back_pressed() -> void:
	_play_sfx()
	var error := Settings.save_settings(_current_settings)
	if error != OK:
		dossier_desc.text = "Impossibile salvare le impostazioni: %s" % error_string(error)
		return
	_show_root_menu()
	options_btn.grab_focus()


func _select_storia_map(map_path: String) -> void:
	_play_sfx()
	Session.free_flight = false
	Session.selected_map = map_path
	_open_loadout()


func _open_loadout() -> void:
	if Session.change_scene(get_tree(), Session.LOADOUT) != OK:
		dossier_desc.text = "Impossibile aprire la selezione armamento."


func _init_options_ui() -> void:
	var master_vol: float = float(_current_settings.get("master_volume", 1.0))
	var music_vol: float = float(_current_settings.get("music_volume", 0.8))
	var sfx_vol: float = float(_current_settings.get("sfx_volume", 0.9))
	var is_fullscreen: bool = bool(_current_settings.get("fullscreen", false))
	var is_vsync: bool = bool(_current_settings.get("vsync", true))

	master_slider.value = master_vol * 100.0
	master_val_label.text = "%3d%%" % roundi(master_slider.value)

	music_slider.value = music_vol * 100.0
	music_val_label.text = "%3d%%" % roundi(music_slider.value)

	sfx_slider.value = sfx_vol * 100.0
	sfx_val_label.text = "%3d%%" % roundi(sfx_slider.value)

	window_mode_btn.text = "MODALITA': FULLSCREEN" if is_fullscreen else "MODALITA': FINESTRA"
	vsync_btn.text = "V-SYNC: ATTIVO" if is_vsync else "V-SYNC: DISATTIVO"


func _on_master_slider_changed(val: float) -> void:
	_current_settings["master_volume"] = val / 100.0
	master_val_label.text = "%3d%%" % roundi(val)
	Settings.apply_settings(_current_settings)


func _on_music_slider_changed(val: float) -> void:
	_current_settings["music_volume"] = val / 100.0
	music_val_label.text = "%3d%%" % roundi(val)
	Settings.apply_settings(_current_settings)


func _on_sfx_slider_changed(val: float) -> void:
	_current_settings["sfx_volume"] = val / 100.0
	sfx_val_label.text = "%3d%%" % roundi(val)
	Settings.apply_settings(_current_settings)


func _on_toggle_window_mode() -> void:
	_play_sfx()
	var current: bool = bool(_current_settings.get("fullscreen", false))
	_current_settings["fullscreen"] = not current
	window_mode_btn.text = "MODALITA': FULLSCREEN" if not current else "MODALITA': FINESTRA"
	Settings.apply_settings(_current_settings)


func _on_toggle_vsync() -> void:
	_play_sfx()
	var current: bool = bool(_current_settings.get("vsync", true))
	_current_settings["vsync"] = not current
	vsync_btn.text = "V-SYNC: ATTIVO" if not current else "V-SYNC: DISATTIVO"
	Settings.apply_settings(_current_settings)


func _set_dossier(mode_key: String) -> void:
	_focused_mode = mode_key
	if radar_widget != null and is_instance_valid(radar_widget) and radar_widget.has_method("set_mode"):
		radar_widget.call("set_mode", mode_key)

	match mode_key:
		"storia":
			dossier_tag.text = "// OPERATION THEATER DEPLOYMENT"
			threat_badge.text = "THREAT: HIGH"
			threat_badge.modulate = Color(1.0, 0.4, 0.2)
			dossier_title.text = "OPERAZIONI AEREE"
			dossier_subtitle.text = "DOGFIGHT SUL GARDA // PREPARAZIONE SORTITA"
			dossier_desc.text = "Seleziona la sortita e configura due tipi di missile prima del decollo.\n\nDogfight sul Garda: quattro caccia ostili e due gregari. Elimina i nemici e torna alla selezione armamento per una nuova sortita."
			dossier_telemetry.text = "STATO: AUTORIZZATO  •  PAYLOAD: ARMATO  •  RADAR: ATTIVO  •  DATALINK: CONNESSO"

		"free_flight":
			dossier_tag.text = "// RECONNAISSANCE & FLIGHT CALIBRATION"
			threat_badge.text = "THREAT: ZERO"
			threat_badge.modulate = Color(0.2, 0.95, 0.4)
			dossier_title.text = "VOLO LIBERO (FREE FLIGHT)"
			dossier_subtitle.text = "SETTORE: GARDA // NESSUN NEMICO RILEVATO"
			dossier_desc.text = "Configura l'armamento e decolla sopra il Garda. Nessun nemico, nessuna ondata e nessun timer di missione.\n\nProva manovre High-G, spin dash e postcombustione oppure esplora liberamente lo scenario. I confini di volo rimangono attivi."
			dossier_telemetry.text = "SETTORE: GARDA  •  MODALITA': ESPLORAZIONE  •  PAYLOAD: CONFIGURABILE"

		"options":
			dossier_tag.text = "// AVIONICS & SYSTEM TELEMETRY"
			threat_badge.text = "SYSTEM: READY"
			threat_badge.modulate = Color(0.2, 0.75, 1.0)
			dossier_title.text = "CONFIGURAZIONE SISTEMI"
			dossier_subtitle.text = "PARAMETRI AVIONICI // CALIBRAZIONE AUDIO & GRAFICA"
			dossier_desc.text = "Regolazione canali mixer audio Master, Colonna Sonora (Music) e Ritorno Sonoro Armamenti (SFX).\n\nConfigurazione display, risoluzione d'aggiornamento e sincronizzazione verticale (V-Sync) per la massima fluidità di puntamento."
			dossier_telemetry.text = "BUS AUDIO: 3 ATTIVI  •  SALVA CON INDIETRO / ESC"

		"quit":
			dossier_tag.text = "// TAC-OPS DISENGAGEMENT"
			threat_badge.text = "TERMINATE"
			threat_badge.modulate = Color(0.9, 0.25, 0.25)
			dossier_title.text = "DISCONNESSIONE E USCITA"
			dossier_subtitle.text = "INTERRUZIONE TELEMETRIA // CHIUSURA TERMINALE"
			dossier_desc.text = "Chiude la sessione avionica del velivolo e termina l'esecuzione dell'ambiente simulato.\n\nI dati di configurazione correnti e le impostazioni audio rimangono salvati per la prossima missione."
			dossier_telemetry.text = "SISTEMA: STANDBY  •  PROTOCOLLO: SHUTDOWN SAFE"

		"map_alps":
			dossier_tag.text = "// THEATER INTEL: GARDA"
			threat_badge.text = "THREAT: HIGH"
			threat_badge.modulate = Color(1.0, 0.3, 0.2)
			dossier_title.text = "SETTORE 01: GARDA"
			dossier_subtitle.text = "QUATTRO BANDIT // DUE GREGARI"
			dossier_desc.text = "Intercetta i caccia ostili con il supporto dei gregari. Scegli fra missili standard, veloci, pesanti, incendiari e multi-bersaglio.\n\nIn volo: Q / D-Pad su cambia slot; TAB / Y cambia bersaglio; SPAZIO / A lancia. ESC / START apre il menu di pausa."
			dossier_telemetry.text = "SETTORE: GARDA  •  SORTITA: DOGFIGHT  •  PAYLOAD: DUE SLOT"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if storia_menu.visible:
			_on_storia_back_pressed()
			get_viewport().set_input_as_handled()
		elif options_menu.visible:
			_on_options_back_pressed()
			get_viewport().set_input_as_handled()
		else:
			_on_quit_pressed()
			get_viewport().set_input_as_handled()
	elif get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
				or event.is_action_pressed("ui_accept"):
			if storia_menu.visible:
				alps_btn.grab_focus()
			elif options_menu.visible:
				master_slider.grab_focus()
			else:
				storia_btn.grab_focus()
			get_viewport().set_input_as_handled()


func _play_sfx() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr != null and audio_mgr.has_method("play_weapon_switch"):
		audio_mgr.play_weapon_switch()
