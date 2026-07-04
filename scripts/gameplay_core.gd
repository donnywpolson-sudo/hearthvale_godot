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

var state := {}
var world: Node
var hud: CanvasLayer
var items_data := {}
var skills_data := {}
var recipes_data := {}
var quests_data := {}
var ground_drop_counter := 0


func setup(initial_state: Dictionary, world_node: Node, hud_node: CanvasLayer) -> void:
	state = initial_state
	world = world_node
	hud = hud_node
	items_data = _load_json(ITEMS_PATH)
	skills_data = _load_json(SKILLS_PATH)
	recipes_data = _load_json(RECIPES_PATH)
	quests_data = _load_json(QUESTS_PATH)
	_ensure_state_shape()


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
	var road_guard := {"quest_id": "road_patrol", "label": "Road Guard"}
	_talk_to_npc(road_guard)
	if not _quest_started("road_patrol"):
		return false
	_open_shop({"stock": [{"item_id": "trail_ration", "price": 3}]})
	if not _quest_has_flag("road_patrol", "used_shop"):
		return false
	_equip_item("bronze_sword")
	if not _quest_has_flag("road_patrol", "equipped_weapon"):
		return false
	_record_quest_flag("defeated_enemy")
	_open_bank()
	if not _quest_has_flag("road_patrol", "used_bank"):
		return false
	var coins_before_reward := _inventory_count("coins")
	_talk_to_npc(road_guard)
	return _quest_completed("road_patrol") and _inventory_count("coins") >= coins_before_reward + 24 and _skill_xp("attack") >= 20 and _bank().size() > 0


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

	_add_inventory_item(item_id, quantity)
	var level_message := _add_xp(skill_id, xp)
	_mark_resource_depleted(node_id)
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
		_remove_inventory_item(str(item_id), 1)
		_add_inventory_item(cooked_item, 1)
		var xp := int(definition.get("cooking_xp", 0))
		var level_message := _add_xp("cooking", xp)
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
		for input_id in recipe.get("inputs", {}).keys():
			_remove_inventory_item(str(input_id), int(recipe["inputs"][input_id]))
		var output_item := str(recipe.get("output_item_id", ""))
		var output_quantity := int(recipe.get("output_quantity", 1))
		_add_inventory_item(output_item, output_quantity)
		var xp := int(recipe.get("xp_reward", 0))
		var level_message := _add_xp(skill_id, xp)
		_record_processing_quest_flags(action_type, str(recipe.get("recipe_id", "")), output_item)
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

	if remaining <= 0:
		mobs[mob_id] = {"hitpoints": 0, "dead": true}
		combat["mobs"] = mobs
		_spawn_drops(object_data)
		_record_combat_quest_flags(mob_id)
		_feedback("Defeated %s; drops appeared; you: %d/%d HP" % [label, int(combat.get("current_hitpoints", 10)), _skill_level("hitpoints")])
		return

	mobs[mob_id] = {"hitpoints": remaining, "dead": false}
	combat["mobs"] = mobs
	_feedback("Hit %s: %d/%d HP left; you: %d/%d HP" % [label, remaining, max_hp, int(combat.get("current_hitpoints", 10)), _skill_level("hitpoints")])


func _pick_up_drop(object_data: Dictionary) -> void:
	var item_id := str(object_data.get("item_id", ""))
	var quantity := int(object_data.get("quantity", 1))
	if item_id.is_empty() or quantity <= 0:
		_feedback("Nothing to take")
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
	var item_id := _first_depositable_item()
	if not item_id.is_empty():
		var quantity := _inventory_count(item_id)
		var removed := _remove_inventory_item(item_id, quantity)
		if removed > 0:
			var bank := _bank()
			bank[item_id] = int(bank.get(item_id, 0)) + removed
			_record_quest_flag("used_bank")
			_feedback("Deposited %d %s" % [removed, _item_name(item_id)])
			return

	var bank_items := _bank()
	for bank_item_id in bank_items.keys():
		var withdraw_item_id := str(bank_item_id)
		var available := int(bank_items[bank_item_id])
		if available <= 0:
			continue
		var quantity_to_withdraw := _max_addable_quantity(withdraw_item_id, available)
		if quantity_to_withdraw <= 0:
			continue
		bank_items[withdraw_item_id] = available - quantity_to_withdraw
		if int(bank_items[withdraw_item_id]) <= 0:
			bank_items.erase(withdraw_item_id)
		_add_inventory_item(withdraw_item_id, quantity_to_withdraw)
		_record_quest_flag("used_bank")
		_feedback("Withdrew %d %s" % [quantity_to_withdraw, _item_name(withdraw_item_id)])
		return

	_record_quest_flag("used_bank")
	_feedback("Bank opened")


