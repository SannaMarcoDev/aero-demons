extends SceneTree
## godot --headless --path . --script tests/controller_ui_flow_check.gd
## Real scenes and native joypad events; no writes to the player's settings.
## A temporary profile is injected after scene loads (OptionsPanel reads the
## production config on ready). Backend restart persistence has its own check.
const Session = preload("res://scripts/ui/game_session.gd")
const Bindings = preload("res://scripts/ui/controller_bindings.gd")
const Settings = preload("res://scripts/ui/settings_manager.gd")
class FailingOptions extends OptionsPanel:
	func save() -> Error:
		return ERR_CANT_OPEN

var profile: Dictionary
var path := "user://controller_ui_check_%d.cfg" % OS.get_process_id()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("AudioManager")._music_player.stop()
	root.get_node("AudioManager")._music_player.stream = null
	assert(not FileAccess.file_exists(path))
	var personal := FileAccess.get_file_as_bytes(Settings.CONFIG_PATH) if FileAccess.file_exists(Settings.CONFIG_PATH) else PackedByteArray()
	var custom := Bindings.defaults()
	custom.ui_accept.events = [{"button": JOY_BUTTON_X}]
	custom.ui_cancel.events = [{"button": JOY_BUTTON_Y}]
	custom.fire_gun.events = [{"button": JOY_BUTTON_B}]
	custom.fire_missile.events = [{"button": JOY_BUTTON_A}]
	custom.cycle_target.events = [{"button": JOY_BUTTON_BACK}]
	custom.switch_missile.events = [{"button": JOY_BUTTON_DPAD_DOWN}]
	# Allowed across contexts: result-confirm must win over the flight pause action.
	custom.pause_menu.events = [{"button": JOY_BUTTON_X}]
	assert(not Bindings.validated(custom).is_empty())
	for candidate in [Bindings.defaults(), custom]:
		profile = candidate
		Session.menu_section = ""
		assert(Session.change_scene(self, Session.MAIN_MENU) == OK)
		await scene_changed
		var menu = current_scene
		_apply_profile(menu.options_panel)
		assert(not menu.options_panel.dirty, "Opening options must not dirty/write the real config")
		assert(menu.get_node("MarginContainer/MainLayout/FooterBar/NavHints").text.contains(Bindings.action_label("ui_accept")))
		# Back at root selects Exit, never closes the process accidentally.
		await _tap("ui_cancel")
		assert(menu.quit_btn.has_focus())
		await _tap("ui_up")
		assert(menu.options_btn.has_focus())
		await _tap("ui_accept")
		assert(menu.options_menu.visible)
		var remap_button: Button = menu.options_panel.get_node("RemapButton")
		assert(remap_button.has_focus())
		await _tap("ui_up")
		assert(menu.options_back_btn.has_focus(), "Options wrap to Back")
		await _tap("ui_up")
		assert(menu.options_panel.sens_slider.has_focus(), "Last scroll control remains reachable")
		assert(menu.options_panel.sens_slider.get_parent().modulate != Color.WHITE, "Focused slider row must stand out")
		assert(menu.options_panel.get_node("Scroll").scroll_vertical > 0)
		await _tap("ui_cancel")
		assert(menu.root_menu.visible and menu.options_btn.has_focus())
		await _tap("ui_up")
		assert(menu.free_flight_btn.has_focus())
		await _tap("ui_accept")
		await _scene(Session.LOADOUT)
		var loadout = current_scene
		assert(loadout._aircraft_buttons[Session.AircraftCatalog.DEFAULT_ID].has_focus())
		assert(loadout.get_node("Main/LeftPanel/VBox/Hint").text == Bindings.menu_hint())
		# Return to the originating free-flight button, then re-enter.
		await _tap("ui_cancel")
		await _scene(Session.MAIN_MENU)
		menu = current_scene
		_apply_profile(menu.options_panel)
		assert(menu.free_flight_btn.has_focus())
		await _tap("ui_accept")
		await _scene(Session.LOADOUT)
		loadout = current_scene
		await _tap("ui_down")
		assert(loadout.avvia_btn.has_focus())
		await _tap("ui_accept")
		assert(not loadout._aircraft_step and loadout.slot1_btn.has_focus())
		await _tap("ui_right")
		assert(loadout.slot2_btn.has_focus())
		await _tap("ui_down")
		await _tap("ui_down")
		await _tap("ui_accept")
		assert(loadout._selected_missiles[1] == "HSSTDM")
		await _tap("ui_up")
		await _tap("ui_up")
		await _tap("ui_up")
		assert(loadout.back_btn.has_focus())
		await _tap("ui_up")
		assert(loadout.avvia_btn.has_focus())
		await _tap("ui_accept")
		await _scene(Session.FREE_FLIGHT)
		var hud: CombatHUD = current_scene.get_node("CombatHUD")
		var player: PlayerFlight = current_scene.get_node("Player")
		_apply_profile(hud._options_panel)
		await _tap("pause_menu")
		assert(paused and hud._resume_button.has_focus())
		var position := player.position
		var ammo: int = player.get_node("WeaponController").gun_ammo
		await _send("fire_gun", true)
		await physics_frame
		await process_frame
		assert(player.position == position and not player.gun_trigger)
		assert(player.get_node("WeaponController").gun_ammo == ammo)
		await _send("fire_gun", false)
		await _tap("ui_down")
		await _tap("ui_down")
		assert(hud._options_button.has_focus())
		await _tap("ui_accept")
		assert(hud._pause_options.visible)
		await _tap("ui_accept")
		var remap: Window = hud._options_panel.get_node("ControllerRemap")
		await process_frame
		assert(remap.visible)
		await _tap("ui_accept")
		assert(remap._capture != null)
		await _tap("pause_menu")
		assert(remap._capture == null and paused and remap.visible)
		assert(not Bindings.validated(remap.draft).is_empty())
		# Discard the draft with the mapped Back button, then return to pause.
		await _tap("ui_cancel")
		assert(not remap.visible and paused)
		# A failed settings save leaves the panel and pause intact.
		var real_options := hud._options_panel
		var failing_options := FailingOptions.new()
		hud._options_panel = failing_options
		hud._on_options_back_pressed()
		assert(hud._pause_options.visible and paused)
		hud._options_panel = real_options
		failing_options.free()
		await _tap("ui_cancel")
		assert(hud._pause_panel.visible and hud._options_button.has_focus())
		assert(hud.get_node("HudText/PauseOverlay/Panel/Menu/Hint").text == Bindings.menu_hint())
		assert(Bindings.action_label("fire_gun") == Bindings.binding_label(profile.fire_gun.events[0]))
		assert(Bindings.action_label("pitch_up") == Bindings.binding_label(profile.pitch_up.events[0]))
		# A held gameplay input cannot leak through a resume request.
		await _send("fire_gun", true)
		hud._on_resume_pressed()
		assert(paused and hud._resume_pending)
		await _send("fire_gun", false)
		await process_frame
		assert(not paused and not hud._pause_overlay.visible)
		assert(not player.gun_trigger)
		# Signal simulation only: this does NOT certify a physical USB disconnect.
		await _send("fire_gun", true)
		Input.joy_connection_changed.emit(99, false)
		assert(paused and hud._disconnect_pause)
		assert(not Input.is_action_pressed("fire_gun") and not player.gun_trigger)
		await _send("fire_gun", false)
		Input.joy_connection_changed.emit(99, true)
		assert(paused and not hud._controller_missing)
		await _tap("ui_cancel")
		assert(paused, "Back must not bypass explicit confirmation after reconnect")
		await _tap("ui_accept")
		assert(not paused)
		# Result screen: Back opens the menu; closing it preserves the result pause.
		hud.show_mission_result("MISSIONE COMPLETATA", "CHECK")
		paused = true
		assert(hud._mission_detail.text.contains("[%s] RIPROVA" % Bindings.action_label("ui_accept")))
		await _tap("ui_cancel")
		assert(hud._pause_overlay.visible and hud._restart_button.has_focus())
		await _tap("ui_cancel")
		assert(paused and not hud._pause_overlay.visible)
		var old_scene := current_scene.get_instance_id()
		await _tap("ui_accept")
		await _replacement(old_scene)
		assert(not paused and current_scene.scene_file_path == Session.FREE_FLIGHT)
		hud = current_scene.get_node("CombatHUD")
		_apply_profile(hud._options_panel)
		await _tap("pause_menu")
		for i in 4:
			await _tap("ui_down")
		assert(root.gui_get_focus_owner().text == "MENU PRINCIPALE")
		await _tap("ui_accept")
		await _scene(Session.MAIN_MENU)
		assert(not paused and current_scene.storia_btn.has_focus())
		print("PASS: controller UI flow ", "custom" if candidate == custom else "defaults")
	assert((FileAccess.get_file_as_bytes(Settings.CONFIG_PATH) if FileAccess.file_exists(Settings.CONFIG_PATH) else PackedByteArray()) == personal)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	current_scene.queue_free()
	await process_frame
	print("PASS: controller UI flow complete; prompts, focus, pause, disconnect, result/retry; personal config unchanged")
	quit(0)


func _apply_profile(panel: OptionsPanel) -> void:
	var remap: Window = panel.get_node("ControllerRemap")
	remap.config_path = path
	remap.draft = profile.duplicate(true)
	# Exercise the production save + bindings_saved refresh, not a manual UI refresh.
	remap._save_profile()
	assert(Settings.load_settings(path).controls_bindings == profile)
	assert(panel.settings.controls_bindings == profile)


func _scene(expected: String) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while true:
		if is_instance_valid(current_scene) and current_scene.scene_file_path == expected:
			if current_scene.get("_transitioning") != true:
				return
		if Time.get_ticks_msec() >= deadline:
			break
		await process_frame
	assert(false, "Expected settled scene: " + expected)


func _replacement(previous: int) -> void:
	for frame in 300:
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != previous:
			return
		await process_frame
	assert(false, "Retry did not replace scene")


func _tap(action: String) -> void:
	await _send(action, true)
	await _send(action, false)


func _send(action: String, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 99
	var binding: Dictionary = profile[action].events[0]
	assert(binding.has("button"), "This flow check uses digital controller navigation")
	event.button_index = binding.button
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame
