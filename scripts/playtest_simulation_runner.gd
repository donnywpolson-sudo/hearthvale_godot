extends SceneTree

const WORLD_PATH := "res://data/world.json"
const ITEMS_PATH := "res://data/items.json"
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
const DEFAULT_TIMEOUT_SECONDS := 7200.0
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

	var watchdog := create_timer(float(config["timeout_seconds"]))
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale playtest simulation timed out.")
		_close_outputs()
		quit(1)
	)

	_load_data()
	_discover_content()
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
		var run_summary := await _run_single_simulation(run_index)
		run_summaries.append(run_summary)
		_write_json_line(runs_file, run_summary)
		_update_scenario_metrics(run_summary)
		_update_telemetry_summary(run_summary)
		_update_polish_telemetry_summary(run_summary)

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

	print("Hearthvale playtest simulation completed: %d runs, %d issue occurrences, %d issue samples." % [
		int(config["runs"]),
		issue_occurrence_count,
		issue_sample_count,
	])
	print("Trust: %s, %s, implementation_ready=%s, latest_publish_status=%s" % [
		str(trust_context.get("run_strength", "")),
		str(trust_context.get("coverage_scope", "")),
		str(trust_context.get("implementation_ready", false)),
		str(trust_context.get("latest_publish_status", "")),
	])
	print("Simulation reports written to %s" % str(config["output_dir"]))
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


func _print_usage() -> void:
	print("Usage: -- --runs 1000 --steps 300 --seed 1 --scenario all --trace issues --balance-profile default --output-dir res://.godot_logs/simulation --publish-latest --public-output-root res://.godot/ai_simulation --timeout-seconds 7200")
	print("Scenarios: all, %s" % ", ".join(SCENARIOS))
	print("Balance profiles: %s" % ", ".join(_balance_profile_ids()))
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
	if float(config["timeout_seconds"]) <= 0.0:
		push_error("--timeout-seconds must be positive.")
		return false
	return true