func _open_shop(shop_data: Dictionary = {}) -> void:
	var stock = shop_data.get("stock", [])
	if not (stock is Array):
		stock = []
	for raw_stock_item in stock:
		if not (raw_stock_item is Dictionary):
			continue
		var item_id := str(raw_stock_item.get("item_id", ""))
		var price := int(raw_stock_item.get("price", _buy_price(item_id)))
		if item_id.is_empty() or price <= 0:
			continue
		if _inventory_count("coins") < price:
			continue
		if not _inventory_can_transact({"coins": price}, {item_id: 1}):
			continue
		_remove_inventory_item("coins", price)
		_add_inventory_item(item_id, 1)
		_record_quest_flag("used_shop")
		_feedback("Bought 1 %s for %d coins" % [_item_name(item_id), price])
		return

	for item_id in _inventory().keys():
		var sell_item_id := str(item_id)
		if sell_item_id == "coins":
			continue
		var price := _sell_price(sell_item_id)
		if price <= 0:
			continue
		var quantity := _inventory_count(sell_item_id)
		var removed := _remove_inventory_item(sell_item_id, quantity)
		if removed <= 0:
			continue
		var coins := removed * price
		_add_inventory_item("coins", coins)
		_record_quest_flag("used_shop")
		_feedback("Sold %d %s for %d coins" % [removed, _item_name(sell_item_id), coins])
		return

	_record_quest_flag("used_shop")
	_feedback("Shop opened")


func _talk_to_npc(npc_data: Dictionary) -> void:
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
	quest_state["completed"] = true
	_apply_quest_rewards(definition)
	_feedback(str(definition.get("completion_text", "Quest complete: %s." % str(definition.get("display_name", quest_id)))))
	_sync_quest_state(root)


func _apply_quest_rewards(definition: Dictionary) -> void:
	var item_rewards = definition.get("item_rewards", [])
	if item_rewards is Array:
		for reward in item_rewards:
			if reward is Dictionary:
				_add_inventory_item(str(reward.get("item_id", "")), int(reward.get("quantity", 1)))
	var skill_rewards = definition.get("skill_rewards", [])
	if skill_rewards is Array:
		for reward in skill_rewards:
			if reward is Dictionary:
				_add_xp(str(reward.get("skill_id", "")), int(reward.get("xp", 0)))


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
		var remove_quantity := int(remove_items[item_id])
		var remaining := int(projected.get(item_id, 0)) - remove_quantity
		if remaining < 0:
			return false
		if remaining > 0:
			projected[item_id] = remaining
		else:
			projected.erase(item_id)
	for item_id in add_items.keys():
		var add_quantity := int(add_items[item_id])
		if add_quantity <= 0:
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


func _add_inventory_item(item_id: String, quantity: int) -> void:
	var inventory := _inventory()
	inventory[item_id] = int(inventory.get(item_id, 0)) + quantity


func _remove_inventory_item(item_id: String, quantity: int) -> int:
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
	return nodes is Dictionary and nodes.has(node_id) and bool(nodes[node_id].get("depleted", false))


func _mark_resource_depleted(node_id: String) -> void:
	var world_state := _world_state()
	var nodes = world_state.get("resource_nodes", {})
	if not (nodes is Dictionary):
		nodes = {}
	nodes[node_id] = {"depleted": true, "respawn_at": null}
	world_state["resource_nodes"] = nodes


func _world_state() -> Dictionary:
	var world_state = state.get("world", {})
	if not (world_state is Dictionary):
		world_state = {}
		state["world"] = world_state
	return world_state


func _combat_set_hitpoints(value: int) -> void:
	var combat := _combat_state()
	combat["current_hitpoints"] = max(0, min(value, _skill_level("hitpoints")))
	var world_state := _world_state()
	var world_combat = world_state.get("combat", {})
	if not (world_combat is Dictionary):
		world_combat = {}
	world_combat["current_hitpoints"] = combat["current_hitpoints"]
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
