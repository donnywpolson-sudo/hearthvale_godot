extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(10.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale runtime integration smoke timed out.")
		quit(1)
	)
	var main = preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var store = main.get("state_store")
	if store == null:
		_fail("StateStore was not wired")
		return
	store.save_dir = "res://.godot_smoke_saves"
	var runtime_username := "codex_runtime_integration_%d" % Time.get_ticks_usec()
	main.call("_start_world", runtime_username)
	await process_frame
	await process_frame
	var gameplay = main.get("gameplay")
	var world = main.get("world")
	if gameplay == null or world == null or str(gameplay.get("clock_mode")) != "realtime":
		_fail("runtime gameplay wiring did not use the realtime clock")
		return
	var clock_before := float(store.current_state.get("world", {}).get("action_clock_seconds", 0.0))
	await create_timer(0.2).timeout
	var clock_after := float(store.current_state.get("world", {}).get("action_clock_seconds", 0.0))
	if clock_after <= clock_before:
		_fail("runtime action clock did not advance across real frames")
		return
	var resource := _first_usable_resource(world)
	if resource.is_empty():
		_fail("no usable resource was available through the real world scene")
		return
	var item_id := str(resource.get("item_reward", ""))
	resource = resource.duplicate(true)
	resource["id"] = "runtime_integration_resource"
	resource["base_gather_seconds"] = 0.15
	resource["respawn_seconds"] = 0.2
	var before_count := int(store.current_state.get("inventory", {}).get(item_id, 0))
	world.object_activated.emit(resource)
	await process_frame
	var after_count := int(store.current_state.get("inventory", {}).get(item_id, 0))
	if after_count <= before_count:
		_fail("the actual world-to-gameplay signal did not mutate inventory")
		return
	var first_gather_count := after_count
	world.object_activated.emit(resource)
	await process_frame
	if int(store.current_state.get("inventory", {}).get(item_id, 0)) != after_count:
		_fail("a realtime resource cooldown allowed an immediate repeat")
		return
	await create_timer(0.3).timeout
	world.object_activated.emit(resource)
	await process_frame
	after_count = int(store.current_state.get("inventory", {}).get(item_id, 0))
	if after_count <= first_gather_count:
		_fail("a realtime resource cooldown or respawn did not expire")
		return
	var mob := _first_mob(world)
	if mob.is_empty():
		_fail("no mob was available for realtime respawn verification")
		return
	mob = mob.duplicate(true)
	mob["id"] = "runtime_integration_mob"
	mob["hitpoints"] = 1
	mob["passive"] = true
	mob["drops"] = []
	mob["respawn_seconds"] = 0.2
	var attack_xp_before := int(store.current_state.get("skills", {}).get("attack", {}).get("xp", 0))
	world.object_activated.emit(mob)
	await process_frame
	var attack_xp_after := int(store.current_state.get("skills", {}).get("attack", {}).get("xp", 0))
	world.object_activated.emit(mob)
	await process_frame
	if int(store.current_state.get("skills", {}).get("attack", {}).get("xp", 0)) != attack_xp_after:
		_fail("a defeated mob was attackable before its realtime respawn")
		return
	await create_timer(0.3).timeout
	world.object_activated.emit(mob)
	await process_frame
	if attack_xp_after <= attack_xp_before or int(store.current_state.get("skills", {}).get("attack", {}).get("xp", 0)) <= attack_xp_after:
		_fail("a defeated mob did not respawn on the realtime clock")
		return
	await create_timer(1.2).timeout
	var loaded: Dictionary = store.load_state(runtime_username)
	if loaded.is_empty() or int(loaded.get("inventory", {}).get(item_id, 0)) != after_count:
		_fail("debounced runtime autosave did not persist the action")
		return
	world.reset_camera_north()
	var movement_tile: Vector2i = world.find_ground_drop_tile(world.current_tile + Vector2i(1, 0))
	if movement_tile == Vector2i(-1, -1) or not world.debug_teleport_to_tile(movement_tile):
		_fail("no safe movement tile was available for autosave verification")
		return
	await create_timer(1.2).timeout
	loaded = store.load_state(runtime_username)
	if loaded.is_empty() or absf(float(loaded.get("camera", {}).get("heading", -1.0))) > 0.01 or _state_tile(loaded) != movement_tile:
		_fail("camera and movement changes were not coalesced into autosave")
		return
	var exit_tile: Vector2i = world.find_ground_drop_tile(movement_tile + Vector2i(1, 0))
	if exit_tile == Vector2i(-1, -1) or not world.debug_teleport_to_tile(exit_tile):
		_fail("no safe tile was available for exit-flush verification")
		return
	main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	loaded = store.load_state(runtime_username)
	if loaded.is_empty() or _state_tile(loaded) != exit_tile:
		_fail("orderly exit did not flush pending state")
		return
	print("Hearthvale runtime integration smoke passed.")
	quit(0)


func _first_usable_resource(world: Node) -> Dictionary:
	var objects = world.get("objects_by_tile")
	if not (objects is Dictionary):
		return {}
	for object_data in objects.values():
		if object_data is Dictionary and str(object_data.get("type", "")) == "resource" and int(object_data.get("required_level", 1)) <= 1:
			return object_data
	return {}


func _first_mob(world: Node) -> Dictionary:
	var objects = world.get("objects_by_tile")
	if not (objects is Dictionary):
		return {}
	for object_data in objects.values():
		if object_data is Dictionary and str(object_data.get("type", "")) == "mob":
			return object_data
	return {}


func _state_tile(state: Dictionary) -> Vector2i:
	var tile = state.get("player", {}).get("tile", [])
	if tile is Array and tile.size() >= 2:
		return Vector2i(int(tile[0]), int(tile[1]))
	return Vector2i(-1, -1)


func _fail(message: String) -> void:
	push_error("Hearthvale runtime integration smoke failed: %s." % message)
	quit(1)
