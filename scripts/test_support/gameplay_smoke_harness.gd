extends "res://scripts/gameplay_core.gd"

func attack_mob_for_smoke(object_data: Dictionary) -> void:
	_attack_mob(object_data)


func pick_up_drop_for_smoke(object_data: Dictionary) -> void:
	_pick_up_drop(object_data)


func drop_inventory_item_for_smoke(item_id: String, quantity: int = 1) -> bool:
	return _drop_inventory_item(item_id, quantity)


func run_core_loop_smoke() -> bool:
	_ensure_state_shape()
	var before_logs := _inventory_count("logs")
	_gather_resource({
		"id": "tree_01",
		"label": "Tree",
		"skill_id": "woodcutting",
		"required_level": 1,
		"xp_reward": 28,
		"item_reward": "logs",
		"quantity_reward": 1,
		"tile": Vector2i(10, 11),
	})
	if _inventory_count("logs") <= before_logs:
		return false

	_process_recipe_type("carpentry")
	if _inventory_count("plain_plank") <= 0:
		return false

	state["inventory"]["copper_ore"] = int(state["inventory"].get("copper_ore", 0)) + 1
	state["inventory"]["tin_ore"] = int(state["inventory"].get("tin_ore", 0)) + 1
	_process_recipe_type("smelting")
	if _inventory_count("bronze_bar") <= 0:
		return false
	var before_swords := _inventory_count("bronze_sword")
	_process_recipe_type("smithing")
	if _inventory_count("bronze_sword") <= before_swords:
		return false

	state["inventory"]["raw_shrimp"] = int(state["inventory"].get("raw_shrimp", 0)) + 1
	_process_cooking()
	if _inventory_count("cooked_shrimp") <= 0:
		return false

	_attack_mob({
		"id": "rat_01",
		"label": "Rat",
		"level": 1,
		"hitpoints": 2,
		"drops": [{"item_id": "coins", "quantity": 5}],
		"tile": Vector2i(17, 16),
	})
	_attack_mob({
		"id": "rat_01",
		"label": "Rat",
		"level": 1,
		"hitpoints": 2,
		"drops": [{"item_id": "coins", "quantity": 5}],
		"tile": Vector2i(17, 16),
	})
	var combat_for_smoke = state.get("combat", {})
	var drops = combat_for_smoke.get("ground_items", []) if combat_for_smoke is Dictionary else []
	if not (drops is Array) or drops.is_empty():
		return false
	_pick_up_drop(drops[0])
	return _inventory_count("coins") >= 5 and _skill_xp("woodcutting") > 0 and _skill_xp("cooking") > 0 and _skill_xp("smithing") > 0 and _skill_xp("attack") > 0


func run_recipe_picker_smoke() -> bool:
	_ensure_state_shape()
	set_simulation_recipe_override("", "")
	if hud != null and hud.has_method("set_simulation_lightweight_mode"):
		hud.set_simulation_lightweight_mode(false)
	state["skills"] = {
		"cooking": {"level": 1, "xp": 0},
		"smithing": {"level": 1, "xp": 0},
		"carpentry": {"level": 1, "xp": 0},
		"herbalism": {"level": 1, "xp": 0},
	}
	state["inventory"] = {"plain_plank": 2, "plain_tool_handle": 1}
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	_process_station({"station_id": "carpentry_bench", "label": "Carpentry bench"})
	if _inventory_count("training_bow") != 0 or _inventory_count("plain_plank") != 2 or _inventory_count("plain_tool_handle") != 1:
		push_error("Recipe picker smoke: station crafted before selection")
		return false
	if hud == null or not bool(hud.call("interaction_panel_is_visible")) or str(hud.call("interaction_panel_title_text")) != "Carpentry bench":
		push_error("Recipe picker smoke: Carpentry picker did not open")
		return false
	if int(hud.call("interaction_panel_row_count")) < 2:
		push_error("Recipe picker smoke: Carpentry picker has too few rows")
		return false

	_handle_recipe_selected_requested("carpentry", "training_bow")
	if _inventory_count("training_bow") != 1 or _inventory_count("plain_plank") != 0 or _inventory_count("plain_tool_handle") != 0:
		push_error("Recipe picker smoke: selected Training bow did not craft")
		return false

	var carpentry_xp_before := _skill_xp("carpentry")
	_handle_recipe_selected_requested("carpentry", "starsteel_staff")
	if _inventory_count("starsteel_staff") != 0 or _skill_xp("carpentry") != carpentry_xp_before:
		push_error("Recipe picker smoke: locked recipe changed state")
		return false

	var station_cases := {
		"cooking_range": "Cooking range",
		"furnace": "Furnace",
		"anvil": "Anvil",
		"carpentry_bench": "Carpentry bench",
		"apothecary_table": "Apothecary table",
	}
	for station_id in station_cases.keys():
		_process_station({"station_id": str(station_id), "label": str(station_cases[station_id])})
		if str(hud.call("interaction_panel_title_text")) != str(station_cases[station_id]) or int(hud.call("interaction_panel_row_count")) < 1:
			push_error("Recipe picker smoke: station picker missing for %s" % str(station_id))
			return false

	state["inventory"] = {"raw_shrimp": 1}
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	_handle_recipe_selected_requested("cooking", "raw_shrimp")
	if _inventory_count("raw_shrimp") != 0 or _inventory_count("cooked_shrimp") != 1:
		push_error("Recipe picker smoke: selected cooking recipe did not craft")
		return false

	if hud != null and hud.has_method("set_simulation_lightweight_mode"):
		hud.set_simulation_lightweight_mode(true)
	state["inventory"] = {"plain_plank": 1, "plain_tool_handle": 1, "charcoal": 1}
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	set_simulation_recipe_override("carpentry", "training_staff")
	_process_station({"station_id": "carpentry_bench", "label": "Carpentry bench"})
	set_simulation_recipe_override("", "")
	if hud != null and hud.has_method("set_simulation_lightweight_mode"):
		hud.set_simulation_lightweight_mode(false)
	if _inventory_count("training_staff") != 1:
		push_error("Recipe picker smoke: simulation override did not craft")
		return false
	return true


func run_economy_quest_smoke() -> bool:
	_ensure_state_shape()
	_add_inventory_item("coins", 100)
	_add_inventory_item("logs", 1)
	_add_inventory_item("bronze_sword", 1)
	var road_guard := {"quest_id": "road_patrol", "label": "Road Guard"}
	_talk_to_npc(road_guard)
	_handle_dialogue_action_requested(road_guard)
	if not _quest_started("road_patrol"):
		return false
	_open_shop({"stock": [{"item_id": "trail_ration", "price": 3}]})
	_handle_shop_buy_requested("trail_ration", 3)
	if not _quest_has_flag("road_patrol", "used_shop"):
		return false
	_equip_item("bronze_sword")
	if not _quest_has_flag("road_patrol", "equipped_weapon"):
		return false
	_record_quest_flag("defeated_enemy")
	_open_bank()
	_handle_bank_deposit_requested("logs", 1)
	if not _quest_has_flag("road_patrol", "used_bank"):
		return false
	var coins_before_reward := _inventory_count("coins")
	_talk_to_npc(road_guard)
	_handle_dialogue_action_requested(road_guard)
	return _quest_completed("road_patrol") and _inventory_count("coins") >= coins_before_reward + 24 and _skill_xp("attack") >= 20 and _bank().size() > 0


