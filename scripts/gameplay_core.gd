extends Node

signal persistent_state_changed

const ITEMS_PATH := "res://data/items.json"
const SKILLS_PATH := "res://data/skills.json"
const RECIPES_PATH := "res://data/recipes.json"
const QUESTS_PATH := "res://data/quests.json"
const INVENTORY_SLOT_LIMIT := 28
const InvariantChecker = preload("res://scripts/invariant_checker.gd")
const StateSnapshot = preload("res://scripts/state_snapshot.gd")
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
const CARPENTRY_WEAPONWRIGHT_RECIPES := [
	"training_bow", "training_staff", "oak_bow", "willow_bow",
	"maple_bow", "lumen_bow", "starsteel_staff", "lumen_staff",
]
const CARPENTRY_FIELDWRIGHT_RECIPES := [
	"storage_crate", "camp_kit", "bait_box", "field_pack", "sap_lacquered_field_pack",
]
const CARPENTRY_SPECIALIZATIONS := ["weaponwright", "fieldwright"]
const CARPENTRY_SPECIALIZATION_LEVEL := 40
const DEFAULT_ACTION_SECONDS := 1.0
const BUFF_BONUS_KEYS := ["attack_bonus", "strength_bonus", "defence_bonus", "ranged_bonus", "magic_bonus", "action_speed_bonus"]

var state := {}
var world: Node
var hud: CanvasLayer
var items_data := {}
var skills_data := {}
var recipes_data := {}
var quests_data := {}
var active_shop_data := {}
var last_feedback_text := ""
var simulation_recipe_action_type := ""
var simulation_recipe_id := ""
var clock_mode := "realtime"
var state_bound := false


func setup(initial_state: Dictionary, world_node: Node, hud_node: CanvasLayer, requested_clock_mode: String = "realtime") -> void:
	state = initial_state
	world = world_node
	hud = hud_node
	clock_mode = requested_clock_mode if requested_clock_mode in ["realtime", "manual"] else "realtime"
	items_data = _load_json(ITEMS_PATH)
	skills_data = _load_json(SKILLS_PATH)
	recipes_data = _load_json(RECIPES_PATH)
	quests_data = _load_json(QUESTS_PATH)
	simulation_recipe_action_type = ""
	simulation_recipe_id = ""
	_ensure_state_shape()
	_connect_hud_requests()
	state_bound = true


func _process(delta: float) -> void:
	if state_bound and clock_mode == "realtime":
		_advance_action_clock(delta)


func set_simulation_recipe_override(action_type: String, recipe_id: String) -> void:
	simulation_recipe_action_type = action_type
	simulation_recipe_id = recipe_id


func notify_persistent_state_changed() -> void:
	_emit_persistent_state_changed()


func _connect_hud_requests() -> void:
	if hud == null:
		return
	_connect_hud_signal("bank_deposit_requested", "_handle_bank_deposit_requested")
	_connect_hud_signal("bank_withdraw_requested", "_handle_bank_withdraw_requested")
	_connect_hud_signal("shop_buy_requested", "_handle_shop_buy_requested")
	_connect_hud_signal("shop_sell_requested", "_handle_shop_sell_requested")
	_connect_hud_signal("quest_route_select_requested", "_handle_quest_route_select_requested")
	_connect_hud_signal("dialogue_action_requested", "_handle_dialogue_action_requested")
	_connect_hud_signal("inventory_item_action_requested", "_handle_inventory_item_action_requested")
	_connect_hud_signal("equipment_item_action_requested", "_handle_equipment_item_action_requested")
	_connect_hud_signal("carpentry_specialization_requested", "_handle_carpentry_specialization_requested")
	_connect_hud_signal("recipe_selected_requested", "_handle_recipe_selected_requested")


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
			var item_id := str(object_data.get("item_reward", ""))
			var xp := int(object_data.get("xp_reward", 0))
			_feedback("%s: %s resource, level %d; gives %s and %d XP." % [label, skill_name, required_level, _item_name(item_id), xp])
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
		_feedback("You need a %s to gather %s." % [str(tool[1]), label])
		return
	if _skill_level(skill_id) < required_level:
		_feedback("You need %s level %d for %s; you are level %d. Reward: %s and %d XP." % [_skill_name(skill_id), required_level, label, _skill_level(skill_id), _item_name(item_id), xp])
		return
	var action_key := "gather:%s" % node_id
	if not _action_is_ready(action_key):
		_feedback("%s is still being gathered; wait %d seconds." % [label, _action_wait_seconds(action_key)])
		return

	var bonus_yield_chance := clampf(_skill_mastery_effect_total(skill_id, "gather_bonus_yield_chance"), 0.0, 1.0)
	var quantity_bonus := 1 if _chance_succeeds("%s:yield" % action_key, bonus_yield_chance) else 0
	var final_quantity := quantity + quantity_bonus
	var secondary_item := str(object_data.get("secondary_item_reward", ""))
	var secondary_quantity := int(object_data.get("secondary_quantity_reward", 1))
	var secondary_chance := clampf(float(object_data.get("secondary_drop_chance", 0.0)) + _skill_mastery_effect_total(skill_id, "gather_secondary_chance_bonus"), 0.0, 1.0)
	var secondary_will_drop := not secondary_item.is_empty() and secondary_quantity > 0 and _chance_succeeds("%s:secondary" % action_key, secondary_chance)
	var final_secondary_quantity := secondary_quantity + int(_skill_mastery_effect_total(skill_id, "gather_secondary_quantity_bonus")) if secondary_will_drop else 0
	var reward_changes := {item_id: final_quantity}
	if secondary_will_drop:
		reward_changes[secondary_item] = int(reward_changes.get(secondary_item, 0)) + final_secondary_quantity
	if not _inventory_can_transact({}, reward_changes):
		_feedback(_inventory_full_message(_item_name(item_id)))
		return
	_add_inventory_item(item_id, final_quantity)
	var secondary_added := false
	if secondary_will_drop:
		secondary_added = _add_inventory_item(secondary_item, final_secondary_quantity)
	var level_message := _add_xp(skill_id, xp)
	_start_action_cooldown(action_key, float(object_data.get("base_gather_seconds", DEFAULT_ACTION_SECONDS)))
	_mark_resource_depleted(node_id, float(object_data.get("respawn_seconds", 0.0)))
	_record_gathering_quest_flags(skill_id, item_id)
	var message := "%s: +%d %s; %s" % [label, final_quantity, _item_name(item_id), _xp_gain_text(skill_id, xp)]
	if quantity_bonus > 0:
		message = "%s; mastery +1 yield" % message
	if secondary_added:
		message = "%s; bonus +%d %s" % [message, final_secondary_quantity, _item_name(secondary_item)]
	message = _with_level_message(message, level_message)
	_trigger_activity_animation("gather")
	_feedback(message)


