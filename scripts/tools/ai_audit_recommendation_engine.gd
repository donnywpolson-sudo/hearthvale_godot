extends RefCounted

const DEFAULT_SUMMARY_PATH := "res://.godot/ai_simulation/_working/current/summary.json"
const DEFAULT_REPORT_PATH := "res://_ai_audit_workflow/_internal/HEARTHVALE_AI_SIMULATION_AUDIT_REPORT.md"
const VALID_SCENARIOS := ["all", "core_loop", "quest_chaser", "economy_stress", "combat_loot", "inventory_pressure", "random_guard"]
const VALID_TRACES := ["issues", "all"]
const VALID_PROFILES := ["default", "progression", "economy", "combat", "coverage"]
const VALID_PROBE_MODES := ["auto", "off", "smoke", "full"]


func recommend(summary_path: String = DEFAULT_SUMMARY_PATH, report_path: String = DEFAULT_REPORT_PATH) -> Dictionary:
	var summary = read_json_safe(summary_path)
	var report_text = read_text_safe(report_path)
	var report_context = get_report_score_context(report_text)
	var baseline_command = new_safe_command(120, 200, 1, "all", "issues", "coverage", 600, "auto")
	var diagnostic_command = baseline_command

	if not (summary is Dictionary):
		if not report_text.strip_edges().is_empty():
			var current = "Markdown fallback"
			if report_context["overall_score"] != null:
				current = "overall %d/100; weakest %s %d/100" % [
					int(report_context["overall_score"]),
					str(report_context["weakest_key"]),
					int(report_context["weakest_score"]),
				]
			var focused_command = get_focused_command_for_weakest_area(str(report_context["weakest_key"]), diagnostic_command)
			if bool(report_context["has_evidence_gap"]) or matches_any(str(report_context["weakest_key"]), ["visual", "audio", "manual", "export"]):
				return _recommendation("_ai_audit_workflow/_internal/HEARTHVALE_AI_SIMULATION_AUDIT_REPORT.md", current, "Run focused diagnostic settings and gather missing non-simulation evidence.", "The report names evidence gaps that higher run counts cannot prove; these settings maximize replay, probe, and telemetry detail for the weakest lane.", focused_command, "", "0")
			return _recommendation("_ai_audit_workflow/_internal/HEARTHVALE_AI_SIMULATION_AUDIT_REPORT.md", current, "Run focused diagnostic settings for the weakest audit lane.", "Markdown was readable, but summary.json was missing or malformed.", focused_command, "", "0")
		return _recommendation("none", "no usable audit summary found", "Run Light audit to create baseline audit evidence.", "No current JSON summary or audit report could be read.", baseline_command, "", "1")

	var summary_context = build_summary_context(summary, report_context)
	var warning = str(summary_context["warning"])
	var current_line = str(summary_context["current_line"])

	if str(summary_context["scenario"]) != "all" or int(summary_context["runs"]) < 12 or int(summary_context["steps"]) < 150:
		return _recommendation(".godot/ai_simulation/_working/current/summary.json", current_line, "Run Light audit.", "The current machine-readable run is below the minimum Light audit shape.", baseline_command, warning, "1")

	if int(summary_context["issue_occurrences"]) > 0 or int(summary_context["probe_issues"]) > 0:
		return _recommendation(".godot/ai_simulation/_working/current/summary.json", current_line, "Run diagnostic simulation with full trace and full scenario probes.", "Findings exist, so replay detail is more useful than a larger blind run.", diagnostic_command, warning, "0")

	var weakest_key = str(summary_context["weakest_key"])
	var focused_command = get_focused_command_for_weakest_area(weakest_key, diagnostic_command)
	if matches_any(weakest_key, ["visual", "audio", "manual", "export"]) or bool(report_context["has_evidence_gap"]):
		return _recommendation(".godot/ai_simulation/_working/current/summary.json", current_line, "Run focused diagnostic settings and gather visual/audio/manual evidence.", "The weakest evidence lane cannot be fixed by headless simulation alone, but this run collects full trace, full probes, and detailed telemetry around the weakest lane.", focused_command, warning, "0")

	if bool(summary_context["performance_over_budget"]):
		return _recommendation(".godot/ai_simulation/_working/current/summary.json", current_line, "Run focused performance diagnostic settings.", "Performance observations are over budget, so full trace, full probes, and coverage profile are more useful than a larger blind run.", get_focused_command_for_weakest_area("performance", diagnostic_command), warning, "0")

	if str(summary_context["run_strength"]) == "strategy_smoke":
		return _recommendation(".godot/ai_simulation/_working/current/summary.json", current_line, "Run focused diagnostic settings for the weakest audit lane.", "The current strategy smoke is clean; targeted full-trace data is more useful than a larger blind run when the audit scorecard has a weakest lane.", focused_command, warning, "0")

	return _recommendation(".godot/ai_simulation/_working/current/summary.json", current_line, "Run focused diagnostic settings for the weakest audit lane.", "Current automated evidence is clean; targeted full-trace data is the best next simulation input for improvement work.", focused_command, warning, "0")


func read_json_safe(path: String):
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return null


