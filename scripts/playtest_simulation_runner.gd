extends SceneTree

const WORLD_PATH := "res://data/world.json"
const ITEMS_PATH := "res://data/items.json"
const SKILLS_PATH := "res://data/skills.json"
const RECIPES_PATH := "res://data/recipes.json"
const QUESTS_PATH := "res://data/quests.json"
const DEFAULT_OUTPUT_DIR := "res://.godot_logs/simulation"
const DEFAULT_PUBLIC_OUTPUT_ROOT := "res://.godot/ai_simulation"
const DEFAULT_RUNS := 1000
const DEFAULT_STEPS := 300
const DEFAULT_SEED := 1
const DEFAULT_SCENARIO := "all"
const DEFAULT_TRACE := "issues"
const DEFAULT_BALANCE_PROFILE := "default"
const DEFAULT_TIMEOUT_SECONDS := 0.0
const DEFAULT_SCENARIO_PROBES := "auto"
const DEFAULT_CAMPAIGN := "baseline"
const DEFAULT_QUEST_POLICY := "baseline"
const CAMPAIGNS := ["baseline", "adversarial", "content", "opportunity", "replay"]
const QUEST_POLICIES := ["baseline", "aware"]
const INVENTORY_SLOT_LIMIT := 28
const PERF_BUDGET_AVERAGE_ACTION_USEC := 16667.0
const PERF_BUDGET_SLOW_ACTION_RATE := 0.25
const PERF_BUDGET_SLOWEST_ACTION_USEC := 50000.0
const PERF_BUDGET_AVERAGE_PATH_LENGTH := 16.0
const PERF_BUDGET_MAX_PATH_LENGTH := 32
const InvariantChecker = preload("res://scripts/invariant_checker.gd")
const StateSnapshot = preload("res://scripts/state_snapshot.gd")
const SCENARIOS := [
	"core_loop",
	"quest_chaser",
	"economy_stress",
	"combat_loot",
	"inventory_pressure",
	"random_guard",
]
const BALANCE_PROFILES := {
	"default": {
		"label": "Default coverage",
		"scenario_mix": ["core_loop", "quest_chaser", "economy_stress", "combat_loot", "inventory_pressure", "random_guard"],
		"focus": "Broad gameplay coverage for bugs, softlocks, QOL, and general balance signals.",
	},
	"progression": {
		"label": "Progression loop",
		"scenario_mix": ["core_loop", "core_loop", "quest_chaser", "inventory_pressure"],
		"focus": "XP gain, quest completion, inventory pressure, and early loop value flow.",
	},
	"economy": {
		"label": "Economy loop",
		"scenario_mix": ["economy_stress", "economy_stress", "core_loop", "inventory_pressure"],
		"focus": "Coin gain/spend, sell value, bank/shop pressure, and net worth growth.",
	},
	"combat": {
		"label": "Combat loop",
		"scenario_mix": ["combat_loot", "combat_loot", "core_loop", "inventory_pressure"],
		"focus": "Survival, damage taken, mob defeats, drops, recovery item pressure, and loot value.",
	},
	"coverage": {
		"label": "Coverage loop",
		"scenario_mix": ["core_loop", "quest_chaser", "economy_stress", "combat_loot", "inventory_pressure", "random_guard", "random_guard"],
		"focus": "Broadest scenario rotation with extra random guard pressure for edge cases.",
	},
}
const STATION_KEYS := [
	"bank",
	"shop",
	"cooking_range",
	"furnace",
	"anvil",
	"carpentry_bench",
	"apothecary_table",
]
const PROCESSING_SKILLS := {
	"smelting": "smithing",
	"smithing": "smithing",
	"carpentry": "carpentry",
	"herbalism": "herbalism",
}
const FAILURE_MARKERS := [
	"need ",
	"full",
	"nothing",
	"no ",
	"too wounded",
	"still in progress",
	"still being",
	"select ",
	"choose ",
	"depleted",
]

var config := {}
var world_data := {}
var items_data := {}
var skills_data := {}
var recipes_data := {}
var quests_data := {}
var resources := []
var mobs := []
var npcs := []
var stations := {}

var runs_file: FileAccess
var issues_file: FileAccess
var trace_file: FileAccess
var issue_groups := {}
var issue_sample_count := 0
var issue_occurrence_count := 0
var run_summaries := []
var scenario_metrics := {}
var replay_metadata := {}
var telemetry_summary := {}
var polish_telemetry_summary := {}
var scenario_probe_report := {}
var coverage_ledger := {}
var trust_context := {}
var previous_latest_context := {}
var latest_publish_status := "not_requested"

var current_state := {}
var current_world: Node
var current_hud: CanvasLayer
var current_gameplay: Node
var current_rng: RandomNumberGenerator
var current_seed := 0
var current_run_index := 0
var current_scenario := ""
var current_step := 0
var current_last_actions := []
var current_feedback_counts := {}
var current_issue_counts := {}
var current_issue_occurrences := 0
var current_issue_samples := 0
var current_max_no_progress_streak := 0
var current_no_progress_streak := 0
var current_run_telemetry := {}
var current_run_polish_telemetry := {}
var current_polish_feedback_counts := {}
var last_progress_percent_printed := -1
var last_progress_status := ""
var progress_started_msec := 0
var timeout_deadline_msec := 0
var timeout_abort_requested := false
var scenario_probe_active := false
var current_probe_issues := []
var current_quest_policy_protected_items := {}
var current_quest_policy_target_item := ""
var current_quest_policy_target_quantity := 0
var current_quest_policy_objective_flag := ""
var current_quest_policy_quest_id := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	config = _parse_args()
	if bool(config.get("help_requested", false)):
		quit(0)
		return
	if not _validate_config():
		quit(1)
		return

	timeout_abort_requested = false
	timeout_deadline_msec = 0
	if float(config["timeout_seconds"]) > 0.0:
		timeout_deadline_msec = Time.get_ticks_msec() + int(ceil(float(config["timeout_seconds"]) * 1000.0))
		var watchdog := create_timer(float(config["timeout_seconds"]))
		watchdog.timeout.connect(func() -> void:
			_request_timeout_abort()
		)

	_load_data()
	_discover_content()
	_initialize_coverage_ledger()
	trust_context = _build_trust_context()
	previous_latest_context = _read_previous_latest_context()
	_apply_latest_publish_status()
	replay_metadata = _build_replay_metadata()
	telemetry_summary = _new_telemetry_bucket()
	polish_telemetry_summary = _new_polish_bucket()
	last_progress_percent_printed = -1
	last_progress_status = ""
	progress_started_msec = Time.get_ticks_msec()
	if not _prepare_output_dir():
		quit(1)
		return
	_write_progress("starting", 0, 0, "")
	if not _open_outputs():
		quit(1)
		return

	for run_index in range(int(config["runs"])):
		if _timeout_exceeded():
			_request_timeout_abort()
			return
		var run_summary := await _run_single_simulation(run_index)
		if timeout_abort_requested or _timeout_exceeded():
			_request_timeout_abort()
			return
		_write_json_line(runs_file, run_summary)
		_update_scenario_metrics(run_summary)
		_update_telemetry_summary(run_summary)
		_update_polish_telemetry_summary(run_summary)
		run_summaries.append(_compact_run_summary_for_reports(run_summary))
		# Scene runs free HUD/world nodes immediately, but Godot may defer part of
		# the queued render/UI cleanup until the next frame. Yield between runs so
		# long audits do not accumulate deferred resources across scene lifecycles.
		if run_index + 1 < int(config["runs"]):
			await process_frame

	# Probe contexts free their HUD/world/gameplay nodes immediately. Give Godot
	# one frame to finish deferred scene/UI cleanup before report finalization.
	_write_progress("scenario_probes", int(config["runs"]), 0, "scenario_probes")
	scenario_probe_report = await _run_scenario_probes()
	await process_frame
	trust_context = _build_trust_context()
	_apply_latest_publish_status()
	replay_metadata["trust"] = trust_context.duplicate(true)
	_write_progress("writing_reports", int(config["runs"]), 0, "")
	_write_summary_file()
	_write_improvement_plan()
	_write_codex_prompt()
	_close_outputs()
	var failed_on_issues := bool(config["fail_on_issues"]) and issue_occurrence_count > 0
	if not failed_on_issues and bool(config.get("publish_latest", false)) and not _publish_latest_outputs():
		quit(1)
		return
	_write_progress("completed", int(config["runs"]), 0, "")

	if OS.get_environment("HV_SIM_LAUNCHER") != "1":
		_print_completion_summary()
	if failed_on_issues:
		quit(1)
	else:
		quit(0)


func _parse_args() -> Dictionary:
	var parsed := {
		"runs": DEFAULT_RUNS,
		"steps": DEFAULT_STEPS,
		"seed": DEFAULT_SEED,
		"scenario": DEFAULT_SCENARIO,
		"trace": DEFAULT_TRACE,
		"balance_profile": DEFAULT_BALANCE_PROFILE,
		"scenario_probes": DEFAULT_SCENARIO_PROBES,
		"campaign": DEFAULT_CAMPAIGN,
		"quest_policy": DEFAULT_QUEST_POLICY,
		"output_dir": DEFAULT_OUTPUT_DIR,
		"public_output_root": DEFAULT_PUBLIC_OUTPUT_ROOT,
		"publish_latest": false,
		"allow_latest_downgrade": false,
		"require_publish_latest": false,
		"timeout_seconds": DEFAULT_TIMEOUT_SECONDS,
		"fail_on_issues": false,
		"help_requested": false,
		"parse_errors": [],
	}
	var errors := []
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var arg := str(args[index])
		match arg:
			"--runs":
				var runs_value := _arg_value(args, index, arg, errors)
				if not runs_value.is_empty():
					index += 1
					if runs_value.is_valid_int():
						parsed["runs"] = int(runs_value)
					else:
						errors.append("--runs must be an integer.")
			"--steps":
				var steps_value := _arg_value(args, index, arg, errors)
				if not steps_value.is_empty():
					index += 1
					if steps_value.is_valid_int():
						parsed["steps"] = int(steps_value)
					else:
						errors.append("--steps must be an integer.")
			"--seed":
				var seed_value := _arg_value(args, index, arg, errors)
				if not seed_value.is_empty():
					index += 1
					if seed_value.is_valid_int():
						parsed["seed"] = int(seed_value)
					else:
						errors.append("--seed must be an integer.")
			"--scenario":
				var scenario_value := _arg_value(args, index, arg, errors)
				if not scenario_value.is_empty():
					index += 1
					parsed["scenario"] = scenario_value
			"--trace":
				var trace_value := _arg_value(args, index, arg, errors)
				if not trace_value.is_empty():
					index += 1
					parsed["trace"] = trace_value
			"--balance-profile":
				var profile_value := _arg_value(args, index, arg, errors)
				if not profile_value.is_empty():
					index += 1
					parsed["balance_profile"] = profile_value
			"--scenario-probes":
				var probe_value := _arg_value(args, index, arg, errors)
				if not probe_value.is_empty():
					index += 1
					parsed["scenario_probes"] = probe_value
			"--campaign":
				var campaign_value := _arg_value(args, index, arg, errors)
				if not campaign_value.is_empty():
					index += 1
					parsed["campaign"] = campaign_value
			"--quest-policy":
				var quest_policy_value := _arg_value(args, index, arg, errors)
				if not quest_policy_value.is_empty():
					index += 1
					parsed["quest_policy"] = quest_policy_value
			"--output-dir":
				var output_value := _arg_value(args, index, arg, errors)
				if not output_value.is_empty():
					index += 1
					parsed["output_dir"] = output_value
			"--public-output-root":
				var public_output_value := _arg_value(args, index, arg, errors)
				if not public_output_value.is_empty():
					index += 1
					parsed["public_output_root"] = public_output_value
			"--timeout-seconds":
				var timeout_value := _arg_value(args, index, arg, errors)
				if not timeout_value.is_empty():
					index += 1
					if timeout_value.is_valid_float():
						parsed["timeout_seconds"] = float(timeout_value)
					else:
						errors.append("--timeout-seconds must be a number.")
			"--fail-on-issues":
				parsed["fail_on_issues"] = true
			"--publish-latest":
				parsed["publish_latest"] = true
			"--allow-latest-downgrade":
				parsed["allow_latest_downgrade"] = true
			"--require-publish-latest":
				parsed["require_publish_latest"] = true
			"--help":
				_print_usage()
				parsed["help_requested"] = true
			_:
				errors.append("Unknown playtest simulation argument: %s" % arg)
		index += 1
	parsed["parse_errors"] = errors
	return parsed


func _timeout_exceeded() -> bool:
	return timeout_deadline_msec > 0 and Time.get_ticks_msec() >= timeout_deadline_msec


func _request_timeout_abort() -> void:
	if timeout_abort_requested:
		return
	timeout_abort_requested = true
	_write_progress("timed_out", current_run_index, current_step, current_scenario)
	push_error("Hearthvale playtest simulation timed out after %s seconds." % str(config.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS)))
	_close_outputs()
	quit(1)


func _timeout_text() -> String:
	if float(config.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS)) <= 0.0:
		return "disabled"
	return "%s seconds" % str(config.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS))


func _print_usage() -> void:
	print("Usage: -- --runs 1000 --steps 300 --seed 1 --scenario all --trace issues --balance-profile default --scenario-probes auto --campaign baseline --quest-policy baseline --output-dir res://.godot_logs/simulation --publish-latest --public-output-root res://.godot/ai_simulation --timeout-seconds 0")
	print("Scenarios: all, %s" % ", ".join(SCENARIOS))
	print("Balance profiles: %s" % ", ".join(_balance_profile_ids()))
	print("Scenario probes: auto, off, smoke, full")
	print("Campaigns: %s" % ", ".join(CAMPAIGNS))
	print("Quest policies: %s" % ", ".join(QUEST_POLICIES))
	print("Trace modes: issues, all")
	print("Add --fail-on-issues only when issue findings should fail the command.")
	print("Add --allow-latest-downgrade only when a weaker run may replace a stronger latest report.")
	print("Add --require-publish-latest when blocked publishing should fail the command.")


func _arg_value(args: Array, index: int, flag: String, errors: Array) -> String:
	if index + 1 >= args.size():
		errors.append("%s requires a value." % flag)
		return ""
	var value := str(args[index + 1])
	if value.begins_with("--"):
		errors.append("%s requires a value." % flag)
		return ""
	return value


func _validate_config() -> bool:
	for error in _as_array(config.get("parse_errors", [])):
		push_error(str(error))
	if not _as_array(config.get("parse_errors", [])).is_empty():
		return false
	if int(config["runs"]) <= 0:
		push_error("--runs must be positive.")
		return false
	if int(config["steps"]) <= 0:
		push_error("--steps must be positive.")
		return false
	var scenario := str(config["scenario"])
	if scenario != "all" and scenario not in SCENARIOS:
		push_error("--scenario must be all or one of: %s" % ", ".join(SCENARIOS))
		return false
	var trace := str(config["trace"])
	if trace not in ["issues", "all"]:
		push_error("--trace must be issues or all.")
		return false
	if str(config["output_dir"]).strip_edges().is_empty():
		push_error("--output-dir cannot be empty.")
		return false
	if bool(config.get("publish_latest", false)) and str(config["public_output_root"]).strip_edges().is_empty():
		push_error("--public-output-root cannot be empty when --publish-latest is used.")
		return false
	var balance_profile := str(config["balance_profile"])
	if not BALANCE_PROFILES.has(balance_profile):
		push_error("--balance-profile must be one of: %s" % ", ".join(_balance_profile_ids()))
		return false
	var scenario_probes := str(config["scenario_probes"])
	if scenario_probes not in ["auto", "off", "smoke", "full"]:
		push_error("--scenario-probes must be auto, off, smoke, or full.")
		return false
	var campaign := str(config.get("campaign", DEFAULT_CAMPAIGN))
	if campaign not in CAMPAIGNS:
		push_error("--campaign must be one of: %s" % ", ".join(CAMPAIGNS))
		return false
	var quest_policy := str(config.get("quest_policy", DEFAULT_QUEST_POLICY))
	if quest_policy not in QUEST_POLICIES:
		push_error("--quest-policy must be one of: %s" % ", ".join(QUEST_POLICIES))
		return false
	if float(config["timeout_seconds"]) < 0.0:
		push_error("--timeout-seconds must be non-negative. Use 0 to disable the timeout.")
		return false
	return true


func _load_data() -> void:
	world_data = _load_json(WORLD_PATH)
	items_data = _load_json(ITEMS_PATH)
	skills_data = _load_json(SKILLS_PATH)
	recipes_data = _load_json(RECIPES_PATH)
	quests_data = _load_json(QUESTS_PATH)


func _discover_content() -> void:
	resources = []
	mobs = []
	npcs = []
	stations = {}

	for node in _as_array(world_data.get("resource_nodes", [])):
		if node is Dictionary:
			var data: Dictionary = node.duplicate(true)
			data["type"] = "resource"
			data["id"] = str(node.get("node_id", ""))
			data["label"] = str(node.get("display_name", "Resource"))
			data["tile"] = _array_to_tile(node.get("position", [0, 0]), Vector2i.ZERO)
			resources.append(data)

	for mob in _as_array(world_data.get("mobs", [])):
		if mob is Dictionary:
			var data: Dictionary = mob.duplicate(true)
			data["type"] = "mob"
			data["id"] = str(mob.get("mob_id", ""))
			data["label"] = str(mob.get("display_name", "Mob"))
			data["tile"] = _array_to_tile(mob.get("position", [0, 0]), Vector2i.ZERO)
			mobs.append(data)

	for npc in _as_array(world_data.get("npcs", [])):
		if npc is Dictionary:
			var data: Dictionary = npc.duplicate(true)
			data["type"] = "npc"
			data["id"] = str(npc.get("id", ""))
			data["label"] = str(npc.get("name", "NPC"))
			data["tile"] = _array_to_tile(npc.get("tile", [0, 0]), Vector2i.ZERO)
			npcs.append(data)

	for station_key in STATION_KEYS:
		var station = world_data.get(station_key, {})
		if station is Dictionary and not station.is_empty():
			var data: Dictionary = station.duplicate(true)
			data["type"] = "station"
			data["station_id"] = station_key
			data["id"] = str(station.get("id", station_key))
			data["label"] = str(station.get("name", _display_label(station_key)))
			data["tile"] = _array_to_tile(station.get("tile", [0, 0]), Vector2i.ZERO)
			stations[station_key] = data

	resources.sort_custom(func(left, right) -> bool: return str(left.get("id", "")) < str(right.get("id", "")))
	mobs.sort_custom(func(left, right) -> bool: return str(left.get("id", "")) < str(right.get("id", "")))
	npcs.sort_custom(func(left, right) -> bool: return str(left.get("id", "")) < str(right.get("id", "")))


func _initialize_coverage_ledger() -> void:
	coverage_ledger = {
		"actions": {},
		"skills": {},
		"recipes": {},
		"quests": {},
		"resources": {},
		"mobs": {},
		"npcs": {},
		"stations": {},
	}
	for action in ["gather_resource", "gather_woodcutting", "gather_mining", "gather_fishing", "cook", "process_furnace", "process_anvil", "process_carpentry", "process_apothecary", "attack_mob", "pickup_drop", "talk_npc", "dialogue_action", "bank_deposit", "bank_withdraw", "shop_buy", "shop_sell", "use_item", "equip_item", "drop_item", "examine_object"]:
		coverage_ledger["actions"][action] = {"attempted": 0, "succeeded": 0}
	for skill in _content_ids(skills_data.get("skills", skills_data), "skill_id"):
		coverage_ledger["skills"][skill] = {"attempted": 0, "succeeded": 0}
	for recipe in _content_ids(recipes_data, "recipe_id"):
		coverage_ledger["recipes"][recipe] = {"attempted": 0, "succeeded": 0}
	for quest in _content_ids(quests_data.get("quests", []), "quest_id"):
		coverage_ledger["quests"][quest] = {"attempted": 0, "succeeded": 0}
	for node in resources:
		coverage_ledger["resources"][str(node.get("id", ""))] = {"attempted": 0, "succeeded": 0}
	for mob in mobs:
		coverage_ledger["mobs"][str(mob.get("id", ""))] = {"attempted": 0, "succeeded": 0}
	for npc in npcs:
		coverage_ledger["npcs"][str(npc.get("id", ""))] = {"attempted": 0, "succeeded": 0}
	for station_key in stations.keys():
		coverage_ledger["stations"][str(station_key)] = {"attempted": 0, "succeeded": 0}


func _content_ids(raw, id_key: String) -> Array:
	var ids := []
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				var value := str(entry.get(id_key, ""))
				if not value.is_empty(): ids.append(value)
	elif raw is Dictionary:
		for key in raw.keys():
			var entry = raw[key]
			if entry is Dictionary:
				var value := str(entry.get(id_key, key))
				if not value.is_empty(): ids.append(value)
			elif entry is Array:
				ids.append_array(_content_ids(entry, id_key))
	ids.sort()
	return ids


func _coverage_missing_count(category: String) -> int:
	var row = _coverage_report().get(category, {})
	if row is Dictionary:
		return _as_array(row.get("missing", [])).size()
	return 0


func _coverage_mark(category: String, content_id: String, succeeded: bool) -> void:
	if content_id.is_empty() or not coverage_ledger.has(category):
		return
	var entries = coverage_ledger[category]
	if not (entries is Dictionary) or not entries.has(content_id):
		return
	var row = entries[content_id]
	if not (row is Dictionary): row = {"attempted": 0, "succeeded": 0}
	row["attempted"] = int(row.get("attempted", 0)) + 1
	if succeeded: row["succeeded"] = int(row.get("succeeded", 0)) + 1
	entries[content_id] = row


func _record_coverage(record: Dictionary) -> void:
	var action := str(record.get("action", ""))
	var succeeded := not bool(record.get("skipped", false)) and not _is_failure_feedback(str(record.get("feedback", "")))
	_coverage_mark("actions", action, succeeded)
	var target_id := str(record.get("target_id", ""))
	if action.begins_with("gather"):
		_coverage_mark("resources", target_id, succeeded)
		var skill_id: String = str({"gather_woodcutting": "woodcutting", "gather_mining": "mining", "gather_fishing": "fishing"}.get(action, ""))
		if action == "gather_resource":
			for resource in resources:
				if resource is Dictionary and str(resource.get("id", "")) == target_id:
					skill_id = str(resource.get("skill_id", ""))
					break
		_coverage_mark("skills", str(skill_id), succeeded)
	elif action.begins_with("process") or action == "cook":
		var station_id: String = str({"process_furnace": "furnace", "process_anvil": "anvil", "process_carpentry": "carpentry_bench", "process_apothecary": "apothecary_table", "cook": "cooking_range"}.get(action, ""))
		_coverage_mark("stations", str(station_id), succeeded)
		_coverage_mark("skills", _processing_skill_for_action(action, target_id), succeeded)
		_record_recipe_coverage(record, succeeded)
	elif action == "attack_mob":
		_coverage_mark("mobs", target_id, succeeded)
		var combat_style := "attack"
		if current_state is Dictionary:
			combat_style = str(current_state.get("combat_training_style", "attack"))
		if combat_style not in ["attack", "strength", "defence", "ranged", "magic"]:
			combat_style = "attack"
		_coverage_mark("skills", combat_style, succeeded)
		_coverage_mark("skills", "hitpoints", succeeded)
		var skill_deltas = record.get("skill_xp_deltas", {})
		if skill_deltas is Dictionary and int(skill_deltas.get("defence", 0)) > 0:
			_coverage_mark("skills", "defence", succeeded)
	elif action in ["talk_npc", "dialogue_action"]:
		_coverage_mark("npcs", target_id, succeeded)
	elif action in ["open_bank", "open_shop"]:
		_coverage_mark("stations", str({"open_bank": "bank", "open_shop": "shop"}.get(action, "")), succeeded)
	var quest_root: Dictionary = {}
	if current_state is Dictionary:
		var raw_quest_root: Variant = current_state.get("quest_state", {})
		if raw_quest_root is Dictionary:
			quest_root = raw_quest_root
	var quest_rows: Dictionary = {}
	var raw_quest_rows: Variant = quest_root.get("quests", {})
	if raw_quest_rows is Dictionary:
		quest_rows = raw_quest_rows
	if quest_rows is Dictionary:
		for quest_id in quest_rows.keys():
			var quest_state = quest_rows[quest_id]
			if quest_state is Dictionary and (bool(quest_state.get("started", false)) or bool(quest_state.get("completed", false)) or not _as_array(quest_state.get("flags", [])).is_empty()):
				_coverage_mark("quests", str(quest_id), succeeded)


func _processing_skill_for_action(action: String, target_id: String) -> String:
	var action_type: String = str({
		"process_furnace": "smelting",
		"process_anvil": "smithing",
		"process_carpentry": "carpentry",
		"process_apothecary": "herbalism",
	}.get(action, ""))
	if action == "process_station":
		action_type = str({
			"furnace": "smelting",
			"anvil": "smithing",
			"carpentry_bench": "carpentry",
			"apothecary_table": "herbalism",
		}.get(target_id, ""))
	if action == "cook":
		return "cooking"
	return str(PROCESSING_SKILLS.get(str(action_type), ""))


func _record_recipe_coverage(record: Dictionary, succeeded: bool) -> void:
	var feedback := str(record.get("feedback", ""))
	if feedback.is_empty():
		return
	var action_type: String = str({
		"process_furnace": "smelting",
		"process_anvil": "smithing",
		"process_carpentry": "carpentry",
		"process_apothecary": "herbalism",
	}.get(str(record.get("action", "")), ""))
	var action_types: Array[String] = []
	if str(record.get("action", "")) == "process_station":
		for recipe_type in recipes_data.keys():
			action_types.append(str(recipe_type))
	else:
		action_types.append(str(action_type))
	if action_types.is_empty():
		return
	for recipe_type in action_types:
		var recipes = recipes_data.get(recipe_type, [])
		if not recipes is Array:
			continue
		for recipe in recipes:
			if not recipe is Dictionary:
				continue
			var recipe_id := str(recipe.get("recipe_id", ""))
			var display_name := str(recipe.get("display_name", recipe_id))
			if (not display_name.is_empty() and feedback.find(display_name) >= 0) or (not recipe_id.is_empty() and feedback.find(recipe_id) >= 0):
				_coverage_mark("recipes", recipe_id, succeeded)
				return


func _skill_xp_snapshot() -> Dictionary:
	var snapshot := {}
	if not current_state is Dictionary:
		return snapshot
	var skills = current_state.get("skills", {})
	if not skills is Dictionary:
		return snapshot
	for skill_id in skills.keys():
		var values = skills[skill_id]
		if values is Dictionary:
			snapshot[str(skill_id)] = int(values.get("xp", 0))
	return snapshot


func _skill_xp_deltas(before: Dictionary, after: Dictionary) -> Dictionary:
	var deltas := {}
	for skill_id in after.keys():
		var delta := int(after[skill_id]) - int(before.get(skill_id, 0))
		if delta != 0:
			deltas[str(skill_id)] = delta
	return deltas


func _coverage_report() -> Dictionary:
	var report := {}
	for category in coverage_ledger.keys():
		var entries = coverage_ledger[category]
		var missing := []
		var failed := []
		var attempted := 0
		var succeeded := 0
		if entries is Dictionary:
			for content_id in _sorted_keys(entries):
				var row = entries[content_id]
				var row_attempted := int(row.get("attempted", 0)) if row is Dictionary else 0
				var row_succeeded := int(row.get("succeeded", 0)) if row is Dictionary else 0
				attempted += row_attempted
				succeeded += row_succeeded
				if row_attempted == 0: missing.append(str(content_id))
				elif row_succeeded == 0: failed.append(str(content_id))
		report[category] = {
			"expected": entries.size() if entries is Dictionary else 0,
			"attempted": attempted,
			"succeeded": succeeded,
			"attempted_ids": (entries.size() - missing.size()) if entries is Dictionary else 0,
			"succeeded_ids": (entries.size() - missing.size() - failed.size()) if entries is Dictionary else 0,
			"failed_count": failed.size(),
			"untested_count": missing.size(),
			"coverage_rate": float(entries.size() - missing.size()) / float(max(1, entries.size())) if entries is Dictionary else 0.0,
			"missing": missing,
			"failed": failed,
		}
	return report


func _opportunity_report() -> Array:
	var opportunities := []
	var coverage := _coverage_report()
	for category in ["skills", "recipes", "quests", "mobs"]:
		var row = coverage.get(category, {})
		var missing = _as_array(row.get("missing", [])) if row is Dictionary else []
		if not missing.is_empty():
			opportunities.append({
				"id": "opportunity-%s-coverage" % category,
				"fingerprint": _combined_hash(["coverage", category, ",".join(missing)]),
				"category": "content_depth",
				"confidence": "medium",
				"hypothesis": "%s content is not exercised by the current campaign and may hide shallow, unreachable, or unbalanced progression." % category.capitalize(),
				"evidence": {"coverage": row, "campaign": str(config.get("campaign", DEFAULT_CAMPAIGN))},
				"smallest_experiment": "Run the content campaign with full scenario probes and inspect the missing IDs before changing data.",
				"acceptance": "Every intended %s ID is attempted and either succeeds or has a documented unsupported reason." % category,
				"verification_gap": "Coverage absence does not prove the content is broken or undesirable.",
			})
	var telemetry := _telemetry_report(10)
	var action_counts = telemetry.get("action_counts", {}) if telemetry is Dictionary else {}
	if action_counts is Dictionary and not action_counts.is_empty():
		var total_actions := 0
		var dominant_action := ""
		var dominant_count := 0
		for action in action_counts.keys():
			var count := int(action_counts[action])
			total_actions += count
			if count > dominant_count:
				dominant_count = count
				dominant_action = str(action)
		if total_actions > 0 and float(dominant_count) / float(total_actions) >= 0.45:
			opportunities.append({
				"id": "opportunity-dominant-action",
				"fingerprint": _combined_hash(["dominant_action", dominant_action, str(dominant_count), str(total_actions)]),
				"category": "choice_depth",
				"confidence": "medium",
				"hypothesis": "The current campaign may converge on %s, reducing meaningful player choice in the existing loop." % dominant_action,
				"evidence": {"dominant_action": dominant_action, "count": dominant_count, "total_actions": total_actions, "action_counts": action_counts},
				"smallest_experiment": "Compare the same campaign under progression, economy, combat, and opportunity profiles before adding new content.",
				"acceptance": "At least two viable action routes produce measurable progression without introducing regressions.",
				"verification_gap": "Bot policy can create artificial dominance; manual review is required before design changes.",
			})
	var balance := _balance_profile_report(10)
	var started := int(balance.get("started_quests", 0)) if balance is Dictionary else 0
	var completed := int(balance.get("completed_quests", 0)) if balance is Dictionary else 0
	if started >= 3 and completed * 2 < started:
		opportunities.append({
			"id": "opportunity-quest-return-depth",
			"fingerprint": _combined_hash(["quest_return_depth", str(started), str(completed)]),
			"category": "quest_depth",
			"confidence": "medium",
			"hypothesis": "Quest routes may start reliably but fail to create enough completion momentum or meaningful return choices.",
			"evidence": {"started_quests": started, "completed_quests": completed, "completion_rate": float(completed) / float(started)},
			"smallest_experiment": "Run a focused quest campaign with full probes and inspect the first incomplete objective for friction.",
			"acceptance": "Quest completion and objective-branch metrics improve without weakening reward-capacity or save contracts.",
			"verification_gap": "Short simulations may under-sample long quest routes.",
		})
	return opportunities


func _prepare_output_dir() -> bool:
	var output_dir := str(config["output_dir"])
	var output_path := ProjectSettings.globalize_path(output_dir)
	var err := DirAccess.make_dir_recursive_absolute(output_path)
	if err != OK:
		push_error("Could not create simulation output directory: %s" % output_path)
		return false
	var saves_path := ProjectSettings.globalize_path("%s/saves" % output_dir)
	err = DirAccess.make_dir_recursive_absolute(saves_path)
	if err != OK:
		push_error("Could not create simulation save directory: %s" % saves_path)
		return false
	var snapshots_path := ProjectSettings.globalize_path("%s/snapshots" % output_dir)
	err = DirAccess.make_dir_recursive_absolute(snapshots_path)
	if err != OK:
		push_error("Could not create simulation snapshots directory: %s" % snapshots_path)
		return false
	return true


func _should_write_progress(step_index: int) -> bool:
	var steps := int(config.get("steps", DEFAULT_STEPS))
	var stride: int = max(1, int(ceil(float(steps) / 20.0)))
	return step_index == 0 or step_index + 1 >= steps or (step_index + 1) % stride == 0


