extends SceneTree
## godot --headless --path . --script tests/menu_flow_check.gd
## Omit --headless for screenshots in user://menu_port_check (uses the real Garda levels).

const Session = preload("res://scripts/ui/game_session.gd")
const Settings = preload("res://scripts/ui/settings_manager.gd")
const Catalog = preload("res://scripts/weapons/missile_catalog.gd")
var launched: Array = []
var started := Time.get_ticks_msec()


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 180000:
		push_error("Menu flow check timed out")
		quit(1)
	return false


func _run() -> void:
	assert(_check_settings())
	assert(ProjectSettings.get_setting("application/run/main_scene") == Session.MAIN_MENU)
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		assert(InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadMotion))
	Session.menu_section = ""
	assert(Session.change_scene(self, Session.MAIN_MENU) == OK)
	await scene_changed
	var menu = current_scene
	assert(menu.root_menu.visible and menu.storia_btn.has_focus())
	assert(menu.dossier_subtitle.text.contains("TUTORIAL") and menu.dossier_desc.text.contains("tre gruppi"))
	await _capture("01_main")
	menu.options_btn.pressed.emit()
	assert(menu.options_menu.visible and menu.master_slider.has_focus())
	await _capture("02_options")
	# Settings persistence is checked against an isolated file, not the user's settings.cfg.
	menu._show_root_menu()
	menu.storia_btn.pressed.emit()
	assert(menu.storia_menu.visible and menu.alps_btn.has_focus())
	await _capture("03_sorties")
	menu.alps_btn.pressed.emit()
	await scene_changed
	assert(current_scene.scene_file_path == Session.LOADOUT and not Session.free_flight)
	var loadout = current_scene
	assert(loadout._aircraft_step and loadout._aircraft_buttons.size() == Session.AircraftCatalog.ids().size())
	loadout._aircraft_buttons["fa_n26"].pressed.emit()
	assert(Session.selected_aircraft_id == "fa_n26")
	await _capture("04_aircraft")
	loadout.avvia_btn.pressed.emit()
	assert(not loadout._aircraft_step and loadout.slot1_btn.has_focus())
	assert(loadout._missile_buttons.size() == 5)
	assert(loadout.avvia_btn.text == "AVVIA MISSIONE" and loadout.map_label.text == "GARDA · TUTORIAL")
	for slot in 2:
		loadout._select_slot(slot)
		for id in Catalog.ids():
			loadout._missile_buttons[id].pressed.emit()
			assert(Session.selected_missiles[slot] == id)
			assert(loadout._speed_bar.value == Catalog.get_def(id).speed)
			assert(loadout.detail_label.text.contains(Catalog.full_name(id)))
	loadout._missile_button_list[0].grab_focus()
	loadout.slot1_btn.grab_focus()
	assert(loadout._active_slot == 0)
	loadout._on_pick("NCGBM")
	loadout.slot2_btn.grab_focus()
	assert(loadout._active_slot == 1)
	loadout._on_pick("MTSM")
	await _capture("04_loadout")
	loadout.back_btn.pressed.emit()
	assert(loadout._aircraft_step and loadout._aircraft_buttons["fa_n26"].has_focus())
	loadout.back_btn.pressed.emit()
	await scene_changed
	assert(current_scene.storia_menu.visible, "Back returns to sortie selection")
	current_scene.alps_btn.pressed.emit()
	await scene_changed
	assert(Session.selected_missiles == ["NCGBM", "MTSM"])
	assert(Session.selected_aircraft_id == "fa_n26")
	current_scene.avvia_btn.pressed.emit()
	current_scene.avvia_btn.pressed.emit()
	await scene_changed
	assert(current_scene.scene_file_path == Session.DOGFIGHT)
	var player: PlayerFlight = current_scene.get_node("Player")
	assert(player.get_node("AircraftModel").scene_file_path == "res://scenes/aircraft/fa_n26.tscn")
	var weapons: WeaponController = player.get_node("WeaponController")
	var hud: CombatHUD = current_scene.get_node("CombatHUD")
	assert(weapons.equipped_missile_ids == ["NCGBM", "MTSM"])
	assert(not Session.free_flight and hud.mission_controller.remaining == 0)
	assert(get_nodes_in_group("targets").is_empty())
	hud._open_pause_menu()
	assert(paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	var position := player.position
	await process_frame
	assert(player.position == position)
	await _capture("05_pause")
	hud._on_resume_pressed()
	assert(not paused)
	assert(DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_HIDDEN)
	# The second encounter supplies four real targets for the existing multi-lock checks.
	await _advance_to_encounter(hud, 1)
	paused = true
	assert(_check_weapons(player, weapons))
	weapons.equipped_missile_ids = Session.selected_missiles.duplicate()
	weapons.reset_loadout()
	weapons.cycle_missile_type()
	hud._update_labels()
	assert(weapons.equipped_missile_id == "MTSM" and weapons.get_secondary_missile_id() == "NCGBM")
	await _capture("06_flight")
	for target in get_nodes_in_group("targets"):
		target.apply_damage(target.max_health)
	assert(not hud.mission_result_visible(), "Clearing an intermediate encounter is not victory")
	paused = false
	await _advance_to_encounter(hud, 2)
	for target in get_nodes_in_group("targets"):
		target.apply_damage(target.max_health)
	assert(not hud.mission_result_visible(), "Final radio precedes victory")
	for frame in 300:
		if hud.mission_result_visible():
			break
		hud.mission_controller.radio._process(30.0)
		await process_frame
	assert(paused and hud.mission_result_visible())
	assert(hud._mission_title.text == "MISSIONE COMPLETATA")
	await _capture("07_victory")
	hud._open_pause_menu()
	assert(hud._resume_button.disabled and hud._restart_button.has_focus())
	hud._on_restart_pressed()
	await scene_changed
	hud = current_scene.get_node("CombatHUD")
	assert(not paused and not hud.mission_result_visible())
	assert(hud.mission_controller.remaining == 0 and get_nodes_in_group("targets").is_empty())
	assert(current_scene.get_node("Player/WeaponController").equipped_missile_ids == Session.selected_missiles)
	assert(current_scene.get_node("Player/AircraftModel").scene_file_path == "res://scenes/aircraft/fa_n26.tscn")
	current_scene.get_node("Player").apply_damage(1000.0)
	assert(paused and hud._mission_title.text == "MISSIONE FALLITA")
	await _capture("08_defeat")
	hud._open_pause_menu()
	hud._on_loadout_pressed()
	await scene_changed
	assert(not paused and current_scene.scene_file_path == Session.LOADOUT)
	current_scene.back_btn.pressed.emit()
	await scene_changed
	current_scene._show_root_menu()
	current_scene.free_flight_btn.pressed.emit()
	await scene_changed
	assert(Session.free_flight and Session.selected_map == Session.FREE_FLIGHT)
	current_scene._aircraft_buttons["fighter"].pressed.emit()
	current_scene.avvia_btn.pressed.emit()
	current_scene.avvia_btn.pressed.emit()
	await scene_changed
	assert(current_scene.scene_file_path == Session.FREE_FLIGHT and get_nodes_in_group("targets").is_empty())
	assert(current_scene.get_node("Player/AircraftModel").scene_file_path == "res://assets/aircraft/aircraft_game_ready.glb")
	hud = current_scene.get_node("CombatHUD")
	hud._open_pause_menu()
	await _capture("09_free_flight_pause")
	hud._on_main_menu_pressed()
	await scene_changed
	assert(not paused and current_scene.root_menu.visible and Session.menu_section.is_empty())
	assert(not root.get_node("AudioManager")._alarm_active)
	print("Menu flow check passed: aircraft selection and persistence, options, focus, all 5 missiles, 2 slots, real level launches, pause, victory/defeat, restart, loadout and return")
	quit()


func _advance_to_encounter(hud: CombatHUD, index: int) -> void:
	var mission: TutorialMission = hud.mission_controller
	for frame in 300:
		mission.player.set_physics_process(false)
		for aircraft in get_nodes_in_group("combat_ai"):
			aircraft.set_physics_process(false)
		if mission.encounter_index == index and mission.remaining > 0:
			return
		for target in mission.active_enemies.duplicate():
			target.apply_damage(target.health)
		mission.radio._process(30.0)
		await process_frame
	assert(false, "Tutorial encounter did not arrive through its radio sequence")


func _check_weapons(player: PlayerFlight, weapons: WeaponController) -> bool:
	var targeting: TargetLock = player.get_node("TargetLock")
	var targets := get_nodes_in_group("targets").filter(CombatDirector.alive)
	for i in targets.size():
		targets[i].global_position = player.global_position + Vector3(i * 80.0, 0, -1200)
	targeting._set_target(targets[0])
	targeting.is_locked = true
	weapons.missile_launched.connect(func(missile): launched.append(missile))
	for id in Catalog.ids():
		launched.clear()
		weapons.equip_missile(id, 0)
		weapons.reset_loadout()
		weapons.fire_missile()
		var def := Catalog.get_def(id)
		var salvo: int = int(def.get("salvo_size", 1))
		assert(launched.size() == salvo, "Each variant must actually launch")
		assert(weapons.missile_ammo == int(def.ammo) - salvo)
		for missile in launched:
			assert(missile.missile_id == id and missile.damage == def.damage and missile.speed == def.speed)
			if id == "MTSM":
				assert(missile._payload_targets.size() == 4)
				missile._release_payload()
		if id == "MTSM":
			assert(get_nodes_in_group("mission_projectiles").filter(func(n): return not n.is_queued_for_deletion()).size() == 8)
		for projectile in get_nodes_in_group("mission_projectiles"):
			projectile.free()
	# The incendiary missile now burns airframes over time rather than using instant fallback damage.
	for aircraft in [player, targets[0]]:
		aircraft.health = 100.0
		aircraft.apply_napalm(75.0, 10.0)
		assert(aircraft.health == 100.0)
		aircraft._process(4.0)
		assert(is_equal_approx(aircraft.health, 70.0))
		aircraft._process(8.0)
		assert(is_equal_approx(aircraft.health, 25.0), "Burn must not overshoot its duration")
		aircraft.reset_player()
		assert(aircraft._napalm_time == 0.0)
	return true


func _check_settings() -> bool:
	var path := "user://menu_settings_check_%d.cfg" % OS.get_process_id()
	var settings := Settings.load_settings(path)
	settings.master_volume = 0.35
	settings.music_volume = 0.45
	settings.sfx_volume = 0.55
	assert(Settings.save_settings(settings, path) == OK)
	assert(Settings.load_settings(path) == settings)
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", "invalid")
	config.set_value("audio", "music_volume", -20.0)
	config.set_value("display", "fullscreen", "invalid")
	assert(config.save(path) == OK)
	var sanitized := Settings.load_settings(path)
	assert(sanitized.master_volume == 1.0 and sanitized.music_volume == 0.0 and not sanitized.fullscreen)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true


func _capture(stem: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "user://menu_port_check"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	assert(root.get_texture().get_image().save_png(directory.path_join(stem + ".png")) == OK)