func _process_station(object_data: Dictionary) -> void:
	var station_id := str(object_data.get("station_id", ""))
	match station_id:
		"cooking_range":
			_open_recipe_station("cooking", str(object_data.get("label", "Cooking range")))
		"furnace":
			_open_recipe_station("smelting", str(object_data.get("label", "Furnace")))
		"anvil":
			_open_recipe_station("smithing", str(object_data.get("label", "Anvil")))
		"carpentry_bench":
			_open_recipe_station("carpentry", str(object_data.get("label", "Carpentry bench")))
		"apothecary_table":
			_open_recipe_station("herbalism", str(object_data.get("label", "Apothecary table")))
		"bank":
			_open_bank()
		"shop":
			_open_shop(object_data)
		_:
			_feedback("Nothing happens")


func _open_recipe_station(action_type: String, station_label: String) -> void:
	var simulation_active := hud != null and hud.has_method("is_simulation_lightweight_mode") and bool(hud.call("is_simulation_lightweight_mode"))
	if simulation_recipe_action_type == action_type and not simulation_recipe_id.is_empty():
		if action_type == "cooking":
			_process_cooking(simulation_recipe_id)
		else:
			_process_recipe_type(action_type, simulation_recipe_id)
		return
	if simulation_active:
		if action_type == "cooking":
			_process_cooking()
		else:
			_process_recipe_type(action_type)
		return
	if hud != null and hud.has_method("show_recipe_picker"):
		hud.show_recipe_picker(action_type, station_label, _recipe_picker_entries(action_type))
		return
	_feedback("No recipe picker is available here.")


func _handle_recipe_selected_requested(action_type: String, recipe_id: String) -> void:
	var clean_action := action_type.strip_edges().to_lower()
	var clean_recipe := recipe_id.strip_edges()
	if clean_action == "cooking":
		_process_cooking(clean_recipe)
	else:
		_process_recipe_type(clean_action, clean_recipe)
	if hud != null and hud.has_method("show_recipe_picker"):
		hud.show_recipe_picker(clean_action, _recipe_picker_station_label(clean_action), _recipe_picker_entries(clean_action))


func _recipe_picker_station_label(action_type: String) -> String:
	return {
		"cooking": "Cooking range",
		"smelting": "Furnace",
		"smithing": "Anvil",
		"carpentry": "Carpentry bench",
		"herbalism": "Apothecary table",
	}.get(action_type, "Station")