func run_progression_regression_smoke() -> bool:
	_ensure_state_shape()
	if not _assert_capacity_edges_for_smoke():
		push_error("Progression smoke failed: capacity edges")
		return false
	if not _assert_core_progression_path_for_smoke():
		push_error("Progression smoke failed: core progression path")
		return false
	if not _assert_inventory_item_actions_for_smoke():
		push_error("Progression smoke failed: inventory item actions")
		return false
	if not _assert_inventory_drop_for_smoke():
		push_error("Progression smoke failed: inventory drop")
		return false
	if not _assert_bank_round_trip_for_smoke():
		push_error("Progression smoke failed: bank round trip")
		return false
	if not _assert_shop_capacity_for_smoke():
		push_error("Progression smoke failed: shop capacity")
		return false
	if not _assert_quest_reward_capacity_for_smoke():
		push_error("Progression smoke failed: quest reward capacity")
		return false
	if not _assert_reward_transaction_edges_for_smoke():
		push_error("Progression smoke failed: reward transaction edges")
		return false
	if not _assert_bank_capacity_edges_for_smoke():
		push_error("Progression smoke failed: bank capacity edges")
		return false
	if not _assert_shop_affordability_for_smoke():
		push_error("Progression smoke failed: shop affordability")
		return false
	if not _assert_food_use_for_smoke():
		push_error("Progression smoke failed: food use")
		return false
	if not _assert_level_unlock_for_smoke():
		push_error("Progression smoke failed: level unlock")
		return false
	if not _assert_equipment_and_drop_paths_for_smoke():
		push_error("Progression smoke failed: equipment and drops")
		return false
	return true


func run_golden_scenarios_smoke() -> bool:
	_ensure_state_shape()
	if not _assert_golden_core_loop_for_smoke():
		push_error("Golden scenario smoke failed: core loop")
		return false
	if not _assert_golden_inventory_pressure_for_smoke():
		push_error("Golden scenario smoke failed: inventory pressure")
		return false
	if not _assert_golden_quest_reward_flow_for_smoke():
		push_error("Golden scenario smoke failed: quest reward flow")
		return false
	if not _assert_golden_combat_loot_recovery_for_smoke():
		push_error("Golden scenario smoke failed: combat loot recovery")
		return false
	if not _assert_golden_bank_shop_round_trip_for_smoke():
		push_error("Golden scenario smoke failed: bank/shop round trip")
		return false
	return _assert_state_invariants_for_smoke("golden scenarios final state")


func run_save_load_torture_smoke(store: Node, username: String) -> bool:
	_ensure_state_shape()
	if store == null:
		push_error("Save/load torture smoke failed: missing StateStore")
		return false
	if not _assert_torture_combat_status_for_smoke(store, "%s_combat" % username):
		push_error("Save/load torture smoke failed: combat/status")
		return false
	if not _assert_torture_quest_reward_for_smoke(store, "%s_quest" % username):
		push_error("Save/load torture smoke failed: quest reward blocking")
		return false
	if not _assert_torture_bank_shop_for_smoke(store, "%s_bank_shop" % username):
		push_error("Save/load torture smoke failed: bank/shop")
		return false
	if not _assert_torture_full_inventory_for_smoke(store, "%s_full_inventory" % username):
		push_error("Save/load torture smoke failed: full inventory")
		return false
	if not _assert_torture_resource_respawn_for_smoke(store, "%s_resource" % username):
		push_error("Save/load torture smoke failed: resource respawn")
		return false
	return _assert_state_invariants_for_smoke("save/load torture final state")


func run_timed_action_smoke() -> bool:
	_ensure_state_shape()
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"bronze_axe": 1, "logs": 2, "raw_shrimp": 2}
	state["skills"] = {}

	var tree := {
		"id": "timed_tree",
		"label": "Timed Tree",
		"skill_id": "woodcutting",
		"required_level": 1,
		"xp_reward": 28,
		"item_reward": "logs",
		"quantity_reward": 1,
		"secondary_item_reward": "sap_glob",
		"secondary_quantity_reward": 1,
		"secondary_drop_chance": 1.0,
		"base_gather_seconds": 2.0,
		"respawn_seconds": 5.0,
	}
	_gather_resource(tree)
	if _inventory_count("logs") != 3 or _inventory_count("sap_glob") != 1 or _skill_xp("woodcutting") != 28:
		return false
	if not _resource_is_depleted("timed_tree"):
		return false
	_gather_resource(tree)
	if _inventory_count("logs") != 3 or _skill_xp("woodcutting") != 28:
		return false
	_advance_action_clock(4.9)
	if not _resource_is_depleted("timed_tree"):
		return false
	_gather_resource(tree)
	if _inventory_count("logs") != 3 or _skill_xp("woodcutting") != 28:
		return false
	_advance_action_clock(0.2)
	_gather_resource(tree)
	if _inventory_count("logs") != 4 or _inventory_count("sap_glob") != 2 or _skill_xp("woodcutting") != 56:
		return false

	var dry_tree := tree.duplicate(true)
	dry_tree["id"] = "dry_tree"
	dry_tree["secondary_drop_chance"] = 0.0
	_advance_action_clock(2.0)
	var sap_before := _inventory_count("sap_glob")
	_gather_resource(dry_tree)
	if _inventory_count("sap_glob") != sap_before:
		return false

	_process_cooking()
	if _inventory_count("cooked_shrimp") != 1 or _inventory_count("raw_shrimp") != 1:
		return false
	_process_cooking()
	if _inventory_count("cooked_shrimp") != 1 or _inventory_count("raw_shrimp") != 1:
		return false
	_advance_action_clock(2.0)
	_process_cooking()
	if _inventory_count("cooked_shrimp") != 2 or _inventory_count("raw_shrimp") != 0:
		return false

	_process_recipe_type("carpentry")
	if _inventory_count("plain_plank") != 1 or _inventory_count("logs") != 4:
		return false
	_process_recipe_type("carpentry")
	if _inventory_count("plain_plank") != 1 or _inventory_count("logs") != 4:
		return false
	_advance_action_clock(1.6)
	_process_recipe_type("carpentry")
	return _inventory_count("plain_plank") == 2 and _inventory_count("logs") == 3


