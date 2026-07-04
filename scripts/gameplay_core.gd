extends Node

const ITEMS_PATH := "res://data/items.json"
const SKILLS_PATH := "res://data/skills.json"
const RECIPES_PATH := "res://data/recipes.json"
const QUESTS_PATH := "res://data/quests.json"
const INVENTORY_SLOT_LIMIT := 28
const REQUIRED_TOOLS := {
	"woodcutting": ["bronze_axe", "woodcutting axe"],
	"mining": ["bronze_pickaxe", "pickaxe"],
	"fishing": ["fishing_rod", "fishing rod"],
}
const PROCESSING_SKILLS := {
	"smelting": "smithing",
	"smithing": "smithing",
	"carpentry": "carpentry",
	"herbalism": "herbalism",
}
const DEFAULT_ACTION_SECONDS := 1.0

var state := {}
var world: Node
var hud: CanvasLayer
var items_data := {}
var skills_data := {}
var recipes_data := {}
var quests_data := {}
var ground_drop_counter := 0
var active_shop_data := {}


func setup(initial_state: Dictionary, world_node: Node, hud_node: CanvasLayer) -> void:
	state = initial_state
	world = world_node
	hud = hud_node
	items_data = _load_json(ITEMS_PATH)
	skills_data = _load_json(SKILLS_PATH)
	recipes_data = _load_json(RECIPES_PATH)
	quests_data = _load_json(QUESTS_PATH)
	_ensure_state_shape()
	_connect_hud_requests()


func _connect_hud_requests() -> void:
	if hud == null:
		return
	_connect_hud_signal("bank_deposit_requested", "_handle_bank_deposit_requested")
	_connect_hud_signal("bank_withdraw_requested", "_handle_bank_withdraw_requested")
	_connect_hud_signal("shop_buy_requested", "_handle_shop_buy_requested")
	_connect_hud_signal("shop_sell_requested", "_handle_shop_sell_requested")
	_connect_hud_signal("dialogue_action_requested", "_handle_dialogue_action_requested")


func _connect_hud_signal(signal_name: String, method_name: String) -> void:
	if not hud.has_signal(signal_name):
		return
	var callable := Callable(self, method_name)
	if not hud.is_connected(signal_name, callable):
		hud.connect(signal_name, callable)


func activate_object(object_data: Dictionary) -> void:
	var action := str(object_data.get("action", "default"))
	if action == "examine":
		_examine_object(object_data)
		_refresh_ui()
		return
	match str(object_data.get("type", "")):
		"resource":
			if action in ["default", "fish_net", "fish_rod"]:
				_gather_resource(object_data)
			else:
				_feedback("Choose a gathering action for %s" % str(object_data.get("label", "Resource")))
		"station":
			_process_station(object_data)
		"mob":
			if action in ["default", "attack"]:
				_attack_mob(object_data)
			else:
				_feedback("Choose Attack to fight %s" % str(object_data.get("label", "Mob")))
		"ground_item":
			_pick_up_drop(object_data)
		"npc":
			_talk_to_npc(object_data)
		_:
			_feedback("Selected %s" % str(object_data.get("label", "object")))
	_refresh_ui()


func _examine_object(object_data: Dictionary) -> void:
	var label := str(object_data.get("label", "object"))
	match str(object_data.get("type", "")):
		"resource":
			var skill_name := _skill_name(str(object_data.get("skill_id", "")))
			var required_level := int(object_data.get("required_level", 1))
			_feedback("%s: %s resource, level %d." % [label, skill_name, required_level])
		"mob":
			_feedback("%s: combat level %d." % [label, int(object_data.get("level", 1))])
		"ground_item":
			_feedback("%s: item on the ground." % label)
		"npc":
			_feedback("%s: local Hearthvale villager." % label)
		"station":
			_feedback("%s: %s station." % [label, _display_label(str(object_data.get("station_id", "work")))])
		_:
			_feedback("%s: nothing unusual." % label)


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


func run_interaction_panel_smoke() -> bool:
	_ensure_state_shape()
	state["inventory"] = {"coins": 50, "logs": 2, "bronze_sword": 1}
	state["bank"] = {"copper_ore": 2}
	state["quest_state"] = {"active_quest_id": "starter_path", "quests": {}}
	state["quest_progress"] = {}

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

	state["combat"] = {"current_hitpoints": _skill_level("hitpoints"), "mobs": {}, "ground_items": [], "status_effects": {}}
	state["combat_training_style"] = "strength"
	var strength_before := _skill_xp("strength")
	var attack_before := _skill_xp("attack")
	_attack_mob({
		"id": "training_style_dummy",
		"label": "Training dummy",
		"level": 1,
		"hitpoints": 2,
		"passive": true,
	})
	return _skill_xp("strength") > strength_before and _skill_xp("attack") == attack_before


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
	return _inventory_count("bones") == 0 and ground_items is Array and ground_items.size() == 1


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


func _gather_resource(object_data: Dictionary) -> void:
	var node_id := str(object_data.get("id", ""))
	var skill_id := str(object_data.get("skill_id", ""))
	var label := str(object_data.get("label", "Resource"))
	var required_level := int(object_data.get("required_level", 1))
	var item_id := str(object_data.get("item_reward", ""))
	var quantity := int(object_data.get("quantity_reward", 1))
	var xp := int(object_data.get("xp_reward", 0))

	if item_id.is_empty():
		_feedback("Nothing to gather")
		return
	if _resource_is_depleted(node_id):
		_feedback("%s is depleted" % label)
		return
	var tool = _required_tool_for_resource(object_data)
	if tool.size() >= 2 and _inventory_count(str(tool[0])) <= 0:
		_feedback("You need a %s" % str(tool[1]))
		return
	if _skill_level(skill_id) < required_level:
		_feedback("You need %s level %d" % [_skill_name(skill_id), required_level])
		return
	if not _inventory_can_transact({}, {item_id: quantity}):
		_feedback("Inventory is full")
		return
	var action_key := "gather:%s" % node_id
	if not _action_is_ready(action_key):
		_feedback("%s is still being gathered" % label)
		return

	_add_inventory_item(item_id, quantity)
	var secondary_item := str(object_data.get("secondary_item_reward", ""))
	var secondary_quantity := int(object_data.get("secondary_quantity_reward", 1))
	var secondary_chance := float(object_data.get("secondary_drop_chance", 0.0))
	if not secondary_item.is_empty() and secondary_quantity > 0 and _chance_succeeds(action_key, secondary_chance):
		_add_inventory_item(secondary_item, secondary_quantity)
	var level_message := _add_xp(skill_id, xp)
	_start_action_cooldown(action_key, float(object_data.get("base_gather_seconds", DEFAULT_ACTION_SECONDS)))
	_mark_resource_depleted(node_id, float(object_data.get("respawn_seconds", 0.0)))
	_record_gathering_quest_flags(skill_id, item_id)
	var message := "Gathered %d %s; +%d %s XP" % [quantity, _item_name(item_id), xp, _skill_name(skill_id)]
	if not level_message.is_empty():
		message = "%s; %s" % [message, level_message]
	_feedback(message)


func _process_station(object_data: Dictionary) -> void:
	var station_id := str(object_data.get("station_id", ""))
	match station_id:
		"cooking_range":
			_process_cooking()
		"furnace":
			_process_recipe_type("smelting")
		"anvil":
			_process_recipe_type("smithing")
		"carpentry_bench":
			_process_recipe_type("carpentry")
		"apothecary_table":
			_process_recipe_type("herbalism")
		"bank":
			_open_bank()
		"shop":
			_open_shop(object_data)
		_:
			_feedback("Nothing happens")


func _process_cooking() -> void:
	var inventory := _inventory()
	for item_id in inventory.keys():
		var definition = items_data.get(str(item_id), {})
		if not (definition is Dictionary) or not definition.has("cook_result"):
			continue
		var required_level := int(definition.get("cooking_required_level", 1))
		if _skill_level("cooking") < required_level:
			_feedback("You need Cooking level %d" % required_level)
			return
		var cooked_item := str(definition["cook_result"])
		if not _inventory_can_transact({str(item_id): 1}, {cooked_item: 1}):
			_feedback("Inventory is full")
			return
		var action_key := "cook:%s" % str(item_id)
		if not _action_is_ready(action_key):
			_feedback("Cooking is still in progress")
			return
		_remove_inventory_item(str(item_id), 1)
		_add_inventory_item(cooked_item, 1)
		var xp := int(definition.get("cooking_xp", 0))
		var level_message := _add_xp("cooking", xp)
		_start_action_cooldown(action_key, float(definition.get("base_cook_seconds", DEFAULT_ACTION_SECONDS)))
		_record_quest_flag("cooked_food")
		var message := "Cooked %s: +1 %s, +%d Cooking XP" % [_item_name(str(item_id)), _item_name(cooked_item), xp]
		if not level_message.is_empty():
			message = "%s; %s" % [message, level_message]
		_feedback(message)
		return
	_feedback("Select a raw fish first")


func _process_recipe_type(action_type: String) -> void:
	var recipes = recipes_data.get(action_type, [])
	if not (recipes is Array):
		_feedback("No recipe available")
		return
	for recipe in recipes:
		if not (recipe is Dictionary):
			continue
		if not _has_recipe_inputs(recipe):
			continue
		var skill_id := str(PROCESSING_SKILLS.get(action_type, action_type))
		var required_level := int(recipe.get("required_level", 1))
		if _skill_level(skill_id) < required_level:
			_feedback("You need %s level %d" % [_skill_name(skill_id), required_level])
			return
		var output_item := str(recipe.get("output_item_id", ""))
		var output_quantity := int(recipe.get("output_quantity", 1))
		if not _inventory_can_transact(recipe.get("inputs", {}), {output_item: output_quantity}):
			_feedback("Inventory is full")
			return
		var recipe_id := str(recipe.get("recipe_id", output_item))
		var action_key := "recipe:%s:%s" % [action_type, recipe_id]
		if not _action_is_ready(action_key):
			_feedback("%s is still in progress" % str(recipe.get("display_name", recipe_id)))
			return
		for input_id in recipe.get("inputs", {}).keys():
			_remove_inventory_item(str(input_id), int(recipe["inputs"][input_id]))
		_add_inventory_item(output_item, output_quantity)
		var xp := int(recipe.get("xp_reward", 0))
		var level_message := _add_xp(skill_id, xp)
		_start_action_cooldown(action_key, float(recipe.get("base_seconds", DEFAULT_ACTION_SECONDS)))
		_record_processing_quest_flags(action_type, recipe_id, output_item)
		var message := "%s %s: +%d %s, +%d %s XP" % [
			_done_verb(action_type),
			str(recipe.get("display_name", recipe.get("recipe_id", output_item))),
			output_quantity,
			_item_name(output_item),
			xp,
			_skill_name(skill_id),
		]
		if not level_message.is_empty():
			message = "%s; %s" % [message, level_message]
		_feedback(message)
		return
	_feedback(_select_feedback(action_type))


func _attack_mob(object_data: Dictionary) -> void:
	var mob_id := str(object_data.get("id", ""))
	var label := str(object_data.get("label", "Mob"))
	var max_hp := int(object_data.get("hitpoints", 1))
	var level := int(object_data.get("level", 1))
	var combat := _combat_state()
	var poison_message := _tick_combat_status_effects()
	if int(combat.get("current_hitpoints", 0)) <= 0:
		_feedback(poison_message if not poison_message.is_empty() else "You are too wounded to keep fighting")
		return
	var mobs = combat.get("mobs", {})
	if not (mobs is Dictionary):
		mobs = {}
	var mob_state = mobs.get(mob_id, {"hitpoints": max_hp, "dead": false})
	if not (mob_state is Dictionary):
		mob_state = {"hitpoints": max_hp, "dead": false}
	if bool(mob_state.get("dead", false)):
		_feedback("%s is defeated" % label)
		return

	var style := str(state.get("combat_training_style", "attack"))
	if style not in ["attack", "strength", "defence", "ranged", "magic"]:
		style = "attack"
	var damage: int = max(1, 1 + int((_skill_level(_damage_skill(style)) - 1) / 10))
	var remaining: int = max(0, int(mob_state.get("hitpoints", max_hp)) - damage)
	_add_xp(style, damage * 4)
	_add_xp("hitpoints", damage)
	var enemy_damage: int = 0 if bool(object_data.get("passive", false)) else max(0, int(level / 3))
	if enemy_damage > 0:
		_combat_set_hitpoints(max(0, int(combat.get("current_hitpoints", 10)) - enemy_damage))
		_add_xp("defence", enemy_damage * 4)
		_apply_poison_from_mob(object_data)

	var status_suffix := ""
	if not poison_message.is_empty():
		status_suffix = "; %s" % poison_message
	if remaining <= 0:
		mobs[mob_id] = {"hitpoints": 0, "dead": true}
		combat["mobs"] = mobs
		_spawn_drops(object_data)
		_record_combat_quest_flags(mob_id)
		_feedback("Defeated %s; drops appeared; you: %d/%d HP%s" % [label, int(combat.get("current_hitpoints", 10)), _skill_level("hitpoints"), status_suffix])
		return

	mobs[mob_id] = {"hitpoints": remaining, "dead": false}
	combat["mobs"] = mobs
	_feedback("Hit %s: %d/%d HP left; you: %d/%d HP%s" % [label, remaining, max_hp, int(combat.get("current_hitpoints", 10)), _skill_level("hitpoints"), status_suffix])


func _pick_up_drop(object_data: Dictionary) -> void:
	var item_id := str(object_data.get("item_id", ""))
	var quantity := int(object_data.get("quantity", 1))
	if item_id.is_empty() or quantity <= 0:
		_feedback("Nothing to take")
		return
	if not _inventory_can_transact({}, {item_id: quantity}):
		_feedback("Inventory is full")
		return
	_add_inventory_item(item_id, quantity)
	var combat := _combat_state()
	var ground_items = combat.get("ground_items", [])
	if ground_items is Array:
		for index in range(ground_items.size() - 1, -1, -1):
			var item = ground_items[index]
			if item is Dictionary and str(item.get("object_id", "")) == str(object_data.get("object_id", "")):
				ground_items.remove_at(index)
				break
	combat["ground_items"] = ground_items
	if world != null and world.has_method("remove_ground_item"):
		world.remove_ground_item(object_data)
	_feedback("Picked up %d %s" % [quantity, _item_name(item_id)])


func _spawn_drops(object_data: Dictionary) -> void:
	var drops = object_data.get("drops", [])
	if not (drops is Array):
		return
	var combat := _combat_state()
	var ground_items = combat.get("ground_items", [])
	if not (ground_items is Array):
		ground_items = []
	var tile: Vector2i = object_data.get("tile", Vector2i(15, 15))
	for drop in drops:
		if not (drop is Dictionary):
			continue
		ground_drop_counter += 1
		var item := {
			"object_id": "ground_item_%04d" % ground_drop_counter,
			"item_id": str(drop.get("item_id", "")),
			"quantity": int(drop.get("quantity", 1)),
			"tile": [tile.x, tile.y],
			"type": "ground_item",
		}
		ground_items.append(item)
		if world != null and world.has_method("add_ground_drop"):
			world.add_ground_drop(tile, item)
	combat["ground_items"] = ground_items


func _open_bank() -> void:
	if hud != null and hud.has_method("show_bank_panel"):
		hud.show_bank_panel()
	_feedback("Bank opened")


func _open_shop(shop_data: Dictionary = {}) -> void:
	active_shop_data = shop_data.duplicate(true)
	if hud != null and hud.has_method("show_shop_panel"):
		hud.show_shop_panel(active_shop_data)
	_feedback("Shop opened")


func _handle_bank_deposit_requested(item_id: String, quantity: int) -> void:
	_deposit_bank_item(item_id, quantity)
	if hud != null and hud.has_method("show_bank_panel"):
		hud.show_bank_panel()
	_refresh_ui()


func _handle_bank_withdraw_requested(item_id: String, quantity: int) -> void:
	_withdraw_bank_item(item_id, quantity)
	if hud != null and hud.has_method("show_bank_panel"):
		hud.show_bank_panel()
	_refresh_ui()


func _handle_shop_buy_requested(item_id: String, price: int) -> void:
	_buy_shop_item(item_id, price)
	if hud != null and hud.has_method("show_shop_panel"):
		hud.show_shop_panel(active_shop_data)
	_refresh_ui()


func _handle_shop_sell_requested(item_id: String, quantity: int) -> void:
	_sell_shop_item(item_id, quantity)
	if hud != null and hud.has_method("show_shop_panel"):
		hud.show_shop_panel(active_shop_data)
	_refresh_ui()


func _handle_dialogue_action_requested(npc_data: Dictionary) -> void:
	_advance_npc_quest(npc_data)
	_show_npc_dialogue(npc_data)
	_refresh_ui()


func _deposit_bank_item(item_id: String, requested_quantity: int) -> bool:
	if item_id.is_empty() or _inventory_count(item_id) <= 0:
		_feedback("Nothing to deposit")
		return false
	var quantity: int = _inventory_count(item_id) if requested_quantity <= 0 else min(requested_quantity, _inventory_count(item_id))
	if quantity <= 0:
		_feedback("Nothing to deposit")
		return false
	var removed := _remove_inventory_item(item_id, quantity)
	if removed <= 0:
		_feedback("Nothing to deposit")
		return false
	var bank := _bank()
	bank[item_id] = int(bank.get(item_id, 0)) + removed
	_record_quest_flag("used_bank")
	_feedback("Deposited %d %s" % [removed, _item_name(item_id)])
	return true


