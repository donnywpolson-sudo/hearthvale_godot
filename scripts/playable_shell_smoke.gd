extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store = preload("res://autoload/state_store.gd").new()
	store.current_state = store.create_default_state("codex_shell_smoke")
	var world = preload("res://scenes/world.tscn").instantiate()
	world.set_script(preload("res://scripts/test_support/world_smoke_harness.gd"))
	root.add_child(world)
	await process_frame
	world.initialize_from_state(store.current_state)
	var passed: bool = world.run_playable_shell_smoke()
	store.free()
	if passed:
		print("Hearthvale playable shell smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale playable shell smoke failed.")
		quit(1)
