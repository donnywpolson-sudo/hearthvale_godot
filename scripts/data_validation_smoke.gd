extends SceneTree

const ITEMS_PATH := "res://data/items.json"
const SKILLS_PATH := "res://data/skills.json"
const RECIPES_PATH := "res://data/recipes.json"
const WORLD_PATH := "res://data/world.json"
const QUESTS_PATH := "res://data/quests.json"
const MANIFEST_PATH := "res://assets/asset_manifest.json"

const ACTIVE_SKILLS := {
	"woodcutting": true,
	"mining": true,
	"fishing": true,
	"foraging": true,
	"herbalism": true,
	"cooking": true,
	"attack": true,
	"strength": true,
	"defence": true,
	"ranged": true,
	"magic": true,
	"hitpoints": true,
	"smithing": true,
	"carpentry": true,
}
const VALID_ITEM_CATEGORIES := {
	"armor": true,
	"bar": true,
	"currency": true,
	"fish": true,
	"misc": true,
	"ore": true,
	"tool": true,
	"weapon": true,
	"wood": true,
}
const PROCESSING_ACTIONS := {
	"smelting": "smithing",
	"smithing": "smithing",
	"carpentry": "carpentry",
	"herbalism": "herbalism",
}
const STATION_KEYS := ["bank", "shop", "cooking_range", "furnace", "anvil", "carpentry_bench", "apothecary_table"]
const REQUIRED_AUDIO := {
	"ambient": true,
	"coin_jingle": true,
	"combat_hit": true,
	"combat_miss": true,
	"craft_shimmer": true,
	"gather_thud": true,
	"level_up": true,
	"quest_complete": true,
	"ui_click": true,
}
const MANIFEST_CATEGORIES := {
	"items": {"prefix": "icons/items/", "extensions": [".png"]},
	"skills": {"prefix": "icons/skills/", "extensions": [".png"]},
	"ui": {"prefix": "icons/ui/", "extensions": [".png"]},
	"effects": {"prefix": "sprites/effects/", "extensions": [".png"]},
	"audio": {"prefix": "audio/", "extensions": [".flac", ".mp3", ".ogg", ".wav"]},
}
const OPTIONAL_MANIFEST_CATEGORIES := {
	"models": {"prefix": "models/", "extensions": [".glb", ".gltf"]},
}
const PROTECTED_TERMS := ["runescape", "osrs", "stardew", "runite", "rune"]
const ISSUE_PRINT_LIMIT := 80

var issues: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := {
		"items": _load_required_json(ITEMS_PATH),
		"skills": _load_required_json(SKILLS_PATH),
		"recipes": _load_required_json(RECIPES_PATH),
		"world": _load_required_json(WORLD_PATH),
		"quests": _load_required_json(QUESTS_PATH),
		"manifest": _load_required_json(MANIFEST_PATH),
	}
	if not issues.is_empty():
		_fail()
		return

	var items: Dictionary = data["items"]
	var skills: Dictionary = data["skills"]
	var recipes: Dictionary = data["recipes"]
	var world: Dictionary = data["world"]
	var quests: Dictionary = data["quests"]
	var manifest: Dictionary = data["manifest"]
	var quest_ids := _quest_ids(quests)

	_validate_items(items, skills)
	_validate_skills(skills)
	_validate_recipes(recipes, items, skills)
	_validate_quests(quests, items, skills)
	_validate_world(world, items, skills, quest_ids)
	_validate_manifest(manifest, items, skills)
	_validate_originality_sources({
		"items.json": items,
		"skills.json": skills,
		"recipes.json": recipes,
		"world.json": world,
		"quests.json": quests,
		"asset_manifest.json": manifest,
	})

	if issues.is_empty():
		print("Hearthvale data validation smoke passed.")
		quit(0)
	else:
		_fail()


func _fail() -> void:
	push_error("Hearthvale data validation smoke failed with %d issue(s)." % issues.size())
	for index in range(min(issues.size(), ISSUE_PRINT_LIMIT)):
		push_error(issues[index])
	if issues.size() > ISSUE_PRINT_LIMIT:
		push_error("... %d more issue(s) omitted." % (issues.size() - ISSUE_PRINT_LIMIT))
	quit(1)


func _load_required_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_issue(path, "missing required file")
		return {}
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		_issue(path, "must contain a valid top-level JSON object")
		return {}
	return parsed