func _withdraw_bank_item(item_id: String, requested_quantity: int) -> bool:
	var bank_items := _bank()
	var available := int(bank_items.get(item_id, 0))
	if item_id.is_empty() or available <= 0:
		_feedback("Nothing to withdraw")
		return false
	var requested: int = available if requested_quantity <= 0 else min(requested_quantity, available)
	var quantity := _max_addable_quantity(item_id, requested)
	if quantity <= 0:
		_feedback("Inventory is full")
		return false
	bank_items[item_id] = available - quantity
	if int(bank_items[item_id]) <= 0:
		bank_items.erase(item_id)
	if not _add_inventory_item(item_id, quantity):
		bank_items[item_id] = int(bank_items.get(item_id, 0)) + quantity
		_feedback("Inventory is full")
		return false
	_record_quest_flag("used_bank")
	_feedback("Withdrew %d %s" % [quantity, _item_name(item_id)])
	return true


func _buy_shop_item(item_id: String, listed_price: int) -> bool:
	var price: int = listed_price if listed_price > 0 else _buy_price(item_id)
	if item_id.is_empty() or price <= 0:
		_feedback("Nothing to buy")
		return false
	if _inventory_count("coins") < price:
		_feedback("Not enough coins")
		return false
	if not _inventory_can_transact({"coins": price}, {item_id: 1}):
		_feedback("Inventory is full")
		return false
	_remove_inventory_item("coins", price)
	_add_inventory_item(item_id, 1)
	_record_quest_flag("used_shop")
	_feedback("Bought 1 %s for %d coins" % [_item_name(item_id), price])
	return true


func _sell_shop_item(item_id: String, requested_quantity: int) -> bool:
	if item_id.is_empty() or item_id == "coins" or _inventory_count(item_id) <= 0:
		_feedback("Nothing to sell")
		return false
	var price := _sell_price(item_id)
	if price <= 0:
		_feedback("%s cannot be sold" % _item_name(item_id))
		return false
	var quantity: int = _inventory_count(item_id) if requested_quantity <= 0 else min(requested_quantity, _inventory_count(item_id))
	if quantity <= 0:
		_feedback("Nothing to sell")
		return false
	var removed := _remove_inventory_item(item_id, quantity)
	if removed <= 0:
		_feedback("Nothing to sell")
		return false
	var coins := removed * price
	_add_inventory_item("coins", coins)
	_record_quest_flag("used_shop")
	_feedback("Sold %d %s for %d coins" % [removed, _item_name(item_id), coins])
	return true


func _use_item(item_id: String) -> bool:
	if _inventory_count(item_id) <= 0:
		_feedback("No %s" % _item_name(item_id))
		return false
	var definition = items_data.get(item_id, {})
	if not (definition is Dictionary):
		_feedback("Nothing happens")
		return false
	var heal_amount := int(definition.get("heal_amount", 0))
	var cleanses_poison := bool(definition.get("cleanses_poison", false))
	if heal_amount <= 0 and not cleanses_poison:
		_feedback("Nothing happens")
		return false
	var combat := _combat_state()
	var max_hitpoints := _skill_level("hitpoints")
	var current_hitpoints := int(combat.get("current_hitpoints", max_hitpoints))
	var can_heal := heal_amount > 0 and current_hitpoints < max_hitpoints
	var can_cleanse := cleanses_poison and _combat_is_poisoned()
	if not can_heal and not can_cleanse:
		_feedback("Already at full health")
		return false
	var healed: int = min(heal_amount, max_hitpoints - current_hitpoints) if can_heal else 0
	_remove_inventory_item(item_id, 1)
	if healed > 0:
		_combat_set_hitpoints(current_hitpoints + healed)
	if can_cleanse:
		_clear_combat_poison()
	_record_quest_flag("ate_food")
	var message := "Used %s" % _item_name(item_id)
	if healed > 0:
		message = "%s: healed %d HP" % [message, healed]
	if can_cleanse:
		message = "%s; poison cleared" % message
	_feedback(message)
	return true


func _talk_to_npc(npc_data: Dictionary) -> void:
	_show_npc_dialogue(npc_data)


func _show_npc_dialogue(npc_data: Dictionary) -> void:
	var quest_id := str(npc_data.get("quest_id", ""))
	var label := str(npc_data.get("label", npc_data.get("name", "NPC")))
	if quest_id.is_empty():
		var no_quest_message := "%s has nothing new for this shell." % label
		if hud != null and hud.has_method("show_dialogue_panel"):
			hud.show_dialogue_panel(npc_data, {}, {}, no_quest_message, "Close")
		_feedback(no_quest_message)
		return
	var definition := _quest_definition(quest_id)
	if definition.is_empty():
		var missing_message := "%s has nothing new for this shell." % label
		if hud != null and hud.has_method("show_dialogue_panel"):
			hud.show_dialogue_panel(npc_data, {}, {}, missing_message, "Close")
		_feedback(missing_message)
		return

	var root := _quest_root()
	root["active_quest_id"] = quest_id
	var quest_state := _quest_state_for(quest_id)
	var message := ""
	var action_label := "Close"
	if bool(quest_state.get("completed", false)):
		message = str(definition.get("completed_text", "%s has nothing new." % label))
	elif not bool(quest_state.get("started", false)):
		message = str(definition.get("start_text", "%s: Hello." % label))
		action_label = "Start"
	else:
		var missing := _missing_objectives(definition, quest_state)
		if missing.is_empty():
			if _can_apply_item_rewards(definition):
				message = str(definition.get("return_objective", "Ready to complete."))
				action_label = "Complete"
			else:
				message = "Inventory is full"
		else:
			var names: Array[String] = []
			for objective in missing:
				if objective is Dictionary:
					names.append(str(objective.get("label", "")).to_lower())
			var progress_text := str(definition.get("in_progress_text", "%s: Still needed: {missing_objectives}." % label))
			message = progress_text.replace("{missing_objectives}", ", ".join(names))
	_sync_quest_state(root)
	if hud != null and hud.has_method("show_dialogue_panel"):
		hud.show_dialogue_panel(npc_data, definition, quest_state.duplicate(true), message, action_label)
	_feedback(message)


