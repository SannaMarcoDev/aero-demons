extends CanvasLayer

const Session = preload("res://scripts/ui/game_session.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const Bindings = preload("res://scripts/ui/controller_bindings.gd")

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
@onready var options_panel: OptionsPanel = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/OptionsPanel
@onready var options_back_btn: Button = $MarginContainer/MainLayout/ContentArea/LeftPanel/MenuContainer/OptionsMenu/OptionsBackButton
var master_slider: HSlider

# Dossier / Intel Panel
@onready var dossier_tag: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/HeaderRow/DossierTag
@onready var threat_badge: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/HeaderRow/ThreatBadge
@onready var dossier_title: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/DossierTitle
@onready var dossier_subtitle: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/DossierSubtitle
@onready var dossier_desc: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/DossierDesc
@onready var dossier_telemetry: Label = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/TelemetryFooter/TelemetryLabel
@onready var radar_widget: Control = $MarginContainer/MainLayout/ContentArea/RightPanel/Margin/VBox/RadarContainer/TacticalRadarWidget
@onready var section_header: Label = $MarginContainer/MainLayout/ContentArea/LeftPanel/SectionHeader

@onready var hangar_camera = $AircraftViewportContainer/SubViewport/MenuAircraftStage/Camera3D
@onready var menu_ui: Control = $MarginContainer
@onready var vignette: ColorRect = $TacticalVignette

var _transitioning := false
var _focused_mode: String = "storia"


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	master_slider = options_panel.master_slider
	_wire_signals()
	options_panel.link_back_button(options_back_btn)
	options_panel.get_node("ControllerRemap").bindings_saved.connect(func(_profile): _refresh_prompts())
	var returning_section: String = Session.menu_section
	if returning_section == "sorties":
		hangar_camera.set_view(1.0)
		_show_storia_menu()
	else:
		_show_root_menu()
	_refresh_prompts()
	if not returning_section.is_empty():
		_transitioning = true
		menu_ui.modulate.a = 0.0
		menu_ui.scale = Vector2(0.985, 0.985)
		vignette.modulate.a = 0.0
		if returning_section == "free_flight":
			hangar_camera.set_view(1.0)
			await hangar_camera.travel_to(false).finished
			free_flight_btn.grab_focus()
		await hangar_camera.fade_ui(menu_ui, true, vignette).finished
		_transitioning = false


func _refresh_prompts() -> void:
	$MarginContainer/MainLayout/FooterBar/NavHints.text = Bindings.menu_hint()
	_set_dossier(_focused_mode)


func _process(_delta: float) -> void:
	if is_instance_valid(radar_widget) and radar_widget.is_visible_in_tree():
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
	if _transitioning:
		return
	_transitioning = true
	_play_sfx()
	await hangar_camera.fade_ui(menu_ui, false, vignette).finished
	await hangar_camera.travel_to(true).finished
	_show_storia_menu()
	await hangar_camera.fade_ui(menu_ui, true, vignette).finished
	_transitioning = false


func _show_storia_menu() -> void:
	Session.menu_section = "sorties"
	root_menu.visible = false
	options_menu.visible = false
	storia_menu.visible = true
	section_header.text = "// SELECT SORTIE SECTOR"
	alps_btn.grab_focus()
	_set_dossier("map_alps")


func _on_free_flight_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	_play_sfx()
	await hangar_camera.fade_ui(menu_ui, false, vignette).finished
	await hangar_camera.travel_to(true).finished
	Session.free_flight = true
	Session.menu_section = "free_flight"
	Session.selected_map = Session.FREE_FLIGHT
	await _open_loadout()


func _on_options_pressed() -> void:
	if _transitioning:
		return
	_play_sfx()
	root_menu.visible = false
	storia_menu.visible = false
	options_menu.visible = true
	section_header.text = "// AVIONICS CONFIGURATION"
	options_panel.grab_first_focus()
	_set_dossier("options")


func _on_quit_pressed() -> void:
	if _transitioning:
		return
	_play_sfx()
	get_tree().quit()


func _on_storia_back_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	_play_sfx()
	await hangar_camera.fade_ui(menu_ui, false, vignette).finished
	await hangar_camera.travel_to(false).finished
	_show_root_menu()
	await hangar_camera.fade_ui(menu_ui, true, vignette).finished
	_transitioning = false


func _on_options_back_pressed() -> void:
	_play_sfx()
	var error := options_panel.save()
	if error != OK:
		dossier_desc.text = "Impossibile salvare le impostazioni: %s" % error_string(error)
		return
	_show_root_menu()
	options_btn.grab_focus()


func _select_storia_map(map_path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	_play_sfx()
	await hangar_camera.fade_ui(menu_ui, false, vignette).finished
	Session.free_flight = false
	Session.selected_map = map_path
	await _open_loadout()


func _open_loadout() -> void:
	if Session.change_scene(get_tree(), Session.LOADOUT) != OK:
		dossier_desc.text = "Impossibile aprire la selezione aereo e armamento."
		$MarginContainer/MainLayout/ContentArea/RightPanel.show()
		await hangar_camera.fade_ui(menu_ui, true, vignette).finished
		_transitioning = false


func _set_dossier(mode_key: String) -> void:
	_focused_mode = mode_key
	var intel_panel: Control = $MarginContainer/MainLayout/ContentArea/RightPanel
	intel_panel.visible = not root_menu.visible
	intel_panel.size_flags_vertical = Control.SIZE_FILL if options_menu.visible else Control.SIZE_SHRINK_END
	radar_widget.get_parent().visible = options_menu.visible
	if radar_widget != null and is_instance_valid(radar_widget) and radar_widget.has_method("set_mode"):
		radar_widget.call("set_mode", mode_key)

	match mode_key:
		"storia":
			dossier_tag.text = "// OPERATION THEATER DEPLOYMENT"
			threat_badge.text = "THREAT: HIGH"
			threat_badge.modulate = Color(1.0, 0.4, 0.2)
			dossier_title.text = "OPERAZIONI AEREE"
			dossier_subtitle.text = "TUTORIAL SUL GARDA // PREPARA LA MISSIONE"
			dossier_desc.text = "Configura i due slot missili del caccia predefinito. Il collaudo dell'aereo appena riparato inizia già in volo sul Garda, con due gregari invulnerabili.\n\nProva movimento e velocità durante il collaudo iniziale. Al punto di contatto trovi le spiegazioni di targeting e armi, poi affronti tre gruppi di caccia nemici: 2, poi 4, infine 8."
			dossier_telemetry.text = "STATO: AUTORIZZATO  •  PAYLOAD: ARMATO  •  RADAR: ATTIVO  •  DATALINK: CONNESSO"

		"free_flight":
			dossier_tag.text = "// RECONNAISSANCE & FLIGHT CALIBRATION"
			threat_badge.text = "THREAT: ZERO"
			threat_badge.modulate = Color(0.2, 0.95, 0.4)
			dossier_title.text = "VOLO LIBERO (FREE FLIGHT)"
			dossier_subtitle.text = "SETTORE: GARDA // NESSUN NEMICO RILEVATO"
			dossier_desc.text = "Configura i due slot missili del caccia predefinito e decolla sopra il Garda. Nessun nemico, nessuna ondata e nessun timer di missione.\n\nProva i comandi di volo oppure esplora liberamente lo scenario. High-G e spin dash non sono disponibili nella build interna. I confini di volo rimangono attivi."
			dossier_telemetry.text = "SETTORE: GARDA  •  MODALITA': ESPLORAZIONE  •  PAYLOAD: CONFIGURABILE"

		"options":
			dossier_tag.text = "// AVIONICS & SYSTEM TELEMETRY"
			threat_badge.text = "SYSTEM: READY"
			threat_badge.modulate = Color(0.2, 0.75, 1.0)
			dossier_title.text = "CONFIGURAZIONE SISTEMI"
			dossier_subtitle.text = "PARAMETRI AVIONICI // CALIBRAZIONE AUDIO & GRAFICA"
			dossier_desc.text = "Preset qualità rapidi (Basso→Ultra) oppure controllo fine su nuvole volumetriche (fino a spegnerle), cielo, ombre, effetti post, tonemap, upscaler FSR 1.0/2.2, scala di rendering con supersampling, anti-aliasing, V-Sync e limite FPS.\n\nMixer audio, risoluzione e controlli di volo in coda alla lista. Salvataggio automatico all'uscita."
			dossier_telemetry.text = "BUS AUDIO: 3 ATTIVI  •  SALVA CON INDIETRO [%s]" % Bindings.action_label("ui_cancel")

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
			dossier_subtitle.text = "COLLAUDO PROTETTO // DUE GREGARI"
			dossier_desc.text = "Ascolta la radio e prova i comandi di volo. Al punto di contatto, tre box spiegano targeting, missili e mitragliatrice mettendo in pausa il gioco.\n\nPoi affronta liberamente le ondate da 2, 4 e 8 caccia, senza esercizi obbligatori o altre interruzioni tutorial.\n[%s] Conferma · [%s] Pausa / opzioni" % [Bindings.action_label("ui_accept"), Bindings.action_label("pause_menu")]
			dossier_telemetry.text = "SETTORE: GARDA  •  MISSIONE: TUTORIAL  •  MISSILI: DUE SLOT"


func _input(_event: InputEvent) -> void:
	if _transitioning:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return
	if event.is_action_pressed("ui_cancel"):
		if storia_menu.visible:
			_on_storia_back_pressed()
			get_viewport().set_input_as_handled()
		elif options_menu.visible:
			_on_options_back_pressed()
			get_viewport().set_input_as_handled()
		else:
			# Back at the root selects Exit; only an explicit confirmation quits.
			quit_btn.grab_focus()
			get_viewport().set_input_as_handled()
	elif get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
				or event.is_action_pressed("ui_accept"):
			if storia_menu.visible:
				alps_btn.grab_focus()
			elif options_menu.visible:
				options_panel.grab_first_focus()
			else:
				storia_btn.grab_focus()
			get_viewport().set_input_as_handled()


func _play_sfx() -> void:
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr != null and audio_mgr.has_method("play_weapon_switch"):
		audio_mgr.play_weapon_switch()