func run_skill_enrichment_smoke() -> bool:
	_ensure_state_shape()
	var original_skills_data := skills_data.duplicate(true)
	var thresholds = skills_data.get("woodcutting", {}).get("xp_thresholds", {})
	if not thresholds is Dictionary or not thresholds.has("40"):
		return false

	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"bronze_axe": 1}
	state["skills"] = {"woodcutting": {"level": 40, "xp": int(thresholds["40"])}}
	if not is_equal_approx(_skill_mastery_effect_total("woodcutting", "gather_bonus_yield_chance"), 0.20):
		return false
	skills_data["woodcutting"]["mastery_perks"][0]["effects"]["gather_bonus_yield_chance"] = 1.0
	_gather_resource({"id": "mastery_tree", "label": "Mastery tree", "skill_id": "woodcutting", "required_level": 1, "xp_reward": 28, "item_reward": "logs", "quantity_reward": 1, "secondary_item_reward": "sap_glob", "secondary_quantity_reward": 1, "secondary_drop_chance": 1.0})
	if _inventory_count("logs") != 2 or _inventory_count("sap_glob") != 1:
		return false

	skills_data = original_skills_data.duplicate(true)
	var carpentry_thresholds = skills_data.get("carpentry", {}).get("xp_thresholds", {})
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"logs": 1}
	state["skills"] = {"carpentry": {"level": 40, "xp": int(carpentry_thresholds["40"])}}
	skills_data["carpentry"]["mastery_perks"][1]["effects"]["processing_bonus_output_chance"] = 1.0
	_process_recipe_type("carpentry")
	if _inventory_count("plain_plank") != 2:
		return false
	var carpentry_xp := int(ceil(8.0 * (1.0 + _skill_mastery_effect_total("carpentry", "processing_xp_bonus_percent"))))
	if _skill_xp("carpentry") != int(carpentry_thresholds["40"]) + carpentry_xp:
		return false

	state["carpentry_specialization"] = ""
	state["skills"] = {"carpentry": {"level": 39, "xp": int(carpentry_thresholds["39"])}}
	_handle_carpentry_specialization_requested("weaponwright")
	if str(state.get("carpentry_specialization", "")) != "":
		push_error("Carpentry specialization unlocked below level 40")
		return false
	state["skills"] = {"carpentry": {"level": 40, "xp": int(carpentry_thresholds["40"])}}
	_handle_carpentry_specialization_requested("invalid")
	if str(state.get("carpentry_specialization", "")) != "":
		push_error("Invalid Carpentry specialization was accepted")
		return false
	_handle_carpentry_specialization_requested("weaponwright")
	if str(state.get("carpentry_specialization", "")) != "weaponwright":
		push_error("Weaponwright selection failed: %s" % str(state.get("carpentry_specialization", "")))
		return false
	_handle_carpentry_specialization_requested("fieldwright")
	if str(state.get("carpentry_specialization", "")) != "weaponwright":
		push_error("Carpentry specialization was changed after selection")
		return false

	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"plain_plank": 2, "plain_tool_handle": 1}
	set_simulation_recipe_override("carpentry", "training_bow")
	var weapon_success_millis := -1
	for millis in range(0, 10000):
		state["world"]["action_clock_seconds"] = float(millis) / 1000.0
		if _chance_succeeds("recipe:carpentry:training_bow:specialization", 0.15):
			weapon_success_millis = millis
			break
	if weapon_success_millis < 0:
		push_error("No deterministic Weaponwright success sample found")
		return false
	state["world"]["action_clock_seconds"] = float(weapon_success_millis) / 1000.0
	_process_recipe_type("carpentry")
	if _inventory_count("training_bow") != 1 or _inventory_count("plain_tool_handle") != 1:
		push_error("Weaponwright craft mismatch: bow=%d handle=%d feedback=%s" % [_inventory_count("training_bow"), _inventory_count("plain_tool_handle"), last_feedback_text])
		return false

	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"plain_plank": 2}
	set_simulation_recipe_override("carpentry", "storage_crate")
	_process_recipe_type("carpentry")
	if _inventory_count("storage_crate") != 1 or _inventory_count("plain_tool_handle") != 0:
		push_error("Weaponwright affected an unlisted utility recipe")
		return false

	state["carpentry_specialization"] = "fieldwright"
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"plain_plank": 2}
	var field_success_millis := -1
	for millis in range(0, 10000):
		state["world"]["action_clock_seconds"] = float(millis) / 1000.0
		if _chance_succeeds("recipe:carpentry:storage_crate:specialization", 0.15):
			field_success_millis = millis
			break
	if field_success_millis < 0:
		push_error("No deterministic Fieldwright success sample found")
		return false
	state["world"]["action_clock_seconds"] = float(field_success_millis) / 1000.0
	_process_recipe_type("carpentry")
	if _inventory_count("storage_crate") != 1 or _inventory_count("plain_plank") != 1:
		push_error("Fieldwright craft mismatch: crate=%d plank=%d feedback=%s" % [_inventory_count("storage_crate"), _inventory_count("plain_plank"), last_feedback_text])
		return false
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": float(field_success_millis) / 1000.0, "action_cooldowns": {}}
	state["inventory"] = {"plain_plank": 2, "bronze_sword": 27}
	_process_recipe_type("carpentry")
	if _inventory_count("plain_plank") != 2 or _inventory_count("bronze_sword") != 27 or _inventory_count("storage_crate") != 0:
		push_error("Fieldwright full-inventory block was not atomic")
		return false
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": float(field_success_millis) / 1000.0, "action_cooldowns": {}}
	state["inventory"] = {"plain_plank": 2, "bronze_sword": 26}
	_process_recipe_type("carpentry")
	if _inventory_count("storage_crate") != 1 or _inventory_count("plain_plank") != 1 or _inventory_count("bronze_sword") != 26:
		push_error("Fieldwright capacity-approved transaction did not apply exactly")
		return false

	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {}
	_process_recipe_type("carpentry")
	if _inventory_count("plain_plank") != 0 or _inventory_count("storage_crate") != 0:
		push_error("Failed Carpentry craft changed inventory")
		return false
	set_simulation_recipe_override("", "")

	skills_data = original_skills_data.duplicate(true)
	var smithing_thresholds = skills_data.get("smithing", {}).get("xp_thresholds", {})
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"bronze_bar": 1}
	state["skills"] = {"smithing": {"level": 40, "xp": int(smithing_thresholds["40"])}}
	_process_recipe_type("smithing")
	if _inventory_count("bronze_sword") != 1:
		return false
	var smithing_xp := int(ceil(12.0 * (1.0 + _skill_mastery_effect_total("smithing", "processing_xp_bonus_percent"))))
	if _skill_xp("smithing") != int(smithing_thresholds["40"]) + smithing_xp:
		return false

	skills_data = original_skills_data.duplicate(true)
	var fishing_thresholds = skills_data.get("fishing", {}).get("xp_thresholds", {})
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"fishing_rod": 1}
	state["skills"] = {"fishing": {"level": 40, "xp": int(fishing_thresholds["40"])}}
	skills_data["fishing"]["mastery_perks"][0]["effects"]["gather_bonus_yield_chance"] = 1.0
	_gather_resource({"id": "mastery_fishing_spot", "label": "Mastery fishing spot", "skill_id": "fishing", "required_level": 1, "xp_reward": 20, "item_reward": "raw_shrimp", "quantity_reward": 1})
	if _inventory_count("raw_shrimp") != 2:
		return false

	skills_data = original_skills_data.duplicate(true)
	var cooking_thresholds = skills_data.get("cooking", {}).get("xp_thresholds", {})
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["inventory"] = {"raw_shrimp": 1}
	state["skills"] = {"cooking": {"level": 40, "xp": int(cooking_thresholds["40"])}}
	skills_data["cooking"]["mastery_perks"][1]["effects"]["processing_bonus_output_chance"] = 1.0
	_process_cooking()
	var cooking_definition = items_data.get("raw_shrimp", {})
	var cooking_base_xp := int(cooking_definition.get("cooking_xp", 0))
	var cooking_xp := int(ceil(float(cooking_base_xp) * (1.0 + _skill_mastery_effect_total("cooking", "processing_xp_bonus_percent"))))
	if _inventory_count("cooked_shrimp") != 2 or _skill_xp("cooking") != int(cooking_thresholds["40"]) + cooking_xp:
		return false

	skills_data = original_skills_data.duplicate(true)
	var combat_mastery_cases := [
		{"skill_id": "strength", "weapon_id": "bronze_sword"},
		{"skill_id": "ranged", "weapon_id": "training_bow"},
		{"skill_id": "magic", "weapon_id": "training_staff"},
	]
	for combat_case in combat_mastery_cases:
		var combat_skill_id := str(combat_case["skill_id"])
		var combat_thresholds = skills_data.get(combat_skill_id, {}).get("xp_thresholds", {})
		if not combat_thresholds is Dictionary or not combat_thresholds.has("40"):
			return false
		state["skills"] = {combat_skill_id: {"level": 40, "xp": int(combat_thresholds["40"])}}
		state["equipment"] = {"weapon": str(combat_case["weapon_id"])}
		if not is_equal_approx(_skill_mastery_effect_total(combat_skill_id, "combat_damage_bonus"), 2.0):
			return false
		var damage_with_mastery := _combat_player_damage(combat_skill_id)
		var mastery_perks = skills_data[combat_skill_id]["mastery_perks"]
		var first_mastery_effects = mastery_perks[0]["effects"]
		var second_mastery_effects = mastery_perks[1]["effects"]
		var saved_first_bonus = first_mastery_effects["combat_damage_bonus"]
		var saved_second_bonus = second_mastery_effects["combat_damage_bonus"]
		first_mastery_effects["combat_damage_bonus"] = 0
		second_mastery_effects["combat_damage_bonus"] = 0
		var damage_without_mastery := _combat_player_damage(combat_skill_id)
		first_mastery_effects["combat_damage_bonus"] = saved_first_bonus
		second_mastery_effects["combat_damage_bonus"] = saved_second_bonus
		if damage_with_mastery != damage_without_mastery + 2:
			return false

	skills_data = original_skills_data
	return true