func _advance_npc_quest(npc_data: Dictionary) -> void:
	var quest_id := str(npc_data.get("quest_id", ""))
	var label := str(npc_data.get("label", npc_data.get("name", "NPC")))
	if quest_id.is_empty():
		_feedback("%s has nothing new for this shell." % label)
		return
	var definition := _quest_definition(quest_id)
	if definition.is_empty():
		_feedback("%s has nothing new for this shell." % label)
		return
	var root := _quest_root()
	root["active_quest_id"] = quest_id
	var quest_state := _quest_state_for(quest_id)
	if bool(quest_state.get("completed", false)):
		_feedback(str(definition.get("completed_text", "%s has nothing new." % label)))
		_sync_quest_state(root)
		return
	if not bool(quest_state.get("started", false)):
		quest_state["started"] = true
		_feedback(str(definition.get("start_text", "%s: Hello." % label)))
		_sync_quest_state(root)
		return
	var missing := _missing_objectives(definition, quest_state)
	if not missing.is_empty():
		var names: Array[String] = []
		for objective in missing:
			if objective is Dictionary:
				names.append(str(objective.get("label", "")).to_lower())
		var progress_text := str(definition.get("in_progress_text", "%s: Still needed: {missing_objectives}." % label))
		_feedback(progress_text.replace("{missing_objectives}", ", ".join(names)))
		_sync_quest_state(root)
		return

	if not _can_apply_item_rewards(definition):
		_feedback("Inventory is full")
		_sync_quest_state(root)
		return
	if not _apply_quest_rewards(definition):
		_feedback("Inventory is full")
		_sync_quest_state(root)
		return
	quest_state["completed"] = true
	_feedback(str(definition.get("completion_text", "Quest complete: %s." % str(definition.get("display_name", quest_id)))))
	_sync_quest_state(root)


func _apply_quest_rewards(definition: Dictionary) -> bool:
	if not _can_apply_item_rewards(definition):
		return false
	var item_rewards = definition.get("item_rewards", [])
	if item_rewards is Array:
		for reward in item_rewards:
			if reward is Dictionary:
				if not _add_inventory_item(str(reward.get("item_id", "")), int(reward.get("quantity", 1))):
					return false
	var skill_rewards = definition.get("skill_rewards", [])
	if skill_rewards is Array:
		for reward in skill_rewards:
			if reward is Dictionary:
				_add_xp(str(reward.get("skill_id", "")), int(reward.get("xp", 0)))
	return true


func _record_gathering_quest_flags(skill_id: String, item_id: String) -> void:
	match skill_id:
		"woodcutting":
			_record_quest_flag("gathered_wood")
		"fishing":
			_record_quest_flag("caught_fish")
		"herbalism":
			_record_quest_flag("gathered_herb")
		"foraging":
			_record_quest_flag("gathered_%s" % item_id)
	if item_id in ["bog_reeds", "fen_reeds"]:
		_record_quest_flag("gathered_%s" % item_id)


func _required_tool_for_resource(object_data: Dictionary) -> Array:
	match str(object_data.get("action", "default")):
		"fish_net":
			return ["small_fishing_net", "small fishing net"]
		"fish_rod":
			return ["fishing_rod", "fishing rod"]
	var skill_id := str(object_data.get("skill_id", ""))
	return REQUIRED_TOOLS.get(skill_id, [])


func _record_processing_quest_flags(action_type: String, recipe_id: String, output_item: String) -> void:
	match action_type:
		"smelting":
			_record_quest_flag("smelted_bar")
		"smithing":
			_record_quest_flag("smithed_gear")
		"carpentry":
			_record_quest_flag("crafted_carpentry")
		"herbalism":
			_record_quest_flag("crafted_herbalism")
	var recipe_flags := {
		"plain_plank": "crafted_plank",
		"charcoal": "crafted_charcoal",
		"split_splinters": "crafted_splinters",
		"plain_tool_handle": "crafted_tool_handle",
		"training_bow": "crafted_training_bow",
		"training_staff": "crafted_training_staff",
		"mire_tonic": "crafted_mire_tonic",
		"fen_tonic": "crafted_fen_tonic",
	}
	if recipe_flags.has(recipe_id):
		_record_quest_flag(str(recipe_flags[recipe_id]))
	elif output_item in ["training_bow", "training_staff", "mire_tonic", "fen_tonic"]:
		_record_quest_flag("crafted_%s" % output_item)


func _record_combat_quest_flags(mob_id: String) -> void:
	_record_quest_flag("defeated_enemy")
	if mob_id.contains("wolf"):
		_record_quest_flag("defeated_wolf")
	if mob_id.contains("mire_bat"):
		_record_quest_flag("defeated_mire_bat")
	if mob_id.contains("fen_crawler"):
		_record_quest_flag("defeated_fen_crawler")


func _equip_item(item_id: String) -> bool:
	if _inventory_count(item_id) <= 0:
		_feedback("No %s" % _item_name(item_id))
		return false
	_remove_inventory_item(item_id, 1)
	var equipment := _equipment()
	equipment["weapon"] = item_id
	_record_quest_flag("equipped_weapon")
	if item_id in ["training_bow", "training_staff"]:
		_record_quest_flag("equipped_%s" % item_id)
	_feedback("Equipped %s" % _item_name(item_id))
	return true


func _record_quest_flag(flag: String) -> bool:
	if flag.is_empty():
		return false
	var root := _quest_root()
	var active_quest_id := str(root.get("active_quest_id", "starter_path"))
	var recorded := false
	for quest_id in _quest_definitions().keys():
		var definition := _quest_definition(str(quest_id))
		if not _definition_has_flag(definition, flag):
			continue
		var state_exists := _quest_states().has(str(quest_id))
		if not state_exists and str(quest_id) != active_quest_id:
			continue
		var quest_state := _quest_state_for(str(quest_id))
		if bool(quest_state.get("completed", false)):
			continue
		var flags := _quest_flags(quest_state)
		if not flags.has(flag):
			flags.append(flag)
			quest_state["flags"] = flags
			recorded = true
	if recorded:
		_sync_quest_state(root)
	return recorded


func _quest_root() -> Dictionary:
	var root = state.get("quest_state", {})
	if not (root is Dictionary) or not root.has("quests"):
		root = {"active_quest_id": "starter_path", "quests": {}}
	state["quest_state"] = root
	if not state.has("quest_progress") or not (state["quest_progress"] is Dictionary):
		state["quest_progress"] = {}
	return root


