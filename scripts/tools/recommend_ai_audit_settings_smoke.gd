extends SceneTree

const RecommendationEngine = preload("res://scripts/tools/ai_audit_recommendation_engine.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tool = RecommendationEngine.new()
	var baseline_args = tool.new_safe_args(120, 200, 1, "all", "issues", "coverage", 600, "auto")
	_assert_eq(baseline_args, "120 200 1 all issues coverage 600 auto", "baseline light audit args")
	_assert_eq(tool.new_safe_args(0, 150, 1, "all", "issues", "default", 0, "auto"), "", "invalid run count rejected")
	_assert_eq(tool.new_safe_args(12, 150, 1, "bad", "issues", "default", 0, "auto"), "", "invalid scenario rejected")

	var no_evidence_report = tool.get_report_score_context("")
	_assert_eq(no_evidence_report["has_evidence_gap"], false, "empty report has no evidence gap")

	var report = "Scorecard | `overall_score=55`; weakest category `visual_audio_confidence=25`\nManual playtest notes are still missing."
	var report_context = tool.get_report_score_context(report)
	_assert_eq(report_context["overall_score"], 55, "report overall score parsed")
	_assert_eq(report_context["weakest_key"], "visual_audio_confidence", "report weakest key parsed")
	_assert_eq(report_context["weakest_score"], 25, "report weakest score parsed")
	_assert_eq(report_context["has_evidence_gap"], true, "report evidence gap parsed")

	var focused_command = tool.get_focused_command_for_weakest_area("performance_budget", "")
	_assert_eq(tool.command_args(focused_command), "120 200 1 all issues coverage 600 auto", "performance focused args")

	var summary = {
		"config": {
			"runs": 12,
			"steps": 150,
			"scenario": "all",
			"scenario_probes": "auto",
		},
		"trust": {
			"run_strength": "strategy_smoke",
			"coverage_scope": "all_scenarios",
			"latest_publish_status": "blocked_lower_coverage",
		},
		"scorecard": {
			"overall_score": 55,
			"weakest_category": {
				"key": "visual_audio_confidence",
				"score": 25,
			},
		},
		"scenario_probes": {
			"mode": "smoke",
			"summary": {
				"issues": 0,
			},
		},
		"issue_occurrences": 0,
		"performance": {
			"status": "over_budget",
		},
	}
	var summary_context = tool.build_summary_context(summary, report_context)
	_assert_eq(summary_context["current_line"], "overall 55/100; weakest visual_audio_confidence 25/100; issues 0; probes requested auto resolved smoke; strategy_smoke/all_scenarios", "summary snapshot text")
	_assert_eq(summary_context["performance_over_budget"], true, "performance over budget detected")
	_assert_eq(summary_context["warning"], "Latest publish is blocked by lower coverage; a stronger previous latest report was preserved.", "publish warning")

	if failures.is_empty():
		print("Hearthvale AI audit recommendation smoke passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _assert_eq(actual, expected, label: String) -> void:
	if actual != expected:
		failures.append("%s: expected '%s' but got '%s'" % [label, str(expected), str(actual)])