func run_interaction_panel_smoke() -> bool:
	_ensure_state_shape()
	state["inventory"] = {"coins": 50, "logs": 2, "bronze_sword": 1}
	state["bank"] = {"copper_ore": 2}
	state["quest_state"] = {"active_quest_id": "starter_path", "quests": {}}

	_open_bank()
	if not _interaction_panel_matches("Bank"):
		return false
	_handle_bank_deposit_requested("logs", 1)
	if _inventory_count("logs") != 1 or int(_bank().get("logs", 0)) != 1:
		return false
	_handle_bank_withdraw_requested("copper_ore", 1)
	if _inventory_count("copper_ore") != 1 or int(_bank().get("copper_ore", 0)) != 1:
		return false

	_open_shop({"name": "General Store", "stock": [{"item_id": "trail_ration", "price": 3}]})
	if not _interaction_panel_matches("General Store"):
		return false
	_handle_shop_buy_requested("trail_ration", 3)
	if _inventory_count("trail_ration") != 1 or _inventory_count("coins") != 47:
		return false
	var coins_before_invalid_shop := _inventory_count("coins")
	_handle_shop_buy_requested("missing_item", 1)
	if _inventory_count("missing_item") != 0 or _inventory_count("coins") != coins_before_invalid_shop:
		push_error("Interaction panel smoke: invalid shop item mutated state")
		return false
	_handle_shop_buy_requested("trail_ration", 99)
	if _inventory_count("trail_ration") != 1 or _inventory_count("coins") != coins_before_invalid_shop:
		push_error("Interaction panel smoke: stale shop price mutated state")
		return false
	_open_shop({})
	_handle_shop_buy_requested("trail_ration", 3)
	if _inventory_count("trail_ration") != 1 or _inventory_count("coins") != coins_before_invalid_shop:
		push_error("Interaction panel smoke: empty stock accepted a HUD price")
		return false
	_open_shop({"stock": [{"item_id": "trail_ration", "price": 3}]})
	_handle_shop_buy_requested("bronze_axe", _buy_price("bronze_axe"))
	if _inventory_count("bronze_axe") != 0 or _inventory_count("coins") != coins_before_invalid_shop:
		push_error("Interaction panel smoke: missing stock item was purchasable")
		return false
	_handle_shop_sell_requested("logs", 1)
	if _inventory_count("logs") != 0 or _inventory_count("coins") <= 47:
		return false

	var road_guard := {"quest_id": "road_patrol", "label": "Road Guard"}
	_talk_to_npc(road_guard)
	if not _interaction_panel_matches("Road Guard") or _quest_started("road_patrol"):
		return false
	_handle_dialogue_action_requested(road_guard)
	if not _quest_started("road_patrol") or _quest_completed("road_patrol"):
		return false
	for flag in ["used_shop", "equipped_weapon", "defeated_enemy", "used_bank"]:
		_record_quest_flag(flag)
	_handle_dialogue_action_requested(road_guard)
	return _quest_completed("road_patrol")


func run_quest_route_smoke(store: Node, username: String) -> bool:
	_ensure_state_shape()
	if store == null:
		push_error("Quest route smoke failed: missing StateStore")
		return false
	state["quest_state"] = {
		"active_quest_id": "starter_path",
		"quests": {
			"starter_path": {"quest_id": "starter_path", "started": true, "completed": false, "flags": []},
			"road_patrol": {"quest_id": "road_patrol", "started": true, "completed": false, "flags": []},
		},
	}
	var road_guard := {"quest_id": "road_patrol", "label": "Road Guard"}
	_talk_to_npc(road_guard)
	if str(_quest_root().get("active_quest_id", "")) != "starter_path":
		push_error("Quest route smoke failed: talking to an NPC replaced the selected route")
		return false
	var selected_route_before_invalid := str(_quest_root().get("active_quest_id", ""))
	_handle_quest_route_select_requested("missing_quest")
	if str(_quest_root().get("active_quest_id", "")) != selected_route_before_invalid:
		push_error("Quest route smoke failed: invalid quest tracking changed the selected route")
		return false
	_handle_quest_route_select_requested("workshop_order")
	if str(_quest_root().get("active_quest_id", "")) != selected_route_before_invalid:
		push_error("Quest route smoke failed: unstarted quest tracking changed the selected route")
		return false
	var route_root := _quest_root()
	route_root["quests"]["road_patrol"]["completed"] = true
	_sync_quest_state(route_root)
	_handle_quest_route_select_requested("road_patrol")
	if str(_quest_root().get("active_quest_id", "")) != selected_route_before_invalid:
		push_error("Quest route smoke failed: completed quest tracking changed the selected route")
		return false
	route_root["quests"]["road_patrol"]["completed"] = false
	_sync_quest_state(route_root)
	_handle_quest_route_select_requested("road_patrol")
	if str(_quest_root().get("active_quest_id", "")) != "road_patrol":
		push_error("Quest route smoke failed: explicit route selection did not update the active route")
		return false
	_handle_quest_route_select_requested("road_patrol")
	if str(_quest_root().get("active_quest_id", "")) != "road_patrol" or not last_feedback_text.to_lower().contains("already tracking"):
		push_error("Quest route smoke failed: repeated route selection did not remain a no-op")
		return false
	_talk_to_npc(road_guard)
	if str(_quest_root().get("active_quest_id", "")) != "road_patrol":
		push_error("Quest route smoke failed: repeated NPC conversation changed the selected route")
		return false
	state["username"] = username
	if not store.save_state(username, state):
		push_error("Quest route smoke failed: save_state returned false")
		return false
	var loaded: Dictionary = store.load_state(username)
	if loaded.is_empty():
		push_error("Quest route smoke failed: load_state returned empty")
		return false
	var loaded_quest_state = loaded.get("quest_state", {})
	var loaded_quests = loaded_quest_state.get("quests", {}) if loaded_quest_state is Dictionary else {}
	if not (loaded_quest_state is Dictionary and str(loaded_quest_state.get("active_quest_id", "")) == "road_patrol"):
		push_error("Quest route smoke failed: selected route was not preserved by save/load")
		return false
	if not (loaded_quests is Dictionary and bool(loaded_quests.get("starter_path", {}).get("started", false)) and bool(loaded_quests.get("road_patrol", {}).get("started", false))):
		push_error("Quest route smoke failed: existing quest states were not preserved by save/load")
		return false

	_reset_for_golden_scenario({
		"inventory": {"bronze_sword": INVENTORY_SLOT_LIMIT},
		"bank": {},
		"skills": {},
		"quest_state": {"active_quest_id": "starter_path", "quests": {}},
	})
	var keeper := {"quest_id": "workshop_order", "label": "Workshop Keeper"}
	_talk_to_npc(keeper)
	_handle_dialogue_action_requested(keeper)
	for flag in ["crafted_plank", "crafted_charcoal", "crafted_splinters"]:
		_record_quest_flag(flag)
	_handle_dialogue_action_requested(keeper)
	if _quest_completed("workshop_order") or not last_feedback_text.to_lower().contains("inventory is full"):
		push_error("Quest route smoke failed: full inventory did not block quest rewards")
		return false
	state["inventory"] = {"bronze_sword": INVENTORY_SLOT_LIMIT - 1}
	_handle_dialogue_action_requested(keeper)
	return _quest_completed("workshop_order") and _inventory_count("coins") == 24 and _assert_state_invariants_for_smoke("quest route")