func _write_progress(status: String, run_index: int, step_in_run: int, scenario: String) -> void:
	var output_dir := str(config.get("output_dir", DEFAULT_OUTPUT_DIR))
	if output_dir.strip_edges().is_empty():
		return
	var total_runs := int(config.get("runs", DEFAULT_RUNS))
	var total_steps_per_run := int(config.get("steps", DEFAULT_STEPS))
	var total_steps: int = max(1, total_runs * total_steps_per_run)
	var completed_steps: int = clamp((run_index * total_steps_per_run) + step_in_run, 0, total_steps)
	if status in ["writing_reports", "completed"]:
		completed_steps = total_steps
	var percent := float(completed_steps) / float(total_steps) * 100.0
	var elapsed_seconds: int = max(0, int(round(float(Time.get_ticks_msec() - progress_started_msec) / 1000.0)))
	var eta_seconds := -1
	if completed_steps > 0 and completed_steps < total_steps:
		eta_seconds = max(0, int(round(float(elapsed_seconds) * float(total_steps - completed_steps) / float(completed_steps))))
	elif completed_steps >= total_steps:
		eta_seconds = 0
	var progress := {
		"status": status,
		"run": clamp(run_index + 1, 1, max(1, total_runs)),
		"runs": total_runs,
		"run_index": run_index,
		"step": clamp(step_in_run, 0, total_steps_per_run),
		"steps": total_steps_per_run,
		"completed_steps": completed_steps,
		"total_steps": total_steps,
		"percent": percent,
		"elapsed_seconds": elapsed_seconds,
		"eta_seconds": eta_seconds,
		"scenario": scenario,
		"issue_occurrences": issue_occurrence_count,
		"issue_samples": issue_sample_count,
		"timestamp_unix": Time.get_unix_time_from_system(),
	}
	var file := FileAccess.open("%s/progress.json" % output_dir, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(progress, "\t", true))
	_print_progress_line(progress)


func _print_progress_line(progress: Dictionary) -> void:
	var status := str(progress.get("status", "starting"))
	if status in ["writing_reports", "completed"]:
		return
	var raw_percent := int(floor(float(progress.get("percent", 0.0))))
	var percent_int: int = clamp(raw_percent, 0, 100)
	if percent_int <= last_progress_percent_printed and status == last_progress_status:
		return
	last_progress_status = status
	last_progress_percent_printed = percent_int
	var bar_width := 30
	var raw_filled := int(floor(float(percent_int) / 100.0 * float(bar_width)))
	var filled: int = clamp(raw_filled, 0, bar_width)
	var bar := ""
	for index in range(bar_width):
		if index < filled:
			bar += "#"
		else:
			bar += "-"
	var steps_per_run: int = max(1, int(progress.get("steps", 1)))
	var completed_runs: int = clamp(int(floor(float(progress.get("completed_steps", 0)) / float(steps_per_run))), 0, int(progress.get("runs", 1)))
	var eta_seconds := int(progress.get("eta_seconds", -1))
	var eta_text := "--"
	if eta_seconds >= 0:
		eta_text = _format_duration(eta_seconds)
	print("  [%s] %d%% | %d/%d runs | elapsed %s | ETA %s" % [
		bar,
		percent_int,
		completed_runs,
		int(progress.get("runs", 1)),
		_format_duration(int(progress.get("elapsed_seconds", 0))),
		eta_text,
	])


func _format_duration(total_seconds: int) -> String:
	var safe_seconds: int = max(0, total_seconds)
	var hours: int = int(floor(float(safe_seconds) / 3600.0))
	var minutes: int = int(floor(float(safe_seconds % 3600) / 60.0))
	var seconds: int = safe_seconds % 60
	if hours > 0:
		return "%dh%02dm" % [hours, minutes]
	if minutes > 0:
		return "%dm%02ds" % [minutes, seconds]
	return "%ds" % seconds


func _open_outputs() -> bool:
	var output_dir := str(config["output_dir"])
	runs_file = FileAccess.open("%s/runs.jsonl" % output_dir, FileAccess.WRITE)
	issues_file = FileAccess.open("%s/issues.jsonl" % output_dir, FileAccess.WRITE)
	if str(config["trace"]) == "all":
		trace_file = FileAccess.open("%s/trace.jsonl" % output_dir, FileAccess.WRITE)
	if runs_file == null or issues_file == null or (str(config["trace"]) == "all" and trace_file == null):
		push_error("Could not open one or more simulation output files.")
		return false
	return true


func _close_outputs() -> void:
	if runs_file != null:
		runs_file.flush()
	if issues_file != null:
		issues_file.flush()
	if trace_file != null:
		trace_file.flush()
	runs_file = null
	issues_file = null
	trace_file = null


func _build_trust_context() -> Dictionary:
	var finding_status := "not_evaluated"
	if issue_occurrence_count > 0:
		finding_status = "advisory_findings_present"
	elif not run_summaries.is_empty():
		finding_status = "no_findings_observed"
	var run_strength := _run_strength()
	var context := {
		"run_strength": run_strength,
		"coverage_scope": _coverage_scope(),
		"implementation_ready": _implementation_ready(),
		"harness_status": "completed" if not run_summaries.is_empty() else "not_evaluated",
		"finding_status": finding_status,
		"latest_publish_status": latest_publish_status,
		"hash_verification": _hash_verification_guidance(),
	}
	if not previous_latest_context.is_empty():
		context["previous_latest_created_at"] = str(previous_latest_context.get("created_at", ""))
		context["previous_latest_run_strength"] = str(previous_latest_context.get("run_strength", ""))
		context["previous_latest_config"] = previous_latest_context.get("config", {})
	if str(latest_publish_status) == "published_allowed_downgrade":
		context["latest_replaced_stronger_run"] = true
	return context


func _run_strength() -> String:
	var runs := int(config.get("runs", DEFAULT_RUNS))
	var steps := int(config.get("steps", DEFAULT_STEPS))
	var scenario := str(config.get("scenario", DEFAULT_SCENARIO))
	if runs < 12 or steps < 150:
		return "publish_smoke"
	if scenario == "all" and runs >= 10000 and steps >= 720:
		return "deep_sweep"
	if scenario == "all" and runs >= 1000 and steps >= 300:
		return "balance_pass"
	if scenario == "all" and runs >= 12 and steps >= 150:
		return "strategy_smoke"
	return "custom"


func _coverage_scope() -> String:
	var scenario := str(config.get("scenario", DEFAULT_SCENARIO))
	if scenario == "all":
		return "all_scenarios"
	return "narrow_%s" % scenario


func _implementation_ready() -> bool:
	return int(config.get("runs", DEFAULT_RUNS)) >= 12 and int(config.get("steps", DEFAULT_STEPS)) >= 150 and str(config.get("scenario", DEFAULT_SCENARIO)) == "all"


func _resolved_scenario_probe_mode() -> String:
	var requested := str(config.get("scenario_probes", DEFAULT_SCENARIO_PROBES))
	if requested == "off":
		return "off"
	if requested in ["smoke", "full"]:
		return requested
	var strength := _run_strength()
	if strength in ["balance_pass", "deep_sweep"]:
		return "full"
	return "smoke"


func _run_strength_rank(strength: String) -> int:
	match strength:
		"publish_smoke":
			return 1
		"custom":
			return 2
		"strategy_smoke":
			return 3
		"balance_pass":
			return 4
		"deep_sweep":
			return 5
	return 0


func _read_previous_latest_context() -> Dictionary:
	if not bool(config.get("publish_latest", false)):
		return {}
	var path := _latest_public_summary_path()
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	var summary: Dictionary = parsed
	var trust = summary.get("trust", {})
	var replay = summary.get("replay_metadata", {})
	var previous_config = summary.get("config", {})
	var run_strength := ""
	if trust is Dictionary:
		run_strength = str(trust.get("run_strength", ""))
	if run_strength.is_empty() and previous_config is Dictionary:
		run_strength = _run_strength_for_config(previous_config)
	var created_at := ""
	if replay is Dictionary:
		created_at = str(replay.get("created_at", ""))
	return {
		"created_at": created_at,
		"run_strength": run_strength,
		"config": previous_config if previous_config is Dictionary else {},
	}


func _latest_public_summary_path() -> String:
	var public_root := str(config.get("public_output_root", DEFAULT_PUBLIC_OUTPUT_ROOT))
	var dir := DirAccess.open(ProjectSettings.globalize_path(public_root))
	var newest_path := ""
	var newest_modified := 0
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.begins_with("ai_simulation_") and file_name.ends_with(".json"):
				var candidate := "%s/%s" % [public_root, file_name]
				var modified := FileAccess.get_modified_time(ProjectSettings.globalize_path(candidate))
				if newest_path.is_empty() or modified > newest_modified:
					newest_path = candidate
					newest_modified = modified
			file_name = dir.get_next()
		dir.list_dir_end()
	if not newest_path.is_empty():
		return newest_path
	var legacy_path := "%s/latest/ai_simulation_latest.json" % public_root
	if FileAccess.file_exists(legacy_path):
		return legacy_path
	return ""


func _run_strength_for_config(raw_config) -> String:
	if not (raw_config is Dictionary):
		return "custom"
	var runs := int(raw_config.get("runs", DEFAULT_RUNS))
	var steps := int(raw_config.get("steps", DEFAULT_STEPS))
	var scenario := str(raw_config.get("scenario", DEFAULT_SCENARIO))
	if runs < 12 or steps < 150:
		return "publish_smoke"
	if scenario == "all" and runs >= 10000 and steps >= 720:
		return "deep_sweep"
	if scenario == "all" and runs >= 1000 and steps >= 300:
		return "balance_pass"
	if scenario == "all" and runs >= 12 and steps >= 150:
		return "strategy_smoke"
	return "custom"


func _apply_latest_publish_status() -> void:
	latest_publish_status = "not_requested"
	if not bool(config.get("publish_latest", false)):
		trust_context["latest_publish_status"] = latest_publish_status
		return
	latest_publish_status = "published"
	if not previous_latest_context.is_empty():
		var previous_rank := _run_strength_rank(str(previous_latest_context.get("run_strength", "")))
		var current_rank := _run_strength_rank(str(trust_context.get("run_strength", _run_strength())))
		if current_rank < previous_rank:
			if bool(config.get("allow_latest_downgrade", false)):
				latest_publish_status = "published_allowed_downgrade"
			else:
				latest_publish_status = "blocked_lower_coverage"
	trust_context["latest_publish_status"] = latest_publish_status
	if str(latest_publish_status) == "published_allowed_downgrade":
		trust_context["latest_replaced_stronger_run"] = true


func _hash_verification_guidance() -> Dictionary:
	return {
		"required": true,
		"rule": "Compare build_hash, all data_hashes, and all script_hashes before using replay to close or dismiss an issue.",
		"mismatch_result": "If any hash differs, replay is under changed code and cannot close the original issue by itself.",
		"automated_checker": false,
	}


func _publish_latest_outputs() -> bool:
	if str(latest_publish_status) == "blocked_lower_coverage":
		return not bool(config.get("require_publish_latest", false))

	var output_dir := str(config["output_dir"])
	var public_root := str(config.get("public_output_root", DEFAULT_PUBLIC_OUTPUT_ROOT))
	var archive_root := "%s/archive" % public_root
	var stamp := _archive_timestamp()
	var archive_dir := _unique_dir_path("%s/%s" % [archive_root, stamp])
	var public_json := _unique_file_path("%s/ai_simulation_data_%s.json" % [public_root, stamp])
	var public_prompt := _unique_file_path("%s/ai_simulation_codex_prompt_%s.md" % [public_root, stamp])

	if not _ensure_dir(public_root) or not _ensure_dir(archive_root):
		return false

	var public_files := [
		{
			"source": "%s/summary.json" % output_dir,
			"target": public_json,
		},
		{
			"source": "%s/codex_prompt.md" % output_dir,
			"target": public_prompt,
		},
	]
	for mapping in public_files:
		if not _copy_file(str(mapping["source"]), str(mapping["target"])):
			return false

	if not _ensure_dir(archive_dir):
		return false
	var full_reports_dir := "%s/full_reports" % archive_dir
	if not _copy_dir_recursive(output_dir, full_reports_dir):
		return false

	print("Published AI simulation outputs:")
	print("  Prompt: %s" % public_prompt)
	print("  JSON: %s" % public_json)
	return true


func _print_completion_summary() -> void:
	print("Hearthvale playtest simulation completed.")
	print("Result: completed")
	print("Runs: %d" % int(config["runs"]))
	print("Issues: %d occurrences, %d samples" % [issue_occurrence_count, issue_sample_count])
	print("Status: %s" % _completion_status_text())
	print("Publication: %s" % _publication_status_text())
	print("Report: %s" % str(config["output_dir"]))
	var warning := _publication_warning_text()
	if not warning.is_empty():
		print("Warnings:")
		print("  %s" % warning)


func _completion_status_text() -> String:
	if _run_strength() == "strategy_smoke":
		return "smoke test completed"
	return "simulation completed"


func _publication_status_text() -> String:
	var status := str(trust_context.get("latest_publish_status", latest_publish_status))
	match status:
		"published":
			return "promoted as latest"
		"published_allowed_downgrade":
			return "promoted as latest with lower coverage allowed"
		"blocked_lower_coverage":
			return "not promoted as latest because lower coverage cannot replace stronger coverage"
		"not_requested":
			return "not requested"
		_:
			return status


func _publication_warning_text() -> String:
	var status := str(trust_context.get("latest_publish_status", latest_publish_status))
	match status:
		"published_allowed_downgrade":
			return "A lower-coverage run replaced a stronger previous latest report."
		"blocked_lower_coverage":
			return "A stronger previous latest report was preserved."
		_:
			return ""


func _archive_timestamp() -> String:
	var time := Time.get_datetime_dict_from_system()
	return "%04d_%02d_%02d_%02d%02d" % [
		int(time.get("year", 0)),
		int(time.get("month", 0)),
		int(time.get("day", 0)),
		int(time.get("hour", 0)),
		int(time.get("minute", 0)),
	]


func _unique_dir_path(base_path: String) -> String:
	if not _dir_exists(base_path):
		return base_path
	var suffix := 2
	while _dir_exists("%s_%d" % [base_path, suffix]):
		suffix += 1
	return "%s_%d" % [base_path, suffix]


func _unique_file_path(base_path: String) -> String:
	if not FileAccess.file_exists(base_path):
		return base_path
	var extension := ""
	var stem := base_path
	var dot_index := base_path.rfind(".")
	if dot_index > -1:
		extension = base_path.substr(dot_index)
		stem = base_path.substr(0, dot_index)
	var suffix := 2
	while FileAccess.file_exists("%s_%d%s" % [stem, suffix, extension]):
		suffix += 1
	return "%s_%d%s" % [stem, suffix, extension]


func _ensure_dir(path: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Could not create directory: %s" % path)
		return false
	return true


func _dir_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _rename_dir(from_path: String, to_path: String) -> bool:
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))
	if err != OK:
		push_error("Could not move directory from %s to %s" % [from_path, to_path])
		return false
	return true


func _copy_file(from_path: String, to_path: String) -> bool:
	if not FileAccess.file_exists(from_path):
		push_error("Could not publish missing file: %s" % from_path)
		return false
	var source := FileAccess.open(from_path, FileAccess.READ)
	if source == null:
		push_error("Could not read file: %s" % from_path)
		return false
	var data := source.get_buffer(source.get_length())
	var target_parent := to_path.get_base_dir()
	if not _ensure_dir(target_parent):
		return false
	var target := FileAccess.open(to_path, FileAccess.WRITE)
	if target == null:
		push_error("Could not write file: %s" % to_path)
		return false
	target.store_buffer(data)
	return true


func _copy_dir_recursive(from_path: String, to_path: String) -> bool:
	var source := DirAccess.open(from_path)
	if source == null:
		push_error("Could not read directory: %s" % from_path)
		return false
	if not _ensure_dir(to_path):
		return false
	source.list_dir_begin()
	var entry := source.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var source_child := "%s/%s" % [from_path, entry]
			var target_child := "%s/%s" % [to_path, entry]
			if source.current_is_dir():
				if not _copy_dir_recursive(source_child, target_child):
					source.list_dir_end()
					return false
			elif not _copy_file(source_child, target_child):
				source.list_dir_end()
				return false
		entry = source.get_next()
	source.list_dir_end()
	return true


func _run_single_simulation(run_index: int) -> Dictionary:
	current_run_index = run_index
	current_seed = int(config["seed"]) + run_index
	current_scenario = _scenario_for_run(run_index)
	current_step = 0
	current_last_actions = []
	current_feedback_counts = {}
	current_issue_counts = {}
	current_issue_occurrences = 0
	current_issue_samples = 0
	current_no_progress_streak = 0
	current_max_no_progress_streak = 0
	current_run_telemetry = _new_telemetry_bucket()
	current_run_polish_telemetry = _new_polish_bucket()
	current_polish_feedback_counts = {}
	current_quest_policy_protected_items = {}
	current_quest_policy_target_item = ""
	current_quest_policy_target_quantity = 0
	current_quest_policy_objective_flag = ""
	current_quest_policy_quest_id = ""
	current_run_telemetry["runs"] = 1
	current_run_telemetry["seed"] = current_seed
	current_run_telemetry["run_index"] = current_run_index
	current_run_telemetry["scenario"] = current_scenario
	current_run_telemetry["quest_policy"] = str(config.get("quest_policy", DEFAULT_QUEST_POLICY))
	current_run_polish_telemetry["runs"] = 1
	current_run_polish_telemetry["seed"] = current_seed
	current_run_polish_telemetry["run_index"] = current_run_index
	current_run_polish_telemetry["scenario"] = current_scenario
	_write_progress("running", current_run_index, 0, current_scenario)

	current_rng = RandomNumberGenerator.new()
	current_rng.seed = current_seed

	var store = preload("res://autoload/state_store.gd").new()
	store.save_dir = "%s/saves" % str(config["output_dir"])
	var username := "sim_%s_%d" % [current_scenario, current_seed]
	current_state = store.create_default_state(username)
	current_world = preload("res://scenes/world.tscn").instantiate()
	current_hud = preload("res://scenes/hud.tscn").instantiate()
	if current_hud.has_method("set_simulation_lightweight_mode"):
		current_hud.call("set_simulation_lightweight_mode", true)
	current_gameplay = preload("res://scripts/gameplay_core.gd").new()
	root.add_child(current_world)
	root.add_child(current_hud)
	root.add_child(current_gameplay)
	await process_frame
	current_hud.bind_state(current_state)
	current_world.initialize_from_state(current_state)
	current_gameplay.setup(current_state, current_world, current_hud, "manual")

	var first_digest := _state_digest()
	var initial_summary := StateSnapshot.summarize_state(current_state)
	for step in range(int(config["steps"])):
		if _timeout_exceeded():
			_write_progress("timed_out", current_run_index, current_step, current_scenario)
			_cleanup_current_simulation_run(store)
			return {}
		current_step = step
		var requested_action := _campaign_action(_choose_action(current_scenario, step), step)
		if _quest_policy_active():
			requested_action = _choose_quest_aware_action(step, requested_action)
		var action_name := requested_action if requested_action.begins_with("adversarial_") else _resolve_action_preconditions(requested_action, step)
		var before_digest := _state_digest()
		var before_gameplay_digest := _gameplay_state_digest()
		var before_feedback := _feedback_text()
		var before_hitpoints := _current_hitpoints()
		var before_coins := int(_inventory().get("coins", 0))
		var before_quest_counts := _quest_counts()
		var before_tile := _player_tile()
		var before_skill_xp := _skill_xp_snapshot()
		var before_quest_target_quantity := int(_inventory().get(current_quest_policy_target_item, 0)) if not current_quest_policy_target_item.is_empty() else 0
		var started_usec := Time.get_ticks_usec()
		var action_record := _execute_action(action_name)
		if str(config.get("campaign", DEFAULT_CAMPAIGN)) == "adversarial" and step % 31 == 0:
			_perform_state_checkpoint(store, username, action_record)
		var after_feedback := _feedback_text()
		var after_digest := _state_digest()
		var after_gameplay_digest := _gameplay_state_digest()
		var after_hitpoints := _current_hitpoints()
		var after_coins := int(_inventory().get("coins", 0))
		var after_quest_counts := _quest_counts()
		var after_tile := _player_tile()
		var after_skill_xp := _skill_xp_snapshot()
		action_record["feedback"] = after_feedback
		action_record["previous_feedback"] = before_feedback
		action_record["changed_state"] = before_digest != after_digest
		action_record["gameplay_state_changed"] = before_gameplay_digest != after_gameplay_digest
		action_record["inventory_slots"] = _inventory_slot_count(_inventory())
		action_record["hitpoints"] = after_hitpoints
		action_record["hitpoints_before"] = before_hitpoints
		action_record["damage_taken"] = max(0, before_hitpoints - after_hitpoints)
		action_record["healing_done"] = max(0, after_hitpoints - before_hitpoints)
		action_record["coin_delta"] = after_coins - before_coins
		action_record["started_quest_delta"] = int(after_quest_counts.get("started", 0)) - int(before_quest_counts.get("started", 0))
		action_record["completed_quest_delta"] = int(after_quest_counts.get("completed", 0)) - int(before_quest_counts.get("completed", 0))
		action_record["skill_xp_deltas"] = _skill_xp_deltas(before_skill_xp, after_skill_xp)
		action_record["from_tile"] = [before_tile.x, before_tile.y]
		action_record["tile"] = [after_tile.x, after_tile.y]
		action_record["tile_key"] = _tile_key(after_tile)
		action_record["elapsed_usec"] = Time.get_ticks_usec() - started_usec
		action_record["requested_action"] = requested_action
		action_record["quest_policy"] = str(config.get("quest_policy", DEFAULT_QUEST_POLICY))
		action_record["quest_policy_quest_id"] = current_quest_policy_quest_id
		action_record["quest_objective_flag"] = current_quest_policy_objective_flag
		action_record["quest_policy_target_item"] = current_quest_policy_target_item
		_record_quest_policy_action_result(action_name, before_quest_target_quantity, action_record)
		_record_coverage(action_record)
		_record_action_telemetry(action_record)
		_record_polish_telemetry(action_record)
		_record_action_trace(action_record)
		_analyze_action_result(action_record)
		_check_invariants(action_record)
		_advance_clock_between_actions(action_record)
		if _should_write_progress(step):
			_write_progress("running", current_run_index, step + 1, current_scenario)
		if _timeout_exceeded():
			_write_progress("timed_out", current_run_index, step + 1, current_scenario)
			_cleanup_current_simulation_run(store)
			return {}

	var final_digest := _state_digest()
	var final_summary := StateSnapshot.summarize_state(current_state)
	var run_metrics := _run_metrics(first_digest, final_digest)
	var balance_metrics := _balance_metrics(run_metrics)
	var run_telemetry := _finalize_telemetry_bucket(current_run_telemetry, 10)
	var run_polish_telemetry := _finalize_polish_bucket(current_run_polish_telemetry, 10)
	var result := "completed"
	if current_issue_occurrences > 0:
		result = "issues_found"
	var summary := {
		"type": "run",
		"seed": current_seed,
		"run_index": current_run_index,
		"scenario": current_scenario,
		"steps": int(config["steps"]),
		"quest_policy": str(config.get("quest_policy", DEFAULT_QUEST_POLICY)),
		"replay": _run_replay_metadata(current_seed, current_scenario),
		"result": result,
		"issue_count": current_issue_occurrences,
		"issue_samples": current_issue_samples,
		"metrics": run_metrics,
		"telemetry": run_telemetry,
		"polish_telemetry": run_polish_telemetry,
		"balance_metrics": balance_metrics,
		"performance_observations": _performance_observations(run_telemetry),
		"state_checkpoints": {
			"initial": initial_summary,
			"final": final_summary,
			"initial_digest": first_digest.sha256_text(),
			"final_digest": final_digest.sha256_text(),
		},
	}

	_cleanup_current_simulation_run(store)
	return summary


func _compact_run_summary_for_reports(run_summary: Dictionary) -> Dictionary:
	var checkpoints = run_summary.get("state_checkpoints", {})
	var compact_checkpoints := {}
	if checkpoints is Dictionary:
		compact_checkpoints = {
			"initial_digest": str(checkpoints.get("initial_digest", "")),
			"final_digest": str(checkpoints.get("final_digest", "")),
		}
	var metrics = run_summary.get("metrics", {})
	var balance_metrics = run_summary.get("balance_metrics", {})
	return {
		"type": "run",
		"seed": int(run_summary.get("seed", 0)),
		"run_index": int(run_summary.get("run_index", 0)),
		"scenario": str(run_summary.get("scenario", "")),
		"steps": int(run_summary.get("steps", 0)),
		"result": str(run_summary.get("result", "")),
		"issue_count": int(run_summary.get("issue_count", 0)),
		"issue_samples": int(run_summary.get("issue_samples", 0)),
		"metrics": metrics.duplicate(true) if metrics is Dictionary else {},
		"balance_metrics": balance_metrics.duplicate(true) if balance_metrics is Dictionary else {},
		"state_checkpoints": compact_checkpoints,
	}


func _cleanup_current_simulation_run(store: Object) -> void:
	if current_gameplay != null and is_instance_valid(current_gameplay):
		current_gameplay.free()
	if current_hud != null and is_instance_valid(current_hud):
		current_hud.free()
	if current_world != null and is_instance_valid(current_world):
		current_world.free()
	if store != null and is_instance_valid(store):
		store.free()
	current_gameplay = null
	current_hud = null
	current_world = null
	current_state = {}
	current_run_telemetry = {}
	current_run_polish_telemetry = {}
	current_polish_feedback_counts = {}
	current_quest_policy_protected_items = {}
	current_quest_policy_target_item = ""
	current_quest_policy_target_quantity = 0
	current_quest_policy_objective_flag = ""
	current_quest_policy_quest_id = ""


func _run_scenario_probes() -> Dictionary:
	var mode := _resolved_scenario_probe_mode()
	var report := {
		"enabled": mode != "off",
		"requested_mode": str(config.get("scenario_probes", DEFAULT_SCENARIO_PROBES)),
		"mode": mode,
		"summary": {
			"total": 0,
			"completed": 0,
			"diagnostic": 0,
			"issues": 0,
		},
		"core_loop_probes": [],
		"skill_probes": [],
		"recipe_probes": [],
		"resource_probes": [],
		"npc_probes": [],
		"station_probes": [],
		"quest_probes": [],
		"combat_probes": [],
		"economy_probes": [],
		"inventory_probes": [],
		"known_gaps": [],
		"issues": [],
	}
	if mode == "off":
		report["summary"]["status"] = "disabled"
		return report
	var probes := _scenario_probe_definitions(mode)
	var index := 0
	for probe in probes:
		if _timeout_exceeded():
			_add_report_probe_issue(report, "scenario_probe_stalled", "Scenario probe run stopped because the simulation timeout was reached.", {"probe_index": index})
			break
		var result = await _run_scenario_probe(probe, index)
		if result is Dictionary:
			_add_probe_result_to_report(report, result)
		index += 1
	report["summary"]["total"] = index
	report["summary"]["issues"] = _as_array(report.get("issues", [])).size()
	report["summary"]["status"] = "clear" if int(report["summary"]["issues"]) == 0 else "diagnostic_issues"
	if mode == "full":
		report["known_gaps"] = _scenario_probe_known_gaps()
	return report