func _quest_states() -> Dictionary:
	var root := _quest_root()
	var quests = root.get("quests", {})
	if not (quests is Dictionary):
		quests = {}
		root["quests"] = quests
	return quests


func _quest_state_for(quest_id: String) -> Dictionary:
	var quests := _quest_states()
	if not quests.has(quest_id) or not (quests[quest_id] is Dictionary):
		quests[quest_id] = {"quest_id": quest_id, "started": false, "completed": false, "flags": []}
	return quests[quest_id]


func _quest_flags(quest_state: Dictionary) -> Array:
	var flags = quest_state.get("flags", [])
	if not (flags is Array):
		flags = []
	return flags


func _quest_started(quest_id: String) -> bool:
	return bool(_quest_state_for(quest_id).get("started", false))


func _quest_completed(quest_id: String) -> bool:
	return bool(_quest_state_for(quest_id).get("completed", false))


func _quest_has_flag(quest_id: String, flag: String) -> bool:
	return _quest_flags(_quest_state_for(quest_id)).has(flag)


func _quest_definition(quest_id: String) -> Dictionary:
	return _quest_definitions().get(quest_id, {})


func _quest_definitions() -> Dictionary:
	var definitions := {}
	var quests = quests_data.get("quests", [])
	if not (quests is Array):
		return definitions
	for quest in quests:
		if quest is Dictionary:
			definitions[str(quest.get("quest_id", ""))] = quest
	return definitions


func _definition_has_flag(definition: Dictionary, flag: String) -> bool:
	var objectives = definition.get("objectives", [])
	if not (objectives is Array):
		return false
	for objective in objectives:
		if objective is Dictionary and str(objective.get("flag", "")) == flag:
			return true
	return false


func _missing_objectives(definition: Dictionary, quest_state: Dictionary) -> Array:
	var missing := []
	var flags := _quest_flags(quest_state)
	var objectives = definition.get("objectives", [])
	if not (objectives is Array):
		return missing
	for objective in objectives:
		if objective is Dictionary and not flags.has(str(objective.get("flag", ""))):
			missing.append(objective)
	return missing


func _sync_quest_state(root: Dictionary) -> void:
	state["quest_state"] = root
	state["quest_progress"] = root.get("quests", {}).duplicate(true)
	var world_state := _world_state()
	world_state["quest_state"] = root.duplicate(true)


func _can_apply_item_rewards(definition: Dictionary) -> bool:
	var add_items := {}
	var item_rewards = definition.get("item_rewards", [])
	if item_rewards is Array:
		for reward in item_rewards:
			if reward is Dictionary:
				var item_id := str(reward.get("item_id", ""))
				add_items[item_id] = int(add_items.get(item_id, 0)) + int(reward.get("quantity", 1))
	return _inventory_can_transact({}, add_items)


func _bank() -> Dictionary:
	var bank = state.get("bank", {})
	if not (bank is Dictionary):
		bank = {}
		state["bank"] = bank
	return bank


func _equipment() -> Dictionary:
	var equipment = state.get("equipment", {})
	if not (equipment is Dictionary):
		equipment = {}
		state["equipment"] = equipment
	return equipment


func _first_depositable_item() -> String:
	for item_id in _inventory().keys():
		var deposit_item_id := str(item_id)
		if _inventory_count(deposit_item_id) > 0 and deposit_item_id != "coins":
			return deposit_item_id
	return ""


func _buy_price(item_id: String) -> int:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		return int(definition.get("buy_price", max(1, _sell_price(item_id) * 3)))
	return 0


func _sell_price(item_id: String) -> int:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		return int(definition.get("sell_price", 0))
	return 0


func _is_stackable_item(item_id: String) -> bool:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary and definition.has("stackable"):
		return bool(definition["stackable"])
	return item_id == "coins"


func _inventory_can_transact(remove_items: Dictionary, add_items: Dictionary) -> bool:
	var projected := _inventory().duplicate(true)
	for item_id in remove_items.keys():
		if str(item_id).is_empty():
			return false
		var remove_quantity := int(remove_items[item_id])
		if remove_quantity < 0:
			return false
		var remaining := int(projected.get(item_id, 0)) - remove_quantity
		if remaining < 0:
			return false
		if remaining > 0:
			projected[item_id] = remaining
		else:
			projected.erase(item_id)
	for item_id in add_items.keys():
		if str(item_id).is_empty():
			return false
		var add_quantity := int(add_items[item_id])
		if add_quantity < 0:
			return false
		if add_quantity == 0:
			continue
		if not _mapping_can_add(projected, str(item_id), add_quantity):
			return false
		projected[str(item_id)] = int(projected.get(str(item_id), 0)) + add_quantity
	return true


func _max_addable_quantity(item_id: String, desired_quantity: int) -> int:
	var quantity: int = max(0, desired_quantity)
	while quantity > 0 and not _mapping_can_add(_inventory(), item_id, quantity):
		quantity -= 1
	return quantity


func _mapping_can_add(mapping: Dictionary, item_id: String, quantity: int) -> bool:
	if quantity <= 0:
		return true
	if _is_stackable_item(item_id) and int(mapping.get(item_id, 0)) > 0:
		return true
	var extra_slots: int = 1 if _is_stackable_item(item_id) else quantity
	return _inventory_slot_count(mapping) + extra_slots <= INVENTORY_SLOT_LIMIT


func _inventory_slot_count(mapping: Dictionary) -> int:
	var count := 0
	for item_id in mapping.keys():
		var quantity := int(mapping[item_id])
		if quantity <= 0:
			continue
		count += 1 if _is_stackable_item(str(item_id)) else quantity
	return count


