extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(4.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale visual recreation smoke timed out.")
		quit(1)
	)

	var store = preload("res://autoload/state_store.gd").new()
	store.current_state = store.create_default_state("codex_visual_recreation_smoke")
	var world = preload("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	world.initialize_from_state(store.current_state)
	var passed: bool = world.run_visual_recreation_smoke()
	store.free()
	if passed:
		print("Hearthvale visual recreation smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale visual recreation smoke failed.")
		quit(1)