func _validate_items(items: Dictionary, skills: Dictionary) -> void:
	if items.is_empty():
		_issue("items.json", "must contain at least one item")
	for item_id in items.keys():
		var source := "items.json:%s" % item_id
		if not _is_non_empty_string(item_id):
			_issue("items.json", "item IDs must be non-empty strings")
			continue
		var definition = items[item_id]
		if not (definition is Dictionary):
			_issue(source, "definition must be an object")
			continue
		_require_string(definition, "name", source)
		_validate_icon_key(definition.get("icon", ""), source, true)
		var category := str(definition.get("category", ""))
		if not VALID_ITEM_CATEGORIES.has(category):
			_issue(source, "'category' must be one of: %s" % _sorted_keys_text(VALID_ITEM_CATEGORIES))
		if not definition.has("sell_price"):
			_issue(source, "missing required integer 'sell_price'")
		elif not _is_non_negative_int(definition["sell_price"]):
			_issue(source, "'sell_price' must be a non-negative integer")
		elif category != "currency" and int(definition["sell_price"]) <= 0:
			_issue(source, "'sell_price' must be a positive integer for non-currency items")
		if not definition.has("stackable"):
			_issue(source, "missing required boolean 'stackable'")
		elif typeof(definition["stackable"]) != TYPE_BOOL:
			_issue(source, "'stackable' must be a boolean")
		if definition.has("buy_price") and not _is_positive_int(definition["buy_price"]):
			_issue(source, "'buy_price' must be a positive integer")
		if definition.has("buy_price") and _is_positive_int(definition["buy_price"]) and definition.has("sell_price") and _is_non_negative_int(definition["sell_price"]) and int(definition["buy_price"]) < int(definition["sell_price"]):
			_issue(source, "'buy_price' must not be below 'sell_price'")
		if definition.has("heal_amount") and not _is_positive_int(definition["heal_amount"]):
			_issue(source, "'heal_amount' must be a positive integer")
		if definition.has("tool_for"):
			var tool_for := str(definition["tool_for"])
			if tool_for.is_empty() or not skills.has(tool_for):
				_issue(source, "unknown tool_for skill '%s'" % tool_for)
		for bonus_key in ["attack_bonus", "strength_bonus", "defence_bonus", "ranged_bonus", "magic_bonus"]:
			if definition.has(bonus_key) and not _is_non_negative_int(definition[bonus_key]):
				_issue(source, "'%s' must be a non-negative integer" % bonus_key)
		if definition.has("equip_slot") and not ["weapon", "shield"].has(str(definition["equip_slot"])):
			_issue(source, "'equip_slot' must be one of: shield, weapon")
		_validate_required_skills(definition, skills, source)
		_validate_consumable_effect(definition, source)
		_validate_cooking_fields(definition, items, source)


func _validate_required_skills(definition: Dictionary, skills: Dictionary, source: String) -> void:
	if not definition.has("required_skills"):
		return
	var requirements = definition["required_skills"]
	if not (requirements is Dictionary) or requirements.is_empty():
		_issue(source, "'required_skills' must be a non-empty object")
		return
	var allowed := _allowed_equipment_requirement_skills(definition)
	for skill_id in requirements.keys():
		if not _is_non_empty_string(skill_id):
			_issue(source, "required skill IDs must be non-empty strings")
			continue
		if not skills.has(skill_id):
			_issue(source, "unknown required skill '%s'" % skill_id)
		if not _is_level(requirements[skill_id]):
			_issue(source, "required skill levels must be between 1 and 99")
		if not allowed.is_empty() and not allowed.has(str(skill_id)):
			_issue(source, "equipment requirement must use only %s" % ", ".join(allowed))


func _allowed_equipment_requirement_skills(definition: Dictionary) -> Array[String]:
	var equip_slot := str(definition.get("equip_slot", ""))
	var category := str(definition.get("category", ""))
	if equip_slot == "shield" or category == "armor":
		return ["defence"]
	if equip_slot != "weapon":
		return []
	if _positive_int_value(definition.get("ranged_bonus", 0)):
		return ["ranged"]
	if _positive_int_value(definition.get("magic_bonus", 0)):
		return ["magic"]
	return ["attack"]


func _validate_consumable_effect(definition: Dictionary, source: String) -> void:
	var bonus_keys := ["attack_bonus", "strength_bonus", "defence_bonus", "ranged_bonus", "magic_bonus"]
	var has_effect := definition.has("effect_duration_seconds") or definition.has("action_speed_bonus") or definition.has("cleanses_poison")
	var has_bonus_effect := not definition.has("equip_slot")
	if has_bonus_effect:
		var found_bonus := false
		for key in bonus_keys:
			if definition.has(key):
				found_bonus = true
				break
		has_bonus_effect = found_bonus
	if not has_effect and not has_bonus_effect:
		return
	if not _is_positive_number(definition.get("effect_duration_seconds", null)):
		_issue(source, "'effect_duration_seconds' must be a positive number")
	if definition.has("action_speed_bonus") and not _is_non_negative_number(definition["action_speed_bonus"]):
		_issue(source, "'action_speed_bonus' must be a non-negative number")
	if definition.has("cleanses_poison") and typeof(definition["cleanses_poison"]) != TYPE_BOOL:
		_issue(source, "'cleanses_poison' must be a boolean")


func _validate_cooking_fields(definition: Dictionary, items: Dictionary, source: String) -> void:
	var cooking_keys := ["cook_result", "cooking_required_level", "cooking_xp", "base_cook_seconds"]
	var present := 0
	for key in cooking_keys:
		if definition.has(key):
			present += 1
	if present == 0:
		return
	if present != cooking_keys.size():
		_issue(source, "cooking items must include cook_result, cooking_required_level, cooking_xp, and base_cook_seconds")
		return
	var cook_result := str(definition.get("cook_result", ""))
	if cook_result.is_empty() or not items.has(cook_result):
		_issue(source, "unknown cook_result '%s'" % cook_result)
	elif not (items[cook_result] is Dictionary) or str(items[cook_result].get("category", "")) != "fish":
		_issue(source, "'cook_result' must refer to a fish item")
	if str(definition.get("category", "")) != "fish":
		_issue(source, "cookable items must use category 'fish'")
	if not _is_level(definition["cooking_required_level"]):
		_issue(source, "'cooking_required_level' must be between 1 and 99")
	if not _is_positive_int(definition["cooking_xp"]):
		_issue(source, "'cooking_xp' must be a positive integer")
	if not _is_positive_number(definition["base_cook_seconds"]):
		_issue(source, "'base_cook_seconds' must be a positive number")


