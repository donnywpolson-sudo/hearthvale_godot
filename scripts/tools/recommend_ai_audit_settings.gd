extends SceneTree

const EngineScript = preload("res://scripts/tools/ai_audit_recommendation_engine.gd")

var output_mode = "text"
var output_file = ""
var summary_path = EngineScript.DEFAULT_SUMMARY_PATH
var report_path = EngineScript.DEFAULT_REPORT_PATH


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed_ok = _parse_args()
	if not parsed_ok:
		quit(1)
		return
	var engine = EngineScript.new()
	var recommendation: Dictionary = engine.recommend(summary_path, report_path)
	_print_recommendation(recommendation)
	quit(0)


func _parse_args() -> bool:
	var args = OS.get_cmdline_user_args()
	var index = 0
	while index < args.size():
		var arg = str(args[index])
		match arg:
			"--summary-path":
				var value = _arg_value(args, index, arg)
				if value.is_empty():
					return false
				index += 1
				summary_path = _resolve_repo_path(value)
			"--report-path":
				var value = _arg_value(args, index, arg)
				if value.is_empty():
					return false
				index += 1
				report_path = _resolve_repo_path(value)
			"--output":
				var value = _arg_value(args, index, arg)
				if value.is_empty():
					return false
				index += 1
				output_mode = value.to_lower()
			"--output-file":
				var value = _arg_value(args, index, arg)
				if value.is_empty():
					return false
				index += 1
				output_file = _resolve_repo_path(value)
			"--help":
				_print_usage()
				quit(0)
			_:
				push_error("Unknown recommendation argument: %s" % arg)
				return false
		index += 1
	if output_mode not in ["text", "args", "choice"]:
		push_error("--output must be text, args, or choice.")
		return false
	return true


func _arg_value(args: Array, index: int, flag: String) -> String:
	if index + 1 >= args.size():
		push_error("%s requires a value." % flag)
		return ""
	var value = str(args[index + 1])
	if value.begins_with("--"):
		push_error("%s requires a value." % flag)
		return ""
	return value


func _resolve_repo_path(path_value: String) -> String:
	if path_value.strip_edges().is_empty():
		return path_value
	var normalized = path_value.replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://") or normalized.begins_with("/") or (normalized.length() > 1 and normalized[1] == ":"):
		return normalized
	return "res://%s" % normalized


func _print_usage() -> void:
	print("Usage: -- --output text|args|choice --output-file res://.godot_logs/recommendation.txt --summary-path res://.godot/ai_simulation/_working/current/summary.json --report-path res://_ai_audit_workflow/_internal/HEARTHVALE_AI_SIMULATION_AUDIT_REPORT.md")


func _print_recommendation(recommendation: Dictionary) -> void:
	var rendered = _render_recommendation(recommendation)
	if not output_file.strip_edges().is_empty():
		var file = FileAccess.open(output_file, FileAccess.WRITE)
		if file == null:
			push_error("Could not write recommendation output file: %s" % output_file)
			return
		file.store_string(rendered)
		if not rendered.ends_with("\n"):
			file.store_string("\n")
		return
	print(rendered)


func _render_recommendation(recommendation: Dictionary) -> String:
	if output_mode == "args":
		return str(recommendation.get("args", ""))
	if output_mode == "choice":
		return str(recommendation.get("menu_choice", "0"))
	var lines = []
	lines.append("Audit recommendation")
	lines.append("  Recommendation: %s" % str(recommendation.get("recommendation", "")))
	lines.append("")
	lines.append("Current evidence")
	lines.append("  Source: %s" % str(recommendation.get("source", "")))
	var current_line = str(recommendation.get("current_line", ""))
	if not current_line.strip_edges().is_empty():
		lines.append("  Snapshot: %s" % current_line)
	lines.append("")
	lines.append("Recommended next run")
	if str(recommendation.get("menu_choice", "0")) == "1":
		lines.append("  Menu choice: 1 Light")
	else:
		lines.append("  Use the suggested command directly; the named menu tiers are Light and Deep only.")
	lines.append("")
	lines.append("Why")
	lines.append("  %s" % str(recommendation.get("reason", "")))
	var command = str(recommendation.get("command", ""))
	if not command.strip_edges().is_empty():
		lines.append("")
		lines.append("Suggested command")
		lines.append("  %s" % command)
	lines.append("")
	lines.append("Limitations")
	lines.append("  Advisory only; it does not prove fun, visual quality, audio quality, export parity, or release readiness.")
	var warning = str(recommendation.get("warning", ""))
	if not warning.strip_edges().is_empty():
		lines.append("  %s" % warning)
	return "\n".join(lines)