func _recipe_picker_entries(action_type: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if action_type == "cooking":
		for item_id in items_data.keys():
			var definition = items_data[item_id]
			if not (definition is Dictionary) or not definition.has("cook_result"):
				continue
			var input_id := str(item_id)
			var output_id := str(definition.get("cook_result", ""))
			entries.append(_recipe_picker_entry(
				"cooking",
				input_id,
				str(definition.get("name", input_id)),
				int(definition.get("cooking_required_level", 1)),
				{input_id: 1},
				output_id,
				1,
				int(definition.get("cooking_xp", 0)),
			))
		return entries
	var recipes = recipes_data.get(action_type, [])
	if not (recipes is Array):
		return entries
	for recipe in recipes:
		if not (recipe is Dictionary):
			continue
		var recipe_id := str(recipe.get("recipe_id", ""))
		entries.append(_recipe_picker_entry(
			action_type,
			recipe_id,
			str(recipe.get("display_name", recipe_id)),
			int(recipe.get("required_level", 1)),
			recipe.get("inputs", {}),
			str(recipe.get("output_item_id", "")),
			int(recipe.get("output_quantity", 1)),
			int(recipe.get("xp_reward", 0)),
		))
	return entries


func _recipe_picker_entry(action_type: String, recipe_id: String, display_name: String, required_level: int, inputs: Dictionary, output_item_id: String, output_quantity: int, xp_reward: int) -> Dictionary:
	var skill_id := "cooking" if action_type == "cooking" else str(PROCESSING_SKILLS.get(action_type, action_type))
	var availability := "Ready"
	var eligible := true
	if _skill_level(skill_id) < required_level:
		eligible = false
		availability = "%s level %d required" % [_skill_name(skill_id), required_level]
	elif not _has_recipe_inputs(inputs):
		eligible = false
		availability = "Missing ingredients"
	else:
		var action_key := ("cook:%s" % recipe_id) if action_type == "cooking" else ("recipe:%s:%s" % [action_type, recipe_id])
		if not _action_is_ready(action_key):
			eligible = false
			availability = "In progress; wait %d seconds" % _action_wait_seconds(action_key)
		else:
			var projected_additions := {output_item_id: output_quantity}
			var specialization_return := _carpentry_specialization_return_item(action_type, recipe_id)
			if not specialization_return.is_empty():
				projected_additions[specialization_return] = int(projected_additions.get(specialization_return, 0)) + 1
			if not _inventory_can_transact(inputs, projected_additions):
				eligible = false
				availability = "Inventory full"
	return {
		"action_type": action_type,
		"recipe_id": recipe_id,
		"display_name": display_name,
		"required_level": required_level,
		"skill_id": skill_id,
		"inputs": inputs.duplicate(true),
		"output_item_id": output_item_id,
		"output_quantity": output_quantity,
		"xp_reward": xp_reward,
		"eligible": eligible,
		"availability": availability,
	}


func _has_recipe_inputs(inputs: Dictionary) -> bool:
	for item_id in inputs.keys():
		if _inventory_count(str(item_id)) < int(inputs[item_id]):
			return false
	return true


func _process_cooking(selected_item_id: String = "") -> void:
	var inventory := _inventory()
	var requested_item_id := selected_item_id
	if requested_item_id.is_empty() and simulation_recipe_action_type == "cooking":
		requested_item_id = simulation_recipe_id
	var selected_found := false
	for item_id in inventory.keys():
		if not requested_item_id.is_empty() and str(item_id) != requested_item_id:
			continue
		var definition = items_data.get(str(item_id), {})
		if not (definition is Dictionary) or not definition.has("cook_result"):
			continue
		selected_found = true
		var required_level := int(definition.get("cooking_required_level", 1))
		if _skill_level("cooking") < required_level:
			_feedback("You need Cooking level %d to cook %s; you are level %d." % [required_level, _item_name(str(item_id)), _skill_level("cooking")])
			return
		var cooked_item := str(definition["cook_result"])
		var action_key := "cook:%s" % str(item_id)
		if not _action_is_ready(action_key):
			_feedback("Cooking is still in progress; wait %d seconds." % _action_wait_seconds(action_key))
			return
		var bonus_output_chance := clampf(_skill_mastery_effect_total("cooking", "processing_bonus_output_chance"), 0.0, 1.0)
		var output_bonus := 1 if _is_stackable_item(cooked_item) and _chance_succeeds("%s:output" % action_key, bonus_output_chance) else 0
		var output_quantity := 1 + output_bonus
		if not _inventory_can_transact({str(item_id): 1}, {cooked_item: output_quantity}):
			_feedback(_inventory_full_message(_item_name(cooked_item)))
			return
		_remove_inventory_item(str(item_id), 1)
		_add_inventory_item(cooked_item, output_quantity)
		var base_xp := int(definition.get("cooking_xp", 0))
		var xp := int(ceil(float(base_xp) * (1.0 + _skill_mastery_effect_total("cooking", "processing_xp_bonus_percent"))))
		var level_message := _add_xp("cooking", xp)
		_start_action_cooldown(action_key, float(definition.get("base_cook_seconds", DEFAULT_ACTION_SECONDS)))
		_record_quest_flag("cooked_food")
		var message := "Cooked %s -> %d %s; %s" % [_item_name(str(item_id)), output_quantity, _item_name(cooked_item), _xp_gain_text("cooking", xp)]
		if output_bonus > 0:
			message = "%s; mastery bonus output" % message
		message = _with_level_message(message, level_message)
		_trigger_activity_animation("craft")
		_feedback(message)
		return
	if not requested_item_id.is_empty() and not selected_found:
		_feedback("That cooking recipe is unavailable.")
		return
	_feedback("Select a raw fish first")


func _process_recipe_type(action_type: String, selected_recipe_id: String = "") -> void:
	var recipes = recipes_data.get(action_type, [])
	if not (recipes is Array):
		_feedback("No recipe available")
		return
	var requested_recipe_id := selected_recipe_id
	if requested_recipe_id.is_empty() and simulation_recipe_action_type == action_type:
		requested_recipe_id = simulation_recipe_id
	for recipe in recipes:
		if not (recipe is Dictionary):
			continue
		var recipe_id := str(recipe.get("recipe_id", ""))
		if not requested_recipe_id.is_empty() and recipe_id != requested_recipe_id:
			continue
		var selected_recipe := not requested_recipe_id.is_empty()
		if not _has_recipe_inputs(recipe.get("inputs", {})):
			if selected_recipe:
				_feedback("Missing ingredients for %s." % str(recipe.get("display_name", recipe_id)))
				return
			continue
		var skill_id := str(PROCESSING_SKILLS.get(action_type, action_type))
		var required_level := int(recipe.get("required_level", 1))
		var output_item := str(recipe.get("output_item_id", ""))
		if _skill_level(skill_id) < required_level:
			_feedback("You need %s level %d to make %s; you are level %d." % [_skill_name(skill_id), required_level, str(recipe.get("display_name", recipe.get("recipe_id", output_item))), _skill_level(skill_id)])
			return
		recipe_id = str(recipe.get("recipe_id", output_item))
		var action_key := "recipe:%s:%s" % [action_type, recipe_id]
		if not _action_is_ready(action_key):
			_feedback("%s is still in progress; wait %d seconds." % [str(recipe.get("display_name", recipe_id)), _action_wait_seconds(action_key)])
			return
		var base_output_quantity := int(recipe.get("output_quantity", 1))
		var bonus_output_chance := clampf(_skill_mastery_effect_total(skill_id, "processing_bonus_output_chance"), 0.0, 1.0)
		var output_bonus := 1 if _is_stackable_item(output_item) and _chance_succeeds("%s:output" % action_key, bonus_output_chance) else 0
		var output_quantity := base_output_quantity + output_bonus
		var specialization_return := _carpentry_specialization_return_item(action_type, recipe_id)
		var add_items := {output_item: output_quantity}
		if not specialization_return.is_empty():
			add_items[specialization_return] = int(add_items.get(specialization_return, 0)) + 1
		if not _inventory_can_transact(recipe.get("inputs", {}), add_items):
			_feedback(_inventory_full_message(_item_name(output_item)))
			return
		for input_id in recipe.get("inputs", {}).keys():
			_remove_inventory_item(str(input_id), int(recipe["inputs"][input_id]))
		_add_inventory_item(output_item, output_quantity)
		if not specialization_return.is_empty():
			_add_inventory_item(specialization_return, 1)
		var base_xp := int(recipe.get("xp_reward", 0))
		var xp := int(ceil(float(base_xp) * (1.0 + _skill_mastery_effect_total(skill_id, "processing_xp_bonus_percent"))))
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
		message = "%s (%s)" % [message, _skill_status_text(skill_id)]
		if output_bonus > 0:
			message = "%s; mastery bonus output" % message
		message = _with_level_message(message, level_message)
		_trigger_activity_animation("craft")
		_feedback(message)
		return
	if not requested_recipe_id.is_empty():
		_feedback("That recipe is unavailable.")
		return
	_feedback(_select_feedback(action_type))


func _handle_carpentry_specialization_requested(specialization: String) -> void:
	var clean_specialization := specialization.strip_edges().to_lower()
	if not CARPENTRY_SPECIALIZATIONS.has(clean_specialization):
		_feedback("That Carpentry specialization is not available.")
		return
	if _skill_level("carpentry") < CARPENTRY_SPECIALIZATION_LEVEL:
		_feedback("You need Carpentry level 40 to choose a specialization.")
		return
	if not str(state.get("carpentry_specialization", "")).strip_edges().is_empty():
		_feedback("Your Carpentry specialization is already permanent.")
		return
	state["carpentry_specialization"] = clean_specialization
	_emit_persistent_state_changed()
	_feedback("Carpentry specialization chosen: %s." % _carpentry_specialization_label(clean_specialization))
	_refresh_ui()


func _carpentry_specialization_return_item(action_type: String, recipe_id: String) -> String:
	if action_type != "carpentry":
		return ""
	var specialization := str(state.get("carpentry_specialization", "")).to_lower()
	var return_item := ""
	var eligible := false
	if specialization == "weaponwright":
		eligible = CARPENTRY_WEAPONWRIGHT_RECIPES.has(recipe_id)
		return_item = "plain_tool_handle"
	elif specialization == "fieldwright":
		eligible = CARPENTRY_FIELDWRIGHT_RECIPES.has(recipe_id)
		return_item = "plain_plank"
	if not eligible or return_item.is_empty():
		return ""
	var action_key := "recipe:carpentry:%s:specialization" % recipe_id
	return return_item if _chance_succeeds(action_key, 0.15) else ""


func _carpentry_specialization_label(specialization: String) -> String:
	return "Weaponwright" if specialization == "weaponwright" else "Fieldwright"


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
		if _mob_respawn_ready(mob_state):
			mob_state = {"hitpoints": max_hp, "dead": false}
			mobs[mob_id] = mob_state
			combat["mobs"] = mobs
		else:
			_feedback(_mob_respawn_wait_message(label, mob_state))
			return

	var style := str(state.get("combat_training_style", "attack"))
	if style not in ["attack", "strength", "defence", "ranged", "magic"]:
		style = "attack"
	var damage := _combat_player_damage(style)
	var target_hp_before_hit := int(mob_state.get("hitpoints", max_hp))
	var actual_damage: int = min(damage, target_hp_before_hit)
	var remaining: int = max(0, target_hp_before_hit - damage)
	var style_xp := actual_damage * 4
	var hitpoints_xp := actual_damage
	var style_level_message := _add_xp(style, style_xp)
	var hitpoints_level_message := _add_xp("hitpoints", hitpoints_xp)
	var enemy_damage := _combat_enemy_damage(level, style, object_data)
	var defence_xp := 0
	var defence_level_message := ""
	if enemy_damage > 0:
		_combat_set_hitpoints(max(0, int(combat.get("current_hitpoints", 10)) - enemy_damage))
		defence_xp = enemy_damage * 4
		defence_level_message = _add_xp("defence", defence_xp)
		_apply_poison_from_mob(object_data)

	var status_suffix := ""
	if not poison_message.is_empty():
		status_suffix = "; %s" % poison_message
	var xp_summary := _combat_xp_summary(style, style_xp, hitpoints_xp, defence_xp)
	var level_summary := _join_non_empty([style_level_message, hitpoints_level_message, defence_level_message])
	if remaining <= 0:
		var defeated_state := {"hitpoints": 0, "dead": true}
		var respawn_seconds := _mob_respawn_seconds(object_data)
		if respawn_seconds > 0.0:
			defeated_state["respawn_at"] = _action_clock_seconds() + respawn_seconds
		mobs[mob_id] = defeated_state
		combat["mobs"] = mobs
		_spawn_drops(object_data)
		_record_combat_quest_flags(mob_id)
		var drops = object_data.get("drops", [])
		var reward_message := "drops appeared" if drops is Array and not drops.is_empty() else "it will return soon"
		var defeated_message := "Defeated %s; %s; %s; you %d/%d HP%s" % [label, reward_message, xp_summary, int(combat.get("current_hitpoints", 10)), _skill_level("hitpoints"), status_suffix]
		_trigger_activity_animation("combat")
		_feedback(_with_level_message(defeated_message, level_summary))
		return

	mobs[mob_id] = {"hitpoints": remaining, "dead": false}
	combat["mobs"] = mobs
	var hit_message := "Hit %s %d dmg; %d/%d HP left; %s; you %d/%d HP%s" % [label, damage, remaining, max_hp, xp_summary, int(combat.get("current_hitpoints", 10)), _skill_level("hitpoints"), status_suffix]
	_trigger_activity_animation("combat")
	_feedback(_with_level_message(hit_message, level_summary))


func _pick_up_drop(object_data: Dictionary) -> void:
	var item_id := str(object_data.get("item_id", ""))
	var quantity := int(object_data.get("quantity", 1))
	if item_id.is_empty() or quantity <= 0:
		_feedback("Nothing to take")
		return
	if not _inventory_can_transact({}, {item_id: quantity}):
		_feedback(_inventory_full_message(_item_name(item_id)))
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
	var origin_tile: Vector2i = object_data.get("tile", Vector2i(15, 15))
	var reserved := {}
	var pending_items: Array[Dictionary] = []
	for drop in drops:
		if not (drop is Dictionary):
			continue
		var tile := _find_ground_drop_tile(origin_tile, reserved)
		if tile == Vector2i(-1, -1):
			continue
		reserved[tile] = true
		var item := {
			"object_id": _next_ground_drop_id(),
			"item_id": str(drop.get("item_id", "")),
			"quantity": int(drop.get("quantity", 1)),
			"tile": [tile.x, tile.y],
			"type": "ground_item",
		}
		pending_items.append(item)
	for item in pending_items:
		var tile_values: Array = item.get("tile", [])
		var tile := Vector2i(int(tile_values[0]), int(tile_values[1])) if tile_values.size() >= 2 else Vector2i(-1, -1)
		if world != null and world.has_method("add_ground_drop") and not bool(world.add_ground_drop(tile, item)):
			continue
		ground_items.append(item)
	combat["ground_items"] = ground_items
	if not pending_items.is_empty():
		_emit_persistent_state_changed()


func _combat_player_damage(style: String) -> int:
	var damage_skill := _damage_skill(style)
	var base_damage := 1 + int((_skill_level(damage_skill) - 1) / 10)
	var mastery_damage_bonus := int(_skill_mastery_effect_total(damage_skill, "combat_damage_bonus"))
	var weapon = items_data.get(str(_equipment().get("weapon", "")), {})
	var attack_bonus := _combat_bonus_from_definition(weapon, "attack_bonus") + _buff_bonus("attack_bonus")
	var strength_bonus := _combat_bonus_from_definition(weapon, "strength_bonus") + _buff_bonus("strength_bonus")
	var ranged_bonus := _combat_bonus_from_definition(weapon, "ranged_bonus") + _buff_bonus("ranged_bonus")
	var magic_bonus := _combat_bonus_from_definition(weapon, "magic_bonus") + _buff_bonus("magic_bonus")
	match style:
		"ranged":
			return max(1, base_damage + mastery_damage_bonus + int(ranged_bonus / 2))
		"magic":
			return max(1, base_damage + mastery_damage_bonus + int(magic_bonus / 2))
		"strength":
			return max(1, base_damage + mastery_damage_bonus + int((attack_bonus + strength_bonus) / 2))
		"defence":
			return max(1, base_damage + int(attack_bonus / 2))
		_:
			return max(1, base_damage + mastery_damage_bonus + int((attack_bonus + strength_bonus) / 2))


func _combat_enemy_damage(level: int, style: String, object_data: Dictionary) -> int:
	if bool(object_data.get("passive", false)):
		return 0
	var shield = items_data.get(str(_equipment().get("shield", "")), {})
	var defence_bonus := _combat_bonus_from_definition(shield, "defence_bonus") + _buff_bonus("defence_bonus")
	var style_relief := 1 if style in ["ranged", "magic"] else 0
	return max(0, int(level / 3) - defence_bonus - style_relief)


func _combat_bonus_from_definition(definition, key: String) -> int:
	if definition is Dictionary:
		return int(definition.get(key, 0))
	return 0


func _drop_inventory_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0 or _inventory_count(item_id) <= 0:
		_feedback("Nothing to drop")
		return false
	var tile := _player_tile()
	var assigned_tile := _find_ground_drop_tile(tile, {})
	if assigned_tile == Vector2i(-1, -1):
		_feedback("There is no safe place nearby to drop that item")
		return false
	var removed := _remove_inventory_item(item_id, min(quantity, _inventory_count(item_id)))
	if removed <= 0:
		_feedback("Nothing to drop")
		return false
	var item := {
		"object_id": _next_ground_drop_id(),
		"item_id": item_id,
		"quantity": removed,
		"tile": [assigned_tile.x, assigned_tile.y],
		"type": "ground_item",
	}
	if world != null and world.has_method("add_ground_drop") and not bool(world.add_ground_drop(assigned_tile, item)):
		_add_inventory_item(item_id, removed)
		_feedback("There is no safe place nearby to drop that item")
		return false
	var combat := _combat_state()
	var ground_items = combat.get("ground_items", [])
	if not (ground_items is Array):
		ground_items = []
	ground_items.append(item)
	combat["ground_items"] = ground_items
	_feedback("Dropped %d %s" % [removed, _item_name(item_id)])
	return true


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


func _handle_quest_route_select_requested(quest_id: String) -> void:
	var clean_id := quest_id.strip_edges()
	var definition := _quest_definition(clean_id)
	var quest_state = _quest_states().get(clean_id, {})
	if definition.is_empty() or not (quest_state is Dictionary):
		_feedback("That quest cannot be tracked yet.")
		return
	if not bool(quest_state.get("started", false)) or bool(quest_state.get("completed", false)):
		_feedback("Only started quests that are not complete can be tracked.")
		return
	var root := _quest_root()
	if str(root.get("active_quest_id", "")) == clean_id:
		_feedback("Already tracking %s." % str(definition.get("display_name", clean_id)))
		return
	root["active_quest_id"] = clean_id
	_sync_quest_state(root)
	_feedback("Tracking %s." % str(definition.get("display_name", clean_id)))
	_refresh_ui()


func _handle_inventory_item_action_requested(item_id: String, action: String) -> void:
	match action:
		"use":
			_use_item(item_id)
		"equip":
			_equip_item(item_id)
		"examine":
			_examine_item(item_id)
		"drop":
			_drop_inventory_item(item_id, 1)
		_:
			_feedback("Nothing happens")
	if hud != null and hud.has_method("show_item_action_panel") and _inventory_count(item_id) > 0:
		hud.show_item_action_panel(item_id)
	elif hud != null and hud.has_method("hide_interaction_panel"):
		hud.hide_interaction_panel()
	_refresh_ui()


func _handle_equipment_item_action_requested(slot: String, action: String) -> void:
	var item_id := str(_equipment().get(slot, ""))
	match action:
		"unequip":
			_unequip_item(slot)
		"examine":
			_examine_item(item_id)
		_:
			_feedback("Nothing happens")
	if hud != null and hud.has_method("show_equipment_action_panel") and not str(_equipment().get(slot, "")).is_empty():
		hud.show_equipment_action_panel(slot)
	elif hud != null and hud.has_method("hide_interaction_panel"):
		hud.hide_interaction_panel()
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
		_feedback(_inventory_full_message(_item_name(item_id)))
		return false
	bank_items[item_id] = available - quantity
	if int(bank_items[item_id]) <= 0:
		bank_items.erase(item_id)
	if not _add_inventory_item(item_id, quantity):
		bank_items[item_id] = int(bank_items.get(item_id, 0)) + quantity
		_feedback(_inventory_full_message(_item_name(item_id)))
		return false
	_record_quest_flag("used_bank")
	_feedback("Withdrew %d %s" % [quantity, _item_name(item_id)])
	return true


func _buy_shop_item(item_id: String, listed_price: int) -> bool:
	if item_id.is_empty():
		_feedback("Nothing to buy")
		return false
	var definition = items_data.get(item_id, {})
	if not (definition is Dictionary) or definition.is_empty():
		_feedback("That item is not available in this shop")
		return false
	var stock = active_shop_data.get("stock", []) if active_shop_data is Dictionary else []
	if not (stock is Array) or stock.is_empty():
		_feedback("That item is not available in this shop")
		return false
	var price := -1
	for entry in stock:
		if entry is Dictionary and str(entry.get("item_id", "")) == item_id:
			price = int(entry.get("price", 0))
			break
	if price <= 0:
		_feedback("That item is not available in this shop")
		return false
	if listed_price != price:
		_feedback("This shop listing is out of date; reopen the shop")
		return false
	if _inventory_count("coins") < price:
		_feedback("Not enough coins")
		return false
	if not _inventory_can_transact({"coins": price}, {item_id: 1}):
		_feedback(_inventory_full_message(_item_name(item_id)))
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
	if _is_protected_gathering_tool(item_id):
		_feedback("Keep your last %s for gathering" % _item_name(item_id))
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
	var has_buff := _definition_has_buff(definition)
	if heal_amount <= 0 and not cleanses_poison and not has_buff:
		_feedback("Nothing happens")
		return false
	var combat := _combat_state()
	var max_hitpoints := _skill_level("hitpoints")
	var current_hitpoints := int(combat.get("current_hitpoints", max_hitpoints))
	var can_heal := heal_amount > 0 and current_hitpoints < max_hitpoints
	var can_cleanse := cleanses_poison and _combat_is_poisoned()
	var can_satisfy_food_quest := heal_amount > 0 and _active_quest_missing_flag("ate_food")
	if not can_heal and not can_cleanse and not has_buff and not can_satisfy_food_quest:
		_feedback("Already at full health")
		return false
	var healed: int = min(heal_amount, max_hitpoints - current_hitpoints) if can_heal else 0
	_remove_inventory_item(item_id, 1)
	if healed > 0:
		_combat_set_hitpoints(current_hitpoints + healed)
	if can_cleanse:
		_clear_combat_poison()
	var buff_message := ""
	if has_buff:
		buff_message = _apply_item_buff(item_id, definition)
	_record_quest_flag("ate_food")
	var message := "Used %s" % _item_name(item_id)
	if healed > 0:
		message = "%s: healed %d HP" % [message, healed]
	elif can_satisfy_food_quest:
		message = "%s: saved for the quest" % message
	if can_cleanse:
		message = "%s; poison cleared" % message
	if not buff_message.is_empty():
		message = "%s; %s" % [message, buff_message]
	_feedback(message)
	return true


func _examine_item(item_id: String) -> void:
	var definition = items_data.get(item_id, {})
	if not (definition is Dictionary):
		_feedback("%s: nothing unusual." % _item_name(item_id))
		return
	var category := str(definition.get("category", "item"))
	var message := "%s: %s item" % [_item_name(item_id), category]
	if definition.has("sell_price"):
		message = "%s, sells for %d coins" % [message, int(definition["sell_price"])]
	if definition.has("equip_slot"):
		message = "%s, equips to %s" % [message, _display_label(str(definition["equip_slot"]))]
	if definition.has("heal_amount"):
		message = "%s, heals %d HP" % [message, int(definition["heal_amount"])]
	var effect_text := _item_buff_summary(definition)
	if not effect_text.is_empty():
		message = "%s, %s" % [message, effect_text]
	_feedback("%s." % message)


func _definition_has_buff(definition: Dictionary) -> bool:
	for key in BUFF_BONUS_KEYS:
		if float(definition.get(key, 0.0)) > 0.0:
			return true
	return false


func _apply_item_buff(item_id: String, definition: Dictionary) -> String:
	var duration := float(definition.get("effect_duration_seconds", 90.0))
	var buff := {"ends_at": _action_clock_seconds() + max(1.0, duration)}
	for key in BUFF_BONUS_KEYS:
		var value := float(definition.get(key, 0.0))
		if value > 0.0:
			buff[key] = value
	var buffs := _combat_buffs()
	buffs[item_id] = buff
	return "%s for %ds" % [_item_buff_summary(definition), int(duration)]


func _item_buff_summary(definition: Dictionary) -> String:
	var parts: Array[String] = []
	for key in BUFF_BONUS_KEYS:
		var value := float(definition.get(key, 0.0))
		if value <= 0.0:
			continue
		if key == "action_speed_bonus":
			parts.append("%d%% faster actions" % int(round(value * 100.0)))
		else:
			parts.append("+%d %s" % [int(value), _display_label(key.replace("_bonus", ""))])
	return ", ".join(parts)


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
	var quest_state := _quest_state_view(quest_id)
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
				message = _inventory_full_message("quest rewards")
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
	var quest_state := _quest_state_for(quest_id)
	if bool(quest_state.get("completed", false)):
		_feedback(str(definition.get("completed_text", "%s has nothing new." % label)))
		_sync_quest_state(root)
		return
	if not bool(quest_state.get("started", false)):
		root["active_quest_id"] = quest_id
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
		_feedback(_inventory_full_message("quest rewards"))
		_sync_quest_state(root)
		return
	if not _apply_quest_rewards(definition):
		_feedback(_inventory_full_message("quest rewards"))
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
	var definition = items_data.get(item_id, {})
	if not (definition is Dictionary):
		_feedback("%s cannot be equipped" % _item_name(item_id))
		return false
	var slot := str(definition.get("equip_slot", ""))
	if slot.is_empty():
		_feedback("%s cannot be equipped" % _item_name(item_id))
		return false
	if not _meets_item_skill_requirements(definition):
		return false
	var equipment := _equipment()
	var previous_item := str(equipment.get(slot, ""))
	if previous_item == item_id:
		_feedback("%s is already equipped to %s" % [_item_name(item_id), _display_label(slot)])
		return false
	var add_back := {}
	if not previous_item.is_empty():
		add_back[previous_item] = 1
	if not _inventory_can_transact({item_id: 1}, add_back):
		_feedback(_inventory_full_message(_item_name(item_id)))
		return false
	_remove_inventory_item(item_id, 1)
	if not previous_item.is_empty():
		_add_inventory_item(previous_item, 1)
	equipment[slot] = item_id
	if slot == "weapon":
		_record_quest_flag("equipped_weapon")
	if item_id in ["training_bow", "training_staff"]:
		_record_quest_flag("equipped_%s" % item_id)
	_feedback("Equipped %s to %s" % [_item_name(item_id), _display_label(slot)])
	return true


func _unequip_item(slot: String) -> bool:
	if slot.is_empty():
		_feedback("No equipment slot selected")
		return false
	var equipment := _equipment()
	var item_id := str(equipment.get(slot, ""))
	if item_id.is_empty():
		_feedback("No item equipped in %s" % _display_label(slot))
		return false
	if not _inventory_can_transact({}, {item_id: 1}):
		_feedback(_inventory_full_message(_item_name(item_id)))
		return false
	equipment.erase(slot)
	if not _add_inventory_item(item_id, 1):
		equipment[slot] = item_id
		_feedback(_inventory_full_message(_item_name(item_id)))
		return false
	_feedback("Unequipped %s from %s" % [_item_name(item_id), _display_label(slot)])
	return true


func _meets_item_skill_requirements(definition: Dictionary) -> bool:
	var requirements = definition.get("required_skills", {})
	if not (requirements is Dictionary):
		return true
	for skill_id in requirements.keys():
		var required_level := int(requirements[skill_id])
		if _skill_level(str(skill_id)) < required_level:
			_feedback("You need %s level %d" % [_skill_name(str(skill_id)), required_level])
			return false
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
	return root


func _active_quest_missing_flag(flag: String) -> bool:
	var root := _quest_root()
	var active_quest_id := str(root.get("active_quest_id", "starter_path"))
	var definition := _quest_definition(active_quest_id)
	if definition.is_empty():
		return false
	var quest_state := _quest_state_for(active_quest_id)
	if not bool(quest_state.get("started", false)) or bool(quest_state.get("completed", false)):
		return false
	for objective in _missing_objectives(definition, quest_state):
		if objective is Dictionary and str(objective.get("flag", "")) == flag:
			return true
	return false


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


func _quest_state_view(quest_id: String) -> Dictionary:
	var quests := _quest_states()
	var value = quests.get(quest_id, {})
	if value is Dictionary:
		return value.duplicate(true)
	return {"quest_id": quest_id, "started": false, "completed": false, "flags": []}


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
	_emit_persistent_state_changed()


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
		if _inventory_count(deposit_item_id) > 0 and deposit_item_id != "coins" and not _is_protected_gathering_tool(deposit_item_id):
			return deposit_item_id
	return ""


func _is_protected_gathering_tool(item_id: String) -> bool:
	if _inventory_count(item_id) > 1:
		return false
	var definition = items_data.get(item_id, {})
	return definition is Dictionary and not str(definition.get("tool_for", "")).is_empty()


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
	_emit_persistent_state_changed()
	if new_level > previous_level:
		return "%s level %d%s" % [_skill_name(skill_id), new_level, _unlock_suffix(skill_id, previous_level, new_level)]
	return ""


func _xp_gain_text(skill_id: String, amount: int) -> String:
	return "+%d %s XP (%s)" % [amount, _skill_name(skill_id), _skill_status_text(skill_id)]


func _skill_status_text(skill_id: String) -> String:
	return "%d XP, Lv %d" % [_skill_xp(skill_id), _skill_level(skill_id)]


func _combat_xp_summary(style: String, style_xp: int, hitpoints_xp: int, defence_xp: int) -> String:
	var parts: Array[String] = []
	var displayed_style_xp := style_xp
	if style == "defence":
		displayed_style_xp += defence_xp
	if displayed_style_xp > 0:
		parts.append("+%d %s XP" % [displayed_style_xp, _skill_name(style)])
	if hitpoints_xp > 0:
		parts.append("+%d HP XP" % hitpoints_xp)
	if defence_xp > 0 and style != "defence":
		parts.append("+%d Defence XP" % defence_xp)
	if parts.is_empty():
		return "no XP gained"
	return ", ".join(parts)


func _with_level_message(message: String, level_message: String) -> String:
	if level_message.strip_edges().is_empty():
		return message
	return "%s; %s" % [message, level_message]


func _join_non_empty(values: Array) -> String:
	var cleaned: Array[String] = []
	for value in values:
		var text := str(value).strip_edges()
		if not text.is_empty():
			cleaned.append(text)
	return "; ".join(cleaned)


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
		combat = {"current_hitpoints": 10, "mobs": {}, "ground_items": [], "ground_drop_sequence": 0, "status_effects": {}}
		state["combat"] = combat
	if not combat.has("mobs"):
		combat["mobs"] = {}
	if not combat.has("ground_items"):
		combat["ground_items"] = []
	if not combat.has("status_effects"):
		combat["status_effects"] = {}
	if not combat.has("ground_drop_sequence"):
		combat["ground_drop_sequence"] = 0
	if not combat.has("current_hitpoints"):
		combat["current_hitpoints"] = _skill_level("hitpoints")
	return combat


func _player_tile() -> Vector2i:
	var player_state = state.get("player", {})
	if player_state is Dictionary:
		var tile = player_state.get("tile", [15, 15])
		if tile is Vector2i:
			return tile
		if tile is Vector2:
			return Vector2i(int(tile.x), int(tile.y))
		if tile is Array and tile.size() >= 2:
			return Vector2i(int(tile[0]), int(tile[1]))
	return Vector2i(15, 15)


func _find_ground_drop_tile(origin: Vector2i, reserved: Dictionary) -> Vector2i:
	if world != null and world.has_method("find_ground_drop_tile"):
		var assigned = world.find_ground_drop_tile(origin, reserved)
		if assigned is Vector2i:
			return assigned
	for distance in range(0, 65):
		for y_offset in range(-distance, distance + 1):
			var x_distance: int = distance - absi(y_offset)
			var candidates: Array[Vector2i] = [origin + Vector2i(-x_distance, y_offset)]
			if x_distance > 0:
				candidates.append(origin + Vector2i(x_distance, y_offset))
			for candidate in candidates:
				if not reserved.has(candidate):
					return candidate
	return Vector2i(-1, -1)


func _next_ground_drop_id() -> String:
	var combat := _combat_state()
	var sequence := int(combat.get("ground_drop_sequence", 0)) + 1
	combat["ground_drop_sequence"] = sequence
	return "ground_item_%08d" % sequence


func _combat_status_effects() -> Dictionary:
	var combat := _combat_state()
	var status_effects = combat.get("status_effects", {})
	if not (status_effects is Dictionary):
		status_effects = {}
	combat["status_effects"] = status_effects
	return status_effects


func _combat_buffs() -> Dictionary:
	var status_effects := _combat_status_effects()
	var buffs = status_effects.get("buffs", {})
	if not (buffs is Dictionary):
		buffs = {}
	status_effects["buffs"] = buffs
	return buffs


func _active_combat_buffs() -> Dictionary:
	var buffs := _combat_buffs()
	var now := _action_clock_seconds()
	for item_id in buffs.keys():
		var buff = buffs[item_id]
		if not (buff is Dictionary) or float(buff.get("ends_at", 0.0)) <= now:
			buffs.erase(item_id)
	return buffs


func _buff_bonus(key: String) -> int:
	var total := 0.0
	for buff in _active_combat_buffs().values():
		if buff is Dictionary:
			total += float(buff.get(key, 0.0))
	return int(total)


func _action_speed_bonus() -> float:
	var total := 0.0
	for buff in _active_combat_buffs().values():
		if buff is Dictionary:
			total += float(buff.get("action_speed_bonus", 0.0))
	return clamp(total, 0.0, 0.35)


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


func _skill_mastery_effect_total(skill_id: String, effect_key: String) -> float:
	var definition = skills_data.get(skill_id, {})
	if not (definition is Dictionary):
		return 0.0
	var perks = definition.get("mastery_perks", [])
	if not (perks is Array):
		return 0.0
	var current_level := _skill_level(skill_id)
	var total := 0.0
	for perk in perks:
		if not (perk is Dictionary) or int(perk.get("level", 0)) > current_level:
			continue
		var effects = perk.get("effects", {})
		if effects is Dictionary:
			total += float(effects.get(effect_key, 0.0))
	return total


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
	_emit_persistent_state_changed()
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
	if removed > 0:
		_emit_persistent_state_changed()
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
	_emit_persistent_state_changed()


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
	var adjusted_seconds: float = max(0.25, seconds * (1.0 - _action_speed_bonus()))
	_action_cooldowns()[action_key] = _action_clock_seconds() + adjusted_seconds
	_emit_persistent_state_changed()


func _action_wait_seconds(action_key: String) -> int:
	var cooldowns := _action_cooldowns()
	if not cooldowns.has(action_key):
		return 0
	return max(1, int(ceil(float(cooldowns[action_key]) - _action_clock_seconds())))


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
	_emit_persistent_state_changed()


func _ensure_state_shape() -> void:
	state["schema"] = "hearthvale_godot_v2"
	state["version"] = 2
	var display_username := str(state.get("username", "player")).strip_edges()
	if display_username.is_empty():
		display_username = "player"
	var account = state.get("account", {})
	if not (account is Dictionary):
		account = {}
	account["username"] = str(account.get("username", display_username))
	account["key"] = str(account["username"]).to_lower()
	state["account"] = account
	state["username"] = str(account["username"])
	if not state.has("player") or not state["player"] is Dictionary:
		state["player"] = {"tile": [15, 15], "position": [15.5, 15.5]}
	if not state.has("camera") or not state["camera"] is Dictionary:
		state["camera"] = {"center_x": 15.0, "center_y": 15.0, "heading": 45.0, "zoom": 48.0}
	if not state.has("inventory") or not state["inventory"] is Dictionary:
		state["inventory"] = {}
	if not state.has("bank") or not state["bank"] is Dictionary:
		state["bank"] = {}
	if not state.has("equipment") or not state["equipment"] is Dictionary:
		state["equipment"] = {}
	if not state.has("skills") or not state["skills"] is Dictionary:
		state["skills"] = {}
	var carpentry_specialization := str(state.get("carpentry_specialization", "")).strip_edges().to_lower()
	state["carpentry_specialization"] = carpentry_specialization if CARPENTRY_SPECIALIZATIONS.has(carpentry_specialization) else ""
	if not state.has("combat_training_style"):
		state["combat_training_style"] = "attack"
	if not state.has("world") or not state["world"] is Dictionary:
		state["world"] = {}
	if not state.has("time") or not state["time"] is Dictionary:
		state["time"] = {"day": 1, "minute": 720.0}
	if not state.has("active_effects") or not state["active_effects"] is Array:
		state["active_effects"] = []
	if not state.has("settings") or not state["settings"] is Dictionary:
		state["settings"] = {}
	if not state.has("quest_state") or not (state["quest_state"] is Dictionary) or not state["quest_state"].has("quests"):
		state["quest_state"] = {"active_quest_id": "starter_path", "quests": {}}
	state.erase("quest_progress")
	var world_state: Dictionary = state["world"]
	for legacy_key in ["combat", "quest_state", "active_effects", "day", "minute"]:
		world_state.erase(legacy_key)
	_combat_state()


func _refresh_ui() -> void:
	if hud != null and hud.has_method("refresh_state"):
		hud.refresh_state()


func _interaction_panel_matches(expected_title: String) -> bool:
	if hud == null or not hud.has_method("interaction_panel_is_visible") or not hud.has_method("interaction_panel_title_text") or not hud.has_method("interaction_panel_row_count"):
		return false
	return bool(hud.call("interaction_panel_is_visible")) and str(hud.call("interaction_panel_title_text")) == expected_title and int(hud.call("interaction_panel_row_count")) > 0


func _feedback(message: String) -> void:
	last_feedback_text = message
	if hud != null and hud.has_method("set_feedback"):
		hud.set_feedback(message)


func _emit_persistent_state_changed() -> void:
	if state_bound:
		persistent_state_changed.emit()


func _trigger_activity_animation(activity: String) -> void:
	if world != null and world.has_method("trigger_activity_animation"):
		world.trigger_activity_animation(activity)


func _inventory_full_message(blocked_label: String = "") -> String:
	var label := blocked_label.strip_edges()
	if label.is_empty():
		return "Inventory is full — open Inv to Drop 1, or bank, sell, or use items to make room."
	return "Inventory is full — open Inv to Drop 1, or bank, sell, or use items to make room for %s." % label


func _last_feedback_contains_all(markers: Array) -> bool:
	var lower_feedback := last_feedback_text.to_lower()
	for marker in markers:
		if lower_feedback.find(str(marker).to_lower()) == -1:
			return false
	return true


func _mob_respawn_seconds(object_data: Dictionary) -> float:
	return max(0.0, float(object_data.get("respawn_seconds", 0.0)))


func _mob_respawn_ready(mob_state: Dictionary) -> bool:
	if not mob_state.has("respawn_at") or mob_state["respawn_at"] == null:
		return false
	return _action_clock_seconds() >= float(mob_state["respawn_at"])


func _mob_respawn_wait_message(label: String, mob_state: Dictionary) -> String:
	if mob_state.has("respawn_at") and mob_state["respawn_at"] != null:
		var remaining: int = max(1, int(ceil(float(mob_state["respawn_at"]) - _action_clock_seconds())))
		return "%s is defeated; wait %d seconds for it to return" % [label, remaining]
	return "%s is defeated" % label


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