func _validate_skills(skills: Dictionary) -> void:
	for skill_id in ACTIVE_SKILLS.keys():
		if not skills.has(skill_id):
			_issue("skills.json", "missing required skill '%s'" % skill_id)
	for skill_id in skills.keys():
		var source := "skills.json:%s" % skill_id
		var definition = skills[skill_id]
		if not (definition is Dictionary):
			_issue(source, "definition must be an object")
			continue
		_require_string(definition, "display_name", source)
		_validate_icon_key(definition.get("icon", ""), source, true)
		if not _is_level(definition.get("starting_level", null)):
			_issue(source, "'starting_level' must be between 1 and 99")
		if definition.has("xp_thresholds"):
			_validate_xp_thresholds(definition["xp_thresholds"], source)
		else:
			_issue(source, "missing required object 'xp_thresholds'")
		_validate_milestones(definition.get("milestones", null), source)


func _validate_xp_thresholds(thresholds, source: String) -> void:
	if not (thresholds is Dictionary):
		_issue(source, "'xp_thresholds' must be an object")
		return
	if not thresholds.has("1") or int(thresholds.get("1", -1)) != 0:
		_issue(source, "'xp_thresholds' must include level 1 at 0 XP")
	var previous_xp := -1
	for level in range(1, 100):
		var key := str(level)
		if not thresholds.has(key):
			_issue(source, "'xp_thresholds' missing level %d" % level)
			continue
		if not _is_non_negative_int(thresholds[key]):
			_issue(source, "'xp_thresholds.%s' must be a non-negative integer" % key)
			continue
		var current_xp := int(thresholds[key])
		if previous_xp > current_xp:
			_issue(source, "'xp_thresholds.%s' must not be lower than the previous level threshold" % key)
		previous_xp = current_xp


func _validate_milestones(milestones, source: String) -> void:
	if not (milestones is Array):
		_issue(source, "'milestones' must be a list")
		return
	var seen_levels := {}
	for index in range(milestones.size()):
		var milestone = milestones[index]
		var milestone_source := "%s.milestones[%d]" % [source, index]
		if not (milestone is Dictionary):
			_issue(milestone_source, "milestone must be an object")
			continue
		if not _is_level(milestone.get("level", null)):
			_issue(milestone_source, "'level' must be between 1 and 99")
		else:
			var level := int(milestone["level"])
			if seen_levels.has(level):
				_issue(milestone_source, "duplicate milestone level %d" % level)
			seen_levels[level] = true
		_require_string(milestone, "label", milestone_source)


func _validate_recipes(recipes: Dictionary, items: Dictionary, skills: Dictionary) -> void:
	var seen_global := {}
	for action_type in PROCESSING_ACTIONS.keys():
		var skill_id: String = PROCESSING_ACTIONS[action_type]
		if not skills.has(skill_id):
			_issue("recipes.json:%s" % action_type, "requires missing skill '%s'" % skill_id)
		var raw_recipes = recipes.get(action_type, [])
		if not (raw_recipes is Array):
			_issue("recipes.json:%s" % action_type, "must be a list")
			continue
		var seen := {}
		for index in range(raw_recipes.size()):
			var recipe = raw_recipes[index]
			var source := "recipes.json:%s[%d]" % [action_type, index]
			if not (recipe is Dictionary):
				_issue(source, "recipe must be an object")
				continue
			var required := ["recipe_id", "inputs", "output_item_id", "required_level", "xp_reward", "base_seconds"]
			for key in required:
				if not recipe.has(key):
					_issue(source, "missing required key '%s'" % key)
			if not recipe.has("recipe_id"):
				continue
			var recipe_id := str(recipe["recipe_id"])
			if recipe_id.is_empty():
				_issue(source, "'recipe_id' must be a non-empty string")
			elif seen.has(recipe_id):
				_issue(source, "duplicate recipe ID '%s'" % recipe_id)
			elif seen_global.has(recipe_id):
				_issue(source, "duplicate recipe ID '%s' across recipe groups" % recipe_id)
			seen[recipe_id] = true
			seen_global[recipe_id] = true
			var inputs = recipe.get("inputs", {})
			if not (inputs is Dictionary) or inputs.is_empty():
				_issue(source, "'inputs' must be a non-empty object")
			else:
				for item_id in inputs.keys():
					if not items.has(item_id):
						_issue(source, "unknown input item '%s'" % item_id)
					if not _is_positive_int(inputs[item_id]):
						_issue(source, "input quantities must be positive integers")
			var output_item_id := str(recipe.get("output_item_id", ""))
			if output_item_id.is_empty() or not items.has(output_item_id):
				_issue(source, "unknown output_item_id '%s'" % output_item_id)
			if recipe.has("output_quantity") and not _is_positive_int(recipe["output_quantity"]):
				_issue(source, "'output_quantity' must be a positive integer")
			if recipe.has("required_level") and not _is_level(recipe["required_level"]):
				_issue(source, "'required_level' must be between 1 and 99")
			if recipe.has("xp_reward") and not _is_positive_int(recipe["xp_reward"]):
				_issue(source, "'xp_reward' must be a positive integer")
			if recipe.has("base_seconds") and not _is_positive_number(recipe["base_seconds"]):
				_issue(source, "'base_seconds' must be a positive number")


