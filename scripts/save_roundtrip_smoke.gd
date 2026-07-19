extends SceneTree


func _init() -> void:
	var store = preload("res://autoload/state_store.gd").new()
	store.save_dir = "res://.godot_smoke_saves"
	var passed: bool = store.run_save_roundtrip_smoke("codex_save_roundtrip_%d" % Time.get_ticks_usec())
	store.free()
	if passed:
		print("Hearthvale save round-trip smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale save round-trip smoke failed.")
		quit(1)