func _add_xp(skill_id: String, amount: int) -> String:
	if amount <= 0:
		return ""
	var skills := _skills()
	var values = skills.get(skill_id, {"xp": 0, "level": _starting_level(skill_id)})
	if not (values is Dictionary):
		values = {"xp": 0, "level": _starting_level(skill_id)}
	var previous_level := int(values.get("level", _starting_level(skill_id)))
	var xp := int(values.get("xp", 0)) + amount
	var new_level := _level_for_xp(skill_id, xp)
	values["xp"] = xp
	values["level"] = new_level
	skills[skill_id] = values
	if new_level > previous_level:
		return "%s level %d%s" % [_skill_name(skill_id), new_level, _unlock_suffix(skill_id, previous_level, new_level)]
	return ""


func _unlock_suffix(skill_id: String, previous_level: int, new_level: int) -> String:
	var definition = skills_data.get(skill_id, {})
	if not (definition is Dictionary):
		return ""
	var milestones = definition.get("milestones", [])
	if not (milestones is Array):
		return ""
	var unlocked: Array[String] = []
	for milestone in milestones:
		if milestone is Dictionary:
			var level := int(milestone.get("level", 0))
			if level > previous_level and level <= new_level:
				unlocked.append(str(milestone.get("label", "")))
	if unlocked.is_empty():
		return ""
	return ": unlocked %s" % ", ".join(unlocked)


func _level_for_xp(skill_id: String, xp: int) -> int:
	var definition = skills_data.get(skill_id, {})
	var starting := _starting_level(skill_id)
	if definition is Dictionary and definition.get("xp_thresholds", {}) is Dictionary:
		var level := 1
		var thresholds: Dictionary = definition["xp_thresholds"]
		for level_text in thresholds.keys():
			if xp >= int(thresholds[level_text]):
				level = max(level, int(level_text))
		return max(starting, level)
	return max(starting, 1 + int(xp / 100))


func _has_recipe_inputs(recipe: Dictionary) -> bool:
	var inputs = recipe.get("inputs", {})
	if not (inputs is Dictionary):
		return false
	for item_id in inputs.keys():
		if _inventory_count(str(item_id)) < int(inputs[item_id]):
			return false
	return true


func _inventory() -> Dictionary:
	var inventory = state.get("inventory", {})
	if not (inventory is Dictionary):
		inventory = {}
		state["inventory"] = inventory
	return inventory


func _skills() -> Dictionary:
	var skills = state.get("skills", {})
	if not (skills is Dictionary):
		skills = {}
		state["skills"] = skills
	return skills


func _combat_state() -> Dictionary:
	var combat = state.get("combat", {})
	if not (combat is Dictionary):
		combat = {"current_hitpoints": 10, "mobs": {}, "ground_items": [], "status_effects": {}}
		state["combat"] = combat
	if not combat.has("mobs"):
		combat["mobs"] = {}
	if not combat.has("ground_items"):
		combat["ground_items"] = []
	if not combat.has("status_effects"):
		combat["status_effects"] = {}
	if not combat.has("current_hitpoints"):
		combat["current_hitpoints"] = _skill_level("hitpoints")
	return combat


func _combat_status_effects() -> Dictionary:
	var combat := _combat_state()
	var status_effects = combat.get("status_effects", {})
	if not (status_effects is Dictionary):
		status_effects = {}
		combat["status_effects"] = status_effects
	return status_effects


func _combat_is_poisoned() -> bool:
	var poison = _combat_status_effects().get("poison", {})
	return poison is Dictionary and int(poison.get("rounds_remaining", 0)) > 0 and int(poison.get("damage", 0)) > 0


func _apply_poison_from_mob(object_data: Dictionary) -> void:
	var chance := float(object_data.get("poison_chance", 0.0))
	if chance <= 0.0:
		return
	var mob_id := str(object_data.get("id", object_data.get("mob_id", "mob")))
	if not _chance_succeeds("poison:%s" % mob_id, chance):
		return
	var damage: int = max(1, int(object_data.get("poison_damage", 1)))
	var rounds: int = max(1, int(object_data.get("poison_rounds", 1)))
	var status_effects := _combat_status_effects()
	var current = status_effects.get("poison", {})
	if current is Dictionary:
		damage = max(damage, int(current.get("damage", 0)))
		rounds = max(rounds, int(current.get("rounds_remaining", 0)))
	status_effects["poison"] = {"damage": damage, "rounds_remaining": rounds}
	_sync_world_combat_state()


func _tick_combat_status_effects() -> String:
	var status_effects := _combat_status_effects()
	var poison = status_effects.get("poison", {})
	if not (poison is Dictionary):
		return ""
	var rounds := int(poison.get("rounds_remaining", 0))
	var damage := int(poison.get("damage", 0))
	if rounds <= 0 or damage <= 0:
		status_effects.erase("poison")
		_sync_world_combat_state()
		return ""
	var combat := _combat_state()
	_combat_set_hitpoints(int(combat.get("current_hitpoints", _skill_level("hitpoints"))) - damage)
	rounds -= 1
	if rounds <= 0:
		status_effects.erase("poison")
	else:
		poison["rounds_remaining"] = rounds
		status_effects["poison"] = poison
	_sync_world_combat_state()
	return "poison dealt %d damage" % damage


func _clear_combat_poison() -> void:
	_combat_status_effects().erase("poison")
	_sync_world_combat_state()


func _inventory_count(item_id: String) -> int:
	return int(_inventory().get(item_id, 0))


func _skill_xp(skill_id: String) -> int:
	var values = _skills().get(skill_id, {})
	return int(values.get("xp", 0)) if values is Dictionary else 0


func _skill_level(skill_id: String) -> int:
	var values = _skills().get(skill_id, {})
	if values is Dictionary:
		return int(values.get("level", _starting_level(skill_id)))
	return _starting_level(skill_id)


func _add_inventory_item(item_id: String, quantity: int) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	if not _inventory_can_transact({}, {item_id: quantity}):
		return false
	var inventory := _inventory()
	inventory[item_id] = int(inventory.get(item_id, 0)) + quantity
	return true


func _remove_inventory_item(item_id: String, quantity: int) -> int:
	if item_id.is_empty() or quantity <= 0:
		return 0
	var inventory := _inventory()
	var removed: int = min(int(inventory.get(item_id, 0)), quantity)
	var remaining: int = int(inventory.get(item_id, 0)) - removed
	if remaining > 0:
		inventory[item_id] = remaining
	else:
		inventory.erase(item_id)
	return removed