func _validate_quests(quests: Dictionary, items: Dictionary, skills: Dictionary) -> void:
	var raw_quests = quests.get("quests", null)
	if not (raw_quests is Array) or raw_quests.is_empty():
		_issue("quests.json:quests", "must be a non-empty list")
		return
	var seen := {}
	var required_strings := [
		"quest_id",
		"display_name",
		"start_text",
		"in_progress_text",
		"completed_text",
		"completion_text",
		"not_started_objective",
		"return_objective",
		"completed_objective",
		"progress_format",
	]
	for index in range(raw_quests.size()):
		var quest = raw_quests[index]
		var source := "quests.json:quests[%d]" % index
		if not (quest is Dictionary):
			_issue(source, "quest must be an object")
			continue
		for key in required_strings:
			_require_string(quest, key, source)
		var quest_id := str(quest.get("quest_id", ""))
		if not quest_id.is_empty():
			if seen.has(quest_id):
				_issue(source, "duplicate quest ID '%s'" % quest_id)
			seen[quest_id] = true
		var objectives = quest.get("objectives", [])
		if not (objectives is Array) or objectives.is_empty():
			_issue(source, "'objectives' must be a non-empty list")
		else:
			var seen_flags := {}
			for objective_index in range(objectives.size()):
				var objective = objectives[objective_index]
				var objective_source := "%s.objectives[%d]" % [source, objective_index]
				if not (objective is Dictionary):
					_issue(objective_source, "objective must be an object")
					continue
				_require_string(objective, "flag", objective_source)
				_require_string(objective, "label", objective_source)
				var flag := str(objective.get("flag", ""))
				if not flag.is_empty():
					if seen_flags.has(flag):
						_issue(objective_source, "duplicate objective flag '%s'" % flag)
					seen_flags[flag] = true
		_validate_quest_item_rewards(quest.get("item_rewards", []), items, source)
		_validate_quest_skill_rewards(quest.get("skill_rewards", []), skills, source)


func _validate_quest_item_rewards(rewards, items: Dictionary, source: String) -> void:
	if not (rewards is Array):
		_issue("%s.item_rewards" % source, "must be a list")
		return
	for index in range(rewards.size()):
		var reward = rewards[index]
		var reward_source := "%s.item_rewards[%d]" % [source, index]
		if not (reward is Dictionary):
			_issue(reward_source, "item reward must be an object")
			continue
		var item_id := str(reward.get("item_id", ""))
		if item_id.is_empty() or not items.has(item_id):
			_issue(reward_source, "unknown item_id '%s'" % item_id)
		if not _is_positive_int(reward.get("quantity", null)):
			_issue(reward_source, "'quantity' must be a positive integer")


func _validate_quest_skill_rewards(rewards, skills: Dictionary, source: String) -> void:
	if not (rewards is Array):
		_issue("%s.skill_rewards" % source, "must be a list")
		return
	for index in range(rewards.size()):
		var reward = rewards[index]
		var reward_source := "%s.skill_rewards[%d]" % [source, index]
		if not (reward is Dictionary):
			_issue(reward_source, "skill reward must be an object")
			continue
		var skill_id := str(reward.get("skill_id", ""))
		if skill_id.is_empty() or not skills.has(skill_id):
			_issue(reward_source, "unknown skill_id '%s'" % skill_id)
		if not _is_positive_int(reward.get("xp", null)):
			_issue(reward_source, "'xp' must be a positive integer")


func _validate_world(world: Dictionary, items: Dictionary, skills: Dictionary, quest_ids: Dictionary) -> void:
	var width = world.get("width", null)
	var height = world.get("height", null)
	if not _is_positive_int(width):
		_issue("world.json:width", "must be a positive integer")
	if not _is_positive_int(height):
		_issue("world.json:height", "must be a positive integer")
	if not _is_positive_int(width) or not _is_positive_int(height):
		return
	var width_int := int(width)
	var height_int := int(height)
	var player_start: Variant = _tile(world.get("player_start", null), "world.json:player_start", width_int, height_int)
	var blocked_tiles := _tile_set(world.get("blocked_tiles", []), "world.json:blocked_tiles", width_int, height_int)
	for tile_key in _tile_set(world.get("water_tiles", []), "world.json:water_tiles", width_int, height_int).keys():
		blocked_tiles[tile_key] = true
	var seen_ids := {}
	var resource_positions := _validate_resource_nodes(world.get("resource_nodes", []), items, skills, width_int, height_int, blocked_tiles, player_start, seen_ids)
	var world_object_positions := {}
	for key in STATION_KEYS:
		if key == "shop":
			_validate_shop(world.get(key, null), items, width_int, height_int, blocked_tiles, player_start, resource_positions, world_object_positions, seen_ids)
		else:
			_validate_station(key, world.get(key, null), width_int, height_int, blocked_tiles, player_start, resource_positions, world_object_positions, seen_ids)
	var mob_positions := _validate_mobs(world.get("mobs", []), items, skills, width_int, height_int, blocked_tiles, player_start, resource_positions, world_object_positions, seen_ids)
	_validate_decorations(world.get("decorations", []), width_int, height_int, blocked_tiles, player_start, resource_positions, world_object_positions, seen_ids)
	_validate_npcs(world.get("npcs", []), quest_ids, width_int, height_int, blocked_tiles, player_start, resource_positions, world_object_positions, mob_positions, seen_ids)