func _load_data() -> void:
	world_data = _load_json(WORLD_PATH)
	items_data = _load_json(ITEMS_PATH)
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
	var raw_percent := int(floor(float(progress.get("percent", 0.0))))
	var percent_int: int = clamp(raw_percent, 0, 100)
	if percent_int <= last_progress_percent_printed:
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
		eta_text = "%ds" % eta_seconds
	print("PROGRESS [%s] %d%% %d/%d runs elapsed %ds ETA %s" % [
		bar,
		percent_int,
		completed_runs,
		int(progress.get("runs", 1)),
		int(progress.get("elapsed_seconds", 0)),
		eta_text,
	])


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
	var path := "%s/latest/ai_simulation_latest.json" % str(config.get("public_output_root", DEFAULT_PUBLIC_OUTPUT_ROOT))
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
		print("WARNING: lower-coverage output was not published to latest.")
		return not bool(config.get("require_publish_latest", false))

	var output_dir := str(config["output_dir"])
	var public_root := str(config.get("public_output_root", DEFAULT_PUBLIC_OUTPUT_ROOT))
	var latest_dir := "%s/latest" % public_root
	var archive_root := "%s/archive" % public_root
	var staging_root := "%s/_staging" % public_root
	var stamp := _archive_timestamp()
	var archive_dir := _unique_dir_path("%s/%s" % [archive_root, stamp])
	var staging_dir := _unique_dir_path("%s/latest_%s" % [staging_root, stamp])

	if not _ensure_dir(public_root) or not _ensure_dir(archive_root) or not _ensure_dir(staging_root):
		return false
	if not _ensure_dir(staging_dir):
		return false

	var public_files := [
		{
			"source": "%s/summary.json" % output_dir,
			"target": "%s/ai_simulation_latest.json" % staging_dir,
		},
		{
			"source": "%s/improvement_plan.md" % output_dir,
			"target": "%s/ai_simulation_latest.md" % staging_dir,
		},
		{
			"source": "%s/codex_prompt.md" % output_dir,
			"target": "%s/ai_simulation_latest_codex_prompt.md" % staging_dir,
		},
		{
			"source": "%s/polish_telemetry.json" % output_dir,
			"target": "%s/ai_simulation_latest_polish_telemetry.json" % staging_dir,
		},
		{
			"source": "%s/manual_polish_review.md" % output_dir,
			"target": "%s/ai_simulation_latest_manual_polish_review.md" % staging_dir,
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

	if _dir_exists(latest_dir):
		var previous_latest_dir := "%s/previous_latest" % archive_dir
		if not _rename_dir(latest_dir, previous_latest_dir):
			return false

	if not _rename_dir(staging_dir, latest_dir):
		return false

	print("Published AI simulation latest outputs to %s" % public_root)
	if str(latest_publish_status) == "published_allowed_downgrade":
		print("WARNING: latest was replaced by lower-coverage output. Use archive for the stronger previous run.")
	return true


func _archive_timestamp() -> String:
	var time := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [
		int(time.get("year", 0)),
		int(time.get("month", 0)),
		int(time.get("day", 0)),
		int(time.get("hour", 0)),
		int(time.get("minute", 0)),
		int(time.get("second", 0)),
	]


func _unique_dir_path(base_path: String) -> String:
	if not _dir_exists(base_path):
		return base_path
	var suffix := 2
	while _dir_exists("%s_%d" % [base_path, suffix]):
		suffix += 1
	return "%s_%d" % [base_path, suffix]


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
	current_run_telemetry["runs"] = 1
	current_run_telemetry["seed"] = current_seed
	current_run_telemetry["run_index"] = current_run_index
	current_run_telemetry["scenario"] = current_scenario
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
	current_gameplay = preload("res://scripts/gameplay_core.gd").new()
	root.add_child(current_world)
	root.add_child(current_hud)
	root.add_child(current_gameplay)
	await process_frame
	current_hud.bind_state(current_state)
	current_world.initialize_from_state(current_state)
	current_gameplay.setup(current_state, current_world, current_hud)

	var first_digest := _state_digest()
	var initial_summary := StateSnapshot.summarize_state(current_state)
	for step in range(int(config["steps"])):
		current_step = step
		var action_name := _resolve_action_preconditions(_choose_action(current_scenario, step), step)
		var before_digest := _state_digest()
		var before_feedback := _feedback_text()
		var before_hitpoints := _current_hitpoints()
		var before_coins := int(_inventory().get("coins", 0))
		var before_quest_counts := _quest_counts()
		var before_tile := _player_tile()
		var started_usec := Time.get_ticks_usec()
		var action_record := _execute_action(action_name)
		var after_feedback := _feedback_text()
		var after_digest := _state_digest()
		var after_hitpoints := _current_hitpoints()
		var after_coins := int(_inventory().get("coins", 0))
		var after_quest_counts := _quest_counts()
		var after_tile := _player_tile()
		action_record["feedback"] = after_feedback
		action_record["previous_feedback"] = before_feedback
		action_record["changed_state"] = before_digest != after_digest
		action_record["inventory_slots"] = _inventory_slot_count(_inventory())
		action_record["hitpoints"] = after_hitpoints
		action_record["hitpoints_before"] = before_hitpoints
		action_record["damage_taken"] = max(0, before_hitpoints - after_hitpoints)
		action_record["healing_done"] = max(0, after_hitpoints - before_hitpoints)
		action_record["coin_delta"] = after_coins - before_coins
		action_record["started_quest_delta"] = int(after_quest_counts.get("started", 0)) - int(before_quest_counts.get("started", 0))
		action_record["completed_quest_delta"] = int(after_quest_counts.get("completed", 0)) - int(before_quest_counts.get("completed", 0))
		action_record["from_tile"] = [before_tile.x, before_tile.y]
		action_record["tile"] = [after_tile.x, after_tile.y]
		action_record["tile_key"] = _tile_key(after_tile)
		action_record["elapsed_usec"] = Time.get_ticks_usec() - started_usec
		_record_action_telemetry(action_record)
		_record_polish_telemetry(action_record)
		_record_action_trace(action_record)
		_analyze_action_result(action_record)
		_check_invariants(action_record)
		_advance_clock_between_actions(action_record)
		if _should_write_progress(step):
			_write_progress("running", current_run_index, step + 1, current_scenario)

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

	current_gameplay.free()
	current_hud.free()
	current_world.free()
	store.free()
	current_gameplay = null
	current_hud = null
	current_world = null
	current_state = {}
	current_run_telemetry = {}
	current_run_polish_telemetry = {}
	current_polish_feedback_counts = {}
	return summary


func _scenario_for_run(run_index: int) -> String:
	var requested := str(config["scenario"])
	if requested != "all":
		return requested
	var profile_mix := _balance_profile_scenario_mix()
	return str(profile_mix[run_index % profile_mix.size()])


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
			if not _ground_items().is_empty():
				return "pickup_drop"
			if _combat_recovery_needed():
				if _has_usable_item():
					return "use_item"
				if not _first_bank_usable_item().is_empty():
					return "bank_withdraw"
				if not _pick_affordable_shop_usable().is_empty():
					return "shop_buy"
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
			if not _ground_items().is_empty():
				return action_name
			return _non_combat_productive_action(step)
		"cook":
			if _has_raw_cookable():
				return action_name
			return "gather_fishing"
		"process_station":
			if _has_useful_processing_input():
				return action_name
			return _processing_input_action()
		"process_furnace":
			if _has_recipe_inputs_for_type("smelting"):
				return action_name
			return "gather_mining"
		"process_anvil":
			if _has_recipe_inputs_for_type("smithing"):
				return action_name
			return "process_furnace" if _has_recipe_inputs_for_type("smelting") else "gather_mining"
		"process_carpentry":
			if _has_recipe_inputs_for_type("carpentry"):
				return action_name
			return "gather_woodcutting"
		"process_apothecary":
			if _has_recipe_inputs_for_type("herbalism"):
				return action_name
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
	if not _ground_items().is_empty():
		return "pickup_drop"
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
			_interact_object(_first_ground_item(), "default", record)
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
	var target_tile = current_world.call("_interaction_target_tile", object_data)
	if not (target_tile is Vector2i) or target_tile == Vector2i(-1, -1):
		_record_issue("softlock", "P1", str(record["action"]), "Object has no reachable interaction tile.", _feedback_text(), {
			"target_id": str(object_data.get("id", "")),
		})
		return false
	var start_tile := _player_tile()
	var path = current_world.call("_find_path", start_tile, target_tile)
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
	if feedback.strip_edges().is_empty():
		_record_issue("qol", "P2", action_name, "Action produced no visible feedback.", feedback, {})
	if _is_failure_feedback(feedback):
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
	if _inventory_slot_count(_inventory()) >= INVENTORY_SLOT_LIMIT and not bool(record.get("changed_state", false)):
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
	if elapsed_usec > 16667:
		_add_telemetry_int(current_run_telemetry, "slow_action_steps_16ms", 1)
	var tile_key := str(record.get("tile_key", ""))
	if not tile_key.is_empty():
		_increment_count(current_run_telemetry["tile_visits"], tile_key)


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
	_add_telemetry_int(current_run_polish_telemetry, "steps", 1)
	_increment_count(current_run_polish_telemetry["action_counts"], action_name)
	if feedback.is_empty():
		_add_polish_flag("empty_feedback", action_name, "Action produced no visible player feedback.", record)
	if not feedback.is_empty() and feedback == previous_feedback:
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
	if bool(record.get("changed_state", false)) and (feedback.is_empty() or feedback == previous_feedback):
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
	if str(snapshot.get("title", "")).strip_edges().is_empty():
		_add_polish_flag("panel_missing_title", action_name, "Visible interaction panel had no title.", record, snapshot)
	if int(snapshot.get("rows", 0)) <= 0:
		_add_polish_flag("panel_empty_rows", action_name, "Visible interaction panel had no useful rows.", record, snapshot)
	if int(snapshot.get("buttons", 0)) <= 0:
		_add_polish_flag("panel_missing_action_buttons", action_name, "Visible interaction panel had no action buttons.", record, snapshot)


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
		"path_moves": 0,
		"path_length_total": 0,
		"max_path_length": 0,
		"action_cost_samples": 0,
		"action_cost_total_usec": 0,
		"slowest_action_usec": 0,
		"slow_action_steps_16ms": 0,
		"action_counts": {},
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
		"panel_checks": 0,
		"quest_clarity_checks": 0,
		"quest_return_prompt_checks": 0,
		"discoverability_checks": 0,
		"sampled_flags": 0,
		"action_counts": {},
		"flag_counts": {},
		"flag_action_counts": {},
		"flag_scenario_counts": {},
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
	for count_key in ["action_counts", "failure_action_counts", "tile_visits", "issue_tile_counts", "issue_action_counts", "issue_severity_counts"]:
		var target_counts = target.get(count_key, {})
		if not (target_counts is Dictionary):
			target_counts = {}
		var source_counts = source.get(count_key, {})
		if source_counts is Dictionary:
			for key in source_counts.keys():
				target_counts[str(key)] = int(target_counts.get(str(key), 0)) + int(source_counts[key])
		target[count_key] = target_counts


func _merge_polish_bucket(target: Dictionary, source: Dictionary) -> void:
	var sum_keys := [
		"runs",
		"steps",
		"failure_feedback_actions",
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
	for count_key in ["action_counts", "flag_counts", "flag_action_counts", "flag_scenario_counts", "panel_type_counts"]:
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
	return _finalize_telemetry_bucket(telemetry_summary, top_limit)


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
				scenario_report["issue_hotspots"] = _top_count_entries(scenario_report.get("issue_tile_counts", {}), min(top_limit, 10))
				scenario_reports[scenario] = scenario_report
		report["scenarios"] = scenario_reports
	return _normalize_value(report)


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
		"snapshots": "%s/snapshots" % str(config["output_dir"]),
	}
	if str(config["trace"]) == "all":
		output_files["trace"] = "%s/trace.jsonl" % str(config["output_dir"])
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
		"counts_by_category": _normalize_value(counts_by_category),
		"counts_by_severity": _normalize_value(counts_by_severity),
		"scenario_metrics": _normalize_value(scenario_metrics),
		"telemetry": _telemetry_report(10),
		"polish": _polish_report(10),
		"balance": _balance_profile_report(10),
		"performance": _performance_report(10),
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
	_write_replay_manifest(output_files)


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
	lines.append("- Timeout: `%s` seconds; fail on issues: `%s`." % [str(config["timeout_seconds"]), str(config["fail_on_issues"])])
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
	var polish := _polish_report(5)
	lines.append("- Polish telemetry: advisory status `%s`, sampled flags `%d`, empty feedback rate `%.3f`, unchanged feedback rate `%.3f`." % [
		str(polish.get("advisory_status", "")),
		int(polish.get("sampled_flags", 0)),
		float(polish.get("empty_feedback_rate", 0.0)),
		float(polish.get("unchanged_feedback_rate", 0.0)),
	])
	lines.append("- Treat findings as evidence candidates. Verify issue samples against current code and data before changing gameplay.")
	lines.append("")
	lines.append("## Replay Guidance")
	lines.append("")
	lines.append("- Use the replay command embedded in each `issues.jsonl` sample to rerun the same seed, scenario, and step count.")
	lines.append("- Replay commands use `--trace all` so `%s` captures every bot action." % _display_output_path("trace.jsonl"))
	lines.append("- Use `replay_manifest.json` for build hash, data hashes, scenario mix, run seeds, and output paths.")
	lines.append("- Use `balance_profiles.json` for profile-specific economy, progression, combat, loot, and dominant-action signals.")
	lines.append("- Use `performance_observations.json` for advisory action-cost and path-cost signals; it is not a failing gate.")
	lines.append("- Use `polish_telemetry.json` and `manual_polish_review.md` for advisory player-facing clarity, UI, feedback, and human-only review prompts.")
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
	lines.append("- Read `%s` first for the ranked findings." % _display_output_path("improvement_plan.md"))
	lines.append("- Read `%s` for replayable samples." % _display_output_path("issues.jsonl"))
	lines.append("- Read `%s` and `%s` for aggregate metrics." % [_display_output_path("runs.jsonl"), _display_output_path("summary.json")])
	lines.append("- Read `%s` for build hash, data hashes, scenario mix, run seeds, and output paths." % _display_output_path("replay_manifest.json"))
	lines.append("- Read `%s` for local telemetry: deaths, damage taken, failed feedback, economy flow, action cost samples, and tile hot spots." % _display_output_path("telemetry_summary.json"))
	lines.append("- Read `%s` for profile-specific economy, progression, combat, loot, and dominant-action signals." % _display_output_path("balance_profiles.json"))
	lines.append("- Read `%s` for advisory action-cost and path-cost signals before doing performance work." % _display_output_path("performance_observations.json"))
	lines.append("- Read `%s` for advisory UI, feedback, quest clarity, and discoverability signals." % _display_output_path("polish_telemetry.json"))
	lines.append("- Read `%s` for human-only review prompts around visuals, animation feel, audio, pacing, and confusion." % _display_output_path("manual_polish_review.md"))
	lines.append("- Replay representative issues with the commands embedded in each issue sample before implementing risky fixes.")
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
	lines.append("- Trace mode: `%s`" % str(config["trace"]))
	lines.append("- Output directory: `%s`" % output_dir)
	lines.append("- Timeout seconds: `%s`" % str(config["timeout_seconds"]))
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
	lines.append("## Generated Artifacts")
	lines.append("")
	lines.append("- `%s`" % _display_output_path("runs.jsonl"))
	lines.append("- `%s`" % _display_output_path("issues.jsonl"))
	lines.append("- `%s`" % _display_output_path("summary.json"))
	lines.append("- `%s`" % _display_output_path("replay_manifest.json"))
	lines.append("- `%s`" % _display_output_path("telemetry_summary.json"))
	lines.append("- `%s`" % _display_output_path("balance_profiles.json"))
	lines.append("- `%s`" % _display_output_path("performance_observations.json"))
	lines.append("- `%s`" % _display_output_path("polish_telemetry.json"))
	lines.append("- `%s`" % _display_output_path("manual_polish_review.md"))
	lines.append("- `%s`" % _display_output_path("improvement_plan.md"))
	lines.append("- `%s`" % _display_output_path("codex_prompt.md"))
	if str(config["trace"]) == "all":
		lines.append("- `%s`" % _display_output_path("trace.jsonl"))
	lines.append("")
	lines.append("## Implementation Instructions")
	lines.append("")
	lines.append("- Preserve unrelated dirty worktree changes. Do not revert, stage, commit, or push unless explicitly asked.")
	lines.append("- Keep changes small, Godot-native, and data-driven where practical.")
	lines.append("- Keep bot-owned work in `scripts/playtest_simulation_runner.gd` and its generated reports: deterministic replay metadata, chaos behavior, simulation-step invariant calls, telemetry summaries, balance profiles, polish telemetry, failed-run state summaries, and advisory simulation performance observations.")
	lines.append("- Keep validators, golden smokes, save/load torture smokes, debug console commands, and debug overlays independently runnable outside the simulation bot.")
	lines.append("- Put shared logic such as invariants or future snapshots in reusable helpers instead of burying it only inside the runner.")
	lines.append("- Fix P0/P1 findings first, then P2 QOL friction if the fix is clear and low risk.")
	lines.append("- If a finding is caused by a weak simulation heuristic rather than game behavior, improve `scripts/playtest_simulation_runner.gd` classification or bot logic instead of changing gameplay.")
	lines.append("- Favor player-facing improvements that reduce repeated failed actions: clearer feedback, recovery paths, better gating, inventory relief, and safer combat/quest flow.")
	lines.append("- Treat polish telemetry as advisory. Use manual review prompts for visual quality, animation feel, audio, fun, and player confusion before making subjective changes.")
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


func _pick_resource(skill_id: String) -> Dictionary:
	var candidates := []
	for resource in resources:
		if not (resource is Dictionary):
			continue
		if not skill_id.is_empty() and str(resource.get("skill_id", "")) != skill_id:
			continue
		if _resource_is_reasonable(resource):
			candidates.append(resource)
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
	return true


func _pick_mob() -> Dictionary:
	var alive := []
	var combat = current_state.get("combat", {})
	var mob_states := {}
	if combat is Dictionary and combat.get("mobs", {}) is Dictionary:
		mob_states = combat.get("mobs", {})
	for mob in mobs:
		if not (mob is Dictionary):
			continue
		var state_for_mob = mob_states.get(str(mob.get("id", "")), {})
		if state_for_mob is Dictionary and bool(state_for_mob.get("dead", false)):
			continue
		alive.append(mob)
	if alive.is_empty():
		alive = mobs.duplicate(true)
	alive.sort_custom(func(left, right) -> bool: return int(left.get("level", 1)) < int(right.get("level", 1)))
	if current_scenario == "random_guard" and current_rng.randf() < 0.35:
		return _random_entry(alive, {})
	return alive[0] if not alive.is_empty() else {}


func _pick_npc() -> Dictionary:
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
	if _has_raw_cookable():
		return _station("cooking_range")
	if _has_recipe_inputs_for_type("smelting"):
		return _station("furnace")
	if _has_recipe_inputs_for_type("smithing"):
		return _station("anvil")
	if _has_recipe_inputs_for_type("carpentry"):
		return _station("carpentry_bench")
	if _has_recipe_inputs_for_type("herbalism"):
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
	return _random_entry(all_objects, {})


func _station(station_key: String) -> Dictionary:
	var station = stations.get(station_key, {})
	if station is Dictionary:
		return station
	return {}


func _first_ground_item() -> Dictionary:
	var drops := _ground_items()
	if drops.is_empty():
		return {}
	var item = drops[0]
	if item is Dictionary:
		var data: Dictionary = item.duplicate(true)
		data["type"] = "ground_item"
		data["id"] = str(data.get("object_id", "ground_item"))
		data["label"] = "%d %s" % [int(data.get("quantity", 1)), str(data.get("item_id", "item")).replace("_", " ")]
		if not data.has("tile"):
			data["tile"] = _player_tile()
		return data
	return {}


func _first_depositable_item() -> String:
	for item_id in _sorted_keys(_inventory()):
		if str(item_id) != "coins" and int(_inventory().get(item_id, 0)) > 0 and not _is_protected_gathering_tool(str(item_id)):
			return str(item_id)
	return ""


func _first_bank_item() -> String:
	if _combat_recovery_needed():
		var usable_item := _first_bank_usable_item()
		if not usable_item.is_empty():
			return usable_item
	for item_id in _sorted_keys(_bank()):
		if int(_bank().get(item_id, 0)) > 0 and _can_add_inventory_item(str(item_id)):
			return str(item_id)
	return ""


func _first_sellable_item() -> String:
	for item_id in _sorted_keys(_inventory()):
		if str(item_id) == "coins":
			continue
		var definition = items_data.get(str(item_id), {})
		if definition is Dictionary and int(definition.get("sell_price", 0)) > 0 and int(_inventory().get(item_id, 0)) > 0 and not _is_protected_gathering_tool(str(item_id)):
			return str(item_id)
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
			return str(item_id)
	return ""


func _first_droppable_item() -> String:
	for item_id in _sorted_keys(_inventory()):
		if int(_inventory().get(item_id, 0)) > 0:
			return str(item_id)
	return ""


func _bank_quantity() -> int:
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


func _has_recipe_inputs(recipe: Dictionary) -> bool:
	var inputs = recipe.get("inputs", {})
	if not (inputs is Dictionary):
		return false
	for item_id in inputs.keys():
		if int(_inventory().get(str(item_id), 0)) < int(inputs[item_id]):
			return false
	return true


func _has_raw_cookable() -> bool:
	for item_id in _inventory().keys():
		var definition = items_data.get(str(item_id), {})
		if definition is Dictionary and definition.has("cook_result") and int(_inventory().get(item_id, 0)) > 0:
			return true
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
			return _has_useful_processing_input()
		"process_furnace":
			return _has_recipe_inputs_for_type("smelting")
		"process_anvil":
			return _has_recipe_inputs_for_type("smithing")
		"process_carpentry":
			return _has_recipe_inputs_for_type("carpentry")
		"process_apothecary":
			return _has_recipe_inputs_for_type("herbalism")
		"cook":
			return _has_raw_cookable()
		"attack_mob":
			return not _pick_mob().is_empty() and not _combat_recovery_needed()
		"pickup_drop":
			return not _ground_items().is_empty()
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


func _item_is_useful_now(item_id: String, definition) -> bool:
	if not (definition is Dictionary):
		return false
	var can_heal := int(definition.get("heal_amount", 0)) > 0 and _needs_healing()
	var can_cleanse := bool(definition.get("cleanses_poison", false)) and _has_poison_status()
	return int(_inventory().get(item_id, 0)) > 0 and (can_heal or can_cleanse)


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
	}
	if current_hud == null:
		return snapshot
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
	var legacy = current_state.get("quest_progress", {})
	if legacy is Dictionary:
		return legacy
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
		"player_tile": [_player_tile().x, _player_tile().y],
	}
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
