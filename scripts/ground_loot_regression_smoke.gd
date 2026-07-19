extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(7.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale ground loot regression smoke timed out.")
		quit(1)
	)
	var store = preload("res://autoload/state_store.gd").new()
	store.save_dir = "res://.godot_smoke_saves"
	var state := store.create_default_state("codex_ground_loot_regression_smoke")
	store.current_state = state
	state["inventory"]["logs"] = 2
	var world = preload("res://scenes/world.tscn").instantiate()
	var hud = preload("res://scenes/hud.tscn").instantiate()
	var gameplay = preload("res://scripts/test_support/gameplay_smoke_harness.gd").new()
	root.add_child(world)
	root.add_child(hud)
	root.add_child(gameplay)
	await process_frame
	gameplay.setup(state, world, hud, "manual")
	world.initialize_from_state(state)
	var mob := _first_mob(world)
	if mob.is_empty():
		_fail("no world mob was available")
		return
	var origin = mob.get("tile", Vector2i(-1, -1))
	mob["hitpoints"] = 1
	mob["passive"] = true
	mob["drops"] = [{"item_id": "coins", "quantity": 3}, {"item_id": "bones", "quantity": 1}]
	gameplay.attack_mob_for_smoke(mob)
	var drops: Array = state["combat"]["ground_items"]
	if drops.size() != 2 or not _drops_are_unique(drops) or not world.objects_by_tile.has(origin):
		_fail("multi-drop combat loot collided or replaced the mob")
		return
	var original_ids := [str(drops[0]["object_id"]), str(drops[1]["object_id"])]
	if not store.save_state("codex_ground_loot_regression_smoke", state):
		_fail("ground loot could not be saved")
		return
	var loaded := store.load_state("codex_ground_loot_regression_smoke")
	var restored_world = preload("res://scenes/world.tscn").instantiate()
	root.add_child(restored_world)
	await process_frame
	restored_world.initialize_from_state(loaded)
	var loaded_drops: Array = loaded["combat"]["ground_items"]
	if loaded_drops.size() != 2 or [str(loaded_drops[0]["object_id"]), str(loaded_drops[1]["object_id"])] != original_ids:
		_fail("saved ground items did not reload with stable IDs")
		return
	for drop in drops.duplicate(true):
		gameplay.pick_up_drop_for_smoke(drop)
	if not state["combat"]["ground_items"].is_empty() or int(state["inventory"].get("coins", 0)) < 3 or int(state["inventory"].get("bones", 0)) < 1:
		_fail("both combat drops were not independently collectible")
		return
	if not gameplay.drop_inventory_item_for_smoke("logs", 1) or not gameplay.drop_inventory_item_for_smoke("logs", 1):
		_fail("player drops failed")
		return
	if not _drops_are_unique(state["combat"]["ground_items"]):
		_fail("multiple player drops were not relocated uniquely")
		return
	world.queue_free()
	hud.queue_free()
	gameplay.queue_free()
	restored_world.queue_free()
	store.free()
	await process_frame
	print("Hearthvale ground loot regression smoke passed.")
	quit(0)


func _first_mob(world: Node) -> Dictionary:
	for object_data in world.objects_by_tile.values():
		if object_data is Dictionary and str(object_data.get("type", "")) == "mob":
			return object_data.duplicate(true)
	return {}


func _drops_are_unique(drops: Array) -> bool:
	var ids := {}
	var tiles := {}
	for drop in drops:
		if not (drop is Dictionary):
			return false
		var object_id := str(drop.get("object_id", ""))
		var tile = drop.get("tile", [])
		if object_id.is_empty() or ids.has(object_id) or not (tile is Array) or tile.size() < 2:
			return false
		var tile_key := "%d,%d" % [int(tile[0]), int(tile[1])]
		if tiles.has(tile_key):
			return false
		ids[object_id] = true
		tiles[tile_key] = true
	return true


func _fail(message: String) -> void:
	push_error("Hearthvale ground loot regression smoke failed: %s." % message)
	quit(1)