func _validate_resource_nodes(raw_nodes, items: Dictionary, skills: Dictionary, width: int, height: int, blocked_tiles: Dictionary, player_start: Variant, seen_ids: Dictionary) -> Dictionary:
	var positions := {}
	if not (raw_nodes is Array):
		_issue("world.json:resource_nodes", "must be a list")
		return positions
	for index in range(raw_nodes.size()):
		var node = raw_nodes[index]
		var source := "world.json:resource_nodes[%d]" % index
		if not (node is Dictionary):
			_issue(source, "resource node must be an object")
			continue
		for key in ["node_id", "node_type", "display_name", "skill_id", "required_level", "xp_reward", "item_reward", "quantity_reward", "respawn_seconds", "base_gather_seconds", "position"]:
			if not node.has(key):
				_issue(source, "missing required key '%s'" % key)
		var node_id := str(node.get("node_id", ""))
		if node_id.is_empty():
			_issue(source, "'node_id' must be a non-empty string")
		elif seen_ids.has(node_id):
			_issue(source, "duplicate object ID '%s'" % node_id)
		seen_ids[node_id] = true
		var skill_id := str(node.get("skill_id", ""))
		if skill_id.is_empty() or not skills.has(skill_id):
			_issue(source, "unknown skill_id '%s'" % skill_id)
		if not _is_level(node.get("required_level", null)):
			_issue(source, "'required_level' must be between 1 and 99")
		if not _is_positive_int(node.get("xp_reward", null)):
			_issue(source, "'xp_reward' must be a positive integer")
		var item_reward := str(node.get("item_reward", ""))
		if item_reward.is_empty() or not items.has(item_reward):
			_issue(source, "unknown item_reward '%s'" % item_reward)
		if not _is_positive_int(node.get("quantity_reward", null)):
			_issue(source, "'quantity_reward' must be a positive integer")
		if node.has("secondary_item_reward"):
			var secondary_item := str(node["secondary_item_reward"])
			if secondary_item.is_empty() or not items.has(secondary_item):
				_issue(source, "unknown secondary_item_reward '%s'" % secondary_item)
			if not _is_positive_int(node.get("secondary_quantity_reward", null)):
				_issue(source, "'secondary_quantity_reward' must be a positive integer when secondary_item_reward is present")
			if not _is_chance(node.get("secondary_drop_chance", null)):
				_issue(source, "'secondary_drop_chance' must be between 0 and 1")
		if not _is_positive_number(node.get("respawn_seconds", null)):
			_issue(source, "'respawn_seconds' must be a positive number")
		if not _is_positive_number(node.get("base_gather_seconds", null)):
			_issue(source, "'base_gather_seconds' must be a positive number")
		if node.has("blocks_movement") and typeof(node["blocks_movement"]) != TYPE_BOOL:
			_issue(source, "'blocks_movement' must be a boolean")
		var tile: Variant = _tile(node.get("position", null), "%s.position" % source, width, height)
		if tile != null:
			var resource_blocked_tiles := blocked_tiles if bool(node.get("blocks_movement", false)) else {}
			_validate_position(source, tile, resource_blocked_tiles, player_start, positions, {}, "resource node")
			positions[_tile_key(tile)] = true
	return positions


func _validate_shop(raw_shop, items: Dictionary, width: int, height: int, blocked_tiles: Dictionary, player_start: Variant, resource_positions: Dictionary, world_object_positions: Dictionary, seen_ids: Dictionary) -> void:
	_validate_station("shop", raw_shop, width, height, blocked_tiles, player_start, resource_positions, world_object_positions, seen_ids)
	if not (raw_shop is Dictionary):
		return
	var stock = raw_shop.get("stock", [])
	if not (stock is Array):
		_issue("world.json:shop.stock", "must be a list")
		return
	if stock.is_empty():
		_issue("world.json:shop.stock", "must contain at least one stock item")
	var seen_stock_items := {}
	for index in range(stock.size()):
		var stock_item = stock[index]
		var source := "world.json:shop.stock[%d]" % index
		if not (stock_item is Dictionary):
			_issue(source, "stock item must be an object")
			continue
		var item_id := str(stock_item.get("item_id", ""))
		if item_id.is_empty() or not items.has(item_id):
			_issue(source, "unknown item_id '%s'" % item_id)
		elif seen_stock_items.has(item_id):
			_issue(source, "duplicate shop stock item_id '%s'" % item_id)
		seen_stock_items[item_id] = true
		if not stock_item.has("price"):
			_issue(source, "missing required integer 'price'")
		elif not _is_positive_int(stock_item["price"]):
			_issue(source, "'price' must be a positive integer")


func _validate_station(key: String, station, width: int, height: int, blocked_tiles: Dictionary, player_start: Variant, resource_positions: Dictionary, world_object_positions: Dictionary, seen_ids: Dictionary) -> void:
	if station == null:
		return
	var source := "world.json:%s" % key
	if not (station is Dictionary):
		_issue(source, "must be an object")
		return
	_require_string(station, "id", source)
	_require_string(station, "name", source)
	var object_id := str(station.get("id", ""))
	if not object_id.is_empty():
		if seen_ids.has(object_id):
			_issue(source, "duplicate object ID '%s'" % object_id)
		seen_ids[object_id] = true
	var tile: Variant = _tile(station.get("tile", null), "%s.tile" % source, width, height)
	if tile == null:
		return
	_validate_position(source, tile, blocked_tiles, player_start, resource_positions, world_object_positions, "world object")
	world_object_positions[_tile_key(tile)] = true