func run_combat_depth_smoke() -> bool:
	_ensure_state_shape()
	state["combat"] = {"current_hitpoints": _skill_level("hitpoints"), "mobs": {}, "ground_items": [], "status_effects": {}}
	state["inventory"] = {"mire_tonic": 1}
	state["skills"] = {}

	var venom_mob := {
		"id": "venom_smoke_mob",
		"label": "Mire stinger",
		"level": 3,
		"hitpoints": 5,
		"poison_chance": 1.0,
		"poison_damage": 1,
		"poison_rounds": 2,
	}
	_attack_mob(venom_mob)
	if not _combat_is_poisoned():
		return false
	var hitpoints_after_poison := int(_combat_state().get("current_hitpoints", 0))
	_attack_mob(venom_mob)
	if int(_combat_state().get("current_hitpoints", 0)) >= hitpoints_after_poison:
		return false
	if not _use_item("mire_tonic"):
		return false
	if _combat_is_poisoned() or _inventory_count("mire_tonic") != 0:
		return false
	if _action_speed_bonus() <= 0.0:
		return false

	state["combat"] = {"current_hitpoints": _skill_level("hitpoints"), "mobs": {}, "ground_items": [], "status_effects": {}}
	state["combat_training_style"] = "strength"
	state["inventory"] = {"bronze_sword": 1, "bronze_shield": 1}
	if not _equip_item("bronze_sword") or not _equip_item("bronze_shield"):
		return false
	var strength_before := _skill_xp("strength")
	var attack_before := _skill_xp("attack")
	var hitpoints_before := int(_combat_state().get("current_hitpoints", 0))
	_attack_mob({
		"id": "training_style_dummy",
		"label": "Training dummy",
		"level": 6,
		"hitpoints": 3,
	})
	if not (_skill_xp("strength") > strength_before and _skill_xp("attack") == attack_before and int(_combat_state().get("current_hitpoints", 0)) == hitpoints_before - 1):
		return false
	state["combat"] = {"current_hitpoints": _skill_level("hitpoints"), "mobs": {}, "ground_items": [], "ground_drop_sequence": 0, "status_effects": {}}
	state["skills"]["strength"] = {"level": 40, "xp": 1000}
	var overkill_strength_before := _skill_xp("strength")
	var overkill_hitpoints_before := _skill_xp("hitpoints")
	_attack_mob({"id": "overkill_dummy", "label": "Overkill dummy", "level": 1, "hitpoints": 1, "passive": true, "drops": []})
	return _skill_xp("strength") - overkill_strength_before == 4 and _skill_xp("hitpoints") - overkill_hitpoints_before == 1


func _assert_golden_core_loop_for_smoke() -> bool:
	_reset_for_golden_scenario({
		"inventory": {"bronze_axe": 1, "raw_shrimp": 1},
		"bank": {},
		"skills": {},
		"world": {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}},
	})
	_gather_resource({
		"id": "golden_tree",
		"label": "Golden Tree",
		"skill_id": "woodcutting",
		"required_level": 1,
		"xp_reward": 28,
		"item_reward": "logs",
		"quantity_reward": 1,
	})
	if _inventory_count("logs") != 1 or _skill_xp("woodcutting") <= 0:
		return false
	_process_recipe_type("carpentry")
	if _inventory_count("plain_plank") != 1 or _inventory_count("logs") != 0 or _skill_xp("carpentry") <= 0:
		return false
	_process_cooking()
	if _inventory_count("cooked_shrimp") != 1 or _skill_xp("cooking") <= 0:
		return false
	_combat_set_hitpoints(_skill_level("hitpoints") - 2)
	if not _use_item("cooked_shrimp"):
		return false
	if int(_combat_state().get("current_hitpoints", 0)) != _skill_level("hitpoints"):
		return false
	_open_shop({})
	_handle_shop_sell_requested("plain_plank", 1)
	return _inventory_count("plain_plank") == 0 and _inventory_count("coins") > 0 and _assert_state_invariants_for_smoke("golden core loop")


func _assert_golden_inventory_pressure_for_smoke() -> bool:
	_reset_for_golden_scenario({
		"inventory": {"coins": 1, "bronze_sword": INVENTORY_SLOT_LIMIT - 1},
		"bank": {},
	})
	if not _add_inventory_item("coins", 5):
		return false
	if _add_inventory_item("bones", 1):
		return false
	if _inventory_count("coins") != 6 or _inventory_count("bones") != 0:
		return false
	return _assert_state_invariants_for_smoke("golden inventory pressure")


func _assert_golden_quest_reward_flow_for_smoke() -> bool:
	_reset_for_golden_scenario({
		"inventory": {"bronze_sword": INVENTORY_SLOT_LIMIT},
		"bank": {},
		"skills": {},
		"quest_state": {"active_quest_id": "workshop_order", "quests": {}},
	})
	var keeper := {"quest_id": "workshop_order", "label": "Workshop Keeper"}
	_talk_to_npc(keeper)
	_handle_dialogue_action_requested(keeper)
	if not _quest_started("workshop_order"):
		return false
	for flag in ["crafted_plank", "crafted_charcoal", "crafted_splinters"]:
		_record_quest_flag(flag)
	_handle_dialogue_action_requested(keeper)
	if _quest_completed("workshop_order") or _inventory_count("coins") != 0:
		return false
	state["inventory"] = {"bronze_sword": INVENTORY_SLOT_LIMIT - 1}
	_handle_dialogue_action_requested(keeper)
	return _quest_completed("workshop_order") and _inventory_count("coins") == 24 and _skill_xp("carpentry") >= 24 and _assert_state_invariants_for_smoke("golden quest reward flow")


func _assert_golden_combat_loot_recovery_for_smoke() -> bool:
	_reset_for_golden_scenario({
		"inventory": {"cooked_shrimp": 1, "bronze_sword": 1},
		"combat": {"current_hitpoints": 8, "mobs": {}, "ground_items": [], "status_effects": {}},
		"skills": {},
	})
	if not _use_item("cooked_shrimp"):
		return false
	if int(_combat_state().get("current_hitpoints", 0)) != _skill_level("hitpoints"):
		return false
	_attack_mob({
		"id": "golden_rat",
		"label": "Golden Rat",
		"level": 1,
		"hitpoints": 1,
		"passive": true,
		"drops": [{"item_id": "coins", "quantity": 9}],
		"tile": Vector2i(17, 16),
	})
	var drops = _combat_state().get("ground_items", [])
	if not (drops is Array) or drops.is_empty():
		return false
	_pick_up_drop(drops[0])
	drops = _combat_state().get("ground_items", [])
	return _inventory_count("coins") == 9 and drops is Array and drops.is_empty() and _skill_xp("attack") > 0 and _assert_state_invariants_for_smoke("golden combat loot recovery")


func _assert_golden_bank_shop_round_trip_for_smoke() -> bool:
	_reset_for_golden_scenario({
		"inventory": {"coins": 50, "logs": 2},
		"bank": {},
	})
	_open_bank()
	_handle_bank_deposit_requested("logs", 0)
	if _inventory_count("logs") != 0 or int(_bank().get("logs", 0)) != 2:
		return false
	_handle_bank_withdraw_requested("logs", 1)
	if _inventory_count("logs") != 1 or int(_bank().get("logs", 0)) != 1:
		return false
	_open_shop({"name": "Golden Store", "stock": [{"item_id": "trail_ration", "price": 3}]})
	_handle_shop_buy_requested("trail_ration", 3)
	if _inventory_count("trail_ration") != 1 or _inventory_count("coins") != 47:
		return false
	_handle_shop_sell_requested("trail_ration", 1)
	return _inventory_count("trail_ration") == 0 and _inventory_count("coins") > 47 and _assert_state_invariants_for_smoke("golden bank/shop round trip")


