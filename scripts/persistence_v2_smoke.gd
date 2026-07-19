extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var base_dir := "res://.godot_smoke_saves/persistence_v2_%d" % Time.get_ticks_usec()
	var store = preload("res://autoload/state_store.gd").new()
	store.save_dir = base_dir
	if not _check_recovery_matrix(store):
		quit(1)
		return
	if not _check_migrations(store):
		quit(1)
		return
	if not _check_case_identity(store):
		quit(1)
		return
	if not _check_failed_promotion(base_dir):
		quit(1)
		return
	store.free()
	print("Hearthvale persistence v2 smoke passed.")
	quit(0)


func _check_recovery_matrix(store: Node) -> bool:
	var primary_state: Dictionary = store.create_default_state("backup_recovery")
	primary_state["inventory"]["coins"] = 1
	store.current_state = primary_state
	if not store.save_state("backup_recovery", primary_state):
		return _fail("initial recovery save failed")
	primary_state["inventory"]["coins"] = 2
	if not store.save_state("backup_recovery", primary_state):
		return _fail("backup rotation save failed")
	_write_text(store.get_save_path("backup_recovery"), "{broken")
	var recovered: Dictionary = store.load_state("backup_recovery")
	if recovered.is_empty() or int(recovered["inventory"].get("coins", 0)) != 1:
		return _fail("corrupt primary did not fall back to its valid backup")

	var valid_primary: Dictionary = store.create_default_state("valid_primary")
	store.current_state = valid_primary
	if not store.save_state("valid_primary", valid_primary) or not store.save_state("valid_primary", valid_primary):
		return _fail("valid-primary fixture save failed")
	_write_text("%s.bak" % store.get_save_path("valid_primary"), "not json")
	if store.load_state("valid_primary").is_empty():
		return _fail("a corrupt backup prevented loading a valid primary")

	_write_text(store.get_save_path("valid_primary"), "not json")
	if not store.load_state("valid_primary").is_empty() or str(store.last_error).is_empty():
		return _fail("corrupt primary and backup did not fail closed")

	var interrupted: Dictionary = store.create_default_state("interrupted")
	store.current_state = interrupted
	if not store.save_state("interrupted", interrupted):
		return _fail("interrupted fixture save failed")
	_write_text("%s.tmp" % store.get_save_path("interrupted"), "partial")
	if store.load_state("interrupted").is_empty():
		return _fail("an interrupted temporary write hid a valid primary")

	_write_text("%s.tmp" % store.get_save_path("orphan_temp"), JSON.stringify(store.create_default_state("orphan_temp")))
	if not store.load_state("orphan_temp").is_empty() or str(store.last_error).is_empty():
		return _fail("an orphan temporary write was treated as a new account")

	var staged_state: Dictionary = store.create_default_state("staged_primary")
	staged_state["inventory"]["coins"] = 17
	store.current_state = staged_state
	if not store.save_state("staged_primary", staged_state):
		return _fail("staged-primary fixture save failed")
	var staged_path: String = store.get_save_path("staged_primary")
	var stage_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(staged_path), ProjectSettings.globalize_path("%s.old" % staged_path))
	if stage_error != OK:
		return _fail("could not stage the recovery fixture")
	var staged_recovered: Dictionary = store.load_or_create_state("staged_primary")
	if staged_recovered.is_empty() or int(staged_recovered["inventory"].get("coins", 0)) != 17:
		return _fail("a validated staged primary was not recovered")
	if not FileAccess.file_exists(staged_path) or FileAccess.file_exists("%s.old" % staged_path):
		return _fail("staged-primary recovery did not restore the canonical primary")
	return true


func _check_migrations(store: Node) -> bool:
	for form in ["nested", "progress", "flat"]:
		var username := "migration_%s" % form
		var legacy: Dictionary = store.create_default_state(username)
		legacy["schema"] = "hearthvale_godot_reset_v1"
		legacy["version"] = 1
		var quest := {"quest_id": "starter_path", "started": true, "completed": false, "flags": ["created_save"]}
		match form:
			"nested":
				legacy["quest_state"] = {"active_quest_id": "starter_path", "quests": {"starter_path": quest}}
				legacy["quest_progress"] = {"ignored": {"started": true}}
			"progress":
				legacy["quest_state"] = {}
				legacy["quest_progress"] = {"starter_path": quest}
			"flat":
				legacy["quest_state"] = {"starter_path": quest}
				legacy.erase("quest_progress")
		legacy["world"]["combat"] = legacy["combat"].duplicate(true)
		_write_text(store.get_save_path(username), JSON.stringify(legacy))
		var migrated: Dictionary = store.load_or_create_state(username)
		if migrated.is_empty() or str(migrated.get("schema", "")) != "hearthvale_godot_v2" or migrated.has("quest_progress"):
			return _fail("%s v1 fixture did not migrate to canonical v2" % form)
		var quests = migrated.get("quest_state", {}).get("quests", {})
		if not (quests is Dictionary) or not quests.has("starter_path") or migrated["world"].has("combat"):
			return _fail("%s v1 fixture lost canonical quest/combat state" % form)
	return true


func _check_case_identity(store: Node) -> bool:
	var state: Dictionary = store.create_default_state("Alice")
	store.current_state = state
	if not store.save_state("Alice", state):
		return _fail("case-insensitive account fixture save failed")
	var loaded: Dictionary = store.load_state("alice")
	if loaded.is_empty() or str(loaded.get("account", {}).get("username", "")) != "Alice":
		return _fail("Alice and alice did not resolve to one display-preserving account")
	var first: Dictionary = store.create_default_state("CaseConflict")
	var second: Dictionary = store.create_default_state("caseconflict")
	for value in [first, second]:
		value["schema"] = "hearthvale_godot_reset_v1"
		value["version"] = 1
	_write_text("%s/CaseConflict.json" % store.save_dir, JSON.stringify(first))
	_write_text("%s/CaseConflict_legacy.json" % store.save_dir, JSON.stringify(second))
	if not store.load_state("caseconflict").is_empty() or not str(store.last_error).contains("Conflicting"):
		return _fail("conflicting legacy account variants did not fail closed")
	return true


func _check_failed_promotion(base_dir: String) -> bool:
	var normal_store = preload("res://autoload/state_store.gd").new()
	normal_store.save_dir = base_dir
	var state: Dictionary = normal_store.create_default_state("promotion_failure")
	normal_store.current_state = state
	if not normal_store.save_state("promotion_failure", state):
		return _fail("promotion fixture save failed")
	var failing_store = preload("res://scripts/test_support/failing_promotion_state_store.gd").new()
	failing_store.save_dir = base_dir
	failing_store.current_state = state
	state["inventory"]["coins"] = 99
	if failing_store.save_state("promotion_failure", state):
		return _fail("injected failed promotion reported success")
	var loaded: Dictionary = normal_store.load_state("promotion_failure")
	if loaded.is_empty() or int(loaded["inventory"].get("coins", 0)) == 99:
		normal_store.free()
		failing_store.free()
		return _fail("failed promotion did not restore the previous primary")
	normal_store.free()
	failing_store.free()
	return true


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _fail(message: String) -> bool:
	push_error("Hearthvale persistence v2 smoke failed: %s." % message)
	return false