func _validate_mobs(raw_mobs, items: Dictionary, skills: Dictionary, width: int, height: int, blocked_tiles: Dictionary, player_start: Variant, resource_positions: Dictionary, world_object_positions: Dictionary, seen_ids: Dictionary) -> Dictionary:
	var positions := {}
	if not (raw_mobs is Array):
		_issue("world.json:mobs", "must be a list")
		return positions
	for index in range(raw_mobs.size()):
		var mob = raw_mobs[index]
		var source := "world.json:mobs[%d]" % index
		if not (mob is Dictionary):
			_issue(source, "mob must be an object")
			continue
		for key in ["mob_id", "display_name", "level", "hitpoints", "attack_seconds", "respawn_seconds", "position", "drops"]:
			if not mob.has(key):
				_issue(source, "missing required key '%s'" % key)
		var mob_id := str(mob.get("mob_id", ""))
		if mob_id.is_empty():
			_issue(source, "'mob_id' must be a non-empty string")
		elif seen_ids.has(mob_id):
			_issue(source, "duplicate object ID '%s'" % mob_id)
		seen_ids[mob_id] = true
		_require_string(mob, "display_name", source)
		if not _is_positive_int(mob.get("level", null)):
			_issue(source, "'level' must be a positive integer")
		if not _is_positive_int(mob.get("hitpoints", null)):
			_issue(source, "'hitpoints' must be a positive integer")
		if not _is_positive_number(mob.get("attack_seconds", null)):
			_issue(source, "'attack_seconds' must be a positive number")
		if not _is_positive_number(mob.get("respawn_seconds", null)):
			_issue(source, "'respawn_seconds' must be a positive number")
		var attack_style := str(mob.get("attack_style", "melee"))
		if not ["melee", "ranged", "magic"].has(attack_style):
			_issue(source, "'attack_style' must be melee, ranged, or magic")
		elif ["ranged", "magic"].has(attack_style) and not skills.has(attack_style):
			_issue(source, "unknown combat skill '%s'" % attack_style)
		if mob.has("attack_range") and not _is_positive_int(mob["attack_range"]):
			_issue(source, "'attack_range' must be a positive integer")
		if mob.has("passive") and typeof(mob["passive"]) != TYPE_BOOL:
			_issue(source, "'passive' must be a boolean")
		var visual_kind := str(mob.get("visual_kind", ""))
		if visual_kind.is_empty() or not _is_asset_name(visual_kind):
			_issue(source, "'visual_kind' must be a non-empty visual style key")
		var poison_keys := ["poison_chance", "poison_damage", "poison_rounds"]
		var poison_count := 0
		for key in poison_keys:
			if mob.has(key):
				poison_count += 1
		if poison_count > 0 and poison_count != poison_keys.size():
			_issue(source, "poison mobs must include poison_chance, poison_damage, and poison_rounds")
		if mob.has("poison_chance") and not _is_chance(mob["poison_chance"]):
			_issue(source, "'poison_chance' must be between 0 and 1")
		if mob.has("poison_damage") and not _is_positive_int(mob["poison_damage"]):
			_issue(source, "'poison_damage' must be a positive integer")
		if mob.has("poison_rounds") and not _is_positive_int(mob["poison_rounds"]):
			_issue(source, "'poison_rounds' must be a positive integer")
		_validate_mob_drops(mob.get("drops", []), items, source, bool(mob.get("passive", false)))
		var tile: Variant = _tile(mob.get("position", null), "%s.position" % source, width, height)
		if tile != null:
			_validate_position(source, tile, blocked_tiles, player_start, resource_positions, world_object_positions, "mob")
			if positions.has(_tile_key(tile)):
				_issue(source, "position cannot overlap another mob")
			positions[_tile_key(tile)] = true
	return positions


func _validate_mob_drops(drops, items: Dictionary, source: String, passive: bool) -> void:
	if not (drops is Array):
		_issue(source, "'drops' must be a list")
		return
	if drops.is_empty() and not passive:
		_issue(source, "non-passive mobs must define at least one drop")
	for index in range(drops.size()):
		var drop = drops[index]
		var drop_source := "%s.drops[%d]" % [source, index]
		if not (drop is Dictionary):
			_issue(drop_source, "drop must be an object")
			continue
		var item_id := str(drop.get("item_id", ""))
		if item_id.is_empty() or not items.has(item_id):
			_issue(drop_source, "unknown item_id '%s'" % item_id)
		if drop.has("quantity") and not _is_positive_int(drop["quantity"]):
			_issue(drop_source, "'quantity' must be a positive integer")


func _validate_decorations(raw_decorations, width: int, height: int, blocked_tiles: Dictionary, player_start: Variant, resource_positions: Dictionary, world_object_positions: Dictionary, seen_ids: Dictionary) -> void:
	if not (raw_decorations is Array):
		_issue("world.json:decorations", "must be a list")
		return
	for index in range(raw_decorations.size()):
		var decoration = raw_decorations[index]
		var source := "world.json:decorations[%d]" % index
		if not (decoration is Dictionary):
			_issue(source, "decoration must be an object")
			continue
		_require_string(decoration, "id", source)
		_require_string(decoration, "kind", source)
		var object_id := str(decoration.get("id", ""))
		if not object_id.is_empty():
			if seen_ids.has(object_id):
				_issue(source, "duplicate object ID '%s'" % object_id)
			seen_ids[object_id] = true
		var tile: Variant = _tile(decoration.get("position", null), "%s.position" % source, width, height)
		if decoration.has("rotation") and not _is_number(decoration["rotation"]):
			_issue(source, "'rotation' must be a number")
		if decoration.has("blocking") and typeof(decoration["blocking"]) != TYPE_BOOL:
			_issue(source, "'blocking' must be a boolean")
		if bool(decoration.get("blocking", false)) and tile != null:
			_validate_position(source, tile, blocked_tiles, player_start, resource_positions, world_object_positions, "blocking decoration")