func _assert_torture_combat_status_for_smoke(store: Node, username: String) -> bool:
	_reset_for_golden_scenario({
		"inventory": {"mire_tonic": 1},
		"combat": {"current_hitpoints": 10, "mobs": {}, "ground_items": [], "status_effects": {}},
		"skills": {},
	})
	var venom_mob := {
		"id": "torture_stinger",
		"label": "Torture Stinger",
		"level": 3,
		"hitpoints": 5,
		"poison_chance": 1.0,
		"poison_damage": 1,
		"poison_rounds": 2,
	}
	_attack_mob(venom_mob)
	if not _combat_is_poisoned():
		return false
	if not _assert_save_load_round_trip_for_smoke(store, username, "combat poison"):
		return false
	var hitpoints_after_load := int(_combat_state().get("current_hitpoints", 0))
	_attack_mob(venom_mob)
	if int(_combat_state().get("current_hitpoints", 0)) >= hitpoints_after_load:
		return false
	if not _use_item("mire_tonic"):
		return false
	if _combat_is_poisoned() or _inventory_count("mire_tonic") != 0:
		return false
	return _assert_save_load_round_trip_for_smoke(store, username, "combat cleanse")


func _assert_torture_quest_reward_for_smoke(store: Node, username: String) -> bool:
	_reset_for_golden_scenario({
		"inventory": {"bronze_sword": INVENTORY_SLOT_LIMIT},
		"bank": {},
		"skills": {},
		"quest_state": {"active_quest_id": "workshop_order", "quests": {}},
	})
	var keeper := {"quest_id": "workshop_order", "label": "Workshop Keeper"}
	_talk_to_npc(keeper)
	_handle_dialogue_action_requested(keeper)
	for flag in ["crafted_plank", "crafted_charcoal", "crafted_splinters"]:
		_record_quest_flag(flag)
	_handle_dialogue_action_requested(keeper)
	if _quest_completed("workshop_order") or _inventory_count("coins") != 0:
		return false
	if not _assert_save_load_round_trip_for_smoke(store, username, "quest blocked"):
		return false
	state["inventory"] = {"bronze_sword": INVENTORY_SLOT_LIMIT - 1}
	_handle_dialogue_action_requested(keeper)
	if not _quest_completed("workshop_order") or _inventory_count("coins") != 24:
		return false
	return _assert_save_load_round_trip_for_smoke(store, username, "quest complete")


func _assert_torture_bank_shop_for_smoke(store: Node, username: String) -> bool:
	_reset_for_golden_scenario({
		"inventory": {"coins": 50, "logs": 2},
		"bank": {},
	})
	_open_bank()
	_handle_bank_deposit_requested("logs", 0)
	if _inventory_count("logs") != 0 or int(_bank().get("logs", 0)) != 2:
		return false
	if not _assert_save_load_round_trip_for_smoke(store, username, "bank deposit"):
		return false
	_handle_bank_withdraw_requested("logs", 1)
	_open_shop({"name": "Torture Store", "stock": [{"item_id": "trail_ration", "price": 3}]})
	_handle_shop_buy_requested("trail_ration", 3)
	if _inventory_count("trail_ration") != 1 or _inventory_count("coins") != 47:
		return false
	if not _assert_save_load_round_trip_for_smoke(store, username, "shop buy"):
		return false
	_handle_shop_sell_requested("trail_ration", 1)
	return _inventory_count("trail_ration") == 0 and _inventory_count("coins") > 47 and _assert_save_load_round_trip_for_smoke(store, username, "shop sell")


func _assert_torture_full_inventory_for_smoke(store: Node, username: String) -> bool:
	_reset_for_golden_scenario({
		"inventory": {"bronze_sword": INVENTORY_SLOT_LIMIT},
		"combat": {"current_hitpoints": 10, "mobs": {}, "ground_items": [], "status_effects": {}},
	})
	var blocked_drop := {
		"object_id": "torture_bones_drop",
		"item_id": "bones",
		"quantity": 1,
		"type": "ground_item",
		"tile": [15, 15],
	}
	_combat_state()["ground_items"] = [blocked_drop.duplicate(true)]
	_pick_up_drop(blocked_drop)
	var drops = _combat_state().get("ground_items", [])
	if _inventory_count("bones") != 0 or not (drops is Array) or drops.size() != 1:
		return false
	if not _assert_save_load_round_trip_for_smoke(store, username, "full inventory blocked drop"):
		return false
	state["inventory"] = {"bronze_sword": INVENTORY_SLOT_LIMIT - 1}
	drops = _combat_state().get("ground_items", [])
	if not (drops is Array) or drops.is_empty():
		return false
	_pick_up_drop(drops[0])
	drops = _combat_state().get("ground_items", [])
	return _inventory_count("bones") == 1 and drops is Array and drops.is_empty() and _assert_save_load_round_trip_for_smoke(store, username, "drop pickup recovery")


func _assert_torture_resource_respawn_for_smoke(store: Node, username: String) -> bool:
	_reset_for_golden_scenario({
		"inventory": {"bronze_axe": 1},
		"world": {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}},
		"skills": {},
	})
	var tree := {
		"id": "torture_tree",
		"label": "Torture Tree",
		"skill_id": "woodcutting",
		"required_level": 1,
		"xp_reward": 28,
		"item_reward": "logs",
		"quantity_reward": 1,
		"base_gather_seconds": 1.0,
		"respawn_seconds": 5.0,
	}
	_gather_resource(tree)
	if _inventory_count("logs") != 1 or not _resource_is_depleted("torture_tree"):
		return false
	if not _assert_save_load_round_trip_for_smoke(store, username, "resource depleted"):
		return false
	_advance_action_clock(5.1)
	_gather_resource(tree)
	if _inventory_count("logs") != 2 or not _resource_is_depleted("torture_tree"):
		return false
	return _assert_save_load_round_trip_for_smoke(store, username, "resource respawn")


func _assert_save_load_round_trip_for_smoke(store: Node, username: String, label: String) -> bool:
	state["username"] = username
	state["account"] = {"username": username, "key": username.to_lower(), "created_at": Time.get_datetime_string_from_system(true), "last_login_at": null}
	var expected := state.duplicate(true)
	if not store.save_state(username, state):
		push_error("Save/load torture smoke failed: %s save_state returned false" % label)
		return false
	var loaded: Dictionary = store.load_state(username)
	if loaded.is_empty():
		push_error("Save/load torture smoke failed: %s load_state returned empty" % label)
		return false
	for key in ["inventory", "bank", "equipment", "skills", "combat", "world", "quest_state", "combat_training_style"]:
		if _normalize_for_smoke_compare(loaded.get(key, {})) != _normalize_for_smoke_compare(expected.get(key, {})):
			push_error("Save/load torture smoke failed: %s %s mismatch" % [label, key])
			return false
	if str(loaded.get("username", "")) != username:
		push_error("Save/load torture smoke failed: %s username mismatch" % label)
		return false
	state.clear()
	for key in loaded.keys():
		state[key] = loaded[key]
	_ensure_state_shape()
	return _assert_state_invariants_for_smoke("save/load torture %s" % label)


func _normalize_for_smoke_compare(value):
	if value is Dictionary:
		var clean := {}
		for key in value.keys():
			clean[str(key)] = _normalize_for_smoke_compare(value[key])
		return clean
	if value is Array:
		var clean_array := []
		for item in value:
			clean_array.append(_normalize_for_smoke_compare(item))
		return clean_array
	if value is float and is_equal_approx(value, round(value)):
		return int(round(value))
	return value