func read_text_safe(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func new_safe_command(runs: int, steps: int, seed: int, scenario: String, trace: String, balance_profile: String, timeout_seconds: int, scenario_probes: String) -> String:
	var args = new_safe_args(runs, steps, seed, scenario, trace, balance_profile, timeout_seconds, scenario_probes)
	if args.is_empty():
		return ""
	return ".\\_ai_audit_workflow\\_internal\\HEARTHVALE_AI_SIMULATION.bat %s" % args


func new_safe_args(runs: int, steps: int, seed: int, scenario: String, trace: String, balance_profile: String, timeout_seconds: int, scenario_probes: String) -> String:
	if runs <= 0 or steps <= 0 or seed < 0 or timeout_seconds < 0:
		return ""
	if scenario not in VALID_SCENARIOS or trace not in VALID_TRACES or balance_profile not in VALID_PROFILES or scenario_probes not in VALID_PROBE_MODES:
		return ""
	return "%d %d %d %s %s %s %d %s" % [runs, steps, seed, scenario, trace, balance_profile, timeout_seconds, scenario_probes]


func command_args(command: String) -> String:
	var marker = "HEARTHVALE_AI_SIMULATION.bat "
	var index = command.find(marker)
	if index == -1:
		return ""
	return command.substr(index + marker.length()).strip_edges()


func get_report_score_context(report_text: String) -> Dictionary:
	var result = {
		"overall_score": null,
		"weakest_key": "",
		"weakest_score": null,
		"has_evidence_gap": false,
	}
	if report_text.strip_edges().is_empty():
		return result

	var regex = RegEx.new()
	if regex.compile("Scorecard\\s*\\|\\s*`overall_score=(\\d+)`;\\s*weakest category\\s*`([^`=]+)=(\\d+)`") == OK:
		var score_match = regex.search(report_text)
		if score_match != null:
			result["overall_score"] = int(score_match.get_string(1))
			result["weakest_key"] = score_match.get_string(2)
			result["weakest_score"] = int(score_match.get_string(3))

	var lower = report_text.to_lower()
	for marker in ["manual playtest notes are still missing", "audio timing", "export and platform parity", "broader visual qa", "subjective fun", "accessibility and localization"]:
		if lower.find(marker) != -1:
			result["has_evidence_gap"] = true
			break
	return result


func build_summary_context(summary: Dictionary, report_context: Dictionary) -> Dictionary:
	var config_data = _dict(summary.get("config", {}))
	var trust = _dict(summary.get("trust", {}))
	var scorecard = _dict(summary.get("scorecard", {}))
	var weakest = _dict(scorecard.get("weakest_category", {}))
	var scenario_probes = _dict(summary.get("scenario_probes", {}))
	var probe_summary = _dict(scenario_probes.get("summary", {}))
	var performance = _dict(summary.get("performance", {}))
	var runs = int(config_data.get("runs", 0))
	var steps = int(config_data.get("steps", 0))
	var scenario = str(config_data.get("scenario", ""))
	var requested_probes = str(config_data.get("scenario_probes", ""))
	var resolved_probes = str(scenario_probes.get("mode", ""))
	var issue_occurrences = int(summary.get("issue_occurrences", 0))
	var probe_issues = int(probe_summary.get("issues", 0))
	var overall_score = int(scorecard.get("overall_score", 0))
	var weakest_key = str(weakest.get("key", ""))
	var weakest_score = int(weakest.get("score", 0))
	var run_strength = str(trust.get("run_strength", ""))
	var coverage_scope = str(trust.get("coverage_scope", ""))
	var latest_status = str(trust.get("latest_publish_status", ""))
	var warning = ""
	if latest_status == "blocked_lower_coverage":
		warning = "Latest publish is blocked by lower coverage; a stronger previous latest report was preserved."
	if report_context["overall_score"] != null and int(report_context["overall_score"]) != overall_score:
		warning = ("%s JSON and Markdown score summaries differ; JSON was used." % warning).strip_edges()
	return {
		"runs": runs,
		"steps": steps,
		"scenario": scenario,
		"issue_occurrences": issue_occurrences,
		"probe_issues": probe_issues,
		"weakest_key": weakest_key,
		"run_strength": run_strength,
		"performance_over_budget": performance_over_budget(performance),
		"warning": warning,
		"current_line": "overall %d/100; weakest %s %d/100; issues %d; probes requested %s resolved %s; %s/%s" % [
			overall_score,
			weakest_key,
			weakest_score,
			issue_occurrences,
			requested_probes,
			resolved_probes,
			run_strength,
			coverage_scope,
		],
	}


func performance_over_budget(performance: Dictionary) -> bool:
	if performance.is_empty():
		return false
	var status = str(performance.get("status", ""))
	if not status.is_empty() and status != "ok":
		return true
	var observations = performance.get("observations", [])
	if not (observations is Array):
		return false
	for observation in observations:
		if observation is Dictionary and str(observation.get("status", "")) == "over_budget":
			return true
	return false


func get_focused_command_for_weakest_area(weakest_key: String, fallback_command: String) -> String:
	return new_safe_command(120, 200, 1, "all", "issues", "coverage", 600, "auto")


func matches_any(value: String, needles: Array) -> bool:
	var lower = value.to_lower()
	for needle in needles:
		if lower.find(str(needle).to_lower()) != -1:
			return true
	return false


func _recommendation(source: String, current_line: String, recommendation: String, reason: String, command: String, warning: String, menu_choice: String) -> Dictionary:
	return {
		"source": source,
		"current_line": current_line,
		"recommendation": recommendation,
		"reason": reason,
		"command": command,
		"warning": warning,
		"menu_choice": menu_choice if menu_choice in ["0", "1"] else "0",
		"args": command_args(command),
	}


func _dict(value) -> Dictionary:
	if value is Dictionary:
		return value
	return {}