func _validate_npcs(raw_npcs, quest_ids: Dictionary, width: int, height: int, blocked_tiles: Dictionary, player_start: Variant, resource_positions: Dictionary, world_object_positions: Dictionary, mob_positions: Dictionary, seen_ids: Dictionary) -> void:
	if not (raw_npcs is Array):
		_issue("world.json:npcs", "must be a list")
		return
	var npc_positions := {}
	var quest_owners := {}
	for index in range(raw_npcs.size()):
		var npc = raw_npcs[index]
		var source := "world.json:npcs[%d]" % index
		if not (npc is Dictionary):
			_issue(source, "npc must be an object")
			continue
		_require_string(npc, "id", source)
		_require_string(npc, "name", source)
		var object_id := str(npc.get("id", ""))
		if not object_id.is_empty():
			if seen_ids.has(object_id):
				_issue(source, "duplicate object ID '%s'" % object_id)
			seen_ids[object_id] = true
		var quest_id := str(npc.get("quest_id", ""))
		if not quest_id.is_empty() and not quest_ids.has(quest_id):
			_issue(source, "unknown quest_id '%s'" % quest_id)
		elif not quest_id.is_empty() and quest_owners.has(quest_id):
			_issue(source, "duplicate NPC quest_id '%s' also used by %s" % [quest_id, str(quest_owners[quest_id])])
		if not quest_id.is_empty():
			quest_owners[quest_id] = source
		var tile: Variant = _tile(npc.get("tile", null), "%s.tile" % source, width, height)
		if tile != null:
			_validate_position(source, tile, blocked_tiles, player_start, resource_positions, world_object_positions, "npc")
			var key := _tile_key(tile)
			if mob_positions.has(key):
				_issue(source, "tile cannot overlap a mob")
			if npc_positions.has(key):
				_issue(source, "tile cannot overlap another NPC")
			npc_positions[key] = true


func _validate_position(source: String, tile: Vector2i, blocked_tiles: Dictionary, player_start: Variant, resource_positions: Dictionary, world_object_positions: Dictionary, label: String) -> void:
	var key := _tile_key(tile)
	if blocked_tiles.has(key):
		_issue(source, "%s position cannot overlap blocked or water tile" % label)
	if player_start != null and tile == player_start:
		_issue(source, "%s position cannot overlap player spawn" % label)
	if resource_positions.has(key):
		_issue(source, "%s position cannot overlap a resource node" % label)
	if world_object_positions.has(key):
		_issue(source, "%s position cannot overlap another world object" % label)


func _validate_manifest(manifest: Dictionary, items: Dictionary, skills: Dictionary) -> void:
	var defaults = manifest.get("defaults", {})
	if not (defaults is Dictionary):
		_issue("asset_manifest.json:defaults", "must be an object")
	else:
		for default_id in ["icon", "effect"]:
			var path := _manifest_entry_path(defaults.get(default_id, null), "asset_manifest.json:defaults:%s" % default_id)
			if not path.is_empty():
				_validate_manifest_path(path, "asset_manifest.json:defaults:%s" % default_id, "", [".png"])
	for category in MANIFEST_CATEGORIES.keys():
		var entries = manifest.get(category, null)
		var rules: Dictionary = MANIFEST_CATEGORIES[category]
		if not (entries is Dictionary):
			_issue("asset_manifest.json:%s" % category, "must be an object")
			continue
		_validate_manifest_entries(category, entries, rules)
	for category in OPTIONAL_MANIFEST_CATEGORIES.keys():
		if not manifest.has(category):
			continue
		var entries = manifest.get(category, null)
		var rules: Dictionary = OPTIONAL_MANIFEST_CATEGORIES[category]
		if not (entries is Dictionary):
			_issue("asset_manifest.json:%s" % category, "must be an object")
			continue
		_validate_manifest_entries(category, entries, rules)
	if manifest.get("audio", {}) is Dictionary:
		var audio: Dictionary = manifest["audio"]
		for audio_id in REQUIRED_AUDIO.keys():
			if not audio.has(audio_id):
				_issue("asset_manifest.json:audio", "missing required audio asset '%s'" % audio_id)
	_validate_icon_refs(items, manifest, "items")
	_validate_icon_refs(skills, manifest, "skills")


func _validate_manifest_entries(category: String, entries: Dictionary, rules: Dictionary) -> void:
	for asset_id in entries.keys():
		if not _is_asset_name(str(asset_id)):
			_issue("asset_manifest.json:%s" % category, "asset names must be lowercase asset keys")
		var source := "asset_manifest.json:%s:%s" % [category, asset_id]
		var path := _manifest_entry_path(entries[asset_id], source)
		if not path.is_empty():
			_validate_manifest_path(path, source, str(rules["prefix"]), rules["extensions"])


func _manifest_entry_path(entry, source: String) -> String:
	if entry is String and not String(entry).is_empty():
		return str(entry)
	if entry is Dictionary and entry.has("path") and entry["path"] is String and not String(entry["path"]).is_empty():
		return str(entry["path"])
	_issue(source, "entry must be a path string or an object with string 'path'")
	return ""


func _validate_manifest_path(path: String, source: String, prefix: String, extensions: Array) -> void:
	var normalized := path.replace("\\", "/")
	if normalized.begins_with("/") or normalized.contains("../") or normalized.contains("..\\"):
		_issue(source, "'path' must be relative and stay inside assets")
	if not prefix.is_empty() and not normalized.begins_with(prefix):
		_issue(source, "'path' must start with '%s'" % prefix)
	var extension_ok := false
	for extension in extensions:
		if normalized.ends_with(str(extension)):
			extension_ok = true
			break
	if not extension_ok:
		_issue(source, "'path' must use one of: %s" % ", ".join(extensions))
	if not FileAccess.file_exists("res://assets/%s" % normalized):
		_issue(source, "'path' must resolve to an existing asset file")