func _reset_for_golden_scenario(overrides: Dictionary) -> void:
	state.clear()
	state["username"] = "codex_golden_scenarios_smoke"
	state["inventory"] = {}
	state["bank"] = {}
	state["equipment"] = {}
	state["skills"] = {}
	state["combat_training_style"] = "attack"
	state["combat"] = {"current_hitpoints": 10, "mobs": {}, "ground_items": [], "status_effects": {}}
	state["world"] = {"resource_nodes": {}, "action_clock_seconds": 0.0, "action_cooldowns": {}}
	state["quest_state"] = {"active_quest_id": "starter_path", "quests": {}}
	state["player"] = {"tile": [15, 15], "position": [15.5, 15.5]}
	for key in overrides.keys():
		state[key] = overrides[key].duplicate(true) if overrides[key] is Dictionary or overrides[key] is Array else overrides[key]
	_ensure_state_shape()


func _assert_state_invariants_for_smoke(label: String) -> bool:
	var invariant_issues: Array = InvariantChecker.check_state(state, items_data, {
		"inventory_slot_limit": INVENTORY_SLOT_LIMIT,
	})
	for issue in invariant_issues:
		if issue is Dictionary:
			push_error("%s invariant failed: %s" % [label, str(issue.get("summary", "state invariant failed"))])
		else:
			push_error("%s invariant failed: %s" % [label, str(issue)])
	return invariant_issues.is_empty()


func _assert_capacity_edges_for_smoke() -> bool:
	state["world"] = {"resource_nodes": {}}
	state["inventory"] = {"bronze_axe": 1, "bronze_sword": INVENTORY_SLOT_LIMIT - 1}
	var full_tree := {
		"id": "capacity_tree",
		"label": "Tree",
		"skill_id": "woodcutting",
		"required_level": 1,
		"xp_reward": 28,
		"item_reward": "logs",
		"quantity_reward": 1,
	}
	_gather_resource(full_tree)
	if _inventory_count("logs") != 0:
		return false
	if _skill_xp("woodcutting") != 0:
		return false
	if _resource_is_depleted("capacity_tree"):
		return false
	if not _last_feedback_contains_all(["Inventory is full", "bank", "sell", "drop"]):
		return false

	state["inventory"] = {"bronze_axe": 1, "bronze_sword": INVENTORY_SLOT_LIMIT - 2, "logs": 1}
	_gather_resource({
		"id": "stack_capacity_tree",
		"label": "Tree",
		"skill_id": "woodcutting",
		"required_level": 1,
		"xp_reward": 28,
		"item_reward": "logs",
		"quantity_reward": 1,
	})
	if _inventory_count("logs") != 2:
		return false
	if not _resource_is_depleted("stack_capacity_tree"):
		return false

	var blocked_drop := {
		"object_id": "blocked_drop_01",
		"item_id": "bones",
		"quantity": 1,
		"type": "ground_item",
	}
	_combat_state()["ground_items"] = [blocked_drop.duplicate(true)]
	_pick_up_drop(blocked_drop)
	var ground_items = _combat_state().get("ground_items", [])
	return _inventory_count("bones") == 0 and ground_items is Array and ground_items.size() == 1 and _last_feedback_contains_all(["Inventory is full", "bank", "sell", "drop"])


func _assert_core_progression_path_for_smoke() -> bool:
	state["inventory"] = {
		"bronze_axe": 1,
		"bronze_pickaxe": 1,
		"fishing_rod": 1,
		"bronze_sword": 1,
		"coins": 20,
	}
	state["bank"] = {}
	state["world"] = {"resource_nodes": {}}
	_combat_state()["ground_items"] = []

	_gather_resource({
		"id": "regression_tree",
		"label": "Tree",
		"skill_id": "woodcutting",
		"required_level": 1,
		"xp_reward": 28,
		"item_reward": "logs",
		"quantity_reward": 1,
	})
	if _inventory_count("logs") != 1:
		return false
	_process_recipe_type("carpentry")
	if _inventory_count("plain_plank") != 1:
		return false
	_add_inventory_item("copper_ore", 1)
	_add_inventory_item("tin_ore", 1)
	_process_recipe_type("smelting")
	if _inventory_count("bronze_bar") != 1:
		return false
	_process_recipe_type("smithing")
	if _inventory_count("bronze_sword") < 2:
		return false
	_add_inventory_item("raw_shrimp", 1)
	_process_cooking()
	return _inventory_count("cooked_shrimp") == 1 and _skill_xp("carpentry") > 0 and _skill_xp("smithing") > 0 and _skill_xp("cooking") > 0


func _assert_inventory_item_actions_for_smoke() -> bool:
	var snapshot := state.duplicate(true)
	var passed := true
	state["inventory"] = {"cooked_shrimp": 1, "bronze_shield": 1, "bronze_sword": 1}
	state["equipment"] = {}
	state["skills"] = {
		"attack": {"xp": 0, "level": 1},
		"defence": {"xp": 0, "level": 1},
		"hitpoints": {"xp": 0, "level": 10},
	}
	state["combat"] = {"current_hitpoints": 8, "mobs": {}, "ground_items": [], "status_effects": {}}
	_handle_inventory_item_action_requested("cooked_shrimp", "use")
	if _inventory_count("cooked_shrimp") != 0 or int(_combat_state().get("current_hitpoints", 0)) != 10:
		passed = false
	if passed:
		_handle_inventory_item_action_requested("bronze_shield", "equip")
		passed = str(_equipment().get("shield", "")) == "bronze_shield" and _inventory_count("bronze_shield") == 0
	if passed:
		_handle_inventory_item_action_requested("bronze_sword", "equip")
		passed = str(_equipment().get("weapon", "")) == "bronze_sword" and _inventory_count("bronze_sword") == 0
	if passed:
		state["inventory"]["bronze_sword"] = 1
		_handle_inventory_item_action_requested("bronze_sword", "equip")
		passed = str(_equipment().get("weapon", "")) == "bronze_sword" and _inventory_count("bronze_sword") == 1 and _last_feedback_contains_all(["already equipped"])
	if passed:
		_handle_equipment_item_action_requested("weapon", "unequip")
		passed = str(_equipment().get("weapon", "")) == "" and _inventory_count("bronze_sword") == 2
	if passed:
		_handle_inventory_item_action_requested("bronze_sword", "equip")
		passed = str(_equipment().get("weapon", "")) == "bronze_sword" and _inventory_count("bronze_sword") == 1
	if passed:
		state["inventory"] = {"iron_sword": INVENTORY_SLOT_LIMIT}
		_handle_equipment_item_action_requested("weapon", "unequip")
		passed = str(_equipment().get("weapon", "")) == "bronze_sword" and _inventory_count("bronze_sword") == 0
	if passed:
		state["inventory"]["iron_sword"] = 1
		_handle_inventory_item_action_requested("iron_sword", "equip")
		passed = str(_equipment().get("weapon", "")) == "bronze_sword" and _inventory_count("iron_sword") == 1
	_restore_state_snapshot(snapshot)
	return passed


func _assert_inventory_drop_for_smoke() -> bool:
	var snapshot := state.duplicate(true)
	var passed := true
	state["inventory"] = {"logs": 2}
	state["player"] = {"tile": [15, 15], "position": [15.5, 15.5]}
	state["combat"] = {"current_hitpoints": 10, "mobs": {}, "ground_items": [], "status_effects": {}}
	_handle_inventory_item_action_requested("logs", "drop")
	var drops = _combat_state().get("ground_items", [])
	if _inventory_count("logs") != 1 or not (drops is Array) or drops.is_empty():
		passed = false
	if passed:
		var drop = drops[0]
		passed = drop is Dictionary and str(drop.get("item_id", "")) == "logs" and int(drop.get("quantity", 0)) == 1
	if passed:
		_pick_up_drop(drops[0])
		drops = _combat_state().get("ground_items", [])
		passed = _inventory_count("logs") == 2 and drops is Array and drops.is_empty()
	_restore_state_snapshot(snapshot)
	return passed