func _scenario_probe_definitions(mode: String) -> Array:
	var probes := [
		{
			"id": "core_loop_basic",
			"bucket": "core_loop_probes",
			"label": "Core gather-process-cook-sell loop",
			"initial_inventory": {"bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1, "logs": 2, "copper_ore": 1, "tin_ore": 1, "raw_shrimp": 1},
			"actions": ["gather_woodcutting", "process_carpentry", "process_furnace", "process_anvil", "cook", "shop_sell"],
			"expect": {"state_delta": true, "xp_gain": true},
		},
		{
			"id": "quest_starter_path",
			"bucket": "quest_probes",
			"label": "Starter quest objective exercise",
			"scenario": "quest_chaser",
			"initial_inventory": {"bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1, "coins": 20, "raw_shrimp": 1, "copper_ore": 1, "tin_ore": 1, "bronze_sword": 1},
			"actions": ["dialogue_action", "cook", "use_item", "process_furnace", "process_anvil", "equip_item", "attack_mob", "bank_deposit", "shop_buy", "dialogue_action"],
			"expect": {"state_delta": true, "xp_gain": true, "quest_started": true},
		},
		{
			"id": "quest_blocked_completion",
			"bucket": "quest_probes",
			"label": "Quest blocked completion stays in progress",
			"scenario": "quest_chaser",
			"active_quest_id": "starter_path",
			"initial_inventory": {"coins": 10, "raw_shrimp": 1},
			"actions": ["dialogue_action", "dialogue_action"],
			"expect": {"state_delta": true, "quest_started": true, "quest_not_completed": true},
		},
		{
			"id": "quest_objective_progress_return",
			"bucket": "quest_probes",
			"label": "Quest objective progress and return-ready state",
			"scenario": "quest_chaser",
			"active_quest_id": "starter_path",
			"initial_inventory": {"bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1, "coins": 20, "raw_shrimp": 1, "copper_ore": 1, "tin_ore": 1, "bronze_sword": 1, "logs": 1},
			"actions": ["dialogue_action", "cook", "use_item", "process_furnace", "process_anvil", "equip_item", "attack_mob", "bank_deposit", "shop_buy"],
			"expect": {"state_delta": true, "xp_gain": true, "quest_started": true, "quest_progress": true, "quest_return_ready": true},
		},
		{
			"id": "quest_completion_reward",
			"bucket": "quest_probes",
			"label": "Quest completion reward",
			"scenario": "quest_chaser",
			"active_quest_id": "starter_path",
			"initial_inventory": {"bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1, "coins": 20, "raw_shrimp": 1, "copper_ore": 1, "tin_ore": 1, "bronze_sword": 1, "logs": 1},
			"actions": ["dialogue_action", "cook", "use_item", "process_furnace", "process_anvil", "equip_item", "attack_mob", "bank_deposit", "shop_buy", "dialogue_action"],
			"expect": {"state_delta": true, "xp_gain": true, "quest_completed": true, "reward_gain": true},
		},
		{
			"id": "combat_loot_recovery",
			"bucket": "combat_probes",
			"label": "Combat, loot, and recovery",
			"initial_inventory": {"bronze_sword": 1, "cooked_shrimp": 2},
			"actions": ["equip_item", "attack_mob", "attack_mob", "attack_mob", "pickup_drop", "use_item"],
			"expect": {"state_delta": true, "xp_gain": true, "mob_defeat": true},
		},
		{
			"id": "combat_low_health_recovery",
			"bucket": "combat_probes",
			"label": "Low-health recovery item use",
			"initial_inventory": {"cooked_shrimp": 1},
			"initial_combat": {"current_hitpoints": 3, "mobs": {}, "ground_items": [], "status_effects": {}},
			"actions": ["use_item"],
			"expect": {"state_delta": true, "healing": true},
		},
		{
			"id": "combat_death_recovery",
			"bucket": "combat_probes",
			"label": "Zero-hitpoint recovery item use",
			"initial_inventory": {"trail_ration": 1},
			"initial_combat": {"current_hitpoints": 0, "mobs": {}, "ground_items": [], "status_effects": {}},
			"actions": ["use_item"],
			"expect": {"state_delta": true, "death_recovery": true},
		},
		{
			"id": "combat_status_cleanse",
			"bucket": "combat_probes",
			"label": "Combat status effect cleanse",
			"initial_inventory": {"mire_tonic": 1},
			"initial_combat": {"current_hitpoints": 8, "mobs": {}, "ground_items": [], "status_effects": {"poison": {"damage": 1, "rounds_remaining": 2}}},
			"actions": ["use_item"],
			"expect": {"state_delta": true, "status_effect_cleared": true},
		},
		{
			"id": "combat_drop_visibility",
			"bucket": "combat_probes",
			"label": "Combat drop creation and pickup",
			"target_mob_id": "rat_01",
			"initial_inventory": {"bronze_sword": 1},
			"actions": ["equip_item", "attack_mob", "attack_mob", "pickup_drop"],
			"expect": {"state_delta": true, "xp_gain": true, "mob_defeat": true, "drop_seen": true},
		},
		{
			"id": "economy_round_trip",
			"bucket": "economy_probes",
			"label": "Shop and bank round trip",
			"initial_inventory": {"coins": 50, "logs": 2},
			"initial_bank": {"copper_ore": 1},
			"actions": ["open_shop", "shop_buy", "shop_sell", "open_bank", "bank_deposit", "bank_withdraw"],
			"expect": {"state_delta": true, "coin_flow": true},
		},
		{
			"id": "inventory_pressure_recovery",
			"bucket": "inventory_probes",
			"label": "Full inventory recovery",
			"initial_inventory": {"bronze_axe": 1, "bronze_sword": 27},
			"actions": ["gather_woodcutting", "drop_item", "gather_woodcutting", "bank_deposit"],
			"expect": {"state_delta": true, "inventory_pressure": true},
		},
	]
	if mode != "full":
		return probes
	probes.append_array(_full_scenario_probe_definitions())
	return probes


func _full_scenario_probe_definitions() -> Array:
	var probes := []
	for resource in resources:
		if not (resource is Dictionary):
			continue
		var resource_id := str(resource.get("id", ""))
		var skill_id := str(resource.get("skill_id", ""))
		if resource_id.is_empty() or skill_id.is_empty():
			continue
		var initial_inventory := {"bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1}
		var required_tool := _required_tool_id(skill_id)
		if not required_tool.is_empty():
			initial_inventory[required_tool] = 1
		probes.append({
			"id": "resource_%s" % resource_id,
			"bucket": "resource_probes",
			"label": "Resource probe: %s" % str(resource.get("label", resource_id)),
			"target_resource_id": resource_id,
			"initial_skill_levels": {skill_id: int(resource.get("required_level", 1))},
			"initial_inventory": initial_inventory,
			"actions": ["gather_resource"],
			"expect": {"state_delta": true, "xp_gain": true},
		})
	for skill_id in ["woodcutting", "mining", "fishing"]:
		var action := "gather_%s" % skill_id
		probes.append({
			"id": "skill_%s" % skill_id,
			"bucket": "skill_probes",
			"label": "%s gathering probe" % _display_label(skill_id),
			"initial_inventory": {"bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1},
			"actions": [action, action],
			"expect": {"state_delta": true, "xp_gain": true},
		})
	for action_type in ["smelting", "smithing", "carpentry", "herbalism"]:
		var recipes = recipes_data.get(action_type, [])
		if not (recipes is Array):
			continue
		for recipe in recipes:
			if recipe is Dictionary:
				var recipe_probe := _recipe_probe_definition(action_type, recipe)
				if not recipe_probe.is_empty():
					probes.append(recipe_probe)
	for combat_style in ["strength", "ranged", "magic"]:
		var weapon_id := str({
			"strength": "bronze_sword",
			"ranged": "training_bow",
			"magic": "training_staff",
		}.get(combat_style, "bronze_sword"))
		probes.append({
			"id": "combat_%s_style" % combat_style,
			"bucket": "combat_probes",
			"label": "%s combat training style probe" % _display_label(combat_style),
			"combat_training_style": combat_style,
			"target_mob_id": "rat_01",
			"initial_inventory": {weapon_id: 1, "cooked_shrimp": 3},
			"actions": ["equip_item", "attack_mob", "attack_mob", "attack_mob", "pickup_drop"],
			"expect": {"state_delta": true, "xp_gain": true, "mob_defeat": true},
		})
	for quest in _as_array(quests_data.get("quests", [])):
		if not (quest is Dictionary):
			continue
		var quest_id := str(quest.get("quest_id", ""))
		if quest_id.is_empty():
			continue
		probes.append({
			"id": "quest_%s" % quest_id,
			"bucket": "quest_probes",
			"label": "Quest start probe: %s" % str(quest.get("display_name", quest_id)),
			"scenario": "quest_chaser",
			"active_quest_id": quest_id,
			"initial_inventory": {"coins": 50, "bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1, "bronze_sword": 1, "raw_shrimp": 1},
			"actions": ["dialogue_action", "dialogue_action"],
			"expect": {"state_delta": true, "quest_started": true},
		})
	for mob in mobs:
		if not (mob is Dictionary):
			continue
		var mob_id := str(mob.get("id", ""))
		if mob_id.is_empty():
			continue
		probes.append({
			"id": "mob_%s" % mob_id,
			"bucket": "combat_probes",
			"label": "Mob combat probe: %s" % str(mob.get("label", mob_id)),
			"target_mob_id": mob_id,
			"initial_inventory": {"bronze_sword": 1, "cooked_shrimp": 3},
			"actions": ["equip_item", "attack_mob", "attack_mob", "attack_mob", "pickup_drop"],
			"expect": {"state_delta": true, "xp_gain": true},
		})
	for npc in npcs:
		if not (npc is Dictionary):
			continue
		var npc_id := str(npc.get("id", ""))
		if npc_id.is_empty():
			continue
		probes.append({
			"id": "npc_%s" % npc_id,
			"bucket": "npc_probes",
			"label": "NPC interaction probe: %s" % str(npc.get("label", npc_id)),
			"target_npc_id": npc_id,
			"initial_inventory": {"coins": 50, "bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1},
			"actions": ["dialogue_action"],
		})
	for station_key in stations.keys():
		var station_id := str(station_key)
		var station_action := "open_bank" if station_id == "bank" else "open_shop" if station_id == "shop" else str({
			"cooking_range": "cook",
			"furnace": "process_furnace",
			"anvil": "process_anvil",
			"carpentry_bench": "process_carpentry",
			"apothecary_table": "process_apothecary",
		}.get(station_id, "process_station"))
		probes.append({
			"id": "station_%s" % station_id,
			"bucket": "station_probes",
			"label": "Station interaction probe: %s" % _display_label(station_id),
			"station_probe_id": station_id,
			"initial_inventory": {"coins": 50, "logs": 2, "plain_plank": 2, "plain_tool_handle": 1},
			"actions": [station_action],
		})
	if not npcs.is_empty():
		var talk_npc_id := str(npcs[0].get("id", ""))
		probes.append({
			"id": "action_talk_npc",
			"bucket": "npc_probes",
			"label": "Talk-to-NPC action probe",
			"target_npc_id": talk_npc_id,
			"actions": ["talk_npc"],
		})
	if not resources.is_empty():
		var examine_object_id := str(resources[0].get("id", ""))
		probes.append({
			"id": "action_examine_object",
			"bucket": "resource_probes",
			"label": "Examine-object action probe",
			"target_examine_object_id": examine_object_id,
			"actions": ["examine_object"],
		})
	return probes


func _recipe_probe_definition(action_type: String, recipe: Dictionary) -> Dictionary:
	if recipe.is_empty():
		return {}
	var inventory := {"bronze_axe": 1, "bronze_pickaxe": 1, "fishing_rod": 1}
	var inputs = recipe.get("inputs", {})
	if inputs is Dictionary:
		for item_id in inputs.keys():
			inventory[str(item_id)] = int(inputs[item_id])
	var action: String = str({
		"smelting": "process_furnace",
		"smithing": "process_anvil",
		"carpentry": "process_carpentry",
		"herbalism": "process_apothecary",
	}.get(action_type, "process_station"))
	return {
		"id": "recipe_%s_%s" % [action_type, str(recipe.get("recipe_id", "first"))],
		"recipe_id": str(recipe.get("recipe_id", "")),
		"recipe_action_type": action_type,
		"bucket": "recipe_probes",
		"label": "%s recipe probe: %s" % [_display_label(action_type), str(recipe.get("display_name", recipe.get("recipe_id", "")))],
		"initial_skill_levels": {str(PROCESSING_SKILLS.get(action_type, action_type)): int(recipe.get("required_level", 1))},
		"initial_inventory": inventory,
		"actions": [action],
		"expect": {"state_delta": true, "xp_gain": true},
	}


func _scenario_probe_known_gaps() -> Array:
	return [
		"Scenario probes exercise direct gameplay APIs, not real mouse/keyboard input timing.",
		"Scenario probes do not inspect rendered screenshots, audio timing, animation quality, or player comprehension.",
		"Full probes now cover every configured resource node, NPC, station, and interaction action through direct APIs; mouse/keyboard timing and rendered UI remain outside this probe lane.",
		"Golden smokes and save/load torture remain the pass/fail authorities; scenario probes are report-only diagnostics.",
	]


func _run_scenario_probe(probe: Dictionary, probe_index: int) -> Dictionary:
	var store = await _setup_scenario_probe_context(probe, probe_index)
	if store == null:
		return _scenario_probe_setup_failed(probe, probe_index)
	var issues := []
	current_probe_issues = issues
	scenario_probe_active = true
	var before_digest := _state_digest()
	var before_snapshot := _probe_state_snapshot()
	var actions := []
	var action_index := 0
	for raw_action in _as_array(probe.get("actions", [])):
		current_step = action_index
		var requested := str(raw_action)
		var resolved := requested if probe.has("recipe_id") or probe.has("station_probe_id") or probe.has("target_resource_id") or probe.has("target_npc_id") or probe.has("target_examine_object_id") else _resolve_action_preconditions(requested, action_index)
		var action_result := _execute_probe_action(requested, resolved, action_index)
		actions.append(action_result)
		action_index += 1
	scenario_probe_active = false
	var after_digest := _state_digest()
	var after_snapshot := _probe_state_snapshot()
	var result := {
		"id": str(probe.get("id", "")),
		"label": str(probe.get("label", probe.get("id", ""))),
		"bucket": str(probe.get("bucket", "core_loop_probes")),
		"mode": _resolved_scenario_probe_mode(),
		"completed": true,
		"diagnostic": false,
		"actions": actions,
		"metrics": _probe_metrics(before_snapshot, after_snapshot, before_digest != after_digest, actions),
		"issues": current_probe_issues.duplicate(true),
	}
	_apply_probe_expectations(result, probe)
	_record_probe_coverage(probe, result)
	_cleanup_current_simulation_run(store)
	current_probe_issues = []
	# Each probe owns a fresh scene context. Yield after freeing it so deferred
	# node/resource cleanup does not accumulate across the full probe suite.
	await process_frame
	return result


func _record_probe_coverage(probe: Dictionary, result: Dictionary) -> void:
	var probe_id := str(probe.get("id", ""))
	var succeeded := _as_array(result.get("issues", [])).is_empty()
	if probe_id.begins_with("skill_"):
		_coverage_mark("skills", probe_id.trim_prefix("skill_"), succeeded)
	elif probe_id.begins_with("recipe_"):
		var recipe_id := str(probe.get("recipe_id", ""))
		if recipe_id.is_empty():
			var parts := probe_id.split("_")
			if parts.size() >= 3:
				recipe_id = "_".join(parts.slice(2))
		_coverage_mark("recipes", recipe_id, succeeded)
	elif probe_id.begins_with("quest_"):
		_coverage_mark("quests", probe_id.trim_prefix("quest_"), succeeded)
	elif probe_id.begins_with("mob_"):
		_coverage_mark("mobs", probe_id.trim_prefix("mob_"), succeeded)
	elif probe_id.begins_with("resource_"):
		_coverage_mark("resources", probe_id.trim_prefix("resource_"), succeeded)
	elif probe_id.begins_with("npc_"):
		_coverage_mark("npcs", probe_id.trim_prefix("npc_"), succeeded)
	elif probe_id.begins_with("station_"):
		_coverage_mark("stations", probe_id.trim_prefix("station_"), succeeded)


func _setup_scenario_probe_context(probe: Dictionary, probe_index: int):
	current_run_index = -1000 - probe_index
	current_seed = int(config["seed"]) + 700000 + probe_index
	current_scenario = str(probe.get("scenario", "scenario_probe"))
	current_step = 0
	current_last_actions = []
	current_feedback_counts = {}
	current_issue_counts = {}
	current_issue_occurrences = 0
	current_issue_samples = 0
	current_no_progress_streak = 0
	current_max_no_progress_streak = 0
	current_run_telemetry = {}
	current_run_polish_telemetry = {}
	current_polish_feedback_counts = {}
	current_rng = RandomNumberGenerator.new()
	current_rng.seed = current_seed
	var store = preload("res://autoload/state_store.gd").new()
	store.save_dir = "%s/probe_saves" % str(config["output_dir"])
	current_state = store.create_default_state("probe_%s_%d" % [str(probe.get("id", "case")), current_seed])
	_apply_probe_initial_state(probe)
	current_world = preload("res://scenes/world.tscn").instantiate()
	current_hud = preload("res://scenes/hud.tscn").instantiate()
	if current_hud.has_method("set_simulation_lightweight_mode"):
		current_hud.call("set_simulation_lightweight_mode", true)
	current_gameplay = preload("res://scripts/gameplay_core.gd").new()
	root.add_child(current_world)
	root.add_child(current_hud)
	root.add_child(current_gameplay)
	await process_frame
	current_hud.bind_state(current_state)
	current_world.initialize_from_state(current_state)
	current_gameplay.setup(current_state, current_world, current_hud, "manual")
	if probe.has("recipe_id") and current_gameplay.has_method("set_simulation_recipe_override"):
		current_gameplay.call("set_simulation_recipe_override", str(probe.get("recipe_action_type", "")), str(probe.get("recipe_id", "")))
	return store


func _apply_probe_initial_state(probe: Dictionary) -> void:
	current_state["inventory"] = _normalize_probe_mapping(probe.get("initial_inventory", current_state.get("inventory", {})))
	current_state["bank"] = _normalize_probe_mapping(probe.get("initial_bank", current_state.get("bank", {})))
	if probe.has("combat_training_style"):
		current_state["combat_training_style"] = str(probe.get("combat_training_style", "attack"))
	var initial_skill_levels: Variant = probe.get("initial_skill_levels", {})
	if initial_skill_levels is Dictionary:
		var skills: Dictionary = current_state.get("skills", {})
		if not (skills is Dictionary):
			skills = {}
		for skill_id in initial_skill_levels.keys():
			var skill_key := str(skill_id)
			var level: int = maxi(1, int(initial_skill_levels[skill_id]))
			var values: Variant = skills.get(skill_key, {})
			if not (values is Dictionary):
				values = {}
			values["level"] = level
			values["xp"] = _skill_xp_threshold(skill_key, level)
			skills[skill_key] = values
		current_state["skills"] = skills
	if probe.has("active_quest_id"):
		current_state["quest_state"] = {"active_quest_id": str(probe["active_quest_id"]), "quests": {}}
	if probe.has("target_mob_id"):
		current_state["probe_target_mob_id"] = str(probe["target_mob_id"])
	if probe.has("target_resource_id"):
		current_state["probe_target_resource_id"] = str(probe["target_resource_id"])
	if probe.has("target_npc_id"):
		current_state["probe_target_npc_id"] = str(probe["target_npc_id"])
	if probe.has("target_examine_object_id"):
		current_state["probe_target_examine_object_id"] = str(probe["target_examine_object_id"])
	if probe.has("initial_combat") and probe["initial_combat"] is Dictionary:
		current_state["combat"] = probe["initial_combat"].duplicate(true)
	var combat = current_state.get("combat", {})
	if combat is Dictionary:
		combat["current_hitpoints"] = int(combat.get("current_hitpoints", _skill_level("hitpoints")))
		current_state["combat"] = combat


func _normalize_probe_mapping(value) -> Dictionary:
	var result := {}
	if value is Dictionary:
		for key in value.keys():
			result[str(key)] = int(value[key])
	return result


func _skill_xp_threshold(skill_id: String, level: int) -> int:
	var definition = skills_data.get(skill_id, {})
	if definition is Dictionary:
		var thresholds = definition.get("xp_thresholds", {})
		if thresholds is Dictionary:
			var exact_key := str(max(1, level))
			if thresholds.has(exact_key):
				return int(thresholds[exact_key])
			var best_level := 1
			var best_xp := 0
			for threshold_key in thresholds.keys():
				var threshold_level := int(threshold_key)
				if threshold_level <= level and threshold_level >= best_level:
					best_level = threshold_level
					best_xp = int(thresholds[threshold_key])
			return best_xp
	return 0


func _scenario_probe_setup_failed(probe: Dictionary, probe_index: int) -> Dictionary:
	return {
		"id": str(probe.get("id", "probe_%d" % probe_index)),
		"label": str(probe.get("label", probe.get("id", ""))),
		"bucket": str(probe.get("bucket", "core_loop_probes")),
		"completed": false,
		"diagnostic": true,
		"actions": [],
		"metrics": {},
		"issues": [{
			"code": "scenario_probe_stalled",
			"summary": "Probe setup failed.",
			"metadata": {"probe_index": probe_index},
		}],
	}


func _execute_probe_action(requested: String, resolved: String, action_index: int) -> Dictionary:
	var before_digest := _state_digest()
	var before_feedback := _feedback_text()
	var before_snapshot := _probe_state_snapshot()
	var before_skill_xp := _skill_xp_snapshot()
	var started_usec := Time.get_ticks_usec()
	var record := _execute_action(resolved)
	var after_feedback := _feedback_text()
	var after_digest := _state_digest()
	var after_snapshot := _probe_state_snapshot()
	var after_skill_xp := _skill_xp_snapshot()
	record["feedback"] = after_feedback
	record["previous_feedback"] = before_feedback
	record["changed_state"] = before_digest != after_digest
	record["inventory_slots"] = _inventory_slot_count(_inventory())
	record["hitpoints"] = _current_hitpoints()
	record["hitpoints_before"] = int(before_snapshot.get("hitpoints", 0))
	record["damage_taken"] = max(0, int(before_snapshot.get("hitpoints", 0)) - _current_hitpoints())
	record["healing_done"] = max(0, _current_hitpoints() - int(before_snapshot.get("hitpoints", 0)))
	record["coin_delta"] = int(after_snapshot.get("coins", 0)) - int(before_snapshot.get("coins", 0))
	record["skill_xp_deltas"] = _skill_xp_deltas(before_skill_xp, after_skill_xp)
	record["elapsed_usec"] = Time.get_ticks_usec() - started_usec
	_record_coverage(record)
	_check_invariants(record)
	_advance_clock_between_actions(record)
	return {
		"step": action_index,
		"requested": requested,
		"resolved": resolved,
		"changed_state": bool(record.get("changed_state", false)),
		"skipped": bool(record.get("skipped", false)),
		"feedback": str(record.get("feedback", "")),
		"target_id": str(record.get("target_id", "")),
		"path_length": int(record.get("path_length", 0)),
		"coin_delta": int(record.get("coin_delta", 0)),
		"damage_taken": int(record.get("damage_taken", 0)),
		"healing_done": int(record.get("healing_done", 0)),
		"xp_delta": int(after_snapshot.get("total_xp", 0)) - int(before_snapshot.get("total_xp", 0)),
		"mobs_defeated_delta": int(after_snapshot.get("mobs_defeated", 0)) - int(before_snapshot.get("mobs_defeated", 0)),
	}


func _probe_state_snapshot() -> Dictionary:
	var quest_counts := _quest_counts()
	return {
		"coins": int(_inventory().get("coins", 0)),
		"inventory_slots": _inventory_slot_count(_inventory()),
		"bank_slots": _inventory_slot_count(_bank()),
		"total_xp": _total_xp(),
		"mobs_defeated": _mobs_defeated_count(),
		"hitpoints": _current_hitpoints(),
		"quests_started": int(quest_counts.get("started", 0)),
		"quests_completed": int(quest_counts.get("completed", 0)),
		"quest_flags": _quest_flag_count(),
		"quests_ready_to_return": _quests_ready_to_return_count(),
		"ground_items": _ground_items_quantity(),
		"status_effects": _status_effect_count(),
		"poison_status": _poison_status_count(),
	}


func _probe_metrics(before_snapshot: Dictionary, after_snapshot: Dictionary, changed_state: bool, actions: Array) -> Dictionary:
	var changed_steps := 0
	var skipped_steps := 0
	var failed_feedback_steps := 0
	var max_path_length := 0
	var healing_done := 0
	var damage_taken := 0
	for action in actions:
		if not (action is Dictionary):
			continue
		if bool(action.get("changed_state", false)):
			changed_steps += 1
		if bool(action.get("skipped", false)):
			skipped_steps += 1
		if _is_failure_feedback(str(action.get("feedback", ""))):
			failed_feedback_steps += 1
		max_path_length = max(max_path_length, int(action.get("path_length", 0)))
		healing_done += int(action.get("healing_done", 0))
		damage_taken += int(action.get("damage_taken", 0))
	return {
		"changed_state": changed_state,
		"changed_steps": changed_steps,
		"skipped_steps": skipped_steps,
		"failed_feedback_steps": failed_feedback_steps,
		"max_path_length": max_path_length,
		"healing_done": healing_done,
		"damage_taken": damage_taken,
		"hitpoints_before": int(before_snapshot.get("hitpoints", 0)),
		"hitpoints_after": int(after_snapshot.get("hitpoints", 0)),
		"hitpoints_delta": int(after_snapshot.get("hitpoints", 0)) - int(before_snapshot.get("hitpoints", 0)),
		"xp_delta": int(after_snapshot.get("total_xp", 0)) - int(before_snapshot.get("total_xp", 0)),
		"coin_delta": int(after_snapshot.get("coins", 0)) - int(before_snapshot.get("coins", 0)),
		"inventory_slot_delta": int(after_snapshot.get("inventory_slots", 0)) - int(before_snapshot.get("inventory_slots", 0)),
		"bank_slot_delta": int(after_snapshot.get("bank_slots", 0)) - int(before_snapshot.get("bank_slots", 0)),
		"mobs_defeated_delta": int(after_snapshot.get("mobs_defeated", 0)) - int(before_snapshot.get("mobs_defeated", 0)),
		"quests_started_delta": int(after_snapshot.get("quests_started", 0)) - int(before_snapshot.get("quests_started", 0)),
		"quests_completed_delta": int(after_snapshot.get("quests_completed", 0)) - int(before_snapshot.get("quests_completed", 0)),
		"quest_flags_delta": int(after_snapshot.get("quest_flags", 0)) - int(before_snapshot.get("quest_flags", 0)),
		"quests_ready_to_return_delta": int(after_snapshot.get("quests_ready_to_return", 0)) - int(before_snapshot.get("quests_ready_to_return", 0)),
		"ground_items_delta": int(after_snapshot.get("ground_items", 0)) - int(before_snapshot.get("ground_items", 0)),
		"status_effects_delta": int(after_snapshot.get("status_effects", 0)) - int(before_snapshot.get("status_effects", 0)),
		"poison_status_delta": int(after_snapshot.get("poison_status", 0)) - int(before_snapshot.get("poison_status", 0)),
	}


func _apply_probe_expectations(result: Dictionary, probe: Dictionary) -> void:
	var expect = probe.get("expect", {})
	if not (expect is Dictionary):
		return
	var metrics = result.get("metrics", {})
	if not (metrics is Dictionary):
		return
	if bool(expect.get("state_delta", false)) and not bool(metrics.get("changed_state", false)):
		_add_probe_issue(result, "scenario_no_state_delta", "Probe completed without changing durable game state.")
	if bool(expect.get("xp_gain", false)) and int(metrics.get("xp_delta", 0)) <= 0:
		_add_probe_issue(result, "scenario_no_xp_gain", "Probe expected XP gain but none was observed.")
	if bool(expect.get("quest_started", false)) and int(metrics.get("quests_started_delta", 0)) <= 0:
		_add_probe_issue(result, "scenario_quest_branch_not_exercised", "Probe expected a quest start or quest branch exercise but none was observed.")
	if bool(expect.get("quest_progress", false)) and int(metrics.get("quest_flags_delta", 0)) <= 0:
		_add_probe_issue(result, "scenario_quest_progress_not_observed", "Probe expected quest objective progress but no quest flags changed.")
	if bool(expect.get("quest_return_ready", false)) and int(metrics.get("quests_ready_to_return_delta", 0)) <= 0:
		_add_probe_issue(result, "scenario_quest_return_prompt_not_reached", "Probe expected a quest return-ready state but did not reach one.")
	if bool(expect.get("quest_completed", false)) and int(metrics.get("quests_completed_delta", 0)) <= 0:
		_add_probe_issue(result, "scenario_quest_completion_not_observed", "Probe expected quest completion but no completion was observed.")
	if bool(expect.get("quest_not_completed", false)) and int(metrics.get("quests_completed_delta", 0)) > 0:
		_add_probe_issue(result, "scenario_quest_unexpected_completion", "Probe expected incomplete quest state but the quest completed.")
	if bool(expect.get("reward_gain", false)) and int(metrics.get("coin_delta", 0)) <= 0 and int(metrics.get("xp_delta", 0)) <= 0:
		_add_probe_issue(result, "scenario_quest_reward_not_observed", "Probe expected a quest reward but saw no coin or XP gain.")
	if bool(expect.get("mob_defeat", false)) and int(metrics.get("mobs_defeated_delta", 0)) <= 0:
		_add_probe_issue(result, "scenario_combat_unresolved", "Probe expected at least one defeated mob but none was observed.")
	if bool(expect.get("healing", false)) and int(metrics.get("healing_done", 0)) <= 0:
		_add_probe_issue(result, "scenario_combat_recovery_not_observed", "Probe expected recovery healing but no healing was observed.")
	if bool(expect.get("death_recovery", false)) and (int(metrics.get("hitpoints_before", 0)) > 0 or int(metrics.get("hitpoints_after", 0)) <= 0):
		_add_probe_issue(result, "scenario_combat_death_recovery_failed", "Probe expected recovery from zero hitpoints but did not observe it.")
	if bool(expect.get("drop_seen", false)) and int(metrics.get("ground_items_delta", 0)) <= 0 and int(metrics.get("mobs_defeated_delta", 0)) <= 0:
		_add_probe_issue(result, "scenario_combat_drop_not_observed", "Probe expected combat loot or drop creation but none was observed.")
	if bool(expect.get("status_effect_cleared", false)) and int(metrics.get("poison_status_delta", 0)) >= 0:
		_add_probe_issue(result, "scenario_combat_status_not_cleared", "Probe expected poison to clear but poison status did not decrease.")
	if bool(expect.get("coin_flow", false)) and int(metrics.get("coin_delta", 0)) == 0:
		_add_probe_issue(result, "scenario_economy_value_out_of_range", "Probe expected a coin delta from shop or bank economy actions.")
	if bool(expect.get("inventory_pressure", false)) and int(metrics.get("skipped_steps", 0)) >= _as_array(probe.get("actions", [])).size():
		_add_probe_issue(result, "scenario_inventory_recovery_failed", "Inventory pressure probe skipped every action.")
	if int(metrics.get("skipped_steps", 0)) >= _as_array(probe.get("actions", [])).size():
		_add_probe_issue(result, "scenario_probe_stalled", "Every requested probe action was skipped.")
	result["diagnostic"] = not _as_array(result.get("issues", [])).is_empty()


func _add_probe_issue(result: Dictionary, code: String, summary: String) -> void:
	var issues = result.get("issues", [])
	if not (issues is Array):
		issues = []
	issues.append({
		"code": code,
		"summary": summary,
	})
	result["issues"] = issues


func _add_probe_result_to_report(report: Dictionary, result: Dictionary) -> void:
	var bucket_name := str(result.get("bucket", "core_loop_probes"))
	if not report.has(bucket_name) or not (report[bucket_name] is Array):
		report[bucket_name] = []
	report[bucket_name].append(result)
	report["summary"]["completed"] = int(report["summary"].get("completed", 0)) + (1 if bool(result.get("completed", false)) else 0)
	if bool(result.get("diagnostic", false)):
		report["summary"]["diagnostic"] = int(report["summary"].get("diagnostic", 0)) + 1
	for issue in _as_array(result.get("issues", [])):
		if issue is Dictionary:
			var report_issue: Dictionary = issue.duplicate(true)
			report_issue["probe_id"] = str(result.get("id", ""))
			report_issue["bucket"] = bucket_name
			report["issues"].append(report_issue)


func _add_report_probe_issue(report: Dictionary, code: String, summary: String, metadata: Dictionary = {}) -> void:
	report["issues"].append({
		"code": code,
		"summary": summary,
		"metadata": metadata,
	})


func _scenario_for_run(run_index: int) -> String:
	var requested := str(config["scenario"])
	if requested != "all":
		return requested
	var profile_mix := _balance_profile_scenario_mix()
	return str(profile_mix[run_index % profile_mix.size()])


func _campaign_action(base_action: String, step: int) -> String:
	var campaign := str(config.get("campaign", DEFAULT_CAMPAIGN))
	if campaign == "adversarial":
		match step % 47:
			0: return "adversarial_invalid_bank"
			11: return "adversarial_invalid_shop"
			23: return "adversarial_invalid_inventory"
			37: return "adversarial_rapid_repeat"
	if campaign == "content":
		var content_actions := ["gather_woodcutting", "gather_mining", "gather_fishing", "process_furnace", "process_anvil", "process_carpentry", "process_apothecary", "cook", "attack_mob", "dialogue_action", "bank_deposit", "bank_withdraw", "shop_buy", "shop_sell", "use_item", "equip_item", "drop_item"]
		var content_action := str(content_actions[step % content_actions.size()])
		if content_action == "dialogue_action" and _dialogue_action_blocked_for_sim():
			# The game intentionally blocks quest completion when the inventory is
			# full. Keep the content campaign from manufacturing that expected block;
			# the audit should measure player-facing defects, not bot inventory policy.
			return _full_inventory_recovery_action(step)
		return content_action
	return base_action


func _perform_state_checkpoint(store: Object, username: String, record: Dictionary) -> void:
	if store == null or not store.has_method("save_state") or not store.has_method("load_state"):
		return
	if not bool(store.call("save_state", username, current_state)):
		record["checkpoint"] = "save_failed"
		_record_issue("bug", "P1", str(record.get("action", "checkpoint")), "Adversarial save checkpoint failed.", _feedback_text(), {})
		return
	var loaded = store.call("load_state", username)
	if not (loaded is Dictionary) or loaded.is_empty():
		record["checkpoint"] = "load_failed"
		_record_issue("bug", "P1", str(record.get("action", "checkpoint")), "Adversarial save checkpoint could not reload state.", _feedback_text(), {})
		return
	current_state = loaded.duplicate(true)
	record["checkpoint"] = "round_trip"
	if current_hud != null and current_hud.has_method("bind_state"):
		current_hud.bind_state(current_state)
	if current_world != null and current_world.has_method("initialize_from_state"):
		current_world.initialize_from_state(current_state)
	if current_gameplay != null and current_gameplay.has_method("setup"):
		current_gameplay.setup(current_state, current_world, current_hud, "manual")


func _choose_action(scenario: String, step: int) -> String:
	match scenario:
		"core_loop":
			var actions := [
				"gather_resource",
				"gather_resource",
				"process_station",
				"cook",
				"attack_mob",
				"pickup_drop",
				"equip_item",
				"use_item",
				"bank_deposit",
				"shop_buy",
				"shop_sell",
			]
			return str(actions[step % actions.size()])
		"quest_chaser":
			return _choose_quest_action(step)
		"economy_stress":
			var actions := [
				"open_shop",
				"shop_buy",
				"shop_sell",
				"open_bank",
				"bank_deposit",
				"bank_withdraw",
				"equip_item",
				"use_item",
			]
			return str(actions[step % actions.size()])
		"combat_loot":
			if not _first_pickable_ground_item().is_empty():
				return "pickup_drop"
			if _combat_recovery_needed():
				if _has_usable_item():
					return "use_item"
				if not _first_bank_usable_item().is_empty():
					return "bank_withdraw"
				if not _pick_affordable_shop_usable().is_empty():
					return "shop_buy"
				return _non_combat_productive_action(step)
			if _pick_mob().is_empty():
				return _non_combat_productive_action(step)
			return "attack_mob"
		"inventory_pressure":
			if _inventory_slot_count(_inventory()) >= INVENTORY_SLOT_LIMIT:
				var pressure_actions := ["gather_resource", "bank_deposit", "drop_item", "process_station", "shop_sell"]
				return str(pressure_actions[step % pressure_actions.size()])
			if step % 9 == 0:
				return "shop_buy"
			if step % 7 == 0:
				return "attack_mob"
			return "gather_resource"
		"random_guard":
			var weighted := [
				"gather_resource",
				"process_station",
				"cook",
				"attack_mob",
				"pickup_drop",
				"talk_npc",
				"dialogue_action",
				"open_bank",
				"bank_deposit",
				"bank_withdraw",
				"open_shop",
				"shop_buy",
				"shop_sell",
				"use_item",
				"equip_item",
				"drop_item",
				"examine_object",
			]
			return _random_entry(weighted, "gather_resource")
	return "gather_resource"


func _choose_quest_action(step: int) -> String:
	if step % 14 == 0:
		return "dialogue_action"
	var target := _active_quest_target()
	if target.is_empty():
		return "dialogue_action"
	var missing := _missing_flags(target)
	if missing.is_empty():
		return "dialogue_action"
	if missing.has("ate_food") and not _has_usable_item():
		var alternate := _first_actionable_quest_flag_action(missing, "ate_food")
		if not alternate.is_empty():
			return alternate
		return "attack_mob"
	var flag := str(missing[0])
	return _quest_action_for_flag(flag)


func _quest_policy_active() -> bool:
	return str(config.get("quest_policy", DEFAULT_QUEST_POLICY)) == "aware" and current_scenario == "quest_chaser"


func _choose_quest_aware_action(_step: int, fallback_action: String) -> String:
	current_quest_policy_protected_items = {}
	current_quest_policy_target_item = ""
	current_quest_policy_target_quantity = 0
	current_quest_policy_objective_flag = ""
	current_quest_policy_quest_id = ""
	var target := _active_quest_target()
	if target.is_empty():
		return fallback_action
	var missing := _missing_flags(target)
	if missing.is_empty():
		return "dialogue_action"
	var flag := str(missing[0])
	current_quest_policy_quest_id = str(target.get("quest_id", ""))
	current_quest_policy_objective_flag = flag
	var recipe := _quest_policy_recipe_for_flag(flag)
	if not recipe.is_empty():
		var inputs = recipe.get("inputs", {})
		if inputs is Dictionary:
			for item_id in inputs.keys():
				var item_key := str(item_id)
				var required_quantity := int(inputs[item_id])
				current_quest_policy_protected_items[item_key] = required_quantity
				var inventory_quantity := int(_inventory().get(item_key, 0))
				var bank_quantity := int(_bank().get(item_key, 0))
				if inventory_quantity < required_quantity and bank_quantity > 0 and _can_add_inventory_item(item_key, 1):
					current_quest_policy_target_item = item_key
					current_quest_policy_target_quantity = min(required_quantity - inventory_quantity, bank_quantity)
					_add_telemetry_int(current_run_telemetry, "quest_policy_withdrawal_requests", 1)
					return "bank_withdraw"
			var recipe_type := str(recipe.get("_audit_recipe_type", ""))
			if _has_recipe_inputs(recipe):
				if _recipe_can_complete_now_for_sim(recipe_type, recipe):
					return _quest_policy_processing_action(recipe_type)
				if _inventory_slot_count(_inventory()) >= INVENTORY_SLOT_LIMIT and _has_depositable_item():
					return "bank_deposit"
			for item_id in inputs.keys():
				var missing_item := str(item_id)
				if int(_inventory().get(missing_item, 0)) < int(inputs[item_id]):
					var producer_action := _quest_policy_producer_action(missing_item)
					if not producer_action.is_empty():
						return producer_action
	for equipped_item in _equipment().values():
		var equipped_key := str(equipped_item)
		if not equipped_key.is_empty():
			current_quest_policy_protected_items[equipped_key] = max(1, int(current_quest_policy_protected_items.get(equipped_key, 0)))
	if flag == "ate_food" and not _has_usable_item():
		var bank_food := _first_bank_usable_item()
		if not bank_food.is_empty() and _can_add_inventory_item(bank_food, 1):
			current_quest_policy_target_item = bank_food
			current_quest_policy_target_quantity = 1
			_add_telemetry_int(current_run_telemetry, "quest_policy_withdrawal_requests", 1)
			return "bank_withdraw"
	if flag == "used_bank" and _has_depositable_item():
		return "bank_deposit"
	var action := _quest_action_for_flag(flag)
	if action.is_empty():
		_add_telemetry_int(current_run_telemetry, "quest_policy_blocked_objectives", 1)
		return fallback_action
	return action


func _quest_policy_recipe_for_flag(flag: String) -> Dictionary:
	var wanted_recipe_id := ""
	var wanted_output_id := ""
	var recipe_types: Array = []
	if flag == "smelted_bar":
		recipe_types = ["smelting"]
	elif flag == "smithed_gear":
		recipe_types = ["smithing"]
	elif flag.begins_with("crafted_"):
		wanted_recipe_id = flag.trim_prefix("crafted_")
		wanted_output_id = wanted_recipe_id
		recipe_types = ["carpentry", "smithing", "herbalism", "smelting"]
	else:
		return {}
	for recipe_type in recipe_types:
		var recipes = recipes_data.get(str(recipe_type), [])
		if not (recipes is Array):
			continue
		for raw_recipe in recipes:
			if not (raw_recipe is Dictionary):
				continue
			var recipe: Dictionary = raw_recipe.duplicate(true)
			if wanted_recipe_id.is_empty() or str(recipe.get("recipe_id", "")) == wanted_recipe_id or str(recipe.get("output_item_id", "")) == wanted_output_id:
				recipe["_audit_recipe_type"] = str(recipe_type)
				return recipe
	return {}


func _quest_policy_processing_action(recipe_type: String) -> String:
	match recipe_type:
		"smelting":
			return "process_furnace"
		"smithing":
			return "process_anvil"
		"carpentry":
			return "process_carpentry"
		"herbalism":
			return "process_apothecary"
	return "process_station"


func _quest_policy_producer_action(item_id: String, seen: Array = []) -> String:
	if item_id.is_empty() or item_id in seen:
		return _quest_policy_raw_item_action(item_id)
	var next_seen := seen.duplicate()
	next_seen.append(item_id)
	for recipe_type in ["smelting", "smithing", "carpentry", "herbalism"]:
		var recipes = recipes_data.get(recipe_type, [])
		if not (recipes is Array):
			continue
		for raw_recipe in recipes:
			if not (raw_recipe is Dictionary) or str(raw_recipe.get("output_item_id", "")) != item_id:
				continue
			var recipe: Dictionary = raw_recipe
			if _has_recipe_inputs(recipe) and _recipe_can_complete_now_for_sim(str(recipe_type), recipe):
				return _quest_policy_processing_action(str(recipe_type))
			var inputs = recipe.get("inputs", {})
			if inputs is Dictionary:
				for input_id in inputs.keys():
					if int(_inventory().get(str(input_id), 0)) < int(inputs[input_id]):
						return _quest_policy_producer_action(str(input_id), next_seen)
	return _quest_policy_raw_item_action(item_id)


func _quest_policy_raw_item_action(item_id: String) -> String:
	if item_id == "logs" or item_id.ends_with("_logs"):
		return "gather_woodcutting"
	if item_id.ends_with("_ore") or item_id == "coal":
		return "gather_mining"
	if item_id == "raw_shrimp" or item_id == "raw_fish":
		return "gather_fishing"
	if item_id.ends_with("herb") or item_id.ends_with("_reeds") or item_id == "bloom_pollen":
		return "gather_resource"
	return "gather_resource"


func _quest_policy_protects_item(item_id: String) -> bool:
	if not _quest_policy_active() or item_id.is_empty():
		return false
	return int(current_quest_policy_protected_items.get(item_id, 0)) > 0


func _record_quest_policy_action_result(action_name: String, before_target_quantity: int, record: Dictionary) -> void:
	if not _quest_policy_active():
		return
	var objective := str(record.get("quest_objective_flag", ""))
	var action_key := "%s:%s" % [objective, action_name]
	_increment_count(current_run_telemetry.get("quest_policy_objective_action_counts", {}), action_key)
	_increment_count(current_run_telemetry.get("quest_policy_quest_counts", {}), str(record.get("quest_policy_quest_id", "")))
	if action_name == "bank_withdraw" and not current_quest_policy_target_item.is_empty():
		var after_target_quantity := int(_inventory().get(current_quest_policy_target_item, 0))
		if after_target_quantity > before_target_quantity:
			_add_telemetry_int(current_run_telemetry, "quest_policy_withdrawal_successes", 1)


func _first_actionable_quest_flag_action(missing: Array, skipped_flag: String = "") -> String:
	for raw_flag in missing:
		var flag := str(raw_flag)
		if flag == skipped_flag:
			continue
		var action := _quest_action_for_flag(flag)
		if not action.is_empty() and _action_has_valid_target(action):
			return action
	return ""


func _quest_action_for_flag(flag: String) -> String:
	if flag == "talk_to_npc":
		return "dialogue_action"
	if flag.begins_with("gathered_") or flag in ["caught_fish", "gathered_wood", "gathered_herb"]:
		return "gather_resource"
	if flag == "cooked_food" or flag == "ate_food":
		if flag == "ate_food" and _has_usable_item():
			return "use_item"
		if not _has_raw_cookable():
			return "gather_fishing"
		return "cook"
	if flag == "smelted_bar":
		if _has_recipe_inputs_for_type("smelting"):
			return "process_furnace"
		return "gather_mining"
	if flag == "smithed_gear":
		if _has_recipe_inputs_for_type("smithing"):
			return "process_anvil"
		if _has_recipe_inputs_for_type("smelting"):
			return "process_furnace"
		return "gather_mining"
	if flag.begins_with("crafted_"):
		if flag in ["crafted_mire_tonic", "crafted_fen_tonic"]:
			if _has_recipe_inputs_for_type("herbalism"):
				return "process_apothecary"
			return "gather_resource"
		if _has_recipe_inputs_for_type("carpentry"):
			return "process_carpentry"
		return "gather_woodcutting"
	if flag.begins_with("equipped_") or flag == "equipped_weapon":
		if _has_equippable_item():
			return "equip_item"
		if _can_afford_shop_item(func(_item_id: String, _stock: Dictionary, definition) -> bool: return definition is Dictionary and definition.has("equip_slot")):
			return "shop_buy"
		return "gather_resource"
	if flag.begins_with("defeated_") or flag == "defeated_enemy":
		return "attack_mob"
	if flag == "used_bank":
		if _has_depositable_item():
			return "bank_deposit"
		if _has_withdrawable_item():
			return "bank_withdraw"
		return "gather_resource"
	if flag == "used_shop":
		if _can_afford_shop_item(func(_item_id: String, _stock: Dictionary, _definition) -> bool: return true):
			return "shop_buy"
		if _has_sellable_item():
			return "shop_sell"
		return "gather_resource"
	return ""


func _resolve_action_preconditions(action_name: String, step: int) -> String:
	match action_name:
		"gather_resource":
			if not _pick_resource("").is_empty():
				return action_name
			return _non_combat_productive_action(step)
		"gather_woodcutting":
			return _resolve_gather_action(action_name, "woodcutting", step)
		"gather_mining":
			return _resolve_gather_action(action_name, "mining", step)
		"gather_fishing":
			return _resolve_gather_action(action_name, "fishing", step)
		"attack_mob":
			if _combat_recovery_needed():
				if _has_usable_item():
					return "use_item"
				if not _first_bank_usable_item().is_empty():
					return "bank_withdraw"
				if not _pick_affordable_shop_usable().is_empty():
					return "shop_buy"
				return _non_combat_productive_action(step)
			if _pick_mob().is_empty():
				return _non_combat_productive_action(step)
		"bank_deposit":
			if _has_depositable_item():
				return action_name
			if _has_withdrawable_item():
				return "bank_withdraw"
			return _non_combat_productive_action(step)
		"bank_withdraw":
			if _has_withdrawable_item():
				return action_name
			if _has_depositable_item():
				return "bank_deposit"
			return _non_combat_productive_action(step)
		"shop_buy":
			if _can_afford_shop_item(func(_item_id: String, _stock: Dictionary, _definition) -> bool: return true):
				return action_name
			if _has_sellable_item():
				return "shop_sell"
			return _non_combat_productive_action(step)
		"shop_sell":
			if _has_sellable_item():
				return action_name
			if _can_afford_shop_item(func(_item_id: String, _stock: Dictionary, _definition) -> bool: return true):
				return "shop_buy"
			return _non_combat_productive_action(step)
		"use_item":
			if _has_usable_item():
				return action_name
			if not _first_bank_usable_item().is_empty():
				return "bank_withdraw"
			if _needs_healing() and not _pick_affordable_shop_usable().is_empty():
				return "shop_buy"
			return _non_combat_productive_action(step)
		"equip_item":
			if _has_equippable_item():
				return action_name
			return _non_combat_productive_action(step)
		"drop_item":
			if _has_droppable_item():
				return action_name
			return _non_combat_productive_action(step)
		"pickup_drop":
			if not _first_pickable_ground_item().is_empty():
				return action_name
			if not _ground_items().is_empty():
				return _full_inventory_recovery_action(step)
			return _non_combat_productive_action(step)
		"cook":
			if _has_raw_cookable_with_room():
				return action_name
			if _has_raw_cookable():
				return _full_inventory_recovery_action(step)
			return "gather_fishing"
		"process_station":
			if _has_useful_processing_input_with_room():
				return action_name
			if _has_useful_processing_input():
				return _full_inventory_recovery_action(step)
			return _processing_input_action()
		"process_furnace":
			if _has_recipe_inputs_for_type_with_room("smelting"):
				return action_name
			if _has_recipe_inputs_for_type("smelting"):
				return _full_inventory_recovery_action(step)
			return "gather_mining"
		"process_anvil":
			if _has_recipe_inputs_for_type_with_room("smithing"):
				return action_name
			if _has_recipe_inputs_for_type("smithing"):
				return _full_inventory_recovery_action(step)
			return "process_furnace" if _has_recipe_inputs_for_type_with_room("smelting") else "gather_mining"
		"process_carpentry":
			if _has_recipe_inputs_for_type_with_room("carpentry"):
				return action_name
			if _has_recipe_inputs_for_type("carpentry"):
				return _full_inventory_recovery_action(step)
			return "gather_woodcutting"
		"process_apothecary":
			if _has_recipe_inputs_for_type_with_room("herbalism"):
				return action_name
			if _has_recipe_inputs_for_type("herbalism"):
				return _full_inventory_recovery_action(step)
			return "gather_resource"
	return action_name


func _resolve_gather_action(action_name: String, skill_id: String, step: int) -> String:
	if not _pick_resource(skill_id).is_empty():
		return action_name
	var required_tool := _required_tool_id(skill_id)
	if not required_tool.is_empty() and int(_inventory().get(required_tool, 0)) <= 0:
		if _can_afford_shop_item(func(item_id: String, _stock: Dictionary, _definition) -> bool: return item_id == required_tool):
			return "shop_buy"
		if _has_sellable_item():
			return "shop_sell"
	return _non_combat_productive_action(step)


func _non_combat_productive_action(step: int) -> String:
	if not _first_pickable_ground_item().is_empty():
		return "pickup_drop"
	if _inventory_slot_count(_inventory()) >= INVENTORY_SLOT_LIMIT:
		return _full_inventory_recovery_action(step)
	if _has_useful_processing_input():
		return "process_station"
	if current_scenario != "quest_chaser" and _has_sellable_item():
		return "shop_sell"
	if _has_depositable_item():
		return "bank_deposit"
	if _inventory_slot_count(_inventory()) < INVENTORY_SLOT_LIMIT:
		return "gather_resource"
	if _has_droppable_item():
		return "drop_item"
	if _has_withdrawable_item():
		return "bank_withdraw"
	return "examine_object" if step % 5 == 0 else "talk_npc"


func _full_inventory_recovery_action(step: int) -> String:
	if _has_usable_item():
		return "use_item"
	if current_scenario != "quest_chaser" and _has_sellable_item():
		return "shop_sell"
	if _has_depositable_item():
		return "bank_deposit"
	if _has_droppable_item():
		return "drop_item"
	return "examine_object" if step % 5 == 0 else "talk_npc"


func _execute_action(action_name: String) -> Dictionary:
	var record := _base_action_record(action_name)
	match action_name:
		"gather_resource":
			_interact_object(_pick_resource(""), "default", record)
		"gather_woodcutting":
			_interact_object(_pick_resource("woodcutting"), "default", record)
		"gather_mining":
			_interact_object(_pick_resource("mining"), "default", record)
		"gather_fishing":
			_interact_object(_pick_resource("fishing"), "default", record)
		"process_station":
			_interact_object(_pick_best_processing_station(), "default", record)
		"process_furnace":
			_interact_object(_station("furnace"), "default", record)
		"process_anvil":
			_interact_object(_station("anvil"), "default", record)
		"process_carpentry":
			_interact_object(_station("carpentry_bench"), "default", record)
		"process_apothecary":
			_interact_object(_station("apothecary_table"), "default", record)
		"cook":
			_interact_object(_station("cooking_range"), "default", record)
		"attack_mob":
			_interact_object(_pick_mob(), "attack", record)
		"pickup_drop":
			_interact_object(_first_ground_item(true), "default", record)
		"talk_npc":
			_interact_object(_pick_npc(), "default", record)
		"dialogue_action":
			_emit_dialogue_action(_pick_npc(), record)
		"open_bank":
			_interact_object(_station("bank"), "default", record)
		"bank_deposit":
			_emit_hud_request("bank_deposit_requested", [_first_depositable_item(), _bank_quantity()], record)
		"bank_withdraw":
			_emit_hud_request("bank_withdraw_requested", [_first_bank_item(), _bank_quantity()], record)
		"open_shop":
			_interact_object(_station("shop"), "default", record)
		"shop_buy":
			var stock_item := _pick_shop_stock()
			_emit_hud_request("shop_buy_requested", [str(stock_item.get("item_id", "")), int(stock_item.get("price", 0))], record)
		"shop_sell":
			_emit_hud_request("shop_sell_requested", [_first_sellable_item(), _bank_quantity()], record)
		"use_item":
			_emit_hud_request("inventory_item_action_requested", [_first_usable_item(), "use"], record)
		"equip_item":
			_emit_hud_request("inventory_item_action_requested", [_first_equippable_item(), "equip"], record)
		"drop_item":
			_emit_hud_request("inventory_item_action_requested", [_first_droppable_item(), "drop"], record)
		"examine_object":
			_interact_object(_pick_examinable_object(), "examine", record)
		"adversarial_invalid_bank":
			_emit_hud_request("bank_deposit_requested", ["missing_item", -1], record)
		"adversarial_invalid_shop":
			_emit_hud_request("shop_buy_requested", ["missing_item", -1], record)
		"adversarial_invalid_inventory":
			_emit_hud_request("inventory_item_action_requested", ["missing_item", "invalid_action"], record)
		"adversarial_rapid_repeat":
			_emit_hud_request("shop_sell_requested", ["missing_item", -2], record)
			_emit_hud_request("shop_sell_requested", ["missing_item", -2], record)
		_:
			_record_issue("bug", "P2", action_name, "Unknown simulation action requested.", "", {"action_name": action_name})
	return record


func _base_action_record(action_name: String) -> Dictionary:
	return {
		"type": "action",
		"seed": current_seed,
		"run_index": current_run_index,
		"scenario": current_scenario,
		"step": current_step,
		"action": action_name,
		"target_id": "",
		"target_label": "",
		"path_length": 0,
		"skipped": false,
	}


func _interact_object(object_data: Dictionary, action: String, record: Dictionary) -> void:
	if object_data.is_empty():
		record["skipped"] = true
		return
	var target := object_data.duplicate(true)
	target["action"] = action
	record["target_id"] = str(target.get("id", ""))
	record["target_label"] = str(target.get("label", target.get("name", "")))
	if not _move_near_object(target, record):
		record["skipped"] = true
		return
	if current_gameplay != null and current_gameplay.has_method("activate_object"):
		current_gameplay.activate_object(target)
	_record_last_action(str(record["action"]))


func _emit_dialogue_action(npc_data: Dictionary, record: Dictionary) -> void:
	if npc_data.is_empty():
		record["skipped"] = true
		return
	record["target_id"] = str(npc_data.get("id", ""))
	record["target_label"] = str(npc_data.get("label", npc_data.get("name", "")))
	_emit_hud_request("dialogue_action_requested", [npc_data], record)


func _emit_hud_request(signal_name: String, args: Array, record: Dictionary) -> void:
	record["target_id"] = str(args[0]) if not args.is_empty() else ""
	record["target_label"] = record["target_id"]
	if current_hud == null or not current_hud.has_signal(signal_name):
		record["skipped"] = true
		_record_issue("bug", "P1", str(record["action"]), "HUD signal is unavailable for simulation action.", _feedback_text(), {"signal": signal_name})
		return
	match args.size():
		0:
			current_hud.emit_signal(signal_name)
		1:
			current_hud.emit_signal(signal_name, args[0])
		2:
			current_hud.emit_signal(signal_name, args[0], args[1])
		_:
			_record_issue("bug", "P2", str(record["action"]), "Simulation action passed too many HUD signal arguments.", _feedback_text(), {"signal": signal_name})
	_record_last_action(str(record["action"]))


func _move_near_object(object_data: Dictionary, record: Dictionary) -> bool:
	if current_world == null or not current_world.has_method("_interaction_target_tile") or not current_world.has_method("_find_path"):
		return true
	var start_tile := _player_tile()
	var path = []
	var target_tile := Vector2i(-1, -1)
	if current_world.has_method("_interaction_target_route"):
		var route_info = current_world.call("_interaction_target_route", object_data)
		if route_info is Dictionary:
			var route_tile = route_info.get("tile", Vector2i(-1, -1))
			if route_tile is Vector2i:
				target_tile = route_tile
			path = route_info.get("path", [])
	else:
		var tile_value = current_world.call("_interaction_target_tile", object_data)
		if tile_value is Vector2i:
			target_tile = tile_value
	if not (target_tile is Vector2i) or target_tile == Vector2i(-1, -1):
		_record_issue("softlock", "P1", str(record["action"]), "Object has no reachable interaction tile.", _feedback_text(), {
			"target_id": str(object_data.get("id", "")),
		})
		return false
	if not (path is Array):
		path = current_world.call("_find_path", start_tile, target_tile)
	var path_length := 0
	if path is Array:
		path_length = path.size()
	record["path_length"] = path_length
	if start_tile != target_tile and (not (path is Array) or path_length == 0):
		_record_issue("softlock", "P1", str(record["action"]), "Target could not be reached by current pathfinding.", _feedback_text(), {
			"target_id": str(object_data.get("id", "")),
			"from_tile": [start_tile.x, start_tile.y],
			"target_tile": [target_tile.x, target_tile.y],
		})
		return false
	if path_length > PERF_BUDGET_MAX_PATH_LENGTH and current_scenario != "random_guard":
		_record_issue("qol", "P2", str(record["action"]), "Common interaction required a long path.", _feedback_text(), {
			"target_id": str(object_data.get("id", "")),
			"path_length": path_length,
		})
	if current_world.has_method("_force_player_tile"):
		current_world.call("_force_player_tile", target_tile)
	return true


func _analyze_action_result(record: Dictionary) -> void:
	var feedback := str(record.get("feedback", ""))
	var action_name := str(record.get("action", ""))
	var skipped := bool(record.get("skipped", false))
	if feedback.strip_edges().is_empty() and not skipped:
		_record_issue("qol", "P2", action_name, "Action produced no visible feedback.", feedback, {})
	if _is_failure_feedback(feedback) and not skipped:
		var feedback_key := "%s|%s" % [action_name, feedback]
		current_feedback_counts[feedback_key] = int(current_feedback_counts.get(feedback_key, 0)) + 1
		if int(current_feedback_counts[feedback_key]) >= 3:
			_record_issue("qol", "P2", action_name, "Repeated failed or blocking feedback.", feedback, {
				"repeat_count": int(current_feedback_counts[feedback_key]),
			})
	if bool(record.get("changed_state", false)):
		current_no_progress_streak = 0
	else:
		current_no_progress_streak += 1
		current_max_no_progress_streak = max(current_max_no_progress_streak, current_no_progress_streak)
		if current_no_progress_streak >= 8:
			_record_issue("softlock", "P1", action_name, "Simulation made no state progress for several actions.", feedback, {
				"no_progress_streak": current_no_progress_streak,
			})
	var lower_feedback := feedback.to_lower()
	if _inventory_slot_count(_inventory()) >= INVENTORY_SLOT_LIMIT and not bool(record.get("changed_state", false)) and not skipped and lower_feedback.find("inventory") != -1 and lower_feedback.find("full") != -1:
		_record_issue("qol", "P2", action_name, "Full inventory blocked the current action.", feedback, {})


func _check_invariants(record: Dictionary) -> void:
	var invariant_issues: Array = InvariantChecker.check_state(current_state, items_data, {
		"inventory_slot_limit": INVENTORY_SLOT_LIMIT,
	})
	for issue in invariant_issues:
		if not (issue is Dictionary):
			continue
		var metadata: Dictionary = issue.get("metadata", {}).duplicate(true)
		metadata["invariant_code"] = str(issue.get("code", ""))
		metadata["invariant_category"] = str(issue.get("category", ""))
		_record_issue("bug", "P0", str(record.get("action", "")), str(issue.get("summary", "State invariant failed.")), str(record.get("feedback", "")), metadata)


func _record_issue(category: String, severity: String, action: String, summary: String, feedback: String, metadata: Dictionary) -> void:
	if scenario_probe_active:
		current_probe_issues.append({
			"code": "runtime_%s_%s" % [category, severity],
			"severity": severity,
			"category": category,
			"action": action,
			"summary": summary,
			"feedback": feedback,
			"metadata": metadata.duplicate(true),
		})
		return
	var group_key := "%s|%s|%s|%s" % [severity, category, action, summary]
	var group = issue_groups.get(group_key, {})
	if not (group is Dictionary) or group.is_empty():
		group = {
			"severity": severity,
			"category": category,
			"action": action,
			"summary": summary,
			"count": 0,
			"sample_count": 0,
			"scenarios": {},
			"first_issue": {},
		}
	group["count"] = int(group.get("count", 0)) + 1
	var scenarios = group.get("scenarios", {})
	if not (scenarios is Dictionary):
		scenarios = {}
	scenarios[current_scenario] = int(scenarios.get(current_scenario, 0)) + 1
	group["scenarios"] = scenarios
	issue_groups[group_key] = group

	issue_occurrence_count += 1
	current_issue_occurrences += 1
	current_issue_counts[group_key] = int(current_issue_counts.get(group_key, 0)) + 1

	var record := {
		"type": "issue",
		"issue_id": _issue_id(group_key),
		"seed": current_seed,
		"run_index": current_run_index,
		"scenario": current_scenario,
		"step": current_step,
		"severity": severity,
		"category": category,
		"action": action,
		"feedback": feedback,
		"summary": summary,
		"last_actions": current_last_actions.duplicate(true),
		"metadata": metadata.duplicate(true),
		"replay": _run_replay_metadata(current_seed, current_scenario),
		"state_summary": StateSnapshot.summarize_state(current_state),
		"state_digest": _state_digest().sha256_text(),
		"replay_command": _replay_command(current_seed, current_scenario),
	}
	_record_issue_telemetry(record)
	if int(group.get("sample_count", 0)) < 5:
		var snapshot_path := _write_issue_snapshot(str(record["issue_id"]), current_seed, current_scenario, current_step, record)
		if not snapshot_path.is_empty():
			record["snapshot_path"] = snapshot_path
	if group.get("first_issue", {}) == {}:
		group["first_issue"] = record.duplicate(true)
		issue_groups[group_key] = group
	if int(group.get("sample_count", 0)) < 5:
		group["sample_count"] = int(group.get("sample_count", 0)) + 1
		issue_groups[group_key] = group
		issue_sample_count += 1
		current_issue_samples += 1
		_write_json_line(issues_file, record)


func _record_action_trace(record: Dictionary) -> void:
	if str(config["trace"]) != "all" or trace_file == null:
		return
	_write_json_line(trace_file, record)


func _record_last_action(action_name: String) -> void:
	current_last_actions.append(action_name)
	while current_last_actions.size() > 8:
		current_last_actions.remove_at(0)


func _record_action_telemetry(record: Dictionary) -> void:
	if current_run_telemetry.is_empty():
		return
	var action_name := str(record.get("action", "unknown"))
	_add_telemetry_int(current_run_telemetry, "steps", 1)
	_increment_count(current_run_telemetry["action_counts"], action_name)
	if bool(record.get("changed_state", false)):
		_add_telemetry_int(current_run_telemetry, "changed_steps", 1)
	else:
		_add_telemetry_int(current_run_telemetry, "unchanged_steps", 1)
	if bool(record.get("skipped", false)):
		_add_telemetry_int(current_run_telemetry, "skipped_actions", 1)
	var feedback := str(record.get("feedback", ""))
	if feedback.strip_edges().is_empty():
		_add_telemetry_int(current_run_telemetry, "no_feedback_actions", 1)
	if _is_failure_feedback(feedback):
		_add_telemetry_int(current_run_telemetry, "failed_feedback_actions", 1)
		_increment_count(current_run_telemetry["failure_action_counts"], action_name)
	if int(record.get("inventory_slots", 0)) >= INVENTORY_SLOT_LIMIT:
		_add_telemetry_int(current_run_telemetry, "full_inventory_steps", 1)
	var damage_taken := int(record.get("damage_taken", 0))
	var healing_done := int(record.get("healing_done", 0))
	_add_telemetry_int(current_run_telemetry, "damage_taken", damage_taken)
	_add_telemetry_int(current_run_telemetry, "healing_done", healing_done)
	if int(record.get("hitpoints_before", 0)) > 0 and int(record.get("hitpoints", 0)) <= 0:
		_add_telemetry_int(current_run_telemetry, "deaths", 1)
	var coin_delta := int(record.get("coin_delta", 0))
	if coin_delta >= 0:
		_add_telemetry_int(current_run_telemetry, "coin_gained", coin_delta)
	else:
		_add_telemetry_int(current_run_telemetry, "coin_spent", -coin_delta)
	_add_telemetry_int(current_run_telemetry, "quest_starts", max(0, int(record.get("started_quest_delta", 0))))
	_add_telemetry_int(current_run_telemetry, "quest_completions", max(0, int(record.get("completed_quest_delta", 0))))
	var path_length := int(record.get("path_length", 0))
	if path_length > 0:
		_add_telemetry_int(current_run_telemetry, "path_moves", 1)
		_add_telemetry_int(current_run_telemetry, "path_length_total", path_length)
		current_run_telemetry["max_path_length"] = max(int(current_run_telemetry.get("max_path_length", 0)), path_length)
	var elapsed_usec := int(record.get("elapsed_usec", 0))
	_add_telemetry_int(current_run_telemetry, "action_cost_samples", 1)
	_add_telemetry_int(current_run_telemetry, "action_cost_total_usec", elapsed_usec)
	current_run_telemetry["slowest_action_usec"] = max(int(current_run_telemetry.get("slowest_action_usec", 0)), elapsed_usec)
	var tile_key := str(record.get("tile_key", ""))
	if elapsed_usec > 16667:
		_add_telemetry_int(current_run_telemetry, "slow_action_steps_16ms", 1)
		_record_slow_action_sample(record, elapsed_usec, path_length, tile_key)
	if not tile_key.is_empty():
		_increment_count(current_run_telemetry["tile_visits"], tile_key)


func _record_slow_action_sample(record: Dictionary, elapsed_usec: int, path_length: int, tile_key: String) -> void:
	var action_name := str(record.get("action", "unknown"))
	_increment_count(current_run_telemetry["slow_action_counts"], action_name)
	_increment_count(current_run_telemetry["slow_action_scenario_counts"], current_scenario)
	if not tile_key.is_empty():
		_increment_count(current_run_telemetry["slow_action_tile_counts"], tile_key)
	_increment_count(current_run_telemetry["slow_path_length_counts"], _path_length_bucket(path_length))
	var samples = current_run_telemetry.get("slow_action_samples", [])
	if samples is Array:
		samples.append({
			"elapsed_usec": elapsed_usec,
			"seed": current_seed,
			"run_index": current_run_index,
			"scenario": current_scenario,
			"step": current_step,
			"action": action_name,
			"target_id": str(record.get("target_id", "")),
			"target_label": str(record.get("target_label", "")),
			"tile_key": tile_key,
			"from_tile": record.get("from_tile", []),
			"tile": record.get("tile", []),
			"path_length": path_length,
			"feedback": str(record.get("feedback", "")),
		})
		current_run_telemetry["slow_action_samples"] = _top_slow_action_samples(samples, 50)


func _path_length_bucket(path_length: int) -> String:
	if path_length <= 0:
		return "0"
	if path_length <= 4:
		return "1-4"
	if path_length <= 8:
		return "5-8"
	if path_length <= 16:
		return "9-16"
	if path_length <= PERF_BUDGET_MAX_PATH_LENGTH:
		return "17-32"
	return "33+"


func _record_issue_telemetry(issue_record: Dictionary) -> void:
	if current_run_telemetry.is_empty():
		return
	_increment_count(current_run_telemetry["issue_tile_counts"], _tile_key(_player_tile()))
	_increment_count(current_run_telemetry["issue_action_counts"], str(issue_record.get("action", "unknown")))
	_increment_count(current_run_telemetry["issue_severity_counts"], str(issue_record.get("severity", "unknown")))


func _record_polish_telemetry(record: Dictionary) -> void:
	if current_run_polish_telemetry.is_empty():
		return
	var action_name := str(record.get("action", "unknown"))
	var feedback := str(record.get("feedback", "")).strip_edges()
	var previous_feedback := str(record.get("previous_feedback", "")).strip_edges()
	var gameplay_state_changed := bool(record.get("gameplay_state_changed", record.get("changed_state", false)))
	var benign_repeated_success := _is_benign_repeated_success_feedback(record, feedback, previous_feedback)
	_add_telemetry_int(current_run_polish_telemetry, "steps", 1)
	_increment_count(current_run_polish_telemetry["action_counts"], action_name)
	if bool(record.get("skipped", false)):
		return
	if feedback.is_empty():
		_add_polish_flag("empty_feedback", action_name, "Action produced no visible player feedback.", record)
	if benign_repeated_success:
		_record_benign_repeated_success_feedback(action_name)
	elif not feedback.is_empty() and feedback == previous_feedback:
		_add_polish_flag("unchanged_feedback", action_name, "Action repeated the previous feedback text.", record)
	if _is_failure_feedback(feedback):
		_add_telemetry_int(current_run_polish_telemetry, "failure_feedback_actions", 1)
		var feedback_key := "%s|%s" % [action_name, feedback]
		current_polish_feedback_counts[feedback_key] = int(current_polish_feedback_counts.get(feedback_key, 0)) + 1
		if int(current_polish_feedback_counts[feedback_key]) >= 3:
			_add_polish_flag("failure_feedback_loop", action_name, "Failure feedback repeated several times for the same action.", record, {
				"repeat_count": int(current_polish_feedback_counts[feedback_key]),
			})
		if not _feedback_explains_failure(feedback):
			_add_polish_flag("failure_without_clear_reason", action_name, "Failure feedback may not explain the required recovery action.", record)
	if gameplay_state_changed and (feedback.is_empty() or feedback == previous_feedback) and not benign_repeated_success:
		_add_polish_flag("state_change_weak_feedback", action_name, "State changed but feedback was empty or unchanged.", record)
	_record_panel_polish(record)
	_record_quest_polish(record)
	_record_discoverability_polish(record)


func _record_panel_polish(record: Dictionary) -> void:
	var action_name := str(record.get("action", ""))
	if action_name not in ["open_bank", "open_shop", "talk_npc", "dialogue_action"]:
		return
	_add_telemetry_int(current_run_polish_telemetry, "panel_checks", 1)
	var snapshot := _interaction_panel_snapshot()
	_increment_count(current_run_polish_telemetry["panel_type_counts"], action_name)
	if not bool(snapshot.get("visible", false)):
		_add_polish_flag("panel_not_visible", action_name, "Expected interaction panel was not visible after a panel action.", record, snapshot)
		return
	if bool(snapshot.get("lightweight_mode", false)):
		# Simulation-only HUD mode intentionally omits transaction rows to avoid
		# rebuilding large control trees on every bot action. Do not classify that
		# harness optimization as a player-facing empty-panel defect.
		return
	if str(snapshot.get("title", "")).strip_edges().is_empty():
		_add_polish_flag("panel_missing_title", action_name, "Visible interaction panel had no title.", record, snapshot)
	if int(snapshot.get("rows", 0)) <= 0 and not _panel_snapshot_has_dialogue_content(record, snapshot):
		_add_polish_flag("panel_empty_rows", action_name, "Visible interaction panel had no useful rows.", record, snapshot)
	if int(snapshot.get("buttons", 0)) <= 0:
		_add_polish_flag("panel_missing_action_buttons", action_name, "Visible interaction panel had no action buttons.", record, snapshot)


func _panel_snapshot_has_dialogue_content(record: Dictionary, snapshot: Dictionary) -> bool:
	var action_name := str(record.get("action", ""))
	if action_name not in ["talk_npc", "dialogue_action"]:
		return false
	if int(snapshot.get("buttons", 0)) <= 0:
		return false
	if str(snapshot.get("title", "")).strip_edges().is_empty():
		return false
	return not str(record.get("feedback", "")).strip_edges().is_empty()


func _record_quest_polish(record: Dictionary) -> void:
	var quest_states := _quest_states()
	var active_quest_id := _active_quest_id()
	if quest_states.is_empty() and active_quest_id.is_empty():
		return
	_add_telemetry_int(current_run_polish_telemetry, "quest_clarity_checks", 1)
	var ids := []
	if not active_quest_id.is_empty():
		ids.append(active_quest_id)
	for quest_id in quest_states.keys():
		var clean_id := str(quest_id)
		if clean_id not in ids:
			ids.append(clean_id)
	for raw_id in ids:
		var quest_id := str(raw_id)
		var definition := _quest_definition(quest_id)
		if definition.is_empty():
			_add_polish_flag("quest_missing_definition", str(record.get("action", "")), "Quest progress referenced a missing quest definition.", record, {"quest_id": quest_id})
			continue
		var state = quest_states.get(quest_id, {})
		if not (state is Dictionary):
			state = {}
		var objective := _quest_objective_for_polish(definition, state)
		if objective.strip_edges().is_empty():
			_add_polish_flag("quest_missing_objective_text", str(record.get("action", "")), "Quest state had no visible next-objective text.", record, {"quest_id": quest_id})
		elif _quest_ready_to_return(definition, state):
			_add_telemetry_int(current_run_polish_telemetry, "quest_return_prompt_checks", 1)
			if objective.strip_edges().is_empty():
				_add_polish_flag("quest_return_prompt_missing", str(record.get("action", "")), "Quest was ready to return but had no return prompt.", record, {"quest_id": quest_id})


func _record_discoverability_polish(record: Dictionary) -> void:
	var target_id := str(record.get("target_id", "")).strip_edges()
	var target_label := str(record.get("target_label", "")).strip_edges()
	if target_id.is_empty():
		return
	_add_telemetry_int(current_run_polish_telemetry, "discoverability_checks", 1)
	if target_label.is_empty():
		_add_polish_flag("target_missing_label", str(record.get("action", "")), "Action target had no readable label.", record)
	if target_label.is_empty() and str(record.get("feedback", "")).strip_edges().is_empty():
		_add_polish_flag("target_missing_label_and_feedback", str(record.get("action", "")), "Action target had neither a readable label nor visible feedback.", record)


func _is_benign_repeated_success_feedback(record: Dictionary, feedback: String, previous_feedback: String) -> bool:
	if feedback.is_empty() or feedback != previous_feedback:
		return false
	if _is_failure_feedback(feedback):
		return false
	var action_name := str(record.get("action", ""))
	if action_name in ["open_bank", "open_shop"] and feedback in ["Bank opened", "Shop opened"]:
		return true
	var lower_feedback := feedback.to_lower()
	if action_name in ["talk_npc", "dialogue_action"] and (
		lower_feedback.find("still needed") != -1 or
		lower_feedback.find("not done") != -1 or
		lower_feedback.find("not filled") != -1 or
		lower_feedback.find("still short") != -1 or
		lower_feedback.find("not ready") != -1
	):
		return true
	if not bool(record.get("gameplay_state_changed", record.get("changed_state", false))):
		return false
	return action_name in [
		"gather_resource",
		"gather_woodcutting",
		"gather_mining",
		"gather_fishing",
		"process_station",
		"process_furnace",
		"process_anvil",
		"process_carpentry",
		"process_apothecary",
		"cook",
		"bank_deposit",
		"bank_withdraw",
		"shop_buy",
		"shop_sell",
		"drop_item",
		"pickup_drop",
	]


func _record_benign_repeated_success_feedback(action_name: String) -> void:
	_add_telemetry_int(current_run_polish_telemetry, "benign_repeated_success_feedback_count", 1)
	_increment_count(current_run_polish_telemetry["benign_repeated_success_action_counts"], action_name)
	_increment_count(current_run_polish_telemetry["benign_repeated_success_scenario_counts"], current_scenario)


func _add_polish_flag(code: String, action: String, summary: String, record: Dictionary, metadata: Dictionary = {}) -> void:
	if current_run_polish_telemetry.is_empty():
		return
	_add_telemetry_int(current_run_polish_telemetry, "%s_count" % code, 1)
	_increment_count(current_run_polish_telemetry["flag_counts"], code)
	_increment_count(current_run_polish_telemetry["flag_action_counts"], action)
	_increment_count(current_run_polish_telemetry["flag_scenario_counts"], current_scenario)
	var samples = current_run_polish_telemetry.get("samples", [])
	if samples is Array and samples.size() < 25:
		samples.append({
			"code": code,
			"summary": summary,
			"seed": current_seed,
			"run_index": current_run_index,
			"scenario": current_scenario,
			"step": current_step,
			"action": action,
			"target_id": str(record.get("target_id", "")),
			"target_label": str(record.get("target_label", "")),
			"feedback": str(record.get("feedback", "")),
			"previous_feedback": str(record.get("previous_feedback", "")),
			"metadata": metadata.duplicate(true),
			"replay_command": _replay_command(current_seed, current_scenario),
		})
		current_run_polish_telemetry["samples"] = samples
	_add_telemetry_int(current_run_polish_telemetry, "sampled_flags", 1)


func _new_telemetry_bucket() -> Dictionary:
	return {
		"runs": 0,
		"steps": 0,
		"changed_steps": 0,
		"unchanged_steps": 0,
		"skipped_actions": 0,
		"failed_feedback_actions": 0,
		"no_feedback_actions": 0,
		"full_inventory_steps": 0,
		"damage_taken": 0,
		"healing_done": 0,
		"deaths": 0,
		"coin_gained": 0,
		"coin_spent": 0,
		"quest_starts": 0,
		"quest_completions": 0,
		"quest_policy_protected_item_skips": 0,
		"quest_policy_withdrawal_requests": 0,
		"quest_policy_withdrawal_successes": 0,
		"quest_policy_blocked_objectives": 0,
		"quest_policy_protected_item_counts": {},
		"quest_policy_objective_action_counts": {},
		"quest_policy_quest_counts": {},
		"path_moves": 0,
		"path_length_total": 0,
		"max_path_length": 0,
		"action_cost_samples": 0,
		"action_cost_total_usec": 0,
		"slowest_action_usec": 0,
		"slow_action_steps_16ms": 0,
		"action_counts": {},
		"slow_action_counts": {},
		"slow_action_scenario_counts": {},
		"slow_action_tile_counts": {},
		"slow_path_length_counts": {},
		"slow_action_samples": [],
		"failure_action_counts": {},
		"tile_visits": {},
		"issue_tile_counts": {},
		"issue_action_counts": {},
		"issue_severity_counts": {},
		"scenarios": {},
	}


func _new_polish_bucket() -> Dictionary:
	return {
		"runs": 0,
		"steps": 0,
		"failure_feedback_actions": 0,
		"benign_repeated_success_feedback_count": 0,
		"panel_checks": 0,
		"quest_clarity_checks": 0,
		"quest_return_prompt_checks": 0,
		"discoverability_checks": 0,
		"sampled_flags": 0,
		"action_counts": {},
		"flag_counts": {},
		"flag_action_counts": {},
		"flag_scenario_counts": {},
		"benign_repeated_success_action_counts": {},
		"benign_repeated_success_scenario_counts": {},
		"panel_type_counts": {},
		"samples": [],
		"scenarios": {},
	}


func _add_telemetry_int(bucket: Dictionary, key: String, amount: int) -> void:
	bucket[key] = int(bucket.get(key, 0)) + amount


func _increment_count(counts, key: String, amount: int = 1) -> void:
	if not (counts is Dictionary) or key.is_empty():
		return
	counts[key] = int(counts.get(key, 0)) + amount


func _merge_telemetry_bucket(target: Dictionary, source: Dictionary) -> void:
	var sum_keys := [
		"runs",
		"steps",
		"changed_steps",
		"unchanged_steps",
		"skipped_actions",
		"failed_feedback_actions",
		"no_feedback_actions",
		"full_inventory_steps",
		"damage_taken",
		"healing_done",
		"deaths",
		"coin_gained",
		"coin_spent",
		"quest_starts",
		"quest_completions",
		"quest_policy_protected_item_skips",
		"quest_policy_withdrawal_requests",
		"quest_policy_withdrawal_successes",
		"quest_policy_blocked_objectives",
		"path_moves",
		"path_length_total",
		"action_cost_samples",
		"action_cost_total_usec",
		"slow_action_steps_16ms",
	]
	for key in sum_keys:
		target[key] = int(target.get(key, 0)) + int(source.get(key, 0))
	target["max_path_length"] = max(int(target.get("max_path_length", 0)), int(source.get("max_path_length", 0)))
	target["slowest_action_usec"] = max(int(target.get("slowest_action_usec", 0)), int(source.get("slowest_action_usec", 0)))
	for count_key in ["action_counts", "slow_action_counts", "slow_action_scenario_counts", "slow_action_tile_counts", "slow_path_length_counts", "failure_action_counts", "tile_visits", "issue_tile_counts", "issue_action_counts", "issue_severity_counts", "quest_policy_protected_item_counts", "quest_policy_objective_action_counts", "quest_policy_quest_counts"]:
		var target_counts = target.get(count_key, {})
		if not (target_counts is Dictionary):
			target_counts = {}
		var source_counts = source.get(count_key, {})
		if source_counts is Dictionary:
			for key in source_counts.keys():
				target_counts[str(key)] = int(target_counts.get(str(key), 0)) + int(source_counts[key])
		target[count_key] = target_counts
	var target_samples = target.get("slow_action_samples", [])
	if not (target_samples is Array):
		target_samples = []
	var source_samples = source.get("slow_action_samples", [])
	if source_samples is Array:
		for sample in source_samples:
			if sample is Dictionary:
				target_samples.append(sample.duplicate(true))
	target["slow_action_samples"] = _top_slow_action_samples(target_samples, 100)


func _merge_polish_bucket(target: Dictionary, source: Dictionary) -> void:
	var sum_keys := [
		"runs",
		"steps",
		"failure_feedback_actions",
		"benign_repeated_success_feedback_count",
		"panel_checks",
		"quest_clarity_checks",
		"quest_return_prompt_checks",
		"discoverability_checks",
		"sampled_flags",
		"empty_feedback_count",
		"unchanged_feedback_count",
		"failure_feedback_loop_count",
		"failure_without_clear_reason_count",
		"state_change_weak_feedback_count",
		"panel_not_visible_count",
		"panel_missing_title_count",
		"panel_empty_rows_count",
		"panel_missing_action_buttons_count",
		"quest_missing_definition_count",
		"quest_missing_objective_text_count",
		"quest_return_prompt_missing_count",
		"target_missing_label_count",
		"target_missing_label_and_feedback_count",
	]
	for key in sum_keys:
		target[key] = int(target.get(key, 0)) + int(source.get(key, 0))
	for count_key in ["action_counts", "flag_counts", "flag_action_counts", "flag_scenario_counts", "benign_repeated_success_action_counts", "benign_repeated_success_scenario_counts", "panel_type_counts"]:
		var target_counts = target.get(count_key, {})
		if not (target_counts is Dictionary):
			target_counts = {}
		var source_counts = source.get(count_key, {})
		if source_counts is Dictionary:
			for key in source_counts.keys():
				target_counts[str(key)] = int(target_counts.get(str(key), 0)) + int(source_counts[key])
		target[count_key] = target_counts
	var target_samples = target.get("samples", [])
	if not (target_samples is Array):
		target_samples = []
	var source_samples = source.get("samples", [])
	if source_samples is Array:
		for sample in source_samples:
			if target_samples.size() >= 25:
				break
			if sample is Dictionary:
				target_samples.append(sample.duplicate(true))
	target["samples"] = target_samples


func _telemetry_report(top_limit: int) -> Dictionary:
	var report := _finalize_telemetry_bucket(telemetry_summary, top_limit)
	report["quest_policy"] = str(config.get("quest_policy", DEFAULT_QUEST_POLICY))
	return report


func _polish_report(top_limit: int) -> Dictionary:
	return _finalize_polish_bucket(polish_telemetry_summary, top_limit)


func _performance_report(top_limit: int) -> Dictionary:
	var telemetry := _telemetry_report(top_limit)
	var report := _performance_observations(telemetry)
	report["type"] = "performance_observations"
	report["budget_type"] = "advisory"
	report["runs"] = run_summaries.size()
	report["scenario_setting"] = str(config.get("scenario", DEFAULT_SCENARIO))
	report["scenario_mix"] = _scenario_mix()
	var scenario_reports := {}
	var scenarios = telemetry.get("scenarios", {})
	if scenarios is Dictionary:
		for scenario in _sorted_keys(scenarios):
			var scenario_telemetry = scenarios[scenario]
			if scenario_telemetry is Dictionary:
				scenario_reports[scenario] = _performance_observations(scenario_telemetry)
	report["scenarios"] = scenario_reports
	report["signals"] = [
		"Performance observations are advisory and do not fail the simulation run.",
		"Use repeated runs with the same seed/profile before treating a timing signal as real.",
		"Investigate persistent over-budget action costs or long-path rates before broad optimization work.",
	]
	return _normalize_value(report)


func _finalize_polish_bucket(bucket: Dictionary, top_limit: int) -> Dictionary:
	var report := bucket.duplicate(true)
	var steps := int(report.get("steps", 0))
	var sampled_flags := int(report.get("sampled_flags", 0))
	report["advisory_status"] = "review" if sampled_flags > 0 else "clean"
	report["flag_rate"] = float(sampled_flags) / float(steps) if steps > 0 else 0.0
	report["empty_feedback_rate"] = float(report.get("empty_feedback_count", 0)) / float(steps) if steps > 0 else 0.0
	report["unchanged_feedback_rate"] = float(report.get("unchanged_feedback_count", 0)) / float(steps) if steps > 0 else 0.0
	report["top_flags"] = _top_count_entries(report.get("flag_counts", {}), top_limit)
	report["top_flag_actions"] = _top_count_entries(report.get("flag_action_counts", {}), top_limit)
	report["top_flag_scenarios"] = _top_count_entries(report.get("flag_scenario_counts", {}), top_limit)
	report["top_benign_repeated_success_actions"] = _top_count_entries(report.get("benign_repeated_success_action_counts", {}), top_limit)
	report["top_benign_repeated_success_scenarios"] = _top_count_entries(report.get("benign_repeated_success_scenario_counts", {}), top_limit)
	report["panel_types_checked"] = _top_count_entries(report.get("panel_type_counts", {}), top_limit)
	var samples = report.get("samples", [])
	if samples is Array and samples.size() > top_limit:
		report["samples"] = samples.slice(0, top_limit)
	var scenarios = report.get("scenarios", {})
	if scenarios is Dictionary and not scenarios.is_empty():
		var scenario_reports := {}
		for scenario in _sorted_keys(scenarios):
			var scenario_bucket = scenarios[scenario]
			if scenario_bucket is Dictionary:
				scenario_reports[scenario] = _finalize_polish_bucket(scenario_bucket, min(top_limit, 10))
		report["scenarios"] = scenario_reports
	report["signals"] = [
		"Polish telemetry is advisory and cannot judge art quality, fun, audio mix, or animation feel by itself.",
		"Use sample replay commands before changing gameplay or UI based on a polish flag.",
		"Use manual_polish_review.md for human-only review prompts.",
	]
	return _normalize_value(report)


func _performance_observations(telemetry: Dictionary) -> Dictionary:
	var samples := int(telemetry.get("action_cost_samples", 0))
	var slow_steps := int(telemetry.get("slow_action_steps_16ms", 0))
	var slow_rate := float(slow_steps) / float(samples) if samples > 0 else 0.0
	var average_action := float(telemetry.get("average_action_cost_usec", 0.0))
	var slowest_action := float(telemetry.get("slowest_action_usec", 0))
	var average_path := float(telemetry.get("average_path_length", 0.0))
	var max_path := int(telemetry.get("max_path_length", 0))
	var observations := []
	_append_performance_observation(observations, "average_action_cost_usec", average_action, PERF_BUDGET_AVERAGE_ACTION_USEC, "Average simulated action cost.")
	_append_performance_observation(observations, "slow_action_rate", slow_rate, PERF_BUDGET_SLOW_ACTION_RATE, "Share of action samples over 16.667ms.")
	_append_performance_observation(observations, "slowest_action_usec", slowest_action, PERF_BUDGET_SLOWEST_ACTION_USEC, "Worst single simulated action cost.")
	_append_performance_observation(observations, "average_path_length", average_path, PERF_BUDGET_AVERAGE_PATH_LENGTH, "Average path length for movement actions.")
	_append_performance_observation(observations, "max_path_length", float(max_path), float(PERF_BUDGET_MAX_PATH_LENGTH), "Longest path observed.")
	return {
		"budget_type": "advisory",
		"status": _performance_status(observations),
		"action_cost_samples": samples,
		"slow_action_steps_16ms": slow_steps,
		"slow_action_rate": slow_rate,
		"average_action_cost_usec": average_action,
		"slowest_action_usec": slowest_action,
		"path_moves": int(telemetry.get("path_moves", 0)),
		"average_path_length": average_path,
		"max_path_length": max_path,
		"top_slow_actions": telemetry.get("top_slow_actions", []),
		"top_slow_scenarios": telemetry.get("top_slow_scenarios", []),
		"top_slow_tiles": telemetry.get("top_slow_tiles", []),
		"top_slow_path_lengths": telemetry.get("top_slow_path_lengths", []),
		"top_slow_action_samples": telemetry.get("top_slow_action_samples", []),
		"observations": observations,
	}


func _append_performance_observation(observations: Array, key: String, value: float, budget: float, description: String) -> void:
	var over_budget := value > budget
	observations.append({
		"key": key,
		"value": value,
		"budget": budget,
		"status": "over_budget" if over_budget else "ok",
		"description": description,
	})


func _performance_status(observations: Array) -> String:
	for observation in observations:
		if observation is Dictionary and str(observation.get("status", "")) == "over_budget":
			return "observe"
	return "ok"


func _finalize_telemetry_bucket(bucket: Dictionary, top_limit: int) -> Dictionary:
	var report := bucket.duplicate(true)
	var path_moves := int(report.get("path_moves", 0))
	var action_samples := int(report.get("action_cost_samples", 0))
	report["average_path_length"] = float(report.get("path_length_total", 0)) / float(path_moves) if path_moves > 0 else 0.0
	report["average_action_cost_usec"] = float(report.get("action_cost_total_usec", 0)) / float(action_samples) if action_samples > 0 else 0.0
	report["top_tiles"] = _top_count_entries(report.get("tile_visits", {}), top_limit)
	report["top_slow_actions"] = _top_count_entries(report.get("slow_action_counts", {}), top_limit)
	report["top_slow_scenarios"] = _top_count_entries(report.get("slow_action_scenario_counts", {}), top_limit)
	report["top_slow_tiles"] = _top_count_entries(report.get("slow_action_tile_counts", {}), top_limit)
	report["top_slow_path_lengths"] = _top_count_entries(report.get("slow_path_length_counts", {}), top_limit)
	report["top_slow_action_samples"] = _top_slow_action_samples(report.get("slow_action_samples", []), top_limit)
	report["issue_hotspots"] = _top_count_entries(report.get("issue_tile_counts", {}), top_limit)
	var scenarios = report.get("scenarios", {})
	if scenarios is Dictionary and not scenarios.is_empty():
		var scenario_reports := {}
		for scenario in _sorted_keys(scenarios):
			var scenario_bucket = scenarios[scenario]
			if scenario_bucket is Dictionary:
				var scenario_report: Dictionary = scenario_bucket.duplicate(true)
				var scenario_path_moves := int(scenario_report.get("path_moves", 0))
				var scenario_action_samples := int(scenario_report.get("action_cost_samples", 0))
				scenario_report["average_path_length"] = float(scenario_report.get("path_length_total", 0)) / float(scenario_path_moves) if scenario_path_moves > 0 else 0.0
				scenario_report["average_action_cost_usec"] = float(scenario_report.get("action_cost_total_usec", 0)) / float(scenario_action_samples) if scenario_action_samples > 0 else 0.0
				scenario_report["top_tiles"] = _top_count_entries(scenario_report.get("tile_visits", {}), min(top_limit, 10))
				scenario_report["top_slow_actions"] = _top_count_entries(scenario_report.get("slow_action_counts", {}), min(top_limit, 10))
				scenario_report["top_slow_tiles"] = _top_count_entries(scenario_report.get("slow_action_tile_counts", {}), min(top_limit, 10))
				scenario_report["top_slow_path_lengths"] = _top_count_entries(scenario_report.get("slow_path_length_counts", {}), min(top_limit, 10))
				scenario_report["top_slow_action_samples"] = _top_slow_action_samples(scenario_report.get("slow_action_samples", []), min(top_limit, 10))
				scenario_report["issue_hotspots"] = _top_count_entries(scenario_report.get("issue_tile_counts", {}), min(top_limit, 10))
				scenario_reports[scenario] = scenario_report
		report["scenarios"] = scenario_reports
	return _normalize_value(report)


func _top_slow_action_samples(raw_samples, limit: int) -> Array:
	if not (raw_samples is Array):
		return []
	var samples := []
	for sample in raw_samples:
		if sample is Dictionary:
			samples.append(sample.duplicate(true))
	samples.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("elapsed_usec", 0)) > int(right.get("elapsed_usec", 0))
	)
	if samples.size() > limit:
		return samples.slice(0, limit)
	return samples


func _top_count_entries(raw_counts, limit: int) -> Array:
	if not (raw_counts is Dictionary):
		return []
	var entries := []
	for key in raw_counts.keys():
		entries.append({
			"key": str(key),
			"count": int(raw_counts[key]),
		})
	entries.sort_custom(func(left, right) -> bool:
		if int(left.get("count", 0)) != int(right.get("count", 0)):
			return int(left.get("count", 0)) > int(right.get("count", 0))
		return str(left.get("key", "")) < str(right.get("key", ""))
	)
	return entries.slice(0, min(limit, entries.size()))


func _top_count_key(raw_counts) -> String:
	var entries := _top_count_entries(raw_counts, 1)
	if entries.is_empty():
		return ""
	var first = entries[0]
	if first is Dictionary:
		return str(first.get("key", ""))
	return ""


func _advance_clock_between_actions(record: Dictionary) -> void:
	if current_gameplay == null or not current_gameplay.has_method("_advance_action_clock"):
		return
	var seconds := 0.25 + current_rng.randf() * 2.25
	if str(record.get("action", "")).begins_with("process_") or str(record.get("action", "")) in ["gather_resource", "cook", "attack_mob"]:
		seconds += 0.75
	current_gameplay.call("_advance_action_clock", seconds)


func _update_scenario_metrics(run_summary: Dictionary) -> void:
	var scenario := str(run_summary.get("scenario", "unknown"))
	var metrics = scenario_metrics.get(scenario, {})
	if not (metrics is Dictionary):
		metrics = {}
	var run_metrics = run_summary.get("metrics", {})
	if not (run_metrics is Dictionary):
		run_metrics = {}
	metrics["runs"] = int(metrics.get("runs", 0)) + 1
	metrics["issue_count"] = int(metrics.get("issue_count", 0)) + int(run_summary.get("issue_count", 0))
	metrics["completed_quests"] = int(metrics.get("completed_quests", 0)) + int(run_metrics.get("completed_quests", 0))
	metrics["started_quests"] = int(metrics.get("started_quests", 0)) + int(run_metrics.get("started_quests", 0))
	metrics["total_xp"] = int(metrics.get("total_xp", 0)) + int(run_metrics.get("total_xp", 0))
	metrics["coins_end_total"] = int(metrics.get("coins_end_total", 0)) + int(run_metrics.get("coins", 0))
	metrics["no_progress_runs"] = int(metrics.get("no_progress_runs", 0)) + (1 if int(run_metrics.get("max_no_progress_streak", 0)) >= 8 else 0)
	scenario_metrics[scenario] = metrics


func _update_telemetry_summary(run_summary: Dictionary) -> void:
	var run_telemetry = run_summary.get("telemetry", {})
	if not (run_telemetry is Dictionary):
		return
	_merge_telemetry_bucket(telemetry_summary, run_telemetry)
	var scenario := str(run_summary.get("scenario", "unknown"))
	var scenarios = telemetry_summary.get("scenarios", {})
	if not (scenarios is Dictionary):
		scenarios = {}
	var scenario_bucket = scenarios.get(scenario, _new_telemetry_bucket())
	if not (scenario_bucket is Dictionary):
		scenario_bucket = _new_telemetry_bucket()
	_merge_telemetry_bucket(scenario_bucket, run_telemetry)
	scenarios[scenario] = scenario_bucket
	telemetry_summary["scenarios"] = scenarios


func _update_polish_telemetry_summary(run_summary: Dictionary) -> void:
	var run_polish = run_summary.get("polish_telemetry", {})
	if not (run_polish is Dictionary):
		return
	_merge_polish_bucket(polish_telemetry_summary, run_polish)
	var scenario := str(run_summary.get("scenario", "unknown"))
	var scenarios = polish_telemetry_summary.get("scenarios", {})
	if not (scenarios is Dictionary):
		scenarios = {}
	var scenario_bucket = scenarios.get(scenario, _new_polish_bucket())
	if not (scenario_bucket is Dictionary):
		scenario_bucket = _new_polish_bucket()
	_merge_polish_bucket(scenario_bucket, run_polish)
	scenarios[scenario] = scenario_bucket
	polish_telemetry_summary["scenarios"] = scenarios


func _simulation_scorecard() -> Dictionary:
	var telemetry := _telemetry_report(10)
	var polish := _polish_report(10)
	var balance := _balance_profile_report(10)
	var performance := _performance_report(10)
	var coverage := _coverage_report()
	var severity_counts := _issue_counts_by_severity()
	var category_counts := _issue_counts_by_category()
	var probe_summary = scenario_probe_report.get("summary", {}) if scenario_probe_report is Dictionary else {}
	if not (probe_summary is Dictionary):
		probe_summary = {}
	var issue_penalty := _score_issue_penalty(severity_counts)
	var probe_issues := int(probe_summary.get("issues", 0))
	var performance_penalty := 5.0 if str(performance.get("status", "ok")) != "ok" else 0.0
	var clean_run_rate := float(balance.get("clean_run_rate", 0.0))
	var state_changed_rate := float(balance.get("state_changed_rate", 0.0))
	var average_xp := float(balance.get("average_total_xp", 0.0))
	var average_net_worth := float(balance.get("average_net_worth", 0.0))
	var average_mobs_defeated := float(balance.get("average_mobs_defeated", 0.0))
	var quest_completion_rate := float(balance.get("quest_completion_rate", 0.0))
	var combat_survival_rate := float(balance.get("combat_survival_rate", 0.0))
	var telemetry_steps: int = max(1, int(telemetry.get("steps", 0)))
	var full_inventory_step_rate := float(telemetry.get("full_inventory_steps", 0)) / float(telemetry_steps)
	var failed_feedback_action_rate := float(telemetry.get("failed_feedback_actions", 0)) / float(telemetry_steps)
	var no_feedback_action_rate := float(telemetry.get("no_feedback_actions", 0)) / float(telemetry_steps)
	var polish_flag_rate := float(polish.get("flag_rate", 0.0))
	var scenario_no_progress_rate := _scenario_no_progress_rate()
	var scorecard := {
		"type": "advisory_scorecard",
		"scoring_range": "0-100",
		"score_meaning": "Higher means this automated run produced stronger evidence for that category. Scores are advisory simulation signals, not proof of fun, balance, visual quality, or release readiness.",
		"overall_score": 0,
		"weakest_category": {},
		"categories": {},
		"relevant_metrics": {
			"runs": run_summaries.size(),
			"steps_per_run": int(config.get("steps", 0)),
			"issue_occurrences": issue_occurrence_count,
			"issue_groups": issue_groups.size(),
			"counts_by_severity": severity_counts,
			"counts_by_category": category_counts,
			"scenario_probe_mode": str(scenario_probe_report.get("mode", "off")) if scenario_probe_report is Dictionary else "off",
			"scenario_probe_issues": probe_issues,
			"clean_run_rate": clean_run_rate,
			"state_changed_rate": state_changed_rate,
			"quest_completion_rate": quest_completion_rate,
			"average_total_xp": average_xp,
			"average_net_worth": average_net_worth,
			"average_mobs_defeated": average_mobs_defeated,
			"combat_survival_rate": combat_survival_rate,
			"full_inventory_step_rate": full_inventory_step_rate,
			"failed_feedback_action_rate": failed_feedback_action_rate,
			"no_feedback_action_rate": no_feedback_action_rate,
			"polish_flag_rate": polish_flag_rate,
			"slow_action_rate": float(performance.get("slow_action_rate", 0.0)),
			"average_action_cost_usec": float(performance.get("average_action_cost_usec", 0.0)),
			"average_path_length": float(performance.get("average_path_length", 0.0)),
			"coverage": coverage,
		},
	}
	var categories := {}
	categories["runtime_gameplay_bugs"] = _scorecard_category(
		"Runtime/gameplay bugs",
		_bounded_score(100.0 - issue_penalty - float(probe_issues * 3) - performance_penalty),
		"high",
		{
			"issue_occurrences": issue_occurrence_count,
			"issue_groups": issue_groups.size(),
			"severity_counts": severity_counts,
			"scenario_probe_issues": probe_issues,
			"performance_status": str(performance.get("status", "ok")),
		},
		"Penalizes grouped findings, probe diagnostics, and advisory performance over-budget observations."
	)
	categories["core_grind_loop"] = _scorecard_category(
		"Core grind loop",
		_bounded_score((state_changed_rate * 35.0) + (_target_score(average_xp, 60.0) * 0.20) + (_target_score(float(telemetry.get("coin_gained", 0)), 75.0) * 0.15) + (clean_run_rate * 20.0) + ((1.0 - scenario_no_progress_rate) * 10.0) - (issue_penalty * 0.25)),
		"medium-high",
		{
			"state_changed_rate": state_changed_rate,
			"average_total_xp": average_xp,
			"coin_gained": int(telemetry.get("coin_gained", 0)),
			"clean_run_rate": clean_run_rate,
			"scenario_no_progress_rate": scenario_no_progress_rate,
		},
		"Rewards state changes, XP, coin flow, clean runs, and low no-progress rates."
	)
	categories["skill_progression"] = _scorecard_category(
		"Skill progression",
		_bounded_score((_target_score(average_xp, 100.0) * 0.55) + (_target_score(float(_top_count_total(balance.get("top_xp_skills", []))), 3.0) * 0.25) + (clean_run_rate * 20.0) - float(_probe_issue_count_matching(["scenario_no_xp_gain"]) * 10) - float(_coverage_missing_count("skills") * 4)),
		"medium-low" if _coverage_missing_count("skills") > 0 else "medium",
		{
			"average_total_xp": average_xp,
			"top_xp_skills": balance.get("top_xp_skills", []),
			"scenario_no_xp_gain_probe_issues": _probe_issue_count_matching(["scenario_no_xp_gain"]),
			"untested_skill_count": _coverage_missing_count("skills"),
		},
		"Rewards XP gain and multi-skill coverage; penalizes explicit no-XP probe diagnostics."
	)
	categories["quest_flow"] = _scorecard_category(
		"Quest flow",
		_bounded_score(35.0 + (quest_completion_rate * 45.0) + (_target_score(float(balance.get("started_quests", 0)), 3.0) * 0.10) + (_target_score(float(balance.get("completed_quests", 0)), 2.0) * 0.10) - float(_issue_count_matching(category_counts, ["quest", "softlock"]) * 8) - float(_probe_issue_count_matching(["quest"]) * 8) - float(_coverage_missing_count("quests") * 3)),
		"medium-low" if _coverage_missing_count("quests") > 0 else "medium",
		{
			"started_quests": int(balance.get("started_quests", 0)),
			"completed_quests": int(balance.get("completed_quests", 0)),
			"quest_completion_rate": quest_completion_rate,
			"quest_or_softlock_issue_count": _issue_count_matching(category_counts, ["quest", "softlock"]),
			"quest_probe_issue_count": _probe_issue_count_matching(["quest"]),
			"untested_quest_count": _coverage_missing_count("quests"),
		},
		"Rewards started and completed quests; penalizes quest, softlock, and quest-probe findings."
	)
	categories["economy_bank_shop"] = _scorecard_category(
		"Economy/bank/shop",
		_bounded_score(30.0 + (_target_score(float(telemetry.get("coin_gained", 0)) + float(telemetry.get("coin_spent", 0)), 100.0) * 0.30) + (_target_score(average_net_worth, 150.0) * 0.25) + (state_changed_rate * 15.0) - float(_issue_count_matching(category_counts, ["economy", "shop", "bank"]) * 8) - float(_probe_issue_count_matching(["economy"]) * 8)),
		"medium-high",
		{
			"coin_gained": int(telemetry.get("coin_gained", 0)),
			"coin_spent": int(telemetry.get("coin_spent", 0)),
			"average_net_worth": average_net_worth,
			"economy_issue_count": _issue_count_matching(category_counts, ["economy", "shop", "bank"]),
			"economy_probe_issue_count": _probe_issue_count_matching(["economy"]),
		},
		"Rewards coin flow and net worth; penalizes economy, shop, bank, and economy-probe findings."
	)
	categories["combat_loot_recovery"] = _scorecard_category(
		"Combat/loot/recovery",
		_bounded_score(30.0 + (combat_survival_rate * 25.0) + (_target_score(average_mobs_defeated, 3.0) * 0.25) + (_target_score(float(balance.get("ground_drop_count", 0)), 3.0) * 0.10) + (_target_score(float(telemetry.get("healing_done", 0)), 20.0) * 0.10) - float(int(balance.get("deaths", 0)) * 8) - float(_issue_count_matching(category_counts, ["combat", "loot", "death"]) * 8) - float(_probe_issue_count_matching(["combat"]) * 8)),
		"medium",
		{
			"combat_survival_rate": combat_survival_rate,
			"deaths": int(balance.get("deaths", 0)),
			"average_mobs_defeated": average_mobs_defeated,
			"ground_drop_count": int(balance.get("ground_drop_count", 0)),
			"healing_done": int(telemetry.get("healing_done", 0)),
			"combat_probe_issue_count": _probe_issue_count_matching(["combat"]),
		},
		"Rewards survival, mob defeats, drops, and recovery signals; penalizes deaths and combat findings."
	)
	categories["inventory_pressure"] = _scorecard_category(
		"Inventory pressure",
		_bounded_score(100.0 - (full_inventory_step_rate * 250.0) - float(_issue_count_matching(category_counts, ["inventory"]) * 8) - float(_probe_issue_count_matching(["inventory"]) * 8) - (issue_penalty * 0.10)),
		"medium-high",
		{
			"full_inventory_steps": int(telemetry.get("full_inventory_steps", 0)),
			"full_inventory_step_rate": full_inventory_step_rate,
			"inventory_issue_count": _issue_count_matching(category_counts, ["inventory"]),
			"inventory_probe_issue_count": _probe_issue_count_matching(["inventory"]),
		},
		"Starts high and penalizes full-inventory friction plus inventory-specific findings."
	)
	categories["ui_action_feedback"] = _scorecard_category(
		"UI/action feedback",
		_bounded_score(100.0 - (polish_flag_rate * 250.0) - (failed_feedback_action_rate * 250.0) - (no_feedback_action_rate * 120.0) - float(_issue_count_matching(category_counts, ["feedback", "ui", "polish"]) * 8)),
		"medium",
		{
			"polish_flag_rate": polish_flag_rate,
			"sampled_polish_flags": int(polish.get("sampled_flags", 0)),
			"failed_feedback_action_rate": failed_feedback_action_rate,
			"no_feedback_action_rate": no_feedback_action_rate,
			"top_flags": polish.get("top_flags", []),
		},
		"Penalizes polish flags, failed feedback actions, no-feedback actions, and feedback/UI findings."
	)
	categories["visual_audio_confidence"] = _scorecard_category(
		"Visual/audio confidence",
		25,
		"low",
		{
			"headless_run": true,
			"screenshot_review_present": false,
			"manual_review_required": true,
		},
		"Headless simulation cannot prove visuals, animation, audio, contrast, clipping, or fun. Add screenshot review to raise this score."
	)
	var playable_components := [
		float(categories["runtime_gameplay_bugs"].get("score", 0)),
		float(categories["core_grind_loop"].get("score", 0)),
		float(categories["skill_progression"].get("score", 0)),
		float(categories["quest_flow"].get("score", 0)),
		float(categories["economy_bank_shop"].get("score", 0)),
		float(categories["combat_loot_recovery"].get("score", 0)),
		float(categories["inventory_pressure"].get("score", 0)),
		float(categories["ui_action_feedback"].get("score", 0)),
		float(categories["visual_audio_confidence"].get("score", 0)),
	]
	var automated_component_average := _average_float(playable_components)
	var visual_audio_evidence_cap := _bounded_score(float(categories["visual_audio_confidence"].get("score", 0)) + 30.0)
	var full_playable_game_confidence := _bounded_score(min(automated_component_average, float(visual_audio_evidence_cap)))
	categories["full_playable_game_confidence"] = _scorecard_category(
		"Full playable game confidence",
		full_playable_game_confidence,
		"medium-low",
		{
			"component_scores": _scorecard_component_scores(categories),
			"automated_component_average": automated_component_average,
			"visual_audio_evidence_cap": visual_audio_evidence_cap,
			"manual_playtest_present": false,
			"export_platform_audited": false,
			"full_focused_smoke_matrix_required": true,
		},
		"Evidence-capped automated signal. This headless runner does not ingest completed visual/audio review, manual playtest evidence, export/platform validation, or the full focused-smoke matrix."
	)
	scorecard["categories"] = categories
	scorecard["overall_score"] = full_playable_game_confidence
	scorecard["weakest_category"] = _weakest_scorecard_category(categories)
	return _normalize_value(scorecard)


func _scorecard_category(label: String, score: int, confidence: String, metrics: Dictionary, basis: String) -> Dictionary:
	return {
		"label": label,
		"score": _bounded_score(float(score)),
		"confidence": confidence,
		"metrics": _normalize_value(metrics),
		"basis": basis,
	}


func _scorecard_category_order() -> Array:
	return [
		"runtime_gameplay_bugs",
		"core_grind_loop",
		"skill_progression",
		"quest_flow",
		"economy_bank_shop",
		"combat_loot_recovery",
		"inventory_pressure",
		"ui_action_feedback",
		"visual_audio_confidence",
		"full_playable_game_confidence",
	]


func _bounded_score(value: float) -> int:
	return int(clamp(round(value), 0.0, 100.0))


func _target_score(value: float, target: float) -> float:
	if target <= 0.0:
		return 0.0
	return clamp(value / target, 0.0, 1.0) * 100.0


func _average_float(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


func _issue_counts_by_category() -> Dictionary:
	var counts := {}
	for group in issue_groups.values():
		if not (group is Dictionary):
			continue
		var category := str(group.get("category", "unknown"))
		counts[category] = int(counts.get(category, 0)) + int(group.get("count", 0))
	return _normalize_value(counts)


func _issue_counts_by_severity() -> Dictionary:
	var counts := {}
	for group in issue_groups.values():
		if not (group is Dictionary):
			continue
		var severity := str(group.get("severity", "unknown"))
		counts[severity] = int(counts.get(severity, 0)) + int(group.get("count", 0))
	return _normalize_value(counts)


func _score_issue_penalty(severity_counts: Dictionary) -> float:
	var runs: float = max(1.0, float(run_summaries.size()))
	var raw := (float(severity_counts.get("P0", 0)) * 35.0) + (float(severity_counts.get("P1", 0)) * 20.0) + (float(severity_counts.get("P2", 0)) * 8.0) + (float(severity_counts.get("P3", 0)) * 3.0) + (float(severity_counts.get("unknown", 0)) * 5.0)
	return min(80.0, raw / sqrt(runs))


func _issue_count_matching(category_counts: Dictionary, keywords: Array) -> int:
	var total := 0
	for category in category_counts.keys():
		var text := str(category).to_lower()
		for keyword in keywords:
			if text.find(str(keyword).to_lower()) >= 0:
				total += int(category_counts[category])
				break
	return total


func _probe_issue_count_matching(keywords: Array) -> int:
	if not (scenario_probe_report is Dictionary):
		return 0
	var issues = scenario_probe_report.get("issues", [])
	if not (issues is Array):
		return 0
	var total := 0
	for issue in issues:
		if not (issue is Dictionary):
			continue
		var text := "%s %s" % [str(issue.get("code", "")).to_lower(), str(issue.get("summary", "")).to_lower()]
		for keyword in keywords:
			if text.find(str(keyword).to_lower()) >= 0:
				total += 1
				break
	return total


func _scenario_no_progress_rate() -> float:
	var runs := 0
	var no_progress_runs := 0
	for scenario in scenario_metrics.keys():
		var metrics = scenario_metrics[scenario]
		if not (metrics is Dictionary):
			continue
		runs += int(metrics.get("runs", 0))
		no_progress_runs += int(metrics.get("no_progress_runs", 0))
	return float(no_progress_runs) / float(runs) if runs > 0 else 0.0


func _top_count_total(entries) -> int:
	if not (entries is Array):
		return 0
	var total := 0
	for entry in entries:
		if entry is Dictionary:
			total += int(entry.get("count", 0))
	return total


func _scorecard_component_scores(categories: Dictionary) -> Dictionary:
	var scores := {}
	for key in _scorecard_category_order():
		if key == "full_playable_game_confidence":
			continue
		var category = categories.get(key, {})
		if category is Dictionary:
			scores[key] = int(category.get("score", 0))
	return scores


func _weakest_scorecard_category(categories: Dictionary) -> Dictionary:
	var weakest_key := ""
	var weakest_score := 101
	var weakest_label := ""
	for key in _scorecard_category_order():
		var category = categories.get(key, {})
		if not (category is Dictionary):
			continue
		var score := int(category.get("score", 0))
		if score < weakest_score:
			weakest_key = key
			weakest_score = score
			weakest_label = str(category.get("label", key))
	return {
		"key": weakest_key,
		"label": weakest_label,
		"score": max(0, weakest_score),
	}


func _append_scorecard_lines(lines: Array, scorecard: Dictionary, include_metrics: bool = false) -> void:
	lines.append("## Advisory Category Scores")
	lines.append("")
	lines.append("Scores are `0-100` advisory automation signals from this run, not proof of fun, visual quality, or release readiness.")
	lines.append("")
	var categories = scorecard.get("categories", {})
	if categories is Dictionary:
		for key in _scorecard_category_order():
			var category = categories.get(key, {})
			if not (category is Dictionary):
				continue
			lines.append("- `%s`: `%d`/100, confidence `%s`." % [
				str(category.get("label", key)),
				int(category.get("score", 0)),
				str(category.get("confidence", "")),
			])
	var weakest = scorecard.get("weakest_category", {})
	if weakest is Dictionary and not str(weakest.get("key", "")).is_empty():
		lines.append("- Weakest category: `%s` at `%d`/100." % [
			str(weakest.get("label", "")),
			int(weakest.get("score", 0)),
		])
	if include_metrics:
		var metrics = scorecard.get("relevant_metrics", {})
		if metrics is Dictionary:
			lines.append("- Key metrics: issues `%d`, probe issues `%d`, clean run rate `%.2f`, state changed rate `%.2f`, quest completion rate `%.2f`, average XP `%.1f`, average net worth `%.1f`, polish flag rate `%.3f`." % [
				int(metrics.get("issue_occurrences", 0)),
				int(metrics.get("scenario_probe_issues", 0)),
				float(metrics.get("clean_run_rate", 0.0)),
				float(metrics.get("state_changed_rate", 0.0)),
				float(metrics.get("quest_completion_rate", 0.0)),
				float(metrics.get("average_total_xp", 0.0)),
				float(metrics.get("average_net_worth", 0.0)),
				float(metrics.get("polish_flag_rate", 0.0)),
			])
	lines.append("")


func _write_summary_file() -> void:
	var counts_by_category := {}
	var counts_by_severity := {}
	for group in issue_groups.values():
		if not (group is Dictionary):
			continue
		var category := str(group.get("category", "unknown"))
		var severity := str(group.get("severity", "unknown"))
		counts_by_category[category] = int(counts_by_category.get(category, 0)) + int(group.get("count", 0))
		counts_by_severity[severity] = int(counts_by_severity.get(severity, 0)) + int(group.get("count", 0))
	var output_files := {
		"runs": "%s/runs.jsonl" % str(config["output_dir"]),
		"issues": "%s/issues.jsonl" % str(config["output_dir"]),
		"summary": "%s/summary.json" % str(config["output_dir"]),
		"improvement_plan": "%s/improvement_plan.md" % str(config["output_dir"]),
		"codex_prompt": "%s/codex_prompt.md" % str(config["output_dir"]),
		"replay_manifest": "%s/replay_manifest.json" % str(config["output_dir"]),
		"telemetry_summary": "%s/telemetry_summary.json" % str(config["output_dir"]),
		"balance_profiles": "%s/balance_profiles.json" % str(config["output_dir"]),
		"performance_observations": "%s/performance_observations.json" % str(config["output_dir"]),
		"polish_telemetry": "%s/polish_telemetry.json" % str(config["output_dir"]),
		"manual_polish_review": "%s/manual_polish_review.md" % str(config["output_dir"]),
		"coverage_manifest": "%s/coverage_manifest.json" % str(config["output_dir"]),
		"snapshots": "%s/snapshots" % str(config["output_dir"]),
	}
	if str(config["trace"]) == "all":
		output_files["trace"] = "%s/trace.jsonl" % str(config["output_dir"])
	var scorecard := _simulation_scorecard()
	var summary := {
		"type": "summary",
		"replay_metadata": replay_metadata,
		"config": {
			"runs": int(config["runs"]),
			"steps": int(config["steps"]),
			"seed": int(config["seed"]),
			"scenario": str(config["scenario"]),
			"scenario_mix": _scenario_mix(),
			"trace": str(config["trace"]),
			"balance_profile": str(config["balance_profile"]),
			"scenario_probes": str(config["scenario_probes"]),
			"campaign": str(config.get("campaign", DEFAULT_CAMPAIGN)),
			"quest_policy": str(config.get("quest_policy", DEFAULT_QUEST_POLICY)),
			"output_dir": str(config["output_dir"]),
			"timeout_seconds": float(config["timeout_seconds"]),
			"fail_on_issues": bool(config["fail_on_issues"]),
			"allow_latest_downgrade": bool(config["allow_latest_downgrade"]),
			"require_publish_latest": bool(config["require_publish_latest"]),
		},
		"trust": trust_context.duplicate(true),
		"issue_occurrences": issue_occurrence_count,
		"issue_samples": issue_sample_count,
		"issue_groups": issue_groups.size(),
		"issue_group_details": _normalize_value(issue_groups),
		"counts_by_category": _normalize_value(counts_by_category),
		"counts_by_severity": _normalize_value(counts_by_severity),
		"scenario_metrics": _normalize_value(scenario_metrics),
		"telemetry": _telemetry_report(10),
		"polish": _polish_report(10),
		"balance": _balance_profile_report(10),
		"performance": _performance_report(10),
		"scenario_probes": _normalize_value(scenario_probe_report),
		"coverage": _normalize_value(_coverage_report()),
		"opportunities": _normalize_value(_opportunity_report()),
		"scorecard": scorecard,
		"output_files": output_files,
		"replay_guidance": {
			"source": "Use issue sample replay_command values from issues.jsonl for deterministic reproduction.",
			"trace_mode": "Replay commands use --trace all so trace.jsonl includes every action.",
			"manifest": "Use replay_manifest.json for build hash, data hashes, scenario mix, and run seeds.",
			"snapshots": "Issue samples may include snapshot_path values with JSON-safe failed-run state snapshots.",
			"hash_verification": str(_hash_verification_guidance().get("rule", "")),
			"hash_mismatch": str(_hash_verification_guidance().get("mismatch_result", "")),
		},
	}
	var file := FileAccess.open("%s/summary.json" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation summary.json.")
		return
	file.store_string(JSON.stringify(summary, "\t", true))
	_write_telemetry_summary(output_files)
	_write_balance_profiles(output_files)
	_write_performance_observations(output_files)
	_write_polish_telemetry(output_files)
	_write_manual_polish_review(output_files)
	_write_coverage_manifest(output_files)
	_write_replay_manifest(output_files)


func _write_coverage_manifest(output_files: Dictionary) -> void:
	var report := {
		"type": "coverage_manifest",
		"campaign": str(config.get("campaign", DEFAULT_CAMPAIGN)),
		"quest_policy": str(config.get("quest_policy", DEFAULT_QUEST_POLICY)),
		"coverage": _coverage_report(),
		"opportunities": _opportunity_report(),
		"output_files": output_files.duplicate(true),
	}
	var file := FileAccess.open("%s/coverage_manifest.json" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation coverage_manifest.json.")
		return
	file.store_string(JSON.stringify(_normalize_value(report), "\t", true))


func _write_telemetry_summary(output_files: Dictionary) -> void:
	var report := _telemetry_report(25)
	report["type"] = "telemetry_summary"
	report["output_files"] = output_files.duplicate(true)
	var file := FileAccess.open("%s/telemetry_summary.json" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation telemetry_summary.json.")
		return
	file.store_string(JSON.stringify(_normalize_value(report), "\t", true))


func _write_balance_profiles(output_files: Dictionary) -> void:
	var report := _balance_profile_report(25)
	report["type"] = "balance_profiles"
	report["output_files"] = output_files.duplicate(true)
	var file := FileAccess.open("%s/balance_profiles.json" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation balance_profiles.json.")
		return
	file.store_string(JSON.stringify(_normalize_value(report), "\t", true))


func _write_performance_observations(output_files: Dictionary) -> void:
	var report := _performance_report(25)
	report["output_files"] = output_files.duplicate(true)
	var file := FileAccess.open("%s/performance_observations.json" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation performance_observations.json.")
		return
	file.store_string(JSON.stringify(_normalize_value(report), "\t", true))


func _write_polish_telemetry(output_files: Dictionary) -> void:
	var report := _polish_report(25)
	report["type"] = "polish_telemetry"
	report["output_files"] = output_files.duplicate(true)
	var file := FileAccess.open("%s/polish_telemetry.json" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation polish_telemetry.json.")
		return
	file.store_string(JSON.stringify(_normalize_value(report), "\t", true))


func _write_manual_polish_review(output_files: Dictionary) -> void:
	var lines := []
	var polish := _polish_report(10)
	lines.append("# Hearthvale Manual Polish Review")
	lines.append("")
	lines.append("Generated from `%d` headless runs, `%d` steps each, base seed `%d`." % [
		int(config["runs"]),
		int(config["steps"]),
		int(config["seed"]),
	])
	lines.append("")
	lines.append("Use this checklist for human-only review areas the headless bot cannot judge. Treat every item as advisory until verified in the running game.")
	lines.append("")
	lines.append("## Simulation Signals To Inspect")
	lines.append("")
	lines.append("- Advisory status: `%s`; sampled flags: `%d`; flag rate: `%.3f`." % [
		str(polish.get("advisory_status", "")),
		int(polish.get("sampled_flags", 0)),
		float(polish.get("flag_rate", 0.0)),
	])
	lines.append("- Review `%s` for aggregate polish telemetry and replay samples." % _display_output_path("polish_telemetry.json"))
	var samples = polish.get("samples", [])
	if samples is Array and not samples.is_empty():
		lines.append("")
		lines.append("## Replay Samples")
		lines.append("")
		for index in range(min(5, samples.size())):
			var sample = samples[index]
			if not (sample is Dictionary):
				continue
			lines.append("- `%s`: %s; scenario `%s`, seed `%s`, step `%s`; replay: `%s`" % [
				str(sample.get("code", "")),
				str(sample.get("summary", "")),
				str(sample.get("scenario", "")),
				str(sample.get("seed", "")),
				str(sample.get("step", "")),
				str(sample.get("replay_command", "")),
			])
	lines.append("")
	lines.append("## Checklist")
	lines.append("")
	_append_manual_polish_section(lines, "Start screen", [
		"Confirm title, subtitle, username field, and start button are readable at normal window sizes.",
		"Confirm the first action is obvious without reading external docs.",
		"Check that errors or empty-name behavior feel clear.",
	])
	_append_manual_polish_section(lines, "HUD", [
		"Confirm feedback text is visible, concise, and changes after meaningful actions.",
		"Check visual hierarchy across account, tile, selection, feedback, stats, inventory, equipment, and quest panels.",
		"Look for overlapping text, cramped labels, missing icons, or unreadable tooltips.",
	])
	_append_manual_polish_section(lines, "Inventory and equipment", [
		"Confirm item icons, quantities, tooltip sections, use/equip/drop actions, and empty slots are understandable.",
		"Check whether a new player can tell what improved after equipping gear.",
	])
	_append_manual_polish_section(lines, "Bank and shop", [
		"Confirm buy, sell, deposit, and withdraw controls are visible and explain failures such as no coins or empty inventory.",
		"Check whether repeated transactions give enough feedback without becoming noisy.",
	])
	_append_manual_polish_section(lines, "Dialogue and quests", [
		"Confirm NPC dialogue states, quest start/completion buttons, active objective text, and return prompts are understandable.",
		"Check whether the player knows the next useful action after starting or completing objectives.",
	])
	_append_manual_polish_section(lines, "Combat", [
		"Confirm attack feedback, damage, low-health warnings, death/recovery, drops, and status effects are visible.",
		"Check whether animation/state changes match combat outcomes.",
	])
	_append_manual_polish_section(lines, "Gathering and crafting", [
		"Confirm resource depletion, level/tool requirements, processing results, XP, and unlock feedback are clear.",
		"Check whether repeated grind actions feel responsive enough.",
	])
	_append_manual_polish_section(lines, "Minimap and camera", [
		"Confirm minimap player marker, heading, compass reset, selected target, destination marker, and camera motion are readable.",
		"Check whether navigation cues make long paths or blocked paths understandable.",
	])
	lines.append("")
	lines.append("Generated artifacts: `%s`, `%s`." % [
		_display_output_path("polish_telemetry.json"),
		_display_output_path("manual_polish_review.md"),
	])
	var file := FileAccess.open("%s/manual_polish_review.md" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation manual_polish_review.md.")
		return
	file.store_string("\n".join(lines))


func _append_manual_polish_section(lines: Array, title: String, prompts: Array) -> void:
	lines.append("### %s" % title)
	lines.append("")
	for prompt in prompts:
		lines.append("- [ ] %s" % str(prompt))
	lines.append("")


func _write_replay_manifest(output_files: Dictionary) -> void:
	var manifest := replay_metadata.duplicate(true)
	manifest["type"] = "replay_manifest"
	manifest["output_files"] = output_files.duplicate(true)
	manifest["run_count"] = run_summaries.size()
	manifest["issue_occurrences"] = issue_occurrence_count
	manifest["issue_samples"] = issue_sample_count
	manifest["trust"] = trust_context.duplicate(true)
	manifest["hash_verification"] = _hash_verification_guidance()
	var manifest_runs := []
	for run_summary in run_summaries:
		if not (run_summary is Dictionary):
			continue
		manifest_runs.append({
			"run_index": int(run_summary.get("run_index", 0)),
			"seed": int(run_summary.get("seed", 0)),
			"scenario": str(run_summary.get("scenario", "")),
			"result": str(run_summary.get("result", "")),
			"replay_command": _replay_command(int(run_summary.get("seed", 0)), str(run_summary.get("scenario", ""))),
			"initial_digest": str(run_summary.get("state_checkpoints", {}).get("initial_digest", "")) if run_summary.get("state_checkpoints", {}) is Dictionary else "",
			"final_digest": str(run_summary.get("state_checkpoints", {}).get("final_digest", "")) if run_summary.get("state_checkpoints", {}) is Dictionary else "",
		})
	manifest["runs"] = manifest_runs
	var file := FileAccess.open("%s/replay_manifest.json" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation replay_manifest.json.")
		return
	file.store_string(JSON.stringify(_normalize_value(manifest), "\t", true))


func _write_issue_snapshot(issue_id: String, seed: int, scenario: String, step: int, issue_record: Dictionary) -> String:
	var safe_issue_id := issue_id.replace(":", "_").replace("/", "_").replace("\\", "_")
	var path := "%s/snapshots/%s_seed_%d_step_%d.json" % [str(config["output_dir"]), safe_issue_id, seed, step]
	var snapshot := StateSnapshot.capture(current_state, "%s %s step %d" % [issue_id, scenario, step], {
		"issue_id": issue_id,
		"seed": seed,
		"run_index": current_run_index,
		"scenario": scenario,
		"step": step,
		"action": str(issue_record.get("action", "")),
		"summary": str(issue_record.get("summary", "")),
		"replay_command": _replay_command(seed, scenario),
		"build_hash": str(replay_metadata.get("build_hash", "")),
	})
	var export_result: Dictionary = StateSnapshot.export_to_file(path, snapshot)
	if not bool(export_result.get("success", false)):
		push_warning("Could not write issue snapshot: %s" % str(export_result.get("message", "")))
		return ""
	return path


func _display_output_dir() -> String:
	var output_dir := str(config.get("output_dir", DEFAULT_OUTPUT_DIR))
	return output_dir.replace("res://", "").replace("/", "\\")


func _display_output_path(file_name: String) -> String:
	var output_dir := _display_output_dir()
	if output_dir.is_empty():
		return file_name
	return "%s\\%s" % [output_dir, file_name]


func _write_improvement_plan() -> void:
	var lines := []
	lines.append("# Hearthvale Playtest Simulation Improvement Plan")
	lines.append("")
	if not bool(trust_context.get("implementation_ready", false)):
		lines.append("NOT IMPLEMENTATION-READY: this run is below strategy-smoke coverage and cannot prove gameplay health.")
		lines.append("")
	lines.append("Generated from `%d` headless runs, `%d` steps each, base seed `%d`." % [
		int(config["runs"]),
		int(config["steps"]),
		int(config["seed"]),
	])
	lines.append("")
	lines.append("## Summary")
	lines.append("")
	lines.append("- Scenario setting: `%s`; scenario mix: `%s`." % [str(config["scenario"]), ", ".join(_scenario_mix())])
	lines.append("- Balance profile: `%s` - %s" % [str(config["balance_profile"]), str(_balance_profile_definition().get("focus", ""))])
	lines.append("- Trace mode: `%s`; output directory: `%s`." % [str(config["trace"]), str(config["output_dir"])])
	lines.append("- Timeout: `%s`; fail on issues: `%s`." % [_timeout_text(), str(config["fail_on_issues"])])
	lines.append("- Trust: run strength `%s`, coverage `%s`, implementation ready `%s`, latest publish status `%s`." % [
		str(trust_context.get("run_strength", "")),
		str(trust_context.get("coverage_scope", "")),
		str(trust_context.get("implementation_ready", false)),
		str(trust_context.get("latest_publish_status", "")),
	])
	if issue_occurrence_count > 0:
		lines.append("- Harness completed; advisory findings present.")
	else:
		lines.append("- Harness completed; no findings observed within this run scope.")
	if issue_occurrence_count == 0:
		lines.append("- No findings observed within this run scope.")
	else:
		lines.append("- Issue occurrences: `%d` across `%d` grouped findings." % [issue_occurrence_count, issue_groups.size()])
		lines.append("- Review `issues.jsonl` for replayable samples and `runs.jsonl` for per-run metrics.")
	lines.append("- Generated artifacts: `runs.jsonl`, `issues.jsonl`, `summary.json`, `replay_manifest.json`, `telemetry_summary.json`, `balance_profiles.json`, `performance_observations.json`, `polish_telemetry.json`, `manual_polish_review.md`, `improvement_plan.md`, `codex_prompt.md`%s." % [
		", `trace.jsonl`" if str(config["trace"]) == "all" else "",
	])
	var telemetry := _telemetry_report(5)
	lines.append("- Telemetry: damage taken `%d`, coin gained `%d`, coin spent `%d`, failed feedback actions `%d`, slow action samples over 16ms `%d`." % [
		int(telemetry.get("damage_taken", 0)),
		int(telemetry.get("coin_gained", 0)),
		int(telemetry.get("coin_spent", 0)),
		int(telemetry.get("failed_feedback_actions", 0)),
		int(telemetry.get("slow_action_steps_16ms", 0)),
	])
	var balance := _balance_profile_report(5)
	lines.append("- Balance: average net worth `%.1f`, average XP `%.1f`, average mobs defeated `%.1f`, completion rate `%.2f`." % [
		float(balance.get("average_net_worth", 0.0)),
		float(balance.get("average_total_xp", 0.0)),
		float(balance.get("average_mobs_defeated", 0.0)),
		float(balance.get("clean_run_rate", 0.0)),
	])
	var performance := _performance_report(5)
	lines.append("- Performance observations: advisory status `%s`, average action cost `%.1f usec`, slow action rate `%.3f`, average path length `%.1f`." % [
		str(performance.get("status", "ok")),
		float(performance.get("average_action_cost_usec", 0.0)),
		float(performance.get("slow_action_rate", 0.0)),
		float(performance.get("average_path_length", 0.0)),
	])
	lines.append("- Performance diagnostics: top slow actions `%s`; top slow path buckets `%s`; review `performance_observations.json` for top offender records by action, scenario, tile, and path length." % [
		_top_entry_text(performance.get("top_slow_actions", [])),
		_top_entry_text(performance.get("top_slow_path_lengths", [])),
	])
	var polish := _polish_report(5)
	lines.append("- Polish telemetry: advisory status `%s`, sampled flags `%d`, empty feedback rate `%.3f`, unchanged feedback rate `%.3f`." % [
		str(polish.get("advisory_status", "")),
		int(polish.get("sampled_flags", 0)),
		float(polish.get("empty_feedback_rate", 0.0)),
		float(polish.get("unchanged_feedback_rate", 0.0)),
	])
	var probes = scenario_probe_report.get("summary", {}) if scenario_probe_report is Dictionary else {}
	lines.append("- Scenario probes: mode `%s`, status `%s`, completed `%d`, diagnostic probes `%d`, issues `%d`." % [
		str(scenario_probe_report.get("mode", "off")) if scenario_probe_report is Dictionary else "off",
		str(probes.get("status", "")) if probes is Dictionary else "",
		int(probes.get("completed", 0)) if probes is Dictionary else 0,
		int(probes.get("diagnostic", 0)) if probes is Dictionary else 0,
		int(probes.get("issues", 0)) if probes is Dictionary else 0,
	])
	var scorecard := _simulation_scorecard()
	var weakest = scorecard.get("weakest_category", {})
	lines.append("- Advisory scorecard: overall `%d`/100; weakest `%s` `%d`/100." % [
		int(scorecard.get("overall_score", 0)),
		str(weakest.get("label", "")) if weakest is Dictionary else "",
		int(weakest.get("score", 0)) if weakest is Dictionary else 0,
	])
	lines.append("- Treat findings as evidence candidates. Verify issue samples against current code and data before changing gameplay.")
	lines.append("")
	_append_scorecard_lines(lines, scorecard, true)
	lines.append("## Replay Guidance")
	lines.append("")
	lines.append("- Use the replay command embedded in each `issues.jsonl` sample to rerun the same seed, scenario, and step count.")
	lines.append("- Replay commands use `--trace all` so `%s` captures every bot action." % _display_output_path("trace.jsonl"))
	lines.append("- Use `replay_manifest.json` for build hash, data hashes, scenario mix, run seeds, and output paths.")
	lines.append("- Use `balance_profiles.json` for profile-specific economy, progression, combat, loot, and dominant-action signals.")
	lines.append("- Use `performance_observations.json` for advisory action-cost and path-cost signals, including top slow samples grouped by action, scenario, tile, and path length; it is not a failing gate.")
	lines.append("- Use `polish_telemetry.json` and `manual_polish_review.md` for advisory player-facing clarity, UI, feedback, and human-only review prompts.")
	lines.append("- Use `summary.json` `scenario_probes` for deterministic report-only coverage diagnostics; probe findings are not pass/fail gates.")
	lines.append("- When an issue sample includes `snapshot_path`, inspect that JSON-safe state snapshot before changing gameplay.")
	lines.append("- Hash verification: compare `build_hash`, all `data_hashes`, and all `script_hashes` before using replay to close or dismiss an issue.")
	lines.append("- If any hash differs, replay is under changed code and cannot close the original issue by itself.")
	lines.append("")
	lines.append("## Ranked Findings")
	lines.append("")
	var groups := _sorted_issue_groups()
	if groups.is_empty():
		lines.append("- No ranked findings.")
	else:
		for index in range(min(groups.size(), 20)):
			var group: Dictionary = groups[index]
			var first_issue = group.get("first_issue", {})
			if not (first_issue is Dictionary):
				first_issue = {}
			lines.append("%d. `%s` `%s` %s" % [
				index + 1,
				str(group.get("severity", "P3")),
				str(group.get("category", "issue")),
				str(group.get("summary", "")),
			])
			lines.append("   - Count: `%d`; action: `%s`; scenarios: `%s`." % [
				int(group.get("count", 0)),
				str(group.get("action", "")),
				_scenario_count_text(group.get("scenarios", {})),
			])
			lines.append("   - Replay: `%s`" % str(first_issue.get("replay_command", "")))
			lines.append("   - First sample: seed `%s`, scenario `%s`, step `%s`, feedback `%s`." % [
				str(first_issue.get("seed", "")),
				str(first_issue.get("scenario", "")),
				str(first_issue.get("step", "")),
				str(first_issue.get("feedback", "")),
			])
	lines.append("")
	lines.append("## Recommended Implementation Order")
	lines.append("")
	if groups.is_empty():
		lines.append("- Keep the simulation in the smoke workflow and raise run counts after new gameplay systems land.")
	else:
		lines.append("- Fix any `P0` invariant bugs first; these indicate invalid state and should block balancing work.")
		lines.append("- Fix `P1` softlocks next, especially repeated no-progress loops and unreachable objective paths.")
		lines.append("- Use `P2` QOL findings to prioritize clearer feedback, inventory relief, and shorter common task paths.")
		lines.append("- Treat balance findings as signals until the related loop has enough successful run coverage.")
	lines.append("")
	lines.append("## Scenario Metrics")
	lines.append("")
	for scenario in _sorted_keys(scenario_metrics):
		var metrics = scenario_metrics[scenario]
		if not (metrics is Dictionary):
			continue
		lines.append("- `%s`: runs `%d`, issues `%d`, completed quests `%d`, total XP `%d`, no-progress runs `%d`." % [
			str(scenario),
			int(metrics.get("runs", 0)),
			int(metrics.get("issue_count", 0)),
			int(metrics.get("completed_quests", 0)),
			int(metrics.get("total_xp", 0)),
			int(metrics.get("no_progress_runs", 0)),
		])

	var file := FileAccess.open("%s/improvement_plan.md" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation improvement_plan.md.")
		return
	file.store_string("\n".join(lines))


func _write_codex_prompt() -> void:
	var groups := _sorted_issue_groups()
	var output_dir := _display_output_dir()
	var lines := []
	lines.append("# Codex Prompt: Implement Hearthvale Simulation Findings")
	lines.append("")
	if not bool(trust_context.get("implementation_ready", false)):
		lines.append("NOT IMPLEMENTATION-READY: this run is below strategy-smoke coverage and cannot prove gameplay health.")
		lines.append("")
	lines.append("You are working in `C:\\Users\\donny\\Desktop\\hearthvale_godot` on the Godot version of Hearthvale.")
	lines.append("")
	lines.append("Implement the credible bugs, softlocks, quality-of-life fixes, and gameplay improvements found by the latest headless playtest simulation. Use the generated evidence as guidance, but verify every finding against the current code and data before changing behavior. Do not blindly optimize around bot mistakes.")
	lines.append("")
	lines.append("## Source Evidence")
	lines.append("")
	lines.append("- This prompt is the single Markdown handoff for the run. Use it first for planning and implementation.")
	lines.append("- If this prompt was published to `.godot\\ai_simulation`, use the same-timestamp `.json` file next to it for structured details.")
	lines.append("- Do not use `.godot\\ai_simulation\\_working\\current` as public evidence after a later run; it is a disposable working folder.")
	lines.append("- Replay representative issues with the commands embedded below before implementing risky fixes.")
	lines.append("- Hash verification: compare `build_hash`, all `data_hashes`, and all `script_hashes` before using replay to close or dismiss an issue.")
	lines.append("- If any hash differs, replay is under changed code and cannot close the original issue by itself.")
	lines.append("")
	lines.append("## Current Simulation Run")
	lines.append("")
	lines.append("- Runs: `%d`" % int(config["runs"]))
	lines.append("- Steps per run: `%d`" % int(config["steps"]))
	lines.append("- Base seed: `%d`" % int(config["seed"]))
	lines.append("- Scenario setting: `%s`" % str(config["scenario"]))
	lines.append("- Scenario mix: `%s`" % ", ".join(_scenario_mix()))
	lines.append("- Balance profile: `%s`" % str(config["balance_profile"]))
	lines.append("- Scenario probes: requested `%s`, resolved `%s`." % [
		str(config["scenario_probes"]),
		str(scenario_probe_report.get("mode", "off")) if scenario_probe_report is Dictionary else "off",
	])
	lines.append("- Trace mode: `%s`" % str(config["trace"]))
	lines.append("- Output directory: `%s`" % output_dir)
	lines.append("- Timeout: `%s`" % _timeout_text())
	lines.append("- Fail on issues: `%s`" % str(config["fail_on_issues"]))
	lines.append("- Issue occurrences: `%d`" % issue_occurrence_count)
	lines.append("- Grouped findings: `%d`" % issue_groups.size())
	lines.append("- Run strength: `%s`" % str(trust_context.get("run_strength", "")))
	lines.append("- Coverage scope: `%s`" % str(trust_context.get("coverage_scope", "")))
	lines.append("- Implementation ready: `%s`" % str(trust_context.get("implementation_ready", false)))
	lines.append("- Harness status: `%s`" % str(trust_context.get("harness_status", "")))
	lines.append("- Finding status: `%s`" % str(trust_context.get("finding_status", "")))
	lines.append("- Latest publish status: `%s`" % str(trust_context.get("latest_publish_status", "")))
	if bool(trust_context.get("latest_replaced_stronger_run", false)):
		lines.append("- Latest replaced stronger run: `true`; previous strength `%s`; previous created at `%s`." % [
			str(trust_context.get("previous_latest_run_strength", "")),
			str(trust_context.get("previous_latest_created_at", "")),
		])
	lines.append("")
	_append_scorecard_lines(lines, _simulation_scorecard(), true)
	lines.append("## Generated Artifacts")
	lines.append("")
	lines.append("- Public publish writes one timestamped Codex prompt Markdown and one same-timestamp JSON summary under `.godot\\ai_simulation`.")
	lines.append("- Internal detailed reports for this run were written to `%s` and archived under `.godot\\ai_simulation\\archive` when publishing succeeds." % output_dir)
	lines.append("- The JSON summary includes trust labels, replay metadata, issue group details, advisory 0-100 category scores, relevant metrics, telemetry, polish signals, balance signals, performance observations, scenario metrics, scenario probe diagnostics, and output file paths.")
	lines.append("- Performance observations include top slow samples grouped by action, scenario, tile, and path length. Treat them as repeatability diagnostics before optimizing.")
	lines.append("")
	lines.append("## Implementation Instructions")
	lines.append("")
	lines.append("- Preserve unrelated dirty worktree changes. Do not revert, stage, commit, or push unless explicitly asked.")
	lines.append("- Keep changes small, Godot-native, and data-driven where practical.")
	lines.append("- Keep bot-owned work in `scripts/playtest_simulation_runner.gd` and its generated reports: deterministic replay metadata, chaos behavior, simulation-step invariant calls, telemetry summaries, balance profiles, polish telemetry, failed-run state summaries, and advisory simulation performance observations.")
	lines.append("- Treat `scenario_probes` as deterministic report-only diagnostics that improve coverage visibility but do not replace focused smokes or manual playtesting.")
	lines.append("- Keep validators, golden smokes, save/load torture smokes, debug console commands, and debug overlays independently runnable outside the simulation bot.")
	lines.append("- Put shared logic such as invariants or future snapshots in reusable helpers instead of burying it only inside the runner.")
	lines.append("- Fix P0/P1 findings first, then P2 QOL friction if the fix is clear and low risk.")
	lines.append("- If a finding is caused by a weak simulation heuristic rather than game behavior, improve `scripts/playtest_simulation_runner.gd` classification or bot logic instead of changing gameplay.")
	lines.append("- Favor player-facing improvements that reduce repeated failed actions: clearer feedback, recovery paths, better gating, inventory relief, and safer combat/quest flow.")
	lines.append("- Treat polish telemetry as advisory. Use manual review prompts for visual quality, animation feel, audio, fun, and player confusion before making subjective changes.")
	lines.append("- Preserve original Hearthvale names, assets, formulas, and progression language; do not copy proprietary or near-branded inspiration-game content.")
	lines.append("- Avoid Python/Panda3D workflow changes and do not touch normal user saves.")
	lines.append("- Treat simulation findings as evidence candidates, not proof. Verify each candidate against current code, data, and deterministic replay before changing gameplay.")
	lines.append("")
	lines.append("## Ranked Findings To Address")
	lines.append("")
	if groups.is_empty():
		lines.append("- No findings observed within this run scope. Keep the runner in the verification workflow and make no gameplay changes unless code inspection reveals an issue.")
	else:
		for index in range(min(groups.size(), 20)):
			var group: Dictionary = groups[index]
			var first_issue = group.get("first_issue", {})
			if not (first_issue is Dictionary):
				first_issue = {}
			lines.append("%d. `%s` `%s` %s" % [
				index + 1,
				str(group.get("severity", "P3")),
				str(group.get("category", "issue")),
				str(group.get("summary", "")),
			])
			lines.append("   - Occurrences: `%d`; action: `%s`; scenarios: `%s`." % [
				int(group.get("count", 0)),
				str(group.get("action", "")),
				_scenario_count_text(group.get("scenarios", {})),
			])
			lines.append("   - First sample: seed `%s`, scenario `%s`, step `%s`, feedback `%s`." % [
				str(first_issue.get("seed", "")),
				str(first_issue.get("scenario", "")),
				str(first_issue.get("step", "")),
				str(first_issue.get("feedback", "")),
			])
			lines.append("   - Replay: `%s`" % str(first_issue.get("replay_command", "")))
	lines.append("")
	lines.append("## Expected Output From Codex")
	lines.append("")
	lines.append("- Implement the verified gameplay/UI/data/simulation fixes.")
	lines.append("- Explain which findings were fixed, which were reclassified as simulation noise, and which remain.")
	lines.append("- Run the smallest relevant smoke checks plus the playtest simulation runner.")
	lines.append("- Include exact commands and pass/fail results in the final response.")
	lines.append("")
	lines.append("## Manual Polish Review")
	lines.append("")
	lines.append("- Check start screen readability, empty-name behavior, and first-action clarity.")
	lines.append("- Check HUD hierarchy, feedback visibility, inventory/equipment clarity, and quest objective clarity.")
	lines.append("- Check bank/shop transaction feedback and failure explanations.")
	lines.append("- Check combat feedback, low-health/death recovery, drops, status effects, and whether visible state changes match outcomes.")
	lines.append("- Check gathering/crafting responsiveness, resource depletion, level/tool requirements, XP, and unlock feedback.")
	lines.append("- Check minimap/camera readability, destination cues, selected target cues, and long/blocked path clarity.")
	lines.append("")
	lines.append("## Suggested Verification Commands")
	lines.append("")
	lines.append("```powershell")
	lines.append("& 'C:\\Users\\donny\\Desktop\\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/data_validation_smoke.gd --log-file .godot_logs\\data_validation.log")
	lines.append("& 'C:\\Users\\donny\\Desktop\\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/core_gameplay_smoke.gd --log-file .godot_logs\\core_gameplay.log")
	lines.append("& 'C:\\Users\\donny\\Desktop\\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/economy_quest_smoke.gd --log-file .godot_logs\\economy_quest.log")
	lines.append("& 'C:\\Users\\donny\\Desktop\\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/playtest_simulation_runner.gd --log-file .godot_logs\\playtest_after_fixes.log -- --runs 100 --steps 150 --seed 1 --scenario all --trace issues")
	lines.append("git diff --check")
	lines.append("```")

	var file := FileAccess.open("%s/codex_prompt.md" % str(config["output_dir"]), FileAccess.WRITE)
	if file == null:
		push_error("Could not write simulation codex_prompt.md.")
		return
	file.store_string("\n".join(lines))


func _sorted_issue_groups() -> Array:
	var groups := []
	for group in issue_groups.values():
		if group is Dictionary:
			groups.append(group)
	groups.sort_custom(func(left, right) -> bool:
		var left_rank := _severity_rank(str(left.get("severity", "P3")))
		var right_rank := _severity_rank(str(right.get("severity", "P3")))
		if left_rank != right_rank:
			return left_rank < right_rank
		return int(left.get("count", 0)) > int(right.get("count", 0))
	)
	return groups


func _severity_rank(severity: String) -> int:
	match severity:
		"P0":
			return 0
		"P1":
			return 1
		"P2":
			return 2
	return 3


func _scenario_count_text(raw_value) -> String:
	if not (raw_value is Dictionary):
		return ""
	var pieces := []
	for key in _sorted_keys(raw_value):
		pieces.append("%s=%d" % [str(key), int(raw_value[key])])
	return ", ".join(pieces)


func _top_entry_text(raw_entries, limit: int = 3) -> String:
	if not (raw_entries is Array) or raw_entries.is_empty():
		return "none"
	var pieces := []
	for index in range(min(limit, raw_entries.size())):
		var entry = raw_entries[index]
		if entry is Dictionary:
			pieces.append("%s=%d" % [str(entry.get("key", "")), int(entry.get("count", 0))])
	return ", ".join(pieces) if not pieces.is_empty() else "none"


func _scenario_mix() -> Array:
	if str(config.get("scenario", DEFAULT_SCENARIO)) != "all":
		return [str(config.get("scenario", DEFAULT_SCENARIO))]
	return _balance_profile_scenario_mix()


func _balance_profile_ids() -> Array:
	var ids := []
	for key in BALANCE_PROFILES.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func _balance_profile_definition() -> Dictionary:
	var profile_id := str(config.get("balance_profile", DEFAULT_BALANCE_PROFILE))
	var definition = BALANCE_PROFILES.get(profile_id, BALANCE_PROFILES[DEFAULT_BALANCE_PROFILE])
	if definition is Dictionary:
		return definition
	return BALANCE_PROFILES[DEFAULT_BALANCE_PROFILE]


func _balance_profile_scenario_mix() -> Array:
	var definition := _balance_profile_definition()
	var raw_mix = definition.get("scenario_mix", SCENARIOS)
	var mix := []
	if raw_mix is Array:
		for scenario in raw_mix:
			var scenario_id := str(scenario)
			if scenario_id in SCENARIOS:
				mix.append(scenario_id)
	if mix.is_empty():
		return SCENARIOS.duplicate()
	return mix


func _build_replay_metadata() -> Dictionary:
	var data_hashes := {
		"world": _file_hash(WORLD_PATH),
		"items": _file_hash(ITEMS_PATH),
		"skills": _file_hash(SKILLS_PATH),
		"recipes": _file_hash(RECIPES_PATH),
		"quests": _file_hash(QUESTS_PATH),
	}
	var script_hashes := {
		"playtest_simulation_runner": _file_hash("res://scripts/playtest_simulation_runner.gd"),
		"gameplay_core": _file_hash("res://scripts/gameplay_core.gd"),
		"invariant_checker": _file_hash("res://scripts/invariant_checker.gd"),
		"state_snapshot": _file_hash("res://scripts/state_snapshot.gd"),
	}
	var scenario_mix := _scenario_mix()
	return {
		"created_at": Time.get_datetime_string_from_system(true),
		"project": str(ProjectSettings.get_setting("application/config/name", "Hearthvale")),
		"godot_version": _godot_version_text(),
		"build_hash": _combined_hash([_file_hash("res://project.godot"), _combined_hash(data_hashes.values()), _combined_hash(script_hashes.values())]),
		"data_hashes": data_hashes,
		"script_hashes": script_hashes,
		"base_seed": int(config["seed"]),
		"runs": int(config["runs"]),
		"steps": int(config["steps"]),
		"scenario": str(config["scenario"]),
		"scenario_mix": scenario_mix,
		"balance_profile": str(config["balance_profile"]),
		"balance_profile_definition": _balance_profile_definition(),
		"scenario_probes": str(config["scenario_probes"]),
		"campaign": str(config.get("campaign", DEFAULT_CAMPAIGN)),
		"quest_policy": str(config.get("quest_policy", DEFAULT_QUEST_POLICY)),
		"action_policy": "adversarial" if str(config.get("campaign", DEFAULT_CAMPAIGN)) == "adversarial" else "safe",
		"trace": str(config["trace"]),
		"output_dir": str(config["output_dir"]),
		"publish_latest": bool(config.get("publish_latest", false)),
		"allow_latest_downgrade": bool(config.get("allow_latest_downgrade", false)),
		"require_publish_latest": bool(config.get("require_publish_latest", false)),
		"trust": trust_context.duplicate(true),
		"replay_command_template": _replay_command(int(config["seed"]), str(scenario_mix[0])),
	}


func _run_replay_metadata(seed: int, scenario: String) -> Dictionary:
	return {
		"seed": seed,
		"base_seed": int(config["seed"]),
		"run_index": current_run_index,
		"scenario": scenario,
		"quest_policy": str(config.get("quest_policy", DEFAULT_QUEST_POLICY)),
		"steps": int(config["steps"]),
		"trace": str(config["trace"]),
		"build_hash": str(replay_metadata.get("build_hash", "")),
		"replay_command": _replay_command(seed, scenario),
	}


func _run_metrics(_first_digest: String, final_digest: String) -> Dictionary:
	var quest_counts := _quest_counts()
	var started := int(quest_counts.get("started", 0))
	var completed := int(quest_counts.get("completed", 0))
	var metrics := {
		"coins": int(_inventory().get("coins", 0)),
		"inventory_slots": _inventory_slot_count(_inventory()),
		"bank_slots": _inventory_slot_count(_bank()),
		"total_xp": _total_xp(),
		"current_hitpoints": _current_hitpoints(),
		"started_quests": started,
		"completed_quests": completed,
		"max_no_progress_streak": current_max_no_progress_streak,
		"state_changed": _first_digest != final_digest,
	}
	if current_scenario == "quest_chaser" and started > 0 and completed <= 0 and int(config["steps"]) >= 50:
		_record_issue("softlock", "P1", "quest_chaser", "Quest chaser started quests but completed none.", _feedback_text(), {
			"started_quests": started,
			"completed_quests": completed,
		})
	return metrics


func _balance_metrics(run_metrics: Dictionary) -> Dictionary:
	var telemetry: Dictionary = _finalize_telemetry_bucket(current_run_telemetry, 5)
	var inventory_value := _mapping_sell_value(_inventory())
	var bank_value := _mapping_sell_value(_bank())
	var equipment_value := _equipment_sell_value()
	var ground_value := _ground_items_sell_value()
	var coin_end := int(_inventory().get("coins", 0))
	var net_worth := coin_end + inventory_value + bank_value + equipment_value
	var completed_quests := int(run_metrics.get("completed_quests", 0))
	var started_quests := int(run_metrics.get("started_quests", 0))
	var mobs_defeated := _mobs_defeated_count()
	var action_counts = telemetry.get("action_counts", {})
	return {
		"profile": str(config.get("balance_profile", DEFAULT_BALANCE_PROFILE)),
		"scenario": current_scenario,
		"clean_run": current_issue_occurrences == 0,
		"state_changed": bool(run_metrics.get("state_changed", false)),
		"coin_end": coin_end,
		"coin_gained": int(telemetry.get("coin_gained", 0)),
		"coin_spent": int(telemetry.get("coin_spent", 0)),
		"inventory_value": inventory_value,
		"bank_value": bank_value,
		"equipment_value": equipment_value,
		"ground_drop_value": ground_value,
		"net_worth": net_worth,
		"total_xp": int(run_metrics.get("total_xp", 0)),
		"xp_by_skill": _xp_by_skill(),
		"started_quests": started_quests,
		"completed_quests": completed_quests,
		"quest_completion_rate": float(completed_quests) / float(started_quests) if started_quests > 0 else 0.0,
		"current_hitpoints": int(run_metrics.get("current_hitpoints", 0)),
		"damage_taken": int(telemetry.get("damage_taken", 0)),
		"healing_done": int(telemetry.get("healing_done", 0)),
		"deaths": int(telemetry.get("deaths", 0)),
		"mobs_defeated": mobs_defeated,
		"combat_survived": int(run_metrics.get("current_hitpoints", 0)) > 0,
		"ground_drop_count": _ground_items_quantity(),
		"high_value_item_count": _high_value_item_count(),
		"dominant_action": _top_count_key(action_counts),
		"full_inventory_steps": int(telemetry.get("full_inventory_steps", 0)),
		"failed_feedback_actions": int(telemetry.get("failed_feedback_actions", 0)),
	}


func _balance_profile_report(top_limit: int) -> Dictionary:
	var aggregate := _new_balance_bucket()
	var scenarios := {}
	for run_summary in run_summaries:
		if not (run_summary is Dictionary):
			continue
		var metrics = run_summary.get("balance_metrics", {})
		if not (metrics is Dictionary):
			continue
		_merge_balance_bucket(aggregate, metrics)
		var scenario := str(run_summary.get("scenario", "unknown"))
		var scenario_bucket = scenarios.get(scenario, _new_balance_bucket())
		if not (scenario_bucket is Dictionary):
			scenario_bucket = _new_balance_bucket()
		_merge_balance_bucket(scenario_bucket, metrics)
		scenarios[scenario] = scenario_bucket
	var report := _finalize_balance_bucket(aggregate, top_limit)
	var scenario_reports := {}
	for scenario in _sorted_keys(scenarios):
		var bucket = scenarios[scenario]
		if bucket is Dictionary:
			scenario_reports[scenario] = _finalize_balance_bucket(bucket, min(top_limit, 10))
	report["profile"] = str(config.get("balance_profile", DEFAULT_BALANCE_PROFILE))
	report["profile_definition"] = _balance_profile_definition()
	report["scenario_setting"] = str(config.get("scenario", DEFAULT_SCENARIO))
	report["scenario_mix"] = _scenario_mix()
	report["scenarios"] = scenario_reports
	report["signals"] = [
		"Treat profile metrics as simulation signals, not final balance truth.",
		"Compare repeated runs with the same profile after gameplay or data changes.",
	]
	return _normalize_value(report)


func _new_balance_bucket() -> Dictionary:
	return {
		"runs": 0,
		"clean_runs": 0,
		"state_changed_runs": 0,
		"coin_end_total": 0,
		"coin_gained_total": 0,
		"coin_spent_total": 0,
		"inventory_value_total": 0,
		"bank_value_total": 0,
		"equipment_value_total": 0,
		"ground_drop_value_total": 0,
		"net_worth_total": 0,
		"total_xp": 0,
		"started_quests": 0,
		"completed_quests": 0,
		"damage_taken": 0,
		"healing_done": 0,
		"deaths": 0,
		"mobs_defeated": 0,
		"combat_survived_runs": 0,
		"ground_drop_count": 0,
		"high_value_item_count": 0,
		"full_inventory_steps": 0,
		"failed_feedback_actions": 0,
		"dominant_actions": {},
		"xp_by_skill": {},
	}


func _merge_balance_bucket(bucket: Dictionary, metrics: Dictionary) -> void:
	bucket["runs"] = int(bucket.get("runs", 0)) + 1
	bucket["clean_runs"] = int(bucket.get("clean_runs", 0)) + (1 if bool(metrics.get("clean_run", false)) else 0)
	bucket["state_changed_runs"] = int(bucket.get("state_changed_runs", 0)) + (1 if bool(metrics.get("state_changed", false)) else 0)
	bucket["coin_end_total"] = int(bucket.get("coin_end_total", 0)) + int(metrics.get("coin_end", 0))
	bucket["coin_gained_total"] = int(bucket.get("coin_gained_total", 0)) + int(metrics.get("coin_gained", 0))
	bucket["coin_spent_total"] = int(bucket.get("coin_spent_total", 0)) + int(metrics.get("coin_spent", 0))
	bucket["inventory_value_total"] = int(bucket.get("inventory_value_total", 0)) + int(metrics.get("inventory_value", 0))
	bucket["bank_value_total"] = int(bucket.get("bank_value_total", 0)) + int(metrics.get("bank_value", 0))
	bucket["equipment_value_total"] = int(bucket.get("equipment_value_total", 0)) + int(metrics.get("equipment_value", 0))
	bucket["ground_drop_value_total"] = int(bucket.get("ground_drop_value_total", 0)) + int(metrics.get("ground_drop_value", 0))
	bucket["net_worth_total"] = int(bucket.get("net_worth_total", 0)) + int(metrics.get("net_worth", 0))
	bucket["total_xp"] = int(bucket.get("total_xp", 0)) + int(metrics.get("total_xp", 0))
	bucket["started_quests"] = int(bucket.get("started_quests", 0)) + int(metrics.get("started_quests", 0))
	bucket["completed_quests"] = int(bucket.get("completed_quests", 0)) + int(metrics.get("completed_quests", 0))
	bucket["damage_taken"] = int(bucket.get("damage_taken", 0)) + int(metrics.get("damage_taken", 0))
	bucket["healing_done"] = int(bucket.get("healing_done", 0)) + int(metrics.get("healing_done", 0))
	bucket["deaths"] = int(bucket.get("deaths", 0)) + int(metrics.get("deaths", 0))
	bucket["mobs_defeated"] = int(bucket.get("mobs_defeated", 0)) + int(metrics.get("mobs_defeated", 0))
	bucket["combat_survived_runs"] = int(bucket.get("combat_survived_runs", 0)) + (1 if bool(metrics.get("combat_survived", false)) else 0)
	bucket["ground_drop_count"] = int(bucket.get("ground_drop_count", 0)) + int(metrics.get("ground_drop_count", 0))
	bucket["high_value_item_count"] = int(bucket.get("high_value_item_count", 0)) + int(metrics.get("high_value_item_count", 0))
	bucket["full_inventory_steps"] = int(bucket.get("full_inventory_steps", 0)) + int(metrics.get("full_inventory_steps", 0))
	bucket["failed_feedback_actions"] = int(bucket.get("failed_feedback_actions", 0)) + int(metrics.get("failed_feedback_actions", 0))
	var dominant_actions = bucket.get("dominant_actions", {})
	if dominant_actions is Dictionary:
		_increment_count(dominant_actions, str(metrics.get("dominant_action", "")))
		bucket["dominant_actions"] = dominant_actions
	var bucket_xp = bucket.get("xp_by_skill", {})
	var metrics_xp = metrics.get("xp_by_skill", {})
	if bucket_xp is Dictionary and metrics_xp is Dictionary:
		for skill_id in metrics_xp.keys():
			bucket_xp[str(skill_id)] = int(bucket_xp.get(str(skill_id), 0)) + int(metrics_xp[skill_id])
		bucket["xp_by_skill"] = bucket_xp


func _finalize_balance_bucket(bucket: Dictionary, top_limit: int) -> Dictionary:
	var report := bucket.duplicate(true)
	var runs := int(report.get("runs", 0))
	report["clean_run_rate"] = float(report.get("clean_runs", 0)) / float(runs) if runs > 0 else 0.0
	report["state_changed_rate"] = float(report.get("state_changed_runs", 0)) / float(runs) if runs > 0 else 0.0
	report["combat_survival_rate"] = float(report.get("combat_survived_runs", 0)) / float(runs) if runs > 0 else 0.0
	report["average_coin_end"] = float(report.get("coin_end_total", 0)) / float(runs) if runs > 0 else 0.0
	report["average_net_worth"] = float(report.get("net_worth_total", 0)) / float(runs) if runs > 0 else 0.0
	report["average_total_xp"] = float(report.get("total_xp", 0)) / float(runs) if runs > 0 else 0.0
	report["average_mobs_defeated"] = float(report.get("mobs_defeated", 0)) / float(runs) if runs > 0 else 0.0
	report["quest_completion_rate"] = float(report.get("completed_quests", 0)) / float(report.get("started_quests", 0)) if int(report.get("started_quests", 0)) > 0 else 0.0
	report["top_dominant_actions"] = _top_count_entries(report.get("dominant_actions", {}), top_limit)
	report["top_xp_skills"] = _top_count_entries(report.get("xp_by_skill", {}), top_limit)
	return report


func _quest_counts() -> Dictionary:
	var counts := {
		"started": 0,
		"completed": 0,
	}
	var quest_root = current_state.get("quest_state", {})
	if quest_root is Dictionary:
		var quest_states = quest_root.get("quests", {})
		if quest_states is Dictionary:
			for quest_id in quest_states.keys():
				var quest_state = quest_states[quest_id]
				if quest_state is Dictionary:
					if bool(quest_state.get("started", false)):
						counts["started"] = int(counts["started"]) + 1
					if bool(quest_state.get("completed", false)):
						counts["completed"] = int(counts["completed"]) + 1
	return counts


func _quest_flag_count() -> int:
	var total := 0
	for quest_id in _quest_states().keys():
		var quest_state = _quest_states()[quest_id]
		if quest_state is Dictionary:
			var flags = quest_state.get("flags", [])
			if flags is Array:
				total += flags.size()
	return total


func _quests_ready_to_return_count() -> int:
	var total := 0
	var states := _quest_states()
	for quest_id in states.keys():
		var quest_state = states[quest_id]
		var definition := _quest_definition(str(quest_id))
		if quest_state is Dictionary and not definition.is_empty() and _quest_ready_to_return(definition, quest_state):
			total += 1
	return total


func _status_effect_count() -> int:
	var combat = current_state.get("combat", {})
	if not (combat is Dictionary):
		return 0
	var status_effects = combat.get("status_effects", {})
	if not (status_effects is Dictionary):
		return 0
	return status_effects.size()


func _poison_status_count() -> int:
	return 1 if _has_poison_status() else 0


func _pick_resource(skill_id: String) -> Dictionary:
	var candidates := []
	for resource in resources:
		if not (resource is Dictionary):
			continue
		if not skill_id.is_empty() and str(resource.get("skill_id", "")) != skill_id:
			continue
		if _resource_is_reasonable(resource):
			candidates.append(resource)
	var probe_target := str(current_state.get("probe_target_resource_id", ""))
	if not probe_target.is_empty():
		for resource in candidates:
			if str(resource.get("id", "")) == probe_target:
				return resource
	return _random_entry(candidates, {})


func _resource_is_reasonable(resource: Dictionary) -> bool:
	if _resource_is_depleted_for_sim(resource):
		return false
	var skill_id := str(resource.get("skill_id", ""))
	if _skill_level(skill_id) < int(resource.get("required_level", 1)):
		return false
	var required_tool := _required_tool_id(skill_id)
	if not required_tool.is_empty() and int(_inventory().get(required_tool, 0)) <= 0:
		return false
	return _resource_reward_can_fit(resource)


func _resource_reward_can_fit(resource: Dictionary) -> bool:
	var add_items := {}
	var item_id := str(resource.get("item_reward", ""))
	var quantity := int(resource.get("quantity_reward", 1))
	if item_id.is_empty() or quantity <= 0:
		return false
	add_items[item_id] = quantity
	var secondary_item := str(resource.get("secondary_item_reward", ""))
	var secondary_quantity := int(resource.get("secondary_quantity_reward", 1))
	var secondary_chance := float(resource.get("secondary_drop_chance", 0.0))
	if not secondary_item.is_empty() and secondary_quantity > 0 and secondary_chance > 0.0:
		add_items[secondary_item] = int(add_items.get(secondary_item, 0)) + secondary_quantity
	return _inventory_can_transact_for_sim({}, add_items)


func _dialogue_action_blocked_for_sim() -> bool:
	# Dialogue can target any NPC in non-quest-chaser scenarios, so checking only
	# the active quest target cannot prove that the selected NPC is safe. A full
	# inventory is sufficient to make a quest-reward dialogue attempt an expected
	# block; recover space before selecting that action in the content campaign.
	return _inventory_slot_count(_inventory()) >= INVENTORY_SLOT_LIMIT


func _pick_mob() -> Dictionary:
	var alive := []
	var combat = current_state.get("combat", {})
	var mob_states := {}
	if combat is Dictionary and combat.get("mobs", {}) is Dictionary:
		mob_states = combat.get("mobs", {})
	for mob in mobs:
		if not (mob is Dictionary):
			continue
		if _mob_is_dead_for_sim(mob, mob_states):
			continue
		alive.append(mob)
	var probe_target := str(current_state.get("probe_target_mob_id", ""))
	if not probe_target.is_empty():
		for mob in alive:
			if mob is Dictionary and str(mob.get("id", "")) == probe_target:
				return mob
	alive.sort_custom(func(left, right) -> bool: return int(left.get("level", 1)) < int(right.get("level", 1)))
	if current_scenario == "random_guard" and current_rng.randf() < 0.35:
		return _random_entry(alive, {})
	return alive[0] if not alive.is_empty() else {}


func _mob_is_dead_for_sim(mob: Dictionary, mob_states: Dictionary) -> bool:
	var mob_id := str(mob.get("id", ""))
	var state_for_mob = mob_states.get(mob_id, {})
	if not (state_for_mob is Dictionary) or not bool(state_for_mob.get("dead", false)):
		return false
	if state_for_mob.has("respawn_at") and state_for_mob["respawn_at"] != null:
		var world_state = current_state.get("world", {})
		var now := float(world_state.get("action_clock_seconds", 0.0)) if world_state is Dictionary else 0.0
		return now < float(state_for_mob["respawn_at"])
	return true


func _pick_npc() -> Dictionary:
	var probe_target := str(current_state.get("probe_target_npc_id", ""))
	if not probe_target.is_empty():
		for npc in npcs:
			if npc is Dictionary and str(npc.get("id", "")) == probe_target:
				return npc
	if current_scenario == "quest_chaser":
		var active := _active_quest_target()
		if not active.is_empty():
			var quest_id := str(active.get("quest_id", ""))
			for npc in npcs:
				if npc is Dictionary and str(npc.get("quest_id", "")) == quest_id:
					return npc
		for npc in npcs:
			if not (npc is Dictionary):
				continue
			var quest_id := str(npc.get("quest_id", ""))
			if not quest_id.is_empty() and not bool(_quest_state(quest_id).get("completed", false)):
				return npc
	return _random_entry(npcs, {})


func _pick_shop_stock() -> Dictionary:
	if _combat_recovery_needed():
		var usable_stock := _pick_affordable_shop_usable()
		if not usable_stock.is_empty():
			return usable_stock
	var missing_tool_stock := _pick_affordable_missing_tool()
	if not missing_tool_stock.is_empty():
		return missing_tool_stock
	var affordable_stock := _pick_affordable_shop_item(func(_item_id: String, _stock: Dictionary, _definition) -> bool: return true)
	if not affordable_stock.is_empty():
		return affordable_stock
	var shop := _station("shop")
	var stock = shop.get("stock", [])
	if not (stock is Array) or stock.is_empty():
		return {}
	return _random_entry(stock, {})


func _pick_best_processing_station() -> Dictionary:
	if _has_raw_cookable_with_room():
		return _station("cooking_range")
	if _has_recipe_inputs_for_type_with_room("smelting"):
		return _station("furnace")
	if _has_recipe_inputs_for_type_with_room("smithing"):
		return _station("anvil")
	if _has_recipe_inputs_for_type_with_room("carpentry"):
		return _station("carpentry_bench")
	if _has_recipe_inputs_for_type_with_room("herbalism"):
		return _station("apothecary_table")
	var processing := [
		_station("cooking_range"),
		_station("furnace"),
		_station("anvil"),
		_station("carpentry_bench"),
		_station("apothecary_table"),
	]
	return _random_entry(processing, {})


func _pick_examinable_object() -> Dictionary:
	var all_objects := []
	all_objects.append_array(resources)
	all_objects.append_array(mobs)
	all_objects.append_array(npcs)
	for station in stations.values():
		if station is Dictionary:
			all_objects.append(station)
	var probe_target := str(current_state.get("probe_target_examine_object_id", ""))
	if not probe_target.is_empty():
		for object_data in all_objects:
			if object_data is Dictionary and str(object_data.get("id", "")) == probe_target:
				return object_data
	return _random_entry(all_objects, {})


func _station(station_key: String) -> Dictionary:
	var station = stations.get(station_key, {})
	if station is Dictionary:
		return station
	return {}


func _first_ground_item(pickable_only: bool = false) -> Dictionary:
	var drops := _ground_items()
	if drops.is_empty():
		return {}
	var item = _first_pickable_ground_item() if pickable_only else drops[0]
	if item is Dictionary:
		var data: Dictionary = item.duplicate(true)
		data["type"] = "ground_item"
		data["id"] = str(data.get("object_id", "ground_item"))
		data["label"] = "%d %s" % [int(data.get("quantity", 1)), str(data.get("item_id", "item")).replace("_", " ")]
		if not data.has("tile"):
			data["tile"] = _player_tile()
		return data
	return {}


func _first_pickable_ground_item() -> Dictionary:
	for item in _ground_items():
		if item is Dictionary and _ground_item_can_fit(item):
			return item
	return {}


func _ground_item_can_fit(item: Dictionary) -> bool:
	return _can_add_inventory_item(str(item.get("item_id", "")), int(item.get("quantity", 1)))


func _first_depositable_item() -> String:
	for item_id in _sorted_keys(_inventory()):
		var item_key := str(item_id)
		if item_key != "coins" and int(_inventory().get(item_id, 0)) > 0 and not _is_protected_gathering_tool(item_key):
			if _quest_policy_protects_item(item_key):
				_add_telemetry_int(current_run_telemetry, "quest_policy_protected_item_skips", 1)
				_increment_count(current_run_telemetry.get("quest_policy_protected_item_counts", {}), item_key)
				continue
			return item_key
	return ""


func _first_bank_item() -> String:
	if _combat_recovery_needed():
		var usable_item := _first_bank_usable_item()
		if not usable_item.is_empty():
			return usable_item
	if _quest_policy_active() and not current_quest_policy_target_item.is_empty() and int(_bank().get(current_quest_policy_target_item, 0)) > 0 and _can_add_inventory_item(current_quest_policy_target_item):
		return current_quest_policy_target_item
	for item_id in _sorted_keys(_bank()):
		if int(_bank().get(item_id, 0)) > 0 and _can_add_inventory_item(str(item_id)):
			return str(item_id)
	return ""


func _first_sellable_item() -> String:
	for item_id in _sorted_keys(_inventory()):
		if str(item_id) == "coins":
			continue
		var definition = items_data.get(str(item_id), {})
		if _quest_needs_food_item(str(item_id), definition):
			continue
		var item_key := str(item_id)
		if definition is Dictionary and int(definition.get("sell_price", 0)) > 0 and int(_inventory().get(item_id, 0)) > 0 and not _is_protected_gathering_tool(item_key):
			if _quest_policy_protects_item(item_key):
				_add_telemetry_int(current_run_telemetry, "quest_policy_protected_item_skips", 1)
				_increment_count(current_run_telemetry.get("quest_policy_protected_item_counts", {}), item_key)
				continue
			return item_key
	return ""


func _first_usable_item() -> String:
	for item_id in _sorted_keys(_inventory()):
		var definition = items_data.get(str(item_id), {})
		if definition is Dictionary and _item_is_useful_now(str(item_id), definition) and int(_inventory().get(item_id, 0)) > 0:
			return str(item_id)
	return ""


func _first_equippable_item() -> String:
	for item_id in _sorted_keys(_inventory()):
		var definition = items_data.get(str(item_id), {})
		if definition is Dictionary and definition.has("equip_slot") and int(_inventory().get(item_id, 0)) > 0:
			var slot := str(definition.get("equip_slot", ""))
			if str(_equipment().get(slot, "")) == str(item_id):
				continue
			return str(item_id)
	return ""


func _first_droppable_item() -> String:
	for item_id in _sorted_keys(_inventory()):
		var item_key := str(item_id)
		if int(_inventory().get(item_id, 0)) > 0:
			if _quest_policy_protects_item(item_key):
				_add_telemetry_int(current_run_telemetry, "quest_policy_protected_item_skips", 1)
				_increment_count(current_run_telemetry.get("quest_policy_protected_item_counts", {}), item_key)
				continue
			return item_key
	return ""


func _bank_quantity() -> int:
	if _quest_policy_active() and current_quest_policy_target_quantity > 0:
		return current_quest_policy_target_quantity
	return 0 if current_rng.randf() < 0.25 else 1


func _active_quest_target() -> Dictionary:
	var quest_root = current_state.get("quest_state", {})
	if quest_root is Dictionary:
		var active_id := str(quest_root.get("active_quest_id", ""))
		if not active_id.is_empty():
			var active_state := _quest_state(active_id)
			var definition := _quest_definition(active_id)
			if not definition.is_empty() and not bool(active_state.get("completed", false)):
				return definition
	var definitions := _quest_definitions()
	for npc in npcs:
		if not (npc is Dictionary):
			continue
		var quest_id := str(npc.get("quest_id", ""))
		if definitions.has(quest_id) and not bool(_quest_state(quest_id).get("completed", false)):
			return definitions[quest_id]
	return {}


func _missing_flags(quest_definition: Dictionary) -> Array:
	var quest_id := str(quest_definition.get("quest_id", ""))
	var state := _quest_state(quest_id)
	if state.is_empty() or not bool(state.get("started", false)):
		return ["talk_to_npc"]
	var flags := _as_array(state.get("flags", []))
	var missing := []
	for objective in _as_array(quest_definition.get("objectives", [])):
		if objective is Dictionary:
			var flag := str(objective.get("flag", ""))
			if not flag.is_empty() and not flags.has(flag):
				missing.append(flag)
	return missing


func _quest_definition(quest_id: String) -> Dictionary:
	for quest in _as_array(quests_data.get("quests", [])):
		if quest is Dictionary and str(quest.get("quest_id", "")) == quest_id:
			return quest
	return {}


func _quest_definitions() -> Dictionary:
	var definitions := {}
	for quest in _as_array(quests_data.get("quests", [])):
		if quest is Dictionary:
			definitions[str(quest.get("quest_id", ""))] = quest
	return definitions


func _quest_state(quest_id: String) -> Dictionary:
	var quest_root = current_state.get("quest_state", {})
	if quest_root is Dictionary:
		var quest_states = quest_root.get("quests", {})
		if quest_states is Dictionary:
			var state = quest_states.get(quest_id, {})
			if state is Dictionary:
				return state
	return {}


func _has_recipe_inputs_for_type(action_type: String) -> bool:
	var recipes = recipes_data.get(action_type, [])
	if not (recipes is Array):
		return false
	for recipe in recipes:
		if recipe is Dictionary and _has_recipe_inputs(recipe):
			return true
	return false


func _has_recipe_inputs_for_type_with_room(action_type: String) -> bool:
	var recipes = recipes_data.get(action_type, [])
	if not (recipes is Array):
		return false
	for recipe in recipes:
		if not (recipe is Dictionary) or not _has_recipe_inputs(recipe):
			continue
		return _recipe_can_complete_now_for_sim(action_type, recipe)
	return false


func _has_recipe_inputs(recipe: Dictionary) -> bool:
	var inputs = recipe.get("inputs", {})
	if not (inputs is Dictionary):
		return false
	for item_id in inputs.keys():
		if int(_inventory().get(str(item_id), 0)) < int(inputs[item_id]):
			return false
	return true


func _has_recipe_inputs_with_room(recipe: Dictionary) -> bool:
	if not _has_recipe_inputs(recipe):
		return false
	return _recipe_inventory_output_fits_for_sim(recipe)


func _recipe_can_complete_now_for_sim(action_type: String, recipe: Dictionary) -> bool:
	var skill_id := str(PROCESSING_SKILLS.get(action_type, action_type))
	if _skill_level(skill_id) < int(recipe.get("required_level", 1)):
		return false
	return _recipe_inventory_output_fits_for_sim(recipe)


func _recipe_inventory_output_fits_for_sim(recipe: Dictionary) -> bool:
	var output_item := str(recipe.get("output_item_id", ""))
	var output_quantity := int(recipe.get("output_quantity", 1))
	if output_item.is_empty():
		return false
	var inputs = recipe.get("inputs", {})
	return inputs is Dictionary and _inventory_can_transact_for_sim(inputs, {output_item: output_quantity})


func _has_raw_cookable() -> bool:
	for item_id in _inventory().keys():
		var definition = items_data.get(str(item_id), {})
		if definition is Dictionary and definition.has("cook_result") and int(_inventory().get(item_id, 0)) > 0:
			return true
	return false


func _has_raw_cookable_with_room() -> bool:
	for item_id in _inventory().keys():
		var definition = items_data.get(str(item_id), {})
		if not (definition is Dictionary) or not definition.has("cook_result") or int(_inventory().get(item_id, 0)) <= 0:
			continue
		if _skill_level("cooking") < int(definition.get("cooking_required_level", 1)):
			return false
		var cooked_item := str(definition.get("cook_result", ""))
		return not cooked_item.is_empty() and _inventory_can_transact_for_sim({str(item_id): 1}, {cooked_item: 1})
	return false


func _has_usable_item() -> bool:
	return not _first_usable_item().is_empty()


func _needs_healing() -> bool:
	return _current_hitpoints() < _skill_level("hitpoints")


func _combat_recovery_needed() -> bool:
	var max_hitpoints := _skill_level("hitpoints")
	var recovery_threshold: int = max(3, int(ceil(float(max_hitpoints) * 0.35)))
	return _current_hitpoints() <= recovery_threshold


func _has_bank_item_matching(predicate: Callable) -> bool:
	return not _first_bank_item_matching(predicate).is_empty()


func _first_bank_item_matching(predicate: Callable) -> String:
	for item_id in _sorted_keys(_bank()):
		var id := str(item_id)
		var definition = items_data.get(id, {})
		if int(_bank().get(id, 0)) > 0 and _can_add_inventory_item(id) and predicate.call(id, definition):
			return id
	return ""


func _first_bank_usable_item() -> String:
	return _first_bank_item_matching(func(item_id: String, definition) -> bool: return _item_is_recovery_item(item_id, definition))


func _can_afford_shop_item(predicate: Callable) -> bool:
	return not _pick_affordable_shop_item(predicate).is_empty()


func _pick_affordable_shop_usable() -> Dictionary:
	return _pick_affordable_shop_item(func(item_id: String, _stock: Dictionary, definition) -> bool: return _item_is_recovery_item(item_id, definition))


func _pick_affordable_missing_tool() -> Dictionary:
	return _pick_affordable_shop_item(func(item_id: String, _stock: Dictionary, _definition) -> bool:
		return item_id in [_required_tool_id("woodcutting"), _required_tool_id("mining"), _required_tool_id("fishing")] and int(_inventory().get(item_id, 0)) <= 0
	)


func _is_protected_gathering_tool(item_id: String) -> bool:
	if int(_inventory().get(item_id, 0)) > 1:
		return false
	var definition = items_data.get(item_id, {})
	return definition is Dictionary and not str(definition.get("tool_for", "")).is_empty()


func _pick_affordable_shop_item(predicate: Callable) -> Dictionary:
	var candidates := []
	var shop := _station("shop")
	var stock = shop.get("stock", [])
	if not (stock is Array):
		return {}
	for raw_stock in stock:
		if not (raw_stock is Dictionary):
			continue
		var item_id := str(raw_stock.get("item_id", ""))
		var price := int(raw_stock.get("price", 0))
		var definition = items_data.get(item_id, {})
		if item_id.is_empty() or price <= 0:
			continue
		if int(_inventory().get("coins", 0)) < price:
			continue
		if not _can_add_inventory_item(item_id):
			continue
		if predicate.call(item_id, raw_stock, definition):
			candidates.append(raw_stock)
	return _random_entry(candidates, {})


func _has_depositable_item() -> bool:
	return not _first_depositable_item().is_empty()


func _has_withdrawable_item() -> bool:
	return not _first_bank_item().is_empty()


func _has_sellable_item() -> bool:
	return not _first_sellable_item().is_empty()


func _has_equippable_item() -> bool:
	return not _first_equippable_item().is_empty()


func _has_droppable_item() -> bool:
	return not _first_droppable_item().is_empty()


func _has_useful_processing_input() -> bool:
	return _has_raw_cookable() or _has_recipe_inputs_for_type("smelting") or _has_recipe_inputs_for_type("smithing") or _has_recipe_inputs_for_type("carpentry") or _has_recipe_inputs_for_type("herbalism")


func _has_useful_processing_input_with_room() -> bool:
	return _has_raw_cookable_with_room() or _has_recipe_inputs_for_type_with_room("smelting") or _has_recipe_inputs_for_type_with_room("smithing") or _has_recipe_inputs_for_type_with_room("carpentry") or _has_recipe_inputs_for_type_with_room("herbalism")


func _processing_input_action() -> String:
	if _has_recipe_inputs_for_type("smelting") or _has_recipe_inputs_for_type("smithing"):
		return "process_station"
	if _has_raw_cookable():
		return "cook"
	if _skill_level("mining") >= 1:
		return "gather_mining"
	if _skill_level("woodcutting") >= 1:
		return "gather_woodcutting"
	return "gather_resource"


func _action_has_valid_target(action_name: String) -> bool:
	match action_name:
		"gather_resource":
			return not _pick_resource("").is_empty()
		"gather_woodcutting":
			return not _pick_resource("woodcutting").is_empty()
		"gather_mining":
			return not _pick_resource("mining").is_empty()
		"gather_fishing":
			return not _pick_resource("fishing").is_empty()
		"process_station":
			return _has_useful_processing_input_with_room()
		"process_furnace":
			return _has_recipe_inputs_for_type_with_room("smelting")
		"process_anvil":
			return _has_recipe_inputs_for_type_with_room("smithing")
		"process_carpentry":
			return _has_recipe_inputs_for_type_with_room("carpentry")
		"process_apothecary":
			return _has_recipe_inputs_for_type_with_room("herbalism")
		"cook":
			return _has_raw_cookable_with_room()
		"attack_mob":
			return not _pick_mob().is_empty() and not _combat_recovery_needed()
		"pickup_drop":
			return not _first_pickable_ground_item().is_empty()
		"talk_npc", "dialogue_action":
			return not _pick_npc().is_empty()
		"open_bank":
			return not _station("bank").is_empty()
		"bank_deposit":
			return _has_depositable_item()
		"bank_withdraw":
			return _has_withdrawable_item()
		"open_shop":
			return not _station("shop").is_empty()
		"shop_buy":
			return _can_afford_shop_item(func(_item_id: String, _stock: Dictionary, _definition) -> bool: return true)
		"shop_sell":
			return _has_sellable_item()
		"use_item":
			return _has_usable_item()
		"equip_item":
			return _has_equippable_item()
		"drop_item":
			return _has_droppable_item()
		"examine_object":
			return not _pick_examinable_object().is_empty()
	return false


func _inventory() -> Dictionary:
	var inventory = current_state.get("inventory", {})
	if inventory is Dictionary:
		return inventory
	return {}


func _bank() -> Dictionary:
	var bank = current_state.get("bank", {})
	if bank is Dictionary:
		return bank
	return {}


func _ground_items() -> Array:
	var combat = current_state.get("combat", {})
	if combat is Dictionary:
		var drops = combat.get("ground_items", [])
		if drops is Array:
			return drops
	return []


func _player_tile() -> Vector2i:
	var player = current_state.get("player", {})
	if player is Dictionary:
		return _array_to_tile(player.get("tile", [15, 15]), Vector2i(15, 15))
	return Vector2i(15, 15)


func _tile_key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


func _current_hitpoints() -> int:
	var combat = current_state.get("combat", {})
	if combat is Dictionary:
		return int(combat.get("current_hitpoints", _skill_level("hitpoints")))
	return _skill_level("hitpoints")


func _skill_level(skill_id: String) -> int:
	var skills = current_state.get("skills", {})
	if skills is Dictionary:
		var skill = skills.get(skill_id, {})
		if skill is Dictionary:
			return int(skill.get("level", 10 if skill_id == "hitpoints" else 1))
	return 10 if skill_id == "hitpoints" else 1


func _total_xp() -> int:
	var total := 0
	var skills = current_state.get("skills", {})
	if skills is Dictionary:
		for skill in skills.values():
			if skill is Dictionary:
				total += int(skill.get("xp", 0))
	return total


func _xp_by_skill() -> Dictionary:
	var result := {}
	var skills = current_state.get("skills", {})
	if skills is Dictionary:
		for skill_id in skills.keys():
			var skill = skills[skill_id]
			if skill is Dictionary:
				result[str(skill_id)] = int(skill.get("xp", 0))
	return result


func _equipment() -> Dictionary:
	var equipment = current_state.get("equipment", {})
	if equipment is Dictionary:
		return equipment
	return {}


func _mapping_sell_value(mapping: Dictionary) -> int:
	var total := 0
	for item_id in mapping.keys():
		if str(item_id) == "coins":
			continue
		total += _item_sell_value(str(item_id)) * int(mapping[item_id])
	return total


func _equipment_sell_value() -> int:
	var total := 0
	for item_id in _equipment().values():
		if str(item_id).is_empty():
			continue
		total += _item_sell_value(str(item_id))
	return total


func _ground_items_sell_value() -> int:
	var total := 0
	for drop in _ground_items():
		if not (drop is Dictionary):
			continue
		total += _item_sell_value(str(drop.get("item_id", ""))) * int(drop.get("quantity", 1))
	return total


func _ground_items_quantity() -> int:
	var total := 0
	for drop in _ground_items():
		if drop is Dictionary:
			total += int(drop.get("quantity", 1))
	return total


func _high_value_item_count() -> int:
	var total := 0
	total += _high_value_mapping_count(_inventory())
	total += _high_value_mapping_count(_bank())
	for item_id in _equipment().values():
		if _item_sell_value(str(item_id)) >= 100:
			total += 1
	for drop in _ground_items():
		if drop is Dictionary and _item_sell_value(str(drop.get("item_id", ""))) >= 100:
			total += int(drop.get("quantity", 1))
	return total


func _high_value_mapping_count(mapping: Dictionary) -> int:
	var total := 0
	for item_id in mapping.keys():
		if _item_sell_value(str(item_id)) >= 100:
			total += int(mapping[item_id])
	return total


func _item_sell_value(item_id: String) -> int:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary:
		return int(definition.get("sell_price", 0))
	return 0


func _mobs_defeated_count() -> int:
	var defeated := 0
	var combat = current_state.get("combat", {})
	if not (combat is Dictionary):
		return defeated
	var mob_states = combat.get("mobs", {})
	if not (mob_states is Dictionary):
		return defeated
	for mob_state in mob_states.values():
		if mob_state is Dictionary and bool(mob_state.get("dead", false)):
			defeated += 1
	return defeated


func _inventory_slot_count(mapping: Dictionary) -> int:
	var total := 0
	for item_id in mapping.keys():
		var quantity := int(mapping[item_id])
		if quantity <= 0:
			continue
		if _is_stackable_item(str(item_id)):
			total += 1
		else:
			total += quantity
	return total


func _is_stackable_item(item_id: String) -> bool:
	var definition = items_data.get(item_id, {})
	if definition is Dictionary and definition.has("stackable"):
		return bool(definition["stackable"])
	return item_id == "coins"


func _can_add_inventory_item(item_id: String, quantity: int = 1) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	if _is_stackable_item(item_id) and int(_inventory().get(item_id, 0)) > 0:
		return true
	var added_slots := 1 if _is_stackable_item(item_id) else quantity
	return _inventory_slot_count(_inventory()) + added_slots <= INVENTORY_SLOT_LIMIT


func _inventory_can_transact_for_sim(remove_items: Dictionary, add_items: Dictionary) -> bool:
	var projected := _inventory().duplicate(true)
	for item_id in remove_items.keys():
		var id := str(item_id)
		if id.is_empty():
			return false
		var remove_quantity := int(remove_items[item_id])
		if remove_quantity < 0:
			return false
		var remaining := int(projected.get(id, 0)) - remove_quantity
		if remaining < 0:
			return false
		if remaining > 0:
			projected[id] = remaining
		else:
			projected.erase(id)
	for item_id in add_items.keys():
		var id := str(item_id)
		if id.is_empty():
			return false
		var add_quantity := int(add_items[item_id])
		if add_quantity < 0:
			return false
		if add_quantity == 0:
			continue
		if not _mapping_can_add_for_sim(projected, id, add_quantity):
			return false
		projected[id] = int(projected.get(id, 0)) + add_quantity
	return true


func _mapping_can_add_for_sim(mapping: Dictionary, item_id: String, quantity: int) -> bool:
	if quantity <= 0:
		return true
	if _is_stackable_item(item_id) and int(mapping.get(item_id, 0)) > 0:
		return true
	var added_slots := 1 if _is_stackable_item(item_id) else quantity
	return _inventory_slot_count(mapping) + added_slots <= INVENTORY_SLOT_LIMIT


func _item_is_useful_now(item_id: String, definition) -> bool:
	if not (definition is Dictionary):
		return false
	var can_heal := int(definition.get("heal_amount", 0)) > 0 and _needs_healing()
	var can_cleanse := bool(definition.get("cleanses_poison", false)) and _has_poison_status()
	return int(_inventory().get(item_id, 0)) > 0 and (can_heal or can_cleanse or _quest_needs_food_item(item_id, definition))


func _quest_needs_food_item(_item_id: String, definition) -> bool:
	if current_scenario != "quest_chaser" or not (definition is Dictionary):
		return false
	if int(definition.get("heal_amount", 0)) <= 0:
		return false
	var target := _active_quest_target()
	return not target.is_empty() and _missing_flags(target).has("ate_food")


func _item_is_recovery_item(_item_id: String, definition) -> bool:
	if not (definition is Dictionary):
		return false
	return int(definition.get("heal_amount", 0)) > 0 or bool(definition.get("cleanses_poison", false))


func _has_poison_status() -> bool:
	var combat = current_state.get("combat", {})
	if not (combat is Dictionary):
		return false
	var status_effects = combat.get("status_effects", {})
	if not (status_effects is Dictionary):
		return false
	for key in status_effects.keys():
		if str(key).find("poison") != -1:
			return true
	return false


func _resource_is_depleted_for_sim(resource: Dictionary) -> bool:
	var node_id := str(resource.get("id", ""))
	if node_id.is_empty():
		return false
	var world_state = current_state.get("world", {})
	if not (world_state is Dictionary):
		return false
	var nodes = world_state.get("resource_nodes", {})
	if not (nodes is Dictionary) or not nodes.has(node_id):
		return false
	var node_state = nodes[node_id]
	if not (node_state is Dictionary) or not bool(node_state.get("depleted", false)):
		return false
	if node_state.has("respawn_at") and node_state["respawn_at"] != null:
		return float(world_state.get("action_clock_seconds", 0.0)) < float(node_state["respawn_at"])
	return true


func _required_tool_id(skill_id: String) -> String:
	match skill_id:
		"woodcutting":
			return "bronze_axe"
		"mining":
			return "bronze_pickaxe"
		"fishing":
			return "fishing_rod"
	return ""


func _feedback_text() -> String:
	if current_hud == null:
		return ""
	var node := current_hud.get_node_or_null("Root/Feedback")
	if node is Label:
		return str(node.text)
	return ""


func _interaction_panel_snapshot() -> Dictionary:
	var snapshot := {
		"visible": false,
		"title": "",
		"rows": 0,
		"buttons": 0,
		"lightweight_mode": false,
	}
	if current_hud == null:
		return snapshot
	var lightweight_mode = current_hud.get("simulation_lightweight_mode")
	snapshot["lightweight_mode"] = bool(lightweight_mode)
	if current_hud.has_method("interaction_panel_is_visible"):
		snapshot["visible"] = bool(current_hud.call("interaction_panel_is_visible"))
	if current_hud.has_method("interaction_panel_title_text"):
		snapshot["title"] = str(current_hud.call("interaction_panel_title_text"))
	if current_hud.has_method("interaction_panel_row_count"):
		snapshot["rows"] = int(current_hud.call("interaction_panel_row_count"))
	var panel := current_hud.get_node_or_null("Root/InteractionPanel")
	if panel != null:
		snapshot["buttons"] = _count_buttons(panel)
	return snapshot


func _count_buttons(node: Node) -> int:
	var count := 1 if node is Button else 0
	for child in node.get_children():
		if child is Node:
			count += _count_buttons(child)
	return count


func _quest_states() -> Dictionary:
	var quest_root = current_state.get("quest_state", {})
	if quest_root is Dictionary:
		var states = quest_root.get("quests", {})
		if states is Dictionary:
			return states
	return {}


func _active_quest_id() -> String:
	var quest_root = current_state.get("quest_state", {})
	if quest_root is Dictionary:
		return str(quest_root.get("active_quest_id", ""))
	return ""


func _quest_objective_for_polish(definition: Dictionary, quest_state: Dictionary) -> String:
	if bool(quest_state.get("completed", false)):
		return str(definition.get("completed_objective", "Quest complete."))
	if not bool(quest_state.get("started", false)):
		return str(definition.get("not_started_objective", "Talk to the quest giver."))
	if _quest_ready_to_return(definition, quest_state):
		return str(definition.get("return_objective", "Return to the quest giver."))
	var objectives = definition.get("objectives", [])
	var flags = quest_state.get("flags", [])
	if not (objectives is Array) or not (flags is Array):
		return str(definition.get("return_objective", "Return to the quest giver."))
	for objective in objectives:
		if not (objective is Dictionary):
			continue
		var flag := str(objective.get("flag", ""))
		if not flag.is_empty() and flag not in flags:
			return str(objective.get("description", definition.get("return_objective", "Return to the quest giver.")))
	return str(definition.get("return_objective", "Return to the quest giver."))


func _quest_ready_to_return(definition: Dictionary, quest_state: Dictionary) -> bool:
	if not bool(quest_state.get("started", false)) or bool(quest_state.get("completed", false)):
		return false
	var objectives = definition.get("objectives", [])
	var flags = quest_state.get("flags", [])
	if not (objectives is Array) or not (flags is Array):
		return false
	for objective in objectives:
		if not (objective is Dictionary):
			continue
		var flag := str(objective.get("flag", ""))
		if not flag.is_empty() and flag not in flags:
			return false
	return true


func _is_failure_feedback(feedback: String) -> bool:
	var lower := feedback.to_lower()
	for marker in FAILURE_MARKERS:
		if lower.find(str(marker)) != -1:
			return true
	return false


func _feedback_explains_failure(feedback: String) -> bool:
	var lower := feedback.to_lower()
	var explanation_markers := [
		"need",
		"requires",
		"require",
		"level",
		"inventory",
		"bank",
		"coins",
		"coin",
		"full",
		"empty",
		"select",
		"choose",
		"return",
		"too wounded",
		"no path",
		"depleted",
		"not enough",
		"already",
	]
	for marker in explanation_markers:
		if lower.find(str(marker)) != -1:
			return true
	return false


func _state_digest() -> String:
	return _state_digest_with_position(true)


func _gameplay_state_digest() -> String:
	return _state_digest_with_position(false)


func _state_digest_with_position(include_player_tile: bool) -> String:
	var quest_root = current_state.get("quest_state", {})
	var combat = current_state.get("combat", {})
	var world_state = current_state.get("world", {})
	var digest := {
		"inventory": _normalize_value(_inventory()),
		"bank": _normalize_value(_bank()),
		"equipment": _normalize_value(current_state.get("equipment", {})),
		"skills": _normalize_value(current_state.get("skills", {})),
		"quest_state": _normalize_value(quest_root),
		"combat": _normalize_value(combat),
		"world": _normalize_value(world_state),
	}
	if include_player_tile:
		digest["player_tile"] = [_player_tile().x, _player_tile().y]
	return JSON.stringify(digest)


func _file_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	return FileAccess.get_file_as_string(path).sha256_text()


func _combined_hash(values: Array) -> String:
	var pieces := PackedStringArray()
	for value in values:
		pieces.append(str(value))
	pieces.sort()
	return "|".join(pieces).sha256_text()


func _godot_version_text() -> String:
	var version := Engine.get_version_info()
	if not (version is Dictionary):
		return ""
	return "%s.%s.%s-%s" % [
		str(version.get("major", "")),
		str(version.get("minor", "")),
		str(version.get("patch", "")),
		str(version.get("status", "")),
	]


func _normalize_value(value):
	if value is Dictionary:
		var clean := {}
		for key in _sorted_keys(value):
			clean[str(key)] = _normalize_value(value[key])
		return clean
	if value is Array:
		var clean_array := []
		for item in value:
			clean_array.append(_normalize_value(item))
		return clean_array
	if value is Vector2i:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is float and is_equal_approx(value, round(value)):
		return int(round(value))
	return value


func _sorted_keys(mapping) -> Array:
	if not (mapping is Dictionary):
		return []
	var keys := []
	for key in mapping.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func _write_json_line(file: FileAccess, value: Dictionary) -> void:
	if file == null:
		return
	file.store_line(JSON.stringify(_normalize_value(value)))
	file.flush()


func _load_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	push_error("Could not parse JSON file: %s" % path)
	return {}


func _as_array(value) -> Array:
	if value is Array:
		return value
	return []


func _array_to_tile(value, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


func _random_entry(values: Array, fallback):
	if values.is_empty():
		return fallback
	return values[current_rng.randi_range(0, values.size() - 1)]


func _display_label(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _issue_id(group_key: String) -> String:
	return "sim_%d" % abs(group_key.hash())


func _replay_command(seed: int, scenario: String) -> String:
	return "& 'C:\\Users\\donny\\Desktop\\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/playtest_simulation_runner.gd --log-file .godot_logs\\playtest_replay.log -- --runs 1 --steps %d --seed %d --scenario %s --trace all" % [
		int(config["steps"]),
		seed,
		scenario,
	]
