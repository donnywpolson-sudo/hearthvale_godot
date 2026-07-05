extends RefCounted

const DEFAULT_INVENTORY_SLOT_LIMIT := 28


static func check_state(state: Dictionary, item_data: Dictionary = {}, options: Dictionary = {}) -> Array:
	var issues := []
	var slot_limit := int(options.get("inventory_slot_limit", DEFAULT_INVENTORY_SLOT_LIMIT))
	_check_mapping_shape(state, "inventory", issues)
	_check_mapping_shape(state, "bank", issues)
	_check_stack_mapping(_dict(state.get("inventory", {})), "inventory", item_data, issues)
	_check_stack_mapping(_dict(state.get("bank", {})), "bank", item_data, issues)
	_check_inventory_slots(_dict(state.get("inventory", {})), item_data, slot_limit, issues)
	_check_skills(_dict(state.get("skills", {})), issues)
	_check_combat(_dict(state.get("combat", {})), _dict(state.get("skills", {})), issues)
	_check_quest_state(_dict(state.get("quest_state", {})), issues)
	_check_world_state(_dict(state.get("world", {})), issues)
	return issues


static func _check_mapping_shape(state: Dictionary, key: String, issues: Array) -> void:
	if state.has(key) and not (state[key] is Dictionary):
		issues.append(_issue("state_shape", key, "%s must be a dictionary." % key.capitalize(), {
			"value_type": type_string(typeof(state[key])),
		}))


static func _check_stack_mapping(mapping: Dictionary, label: String, item_data: Dictionary, issues: Array) -> void:
	for raw_item_id in mapping.keys():
		var item_id := str(raw_item_id)
		var quantity := int(mapping[raw_item_id])
		if item_id.strip_edges().is_empty():
			issues.append(_issue("item_stack", label, "%s contains a blank item id." % label.capitalize(), {}))
		if quantity < 0:
			issues.append(_issue("item_stack", label, "%s item quantity became negative." % label.capitalize(), {
				"item_id": item_id,
				"quantity": quantity,
			}))
		if not item_data.is_empty() and not item_data.has(item_id):
			issues.append(_issue("item_reference", label, "%s references an unknown item id." % label.capitalize(), {
				"item_id": item_id,
				"quantity": quantity,
			}))


static func _check_inventory_slots(inventory: Dictionary, item_data: Dictionary, slot_limit: int, issues: Array) -> void:
	var slots := _inventory_slot_count(inventory, item_data)
	if slots > slot_limit:
		issues.append(_issue("inventory_capacity", "inventory", "Inventory uses more slots than the configured limit.", {
			"slots": slots,
			"slot_limit": slot_limit,
		}))


static func _check_skills(skills: Dictionary, issues: Array) -> void:
	for raw_skill_id in skills.keys():
		var skill_id := str(raw_skill_id)
		var skill = skills[raw_skill_id]
		if not (skill is Dictionary):
			issues.append(_issue("skill_shape", "skills", "Skill entry must be a dictionary.", {"skill_id": skill_id}))
			continue
		var skill_data: Dictionary = skill
		var level := int(skill_data.get("level", 0))
		var xp := int(skill_data.get("xp", 0))
		if level <= 0:
			issues.append(_issue("skill_level", "skills", "Skill level must be positive.", {
				"skill_id": skill_id,
				"level": level,
			}))
		if xp < 0:
			issues.append(_issue("skill_xp", "skills", "Skill XP became negative.", {
				"skill_id": skill_id,
				"xp": xp,
			}))


static func _check_combat(combat: Dictionary, skills: Dictionary, issues: Array) -> void:
	var max_hp := 10
	var hitpoints = skills.get("hitpoints", {})
	if hitpoints is Dictionary:
		max_hp = int(hitpoints.get("level", max_hp))
	var hp := int(combat.get("current_hitpoints", max_hp))
	if hp < 0 or hp > max_hp:
		issues.append(_issue("combat_hitpoints", "combat", "Combat hitpoints moved outside valid bounds.", {
			"hitpoints": hp,
			"max_hitpoints": max_hp,
		}))
	if combat.has("status_effects") and not (combat["status_effects"] is Dictionary):
		issues.append(_issue("combat_status_shape", "combat", "Combat status_effects must be a dictionary.", {
			"value_type": type_string(typeof(combat["status_effects"])),
		}))


static func _check_quest_state(quest_root: Dictionary, issues: Array) -> void:
	if quest_root.has("quests") and not (quest_root["quests"] is Dictionary):
		issues.append(_issue("quest_shape", "quest_state", "Quest state has an invalid quests shape.", {}))
		return
	var quest_states = quest_root.get("quests", {})
	if not (quest_states is Dictionary):
		return
	for raw_quest_id in quest_states.keys():
		var quest_id := str(raw_quest_id)
		var quest_state = quest_states[raw_quest_id]
		if not (quest_state is Dictionary):
			issues.append(_issue("quest_entry_shape", "quest_state", "Quest entry must be a dictionary.", {"quest_id": quest_id}))
			continue
		var quest_data: Dictionary = quest_state
		if quest_data.has("flags") and not (quest_data["flags"] is Array):
			issues.append(_issue("quest_flags_shape", "quest_state", "Quest flags must be an array.", {"quest_id": quest_id}))


static func _check_world_state(world_state: Dictionary, issues: Array) -> void:
	if world_state.has("resource_nodes") and not (world_state["resource_nodes"] is Dictionary):
		issues.append(_issue("world_resource_shape", "world", "World resource_nodes must be a dictionary.", {}))
		return
	var nodes = world_state.get("resource_nodes", {})
	if not (nodes is Dictionary):
		return
	var clock := float(world_state.get("action_clock_seconds", 0.0))
	if clock < 0.0:
		issues.append(_issue("world_clock", "world", "World action clock became negative.", {"action_clock_seconds": clock}))
	for raw_node_id in nodes.keys():
		var node_id := str(raw_node_id)
		var node_state = nodes[raw_node_id]
		if not (node_state is Dictionary):
			issues.append(_issue("world_resource_entry_shape", "world", "World resource node state must be a dictionary.", {"node_id": node_id}))
			continue
		var node_data: Dictionary = node_state
		if node_data.has("respawn_at") and node_data["respawn_at"] != null and float(node_data["respawn_at"]) < 0.0:
			issues.append(_issue("world_respawn", "world", "Resource respawn time became negative.", {
				"node_id": node_id,
				"respawn_at": float(node_data["respawn_at"]),
			}))


static func _inventory_slot_count(mapping: Dictionary, item_data: Dictionary) -> int:
	var total := 0
	for raw_item_id in mapping.keys():
		var item_id := str(raw_item_id)
		var quantity := int(mapping[raw_item_id])
		if quantity <= 0:
			continue
		if _is_stackable_item(item_id, item_data):
			total += 1
		else:
			total += quantity
	return total


static func _is_stackable_item(item_id: String, item_data: Dictionary) -> bool:
	var definition = item_data.get(item_id, {})
	if definition is Dictionary and definition.has("stackable"):
		return bool(definition["stackable"])
	return item_id == "coins"


static func _dict(value) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


static func _issue(code: String, category: String, summary: String, metadata: Dictionary) -> Dictionary:
	return {
		"code": code,
		"category": category,
		"summary": summary,
		"metadata": metadata,
	}
