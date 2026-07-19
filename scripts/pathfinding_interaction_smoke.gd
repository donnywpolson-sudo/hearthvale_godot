extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(4.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale pathfinding interaction smoke timed out.")
		quit(1)
	)
	var store = preload("res://autoload/state_store.gd").new()
	store.current_state = store.create_default_state("codex_pathfinding_smoke")
	var world = preload("res://scenes/world.tscn").instantiate()
	world.set_script(preload("res://scripts/test_support/world_smoke_harness.gd"))
	root.add_child(world)
	await process_frame
	if not world.has_method("initialize_from_state") or not world.has_method("run_pathfinding_interaction_smoke"):
		push_error("Hearthvale pathfinding interaction smoke failed to load world script.")
		quit(1)
		return
	world.initialize_from_state(store.current_state)
	var passed: bool = world.run_pathfinding_interaction_smoke()
	store.free()
	if passed:
		print("Hearthvale pathfinding interaction smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale pathfinding interaction smoke failed.")
		quit(1)
