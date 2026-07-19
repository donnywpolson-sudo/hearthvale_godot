extends "res://scripts/hud.gd"

func run_audio_feedback_smoke() -> bool:
	if not audio_assets_loaded() or effect_player == null:
		return false
	var cue_cases := {
		"Quest complete: Starter path": "quest_complete",
		"Woodcutting level 2": "level_up",
		"Hit Rat 1 dmg": "combat_hit",
		"You missed the target": "combat_miss",
		"Bought Trail ration for 3 coins": "coin_jingle",
		"Crafted Training bow -> 1 Training bow": "craft_shimmer",
		"Tree: +1 Logs; +28 Woodcutting XP": "gather_thud",
	}
	for message in cue_cases.keys():
		var expected_cue := str(cue_cases[message])
		if _feedback_cue(str(message)) != expected_cue:
			push_error("Audio feedback smoke failed: message mapped to the wrong cue")
			return false
		set_feedback(str(message))
		if effect_player.playing:
			push_error("Audio feedback smoke failed: action feedback audio is enabled")
			return false
	var skills_button = tab_buttons.get("skills")
	if not (skills_button is BaseButton):
		return false
	skills_button.pressed.emit()
	return not effect_player.playing


func run_ui_state_smoke() -> bool:
	if current_state.is_empty():
		return false
	if not audio_assets_loaded():
		push_error("UI state smoke failed: declared audio assets did not load")
		return false
	for tab_id in ["inventory", "equipment", "skills", "quests", "state"]:
		select_tab(tab_id)
		if panel_body.get_child_count() == 0:
			return false
	select_tab("skills")
	var skill_ids := _panel_skill_ids_for_smoke()
	var magic_index := skill_ids.find("magic")
	var woodcutting_index := skill_ids.find("woodcutting")
	if skill_ids.is_empty() or skill_ids[0] != "attack" or magic_index == -1 or woodcutting_index == -1 or magic_index > woodcutting_index:
		return false
	if not _panel_contains_skill_icon("attack") or not _panel_contains_skill_icon("hitpoints"):
		return false
	var carpentry_snapshot = current_state.get("skills", {}).get("carpentry", {}).duplicate(true)
	var specialization_snapshot := str(current_state.get("carpentry_specialization", ""))
	current_state["skills"]["carpentry"] = {"level": 40, "xp": 0}
	current_state["carpentry_specialization"] = ""
	select_tab("skills")
	if not _panel_contains_text("Weaponwright") or not _panel_contains_text("Fieldwright"):
		return false
	var selected_specializations: Array[String] = []
	var specialization_callable := func(choice: String) -> void: selected_specializations.append(choice)
	carpentry_specialization_requested.connect(specialization_callable)
	var weaponwright_button := _panel_button_for_smoke("Weaponwright\nTool-handle recovery")
	if weaponwright_button == null:
		carpentry_specialization_requested.disconnect(specialization_callable)
		return false
	weaponwright_button.pressed.emit()
	carpentry_specialization_requested.disconnect(specialization_callable)
	if selected_specializations != ["weaponwright"]:
		return false
	current_state["carpentry_specialization"] = "weaponwright"
	select_tab("skills")
	if not _panel_contains_text("Weaponwright") or _panel_contains_text("Fieldwright"):
		return false
	current_state["skills"]["carpentry"] = carpentry_snapshot
	current_state["carpentry_specialization"] = specialization_snapshot
	_refresh_state_panel()
	select_tab("quests")
	if not _panel_contains_button("Starter path") or not _panel_contains_button("Trail supplies"):
		push_error("UI state smoke failed: quest panel did not render Starter path and Trail supplies")
		return false
	var quest_state_snapshot = current_state.get("quest_state", {}).duplicate(true)
	current_state["quest_state"] = {
		"active_quest_id": "starter_path",
		"quests": {
			"starter_path": {"quest_id": "starter_path", "started": true, "completed": false, "flags": []},
			"road_patrol": {"quest_id": "road_patrol", "started": true, "completed": false, "flags": []},
		},
	}
	select_tab("quests")
	if not _panel_contains_button("Track") or not _panel_contains_text("Reward:"):
		push_error("UI state smoke failed: quest panel did not render Track and reward preview")
		return false
	if not _panel_contains_text("Active") or not _panel_contains_text("Started") or not _panel_contains_text("Available"):
		push_error("UI state smoke failed: quest panel did not render Active, Started, and Available states")
		return false
	var selected_routes: Array[String] = []
	var route_callable := func(quest_id: String) -> void: selected_routes.append(quest_id)
	quest_route_select_requested.connect(route_callable)
	var track_button := _panel_button_for_smoke("Track")
	if track_button == null:
		quest_route_select_requested.disconnect(route_callable)
		push_error("UI state smoke failed: Track button could not be found")
		return false
	track_button.pressed.emit()
	quest_route_select_requested.disconnect(route_callable)
	current_state["quest_state"]["quests"]["road_patrol"]["flags"] = ["used_shop", "equipped_weapon", "defeated_enemy", "used_bank"]
	select_tab("quests")
	if not _panel_contains_text("Ready to return"):
		push_error("UI state smoke failed: quest panel did not render Ready to return")
		return false
	current_state["quest_state"]["quests"]["road_patrol"]["completed"] = true
	select_tab("quests")
	if not _panel_contains_text("Complete"):
		push_error("UI state smoke failed: quest panel did not render Complete")
		return false
	current_state["quest_state"] = quest_state_snapshot
	_refresh_state_panel()
	if selected_routes.size() != 1 or selected_routes[0] != "road_patrol":
		push_error("UI state smoke failed: Track button emitted routes %s" % str(selected_routes))
		return false
	if _item_icon_texture("logs") == null:
		return false
	if not _item_tooltip("logs", 3).contains("Category: wood"):
		return false
	show_item_action_panel("logs")
	if interaction_title.text != "Logs" or interaction_body.get_child_count() == 0 or not _interaction_contains_button("Drop 1"):
		return false
	hide_interaction_panel()
	set_hover_target("Tree (Woodcutting)")
	if not hover_hint_is_visible() or hover_hint_text() != "Tree (Woodcutting)":
		return false
	set_hover_target("")
	if hover_hint_is_visible():
		return false
	configure_minimap({"width": 100, "height": 100, "dirt_tiles": [[15, 15]], "water_tiles": [], "blocked_tiles": [], "objects": [{"tile": [16, 15], "type": "resource", "label": "Tree"}]})
	set_minimap_player_tile(Vector2i(15, 15))
	set_minimap_heading(42.0)
	if not minimap_has_data_for_smoke() or minimap_player_tile_for_smoke() != Vector2i(15, 15) or absf(minimap_heading_for_smoke() - 42.0) > 0.1 or not minimap_player_is_centered_for_smoke():
		return false
	var snapshot := current_state.duplicate(true)
	current_state["equipment"] = {"weapon": "bronze_sword"}
	select_tab("equipment")
	var bronze_sword_name := _item_name("bronze_sword")
	var equipment_panel_ok := panel_title.text == "Equipment" and _panel_contains_button(bronze_sword_name)
	show_equipment_action_panel("weapon")
	var equipment_action_ok := interaction_title.text == "Weapon: %s" % bronze_sword_name and _interaction_contains_button("Unequip") and _item_tooltip("bronze_sword").contains("Attack +1")
	current_state.clear()
	for key in snapshot.keys():
		current_state[key] = snapshot[key]
	if not equipment_panel_ok or not equipment_action_ok:
		return false
	hide_interaction_panel()
	select_tab("inventory")
	return account_label.text.contains(str(current_state.get("username", ""))) and panel_title.text == "Inventory"


func run_interaction_panel_smoke() -> bool:
	if current_state.is_empty():
		return false
	show_bank_panel()
	if interaction_title.text != "Bank" or interaction_body.get_child_count() == 0:
		return false
	show_shop_panel({"name": "General Store", "stock": [{"item_id": "trail_ration", "price": 3}]})
	if interaction_title.text != "General Store" or interaction_body.get_child_count() == 0:
		return false
	show_dialogue_panel({"name": "Guide", "quest_id": "starter_path"}, {"display_name": "Starter path"}, {}, "Guide: Welcome.", "Start")
	if interaction_title.text != "Guide" or interaction_body.get_child_count() == 0:
		return false
	hide_interaction_panel()
	return not interaction_panel.visible