func _resource_is_depleted(node_id: String) -> bool:
	var world_state := _world_state()
	var nodes = world_state.get("resource_nodes", {})
	if not (nodes is Dictionary) or not nodes.has(node_id):
		return false
	var node_state = nodes[node_id]
	if not (node_state is Dictionary) or not bool(node_state.get("depleted", false)):
		return false
	if node_state.has("respawn_at") and node_state["respawn_at"] != null:
		if _action_clock_seconds() >= float(node_state["respawn_at"]):
			nodes.erase(node_id)
			world_state["resource_nodes"] = nodes
			return false
	return true


func _mark_resource_depleted(node_id: String, respawn_seconds: float = 0.0) -> void:
	var world_state := _world_state()
	var nodes = world_state.get("resource_nodes", {})
	if not (nodes is Dictionary):
		nodes = {}
	var respawn_at = null
	if respawn_seconds > 0.0:
		respawn_at = _action_clock_seconds() + respawn_seconds
	nodes[node_id] = {"depleted": true, "respawn_at": respawn_at}
	world_state["resource_nodes"] = nodes


func _world_state() -> Dictionary:
	var world_state = state.get("world", {})
	if not (world_state is Dictionary):
		world_state = {}
		state["world"] = world_state
	return world_state


func _action_clock_seconds() -> float:
	var world_state := _world_state()
	var value := float(world_state.get("action_clock_seconds", 0.0))
	world_state["action_clock_seconds"] = value
	return value


func _advance_action_clock(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var world_state := _world_state()
	world_state["action_clock_seconds"] = _action_clock_seconds() + seconds


func _action_cooldowns() -> Dictionary:
	var world_state := _world_state()
	var cooldowns = world_state.get("action_cooldowns", {})
	if not (cooldowns is Dictionary):
		cooldowns = {}
		world_state["action_cooldowns"] = cooldowns
	return cooldowns


func _action_is_ready(action_key: String) -> bool:
	var cooldowns := _action_cooldowns()
	if not cooldowns.has(action_key):
		return true
	var ready_at := float(cooldowns[action_key])
	if _action_clock_seconds() >= ready_at:
		cooldowns.erase(action_key)
		return true
	return false


func _start_action_cooldown(action_key: String, seconds: float) -> void:
	if action_key.is_empty() or seconds <= 0.0:
		return
	_action_cooldowns()[action_key] = _action_clock_seconds() + seconds


func _chance_succeeds(action_key: String, chance: float) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	var seed := action_key.hash() + int(_action_clock_seconds() * 1000.0)
	return float(abs(seed) % 10000) / 10000.0 < chance


func _combat_set_hitpoints(value: int) -> void:
	var combat := _combat_state()
	combat["current_hitpoints"] = max(0, min(value, _skill_level("hitpoints")))
	_sync_world_combat_state()


func _sync_world_combat_state() -> void:
	var combat := _combat_state()
	var world_state := _world_state()
	var world_combat = world_state.get("combat", {})
	if not (world_combat is Dictionary):
		world_combat = {}
	world_combat["current_hitpoints"] = combat["current_hitpoints"]
	world_combat["status_effects"] = _combat_status_effects().duplicate(true)
	world_state["combat"] = world_combat


func _ensure_state_shape() -> void:
	if not state.has("inventory"):
		state["inventory"] = {}
	if not state.has("bank"):
		state["bank"] = {}
	if not state.has("equipment"):
		state["equipment"] = {}
	if not state.has("skills"):
		state["skills"] = {}
	if not state.has("combat_training_style"):
		state["combat_training_style"] = "attack"
	if not state.has("world"):
		state["world"] = {}
	if not state.has("quest_state") or not (state["quest_state"] is Dictionary) or not state["quest_state"].has("quests"):
		state["quest_state"] = {"active_quest_id": "starter_path", "quests": {}}
	if not state.has("quest_progress") or not (state["quest_progress"] is Dictionary):
		state["quest_progress"] = {}
	_combat_state()


func _refresh_ui() -> void:
	if hud != null and hud.has_method("refresh_state"):
		hud.refresh_state()


func _interaction_panel_matches(expected_title: String) -> bool:
	if hud == null or not hud.has_method("interaction_panel_is_visible") or not hud.has_method("interaction_panel_title_text") or not hud.has_method("interaction_panel_row_count"):
		return false
	return bool(hud.call("interaction_panel_is_visible")) and str(hud.call("interaction_panel_title_text")) == expected_title and int(hud.call("interaction_panel_row_count")) > 0


func _feedback(message: String) -> void:
	if hud != null and hud.has_method("set_feedback"):
		hud.set_feedback(message)


func _load_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}


func _item_name(item_id: String) -> String:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		return str(definition.get("name", _display_label(item_id)))
	return _display_label(item_id)


func _skill_name(skill_id: String) -> String:
	var definition = skills_data.get(skill_id, {})
	if definition is Dictionary:
		return str(definition.get("display_name", _display_label(skill_id)))
	return _display_label(skill_id)


func _starting_level(skill_id: String) -> int:
	var definition = skills_data.get(skill_id, {})
	if definition is Dictionary:
		return int(definition.get("starting_level", 10 if skill_id == "hitpoints" else 1))
	return 10 if skill_id == "hitpoints" else 1


func _damage_skill(style: String) -> String:
	if style in ["ranged", "magic"]:
		return style
	return "strength"


func _done_verb(action_type: String) -> String:
	return {
		"smelting": "Smelted",
		"smithing": "Smithed",
		"carpentry": "Crafted",
		"herbalism": "Brewed",
	}.get(action_type, "Processed")


func _select_feedback(action_type: String) -> String:
	return {
		"smelting": "Select ore to smelt",
		"smithing": "Select bars to smith",
		"carpentry": "Select wood to craft",
		"herbalism": "Select herbs to brew",
	}.get(action_type, "Select materials first")


func _display_label(value: String) -> String:
	return value.replace("_", " ").capitalize()