func _restore_state_snapshot(snapshot: Dictionary) -> void:
	StateSnapshot.restore_into(state, snapshot)


func _assert_bank_round_trip_for_smoke() -> bool:
	var coins_before := _inventory_count("coins")
	_open_shop({"stock": [{"item_id": "trail_ration", "price": 3}]})
	_handle_shop_buy_requested("trail_ration", 3)
	if _inventory_count("trail_ration") != 1 or _inventory_count("coins") != coins_before - 3:
		return false
	state["inventory"] = {"coins": _inventory_count("coins"), "plain_plank": 2}
	_open_bank()
	_handle_bank_deposit_requested("plain_plank", 0)
	if _inventory_count("plain_plank") != 0 or int(_bank().get("plain_plank", 0)) != 2:
		return false
	_open_bank()
	_handle_bank_withdraw_requested("plain_plank", 0)
	return _inventory_count("plain_plank") == 2 and not _bank().has("plain_plank")


func _assert_shop_capacity_for_smoke() -> bool:
	state["inventory"] = {"plain_plank": 2}
	_open_shop({})
	_handle_shop_sell_requested("plain_plank", 0)
	if _inventory_count("plain_plank") != 0 or _inventory_count("coins") != 10:
		return false
	state["inventory"] = {"coins": 30, "bronze_sword": INVENTORY_SLOT_LIMIT - 1}
	_open_shop({"stock": [{"item_id": "cooking_pot", "price": 15}]})
	_handle_shop_buy_requested("cooking_pot", 15)
	return _inventory_count("coins") == 30 and _inventory_count("bronze_sword") == INVENTORY_SLOT_LIMIT - 1 and _inventory_count("cooking_pot") == 0


func _assert_quest_reward_capacity_for_smoke() -> bool:
	state["inventory"] = {"bronze_sword": INVENTORY_SLOT_LIMIT}
	state["bank"] = {}
	var keeper := {"quest_id": "workshop_order", "label": "Workshop Keeper"}
	_talk_to_npc(keeper)
	_handle_dialogue_action_requested(keeper)
	for flag in ["crafted_plank", "crafted_charcoal", "crafted_splinters"]:
		_record_quest_flag(flag)
	var carpentry_xp_before := _skill_xp("carpentry")
	_talk_to_npc(keeper)
	_handle_dialogue_action_requested(keeper)
	if _quest_completed("workshop_order"):
		return false
	if _inventory_count("coins") != 0 or _skill_xp("carpentry") != carpentry_xp_before:
		return false
	state["inventory"]["bronze_sword"] = INVENTORY_SLOT_LIMIT - 1
	_talk_to_npc(keeper)
	_handle_dialogue_action_requested(keeper)
	return _quest_completed("workshop_order") and _inventory_count("coins") == 24 and _skill_xp("carpentry") >= carpentry_xp_before + 24


func _assert_reward_transaction_edges_for_smoke() -> bool:
	state["inventory"] = {"bronze_sword": INVENTORY_SLOT_LIMIT - 1}
	var carpentry_xp_before := _skill_xp("carpentry")
	var blocked_definition := {
		"item_rewards": [
			{"item_id": "plain_tool_handle", "quantity": 1},
			{"item_id": "moon_gem", "quantity": 1},
		],
		"skill_rewards": [{"skill_id": "carpentry", "xp": 10}],
	}
	if _can_apply_item_rewards(blocked_definition):
		return false
	if _apply_quest_rewards(blocked_definition):
		return false
	if _inventory_count("plain_tool_handle") != 0 or _inventory_count("moon_gem") != 0 or _skill_xp("carpentry") != carpentry_xp_before:
		return false
	state["inventory"] = {"bronze_sword": INVENTORY_SLOT_LIMIT - 2}
	if not _can_apply_item_rewards(blocked_definition):
		return false
	if not _apply_quest_rewards(blocked_definition):
		return false
	if _inventory_count("plain_tool_handle") != 1 or _inventory_count("moon_gem") != 1 or _skill_xp("carpentry") != carpentry_xp_before + 10:
		return false
	state["inventory"] = {"coins": 5}
	if _inventory_can_transact({"coins": -1}, {}):
		return false
	if _remove_inventory_item("coins", -1) != 0:
		return false
	if _inventory_count("coins") != 5:
		return false
	return not _add_inventory_item("coins", -1)


func _assert_bank_capacity_edges_for_smoke() -> bool:
	state["inventory"] = {"coins": 1}
	state["bank"] = {"bronze_sword": INVENTORY_SLOT_LIMIT + 2}
	_open_bank()
	_handle_bank_withdraw_requested("bronze_sword", 0)
	if _inventory_count("coins") != 1:
		return false
	if _inventory_count("bronze_sword") != INVENTORY_SLOT_LIMIT - 1:
		return false
	return int(_bank().get("bronze_sword", 0)) == 3


func _assert_shop_affordability_for_smoke() -> bool:
	state["inventory"] = {"coins": 2}
	_open_shop({"stock": [{"item_id": "trail_ration", "price": 3}]})
	_handle_shop_buy_requested("trail_ration", 3)
	return _inventory_count("coins") == 2 and _inventory_count("trail_ration") == 0


func _assert_food_use_for_smoke() -> bool:
	state["inventory"] = {"cooked_shrimp": 2}
	_combat_set_hitpoints(_skill_level("hitpoints") - 2)
	if not _use_item("cooked_shrimp"):
		return false
	if int(_combat_state().get("current_hitpoints", 0)) != _skill_level("hitpoints"):
		return false
	if _inventory_count("cooked_shrimp") != 1:
		return false
	var quest_before := _quest_root().duplicate(true)
	if _use_item("cooked_shrimp"):
		return false
	return _inventory_count("cooked_shrimp") == 1 and _quest_root() == quest_before


func _assert_level_unlock_for_smoke() -> bool:
	var definition = skills_data.get("woodcutting", {})
	if not (definition is Dictionary):
		return false
	var thresholds = definition.get("xp_thresholds", {})
	if not (thresholds is Dictionary) or not thresholds.has("15"):
		return false
	_skills()["woodcutting"] = {"xp": int(thresholds["15"]) - 1, "level": 14}
	var level_message := _add_xp("woodcutting", 1)
	return level_message.contains("Woodcutting level 15") and level_message.contains("oak logs")


func _assert_equipment_and_drop_paths_for_smoke() -> bool:
	state["inventory"] = {"training_bow": 1, "coins": 5}
	state["bank"] = {"plain_plank": 2}
	if not _equip_item("training_bow"):
		return false
	if str(_equipment().get("weapon", "")) != "training_bow" or _inventory_count("training_bow") != 0:
		return false
	_attack_mob({
		"id": "regression_rat",
		"label": "Rat",
		"level": 1,
		"hitpoints": 1,
		"passive": true,
		"drops": [{"item_id": "coins", "quantity": 7}],
		"tile": Vector2i(17, 16),
	})
	var drops = _combat_state().get("ground_items", [])
	if not (drops is Array) or drops.is_empty():
		return false
	var coins_before := _inventory_count("coins")
	_pick_up_drop(drops[0])
	drops = _combat_state().get("ground_items", [])
	return _inventory_count("coins") == coins_before + 7 and drops is Array and drops.is_empty()