func _validate_icon_refs(definitions: Dictionary, manifest: Dictionary, source_name: String) -> void:
	for object_id in definitions.keys():
		var definition = definitions[object_id]
		if not (definition is Dictionary):
			continue
		var icon := str(definition.get("icon", ""))
		if icon.is_empty():
			continue
		var parts := icon.split("/", false, 1)
		if parts.size() != 2:
			continue
		var category := parts[0]
		var asset_id := parts[1]
		var entries = manifest.get(category, {})
		if not (entries is Dictionary) or not entries.has(asset_id):
			_issue("%s.json:%s" % [source_name, object_id], "unknown icon asset '%s'" % icon)


func _validate_originality_sources(sources: Dictionary) -> void:
	for source in sources.keys():
		_validate_originality_value(sources[source], str(source))


func _validate_originality_value(value, source: String) -> void:
	if value is String:
		var text := str(value).to_lower()
		for term in PROTECTED_TERMS:
			if _contains_protected_term(text, term):
				_issue(source, "contains protected or near-branded term '%s'" % term)
		return
	if value is Dictionary:
		for key in value.keys():
			_validate_originality_value(str(key), "%s:%s" % [source, key])
			_validate_originality_value(value[key], "%s:%s" % [source, key])
		return
	if value is Array:
		for index in range(value.size()):
			_validate_originality_value(value[index], "%s[%d]" % [source, index])


func _contains_protected_term(text: String, term: String) -> bool:
	var start := 0
	while true:
		var index := text.find(term, start)
		if index == -1:
			return false
		var before_ok := index == 0 or not _is_ascii_alnum(text[index - 1])
		var after_index := index + term.length()
		var after_ok := after_index >= text.length() or not _is_ascii_alnum(text[after_index])
		if before_ok and after_ok:
			return true
		start = index + term.length()
	return false


func _quest_ids(quests: Dictionary) -> Dictionary:
	var ids := {}
	var raw_quests = quests.get("quests", [])
	if not (raw_quests is Array):
		return ids
	for quest in raw_quests:
		if quest is Dictionary and quest.has("quest_id") and quest["quest_id"] is String and not String(quest["quest_id"]).is_empty():
			ids[str(quest["quest_id"])] = true
	return ids


func _tile_set(raw_tiles, source: String, width: int, height: int) -> Dictionary:
	var tiles := {}
	if not (raw_tiles is Array):
		_issue(source, "must be a list")
		return tiles
	for index in range(raw_tiles.size()):
		var tile: Variant = _tile(raw_tiles[index], "%s[%d]" % [source, index], width, height)
		if tile != null:
			tiles[_tile_key(tile)] = true
	return tiles


func _tile(raw_tile, source: String, width: int, height: int) -> Variant:
	if not (raw_tile is Array) or raw_tile.size() != 2 or not _is_int_number(raw_tile[0]) or not _is_int_number(raw_tile[1]):
		_issue(source, "must be a two-integer tile")
		return null
	var tile := Vector2i(int(raw_tile[0]), int(raw_tile[1]))
	if tile.x < 0 or tile.x >= width or tile.y < 0 or tile.y >= height:
		_issue(source, "tile is out of bounds")
		return null
	return tile


func _tile_key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


func _require_string(definition: Dictionary, key: String, source: String) -> void:
	if not definition.has(key) or not _is_non_empty_string(definition[key]):
		_issue(source, "missing required string '%s'" % key)


func _validate_icon_key(value, source: String, optional: bool) -> void:
	if optional and (value == null or str(value).is_empty()):
		return
	var text := str(value)
	var parts := text.split("/", false, 1)
	if parts.size() != 2 or not ["items", "skills", "ui", "effects"].has(parts[0]) or not _is_asset_name(parts[1]):
		_issue(source, "'icon' must be an asset key like 'items/sword'")


func _is_asset_name(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character != "_" and character != "-" and character != "/":
			return false
	return true


func _is_non_empty_string(value) -> bool:
	return value is String and not String(value).is_empty()


func _is_int_number(value) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and float(value) == floor(float(value)))


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_positive_int(value) -> bool:
	return _is_int_number(value) and int(value) > 0


func _is_non_negative_int(value) -> bool:
	return _is_int_number(value) and int(value) >= 0


func _is_level(value) -> bool:
	return _is_int_number(value) and int(value) >= 1 and int(value) <= 99


func _is_positive_number(value) -> bool:
	return _is_number(value) and float(value) > 0.0


func _is_non_negative_number(value) -> bool:
	return _is_number(value) and float(value) >= 0.0


func _is_chance(value) -> bool:
	return _is_number(value) and float(value) >= 0.0 and float(value) <= 1.0


func _positive_int_value(value) -> bool:
	return _is_int_number(value) and int(value) > 0


func _is_ascii_alnum(character: String) -> bool:
	return (character >= "a" and character <= "z") or (character >= "0" and character <= "9")


func _sorted_keys_text(mapping: Dictionary) -> String:
	var keys := mapping.keys()
	keys.sort()
	var values: Array[String] = []
	for key in keys:
		values.append(str(key))
	return ", ".join(values)


func _issue(source: String, message: String) -> void:
	issues.append("%s: %s" % [source, message])
