@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "WORKFLOW_ROOT=%~dp0"
for %%I in ("%WORKFLOW_ROOT%..\..") do set "PROJECT_ROOT=%%~fI\"
set "GODOT_EXE=C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe"
set "RUNNER_SCRIPT=res://scripts/playtest_simulation_runner.gd"
set "LOG_FILE=.godot_logs\playtest_simulation.log"
set "OUTPUT_DIR=res://.godot/ai_simulation/_working/current"
set "PUBLIC_OUTPUT_ROOT=res://.godot/ai_simulation"
set "RECOMMEND_SCRIPT=res://scripts/tools/recommend_ai_audit_settings.gd"
set "RECOMMEND_SCRIPT_FILE=scripts\tools\recommend_ai_audit_settings.gd"
set "RECOMMEND_LOG=.godot_logs\recommend_ai_audit_settings.log"
set "SUMMARY_READER_SCRIPT=res://scripts/tools/read_ai_simulation_summary.gd"
set "SUMMARY_READER_LOG=.godot_logs\ai_simulation_summary_values.log"
set "SHOW_COMMAND=%HV_SIM_SHOW_COMMAND%"
set "TIER_NAME=Custom"
set "PURPOSE=custom run"
set "EST_RUNTIME_LABEL=not estimated"
set "RECOMMENDED_CHOICE=1"

if /I "%~1"=="--recommend" (
	pushd "%PROJECT_ROOT%" >nul 2>nul
	if errorlevel 1 (
		echo Could not enter Hearthvale Godot project root:
		echo %PROJECT_ROOT%
		exit /b 1
	)
	if not exist ".godot_logs" mkdir ".godot_logs" >nul 2>nul
	call :print_recommendation
	popd
	exit /b 0
)

if /I "%~1"=="--show-command" (
	set "SHOW_COMMAND=1"
	shift /1
)
if /I "%~1"=="debug" (
	set "SHOW_COMMAND=1"
	shift /1
)

if not exist "%GODOT_EXE%" (
	echo Godot executable was not found:
	echo %GODOT_EXE%
	call :pause_if_needed
	exit /b 1
)

pushd "%PROJECT_ROOT%" >nul 2>nul
if errorlevel 1 (
	echo Could not enter Hearthvale Godot project root:
	echo %PROJECT_ROOT%
	call :pause_if_needed
	exit /b 1
)

if not exist "project.godot" (
	echo project.godot was not found in:
	echo %CD%
	popd
	call :pause_if_needed
	exit /b 1
)
if not exist ".godot_logs" mkdir ".godot_logs" >nul 2>nul

set "RUNS=120"
set "STEPS=200"
set "SEED=1"
set "SCENARIO=all"
set "TRACE=issues"
set "BALANCE_PROFILE=coverage"
set "SCENARIO_PROBES=auto"
set "TIMEOUT_SECONDS=600"

if "%~1"=="" (
	call :choose_tier
	set "TIER_RESULT=!ERRORLEVEL!"
	if not "!TIER_RESULT!"=="0" (
		popd
		if "!TIER_RESULT!"=="2" exit /b 0
		call :pause_if_needed
		exit /b 1
	)
) else (
	if not "%~1"=="" set "RUNS=%~1"
	if not "%~2"=="" set "STEPS=%~2"
	if not "%~3"=="" set "SEED=%~3"
	if not "%~4"=="" set "SCENARIO=%~4"
	if not "%~5"=="" set "TRACE=%~5"
	if not "%~6"=="" set "BALANCE_PROFILE=%~6"
	if not "%~7"=="" set "TIMEOUT_SECONDS=%~7"
	if not "%~8"=="" set "SCENARIO_PROBES=%~8"
)

call :validate_config
if errorlevel 1 (
	popd
	call :pause_if_needed
	exit /b 1
)

if not exist ".godot\ai_simulation" mkdir ".godot\ai_simulation" >nul 2>nul
set "LATEST_PROMPT_BEFORE="
for /f "delims=" %%F in ('dir /b /a-d /o-d ".godot\ai_simulation\ai_simulation_codex_prompt_*.md" 2^>nul') do if not defined LATEST_PROMPT_BEFORE set "LATEST_PROMPT_BEFORE=.godot\ai_simulation\%%F"

set "PUBLISH_ARGS=--publish-latest --public-output-root %PUBLIC_OUTPUT_ROOT%"
if /I "%HV_SIM_ALLOW_LATEST_DOWNGRADE%"=="1" set "PUBLISH_ARGS=%PUBLISH_ARGS% --allow-latest-downgrade"
if /I "%HV_SIM_REQUIRE_PUBLISH_LATEST%"=="1" set "PUBLISH_ARGS=%PUBLISH_ARGS% --require-publish-latest"
call :prepare_display_values

echo Hearthvale AI simulation launcher
echo Godot: 4.7 stable
echo.
echo Selected:
echo   Tier: %TIER_NAME%
echo   Runs: %RUNS_LABEL%
echo   Scope: %SCOPE_LABEL%
echo   Profile: %PROFILE_LABEL%
echo   Scenario probes: %SCENARIO_PROBES%
echo   Estimated runtime: %EST_RUNTIME_LABEL%
if not "%TIMEOUT_SECONDS%"=="0" echo   Timeout override: %TIME_CAP_LABEL%
echo   Purpose: %PURPOSE%
echo.
echo Project:
echo   %CD%
echo.
echo Logs:
echo   Godot: %LOG_FILE%
echo   Output: .godot\ai_simulation
if /I "%SHOW_COMMAND%"=="1" (
	echo.
	echo Command:
	echo "%GODOT_EXE%" --headless --path . --script %RUNNER_SCRIPT% --log-file %LOG_FILE% -- --runs %RUNS% --steps %STEPS% --seed %SEED% --scenario %SCENARIO% --trace %TRACE% --balance-profile %BALANCE_PROFILE% --scenario-probes %SCENARIO_PROBES% --output-dir %OUTPUT_DIR% %PUBLISH_ARGS% --timeout-seconds %TIMEOUT_SECONDS%
)
echo.
echo Progress:
echo.

set "HV_SIM_LAUNCHER=1"
"%GODOT_EXE%" --headless --path . --script %RUNNER_SCRIPT% --log-file %LOG_FILE% -- --runs %RUNS% --steps %STEPS% --seed %SEED% --scenario %SCENARIO% --trace %TRACE% --balance-profile %BALANCE_PROFILE% --scenario-probes %SCENARIO_PROBES% --output-dir %OUTPUT_DIR% %PUBLISH_ARGS% --timeout-seconds %TIMEOUT_SECONDS%
set "RESULT=%ERRORLEVEL%"
if exist "%LOG_FILE%" (
	findstr /c:"Hearthvale playtest simulation timed out" "%LOG_FILE%" >nul 2>nul
	if not errorlevel 1 set "RESULT=1"
	findstr /c:"SCRIPT ERROR:" "%LOG_FILE%" >nul 2>nul
	if not errorlevel 1 set "RESULT=1"
	findstr /c:"Failed to load script" "%LOG_FILE%" >nul 2>nul
	if not errorlevel 1 set "RESULT=1"
)

echo.
if "%RESULT%"=="0" (
	call :load_run_summary_values
	echo Summary:
	echo Result: completed
	echo Runs: !SUMMARY_RUNS!
	echo Issues: !SUMMARY_ISSUE_OCCURRENCES! occurrences, !SUMMARY_ISSUE_SAMPLES! samples
	echo Status: !SUMMARY_STATUS!
	echo Publication: !SUMMARY_PUBLICATION!
	echo Report: !SUMMARY_REPORT!
	if defined SUMMARY_WARNING (
		echo.
		echo Warnings:
		echo   !SUMMARY_WARNING!
	)
	set "LATEST_PROMPT_AFTER="
	for /f "delims=" %%F in ('dir /b /a-d /o-d ".godot\ai_simulation\ai_simulation_codex_prompt_*.md" 2^>nul') do if not defined LATEST_PROMPT_AFTER set "LATEST_PROMPT_AFTER=.godot\ai_simulation\%%F"
	if defined LATEST_PROMPT_AFTER if not "!LATEST_PROMPT_AFTER!"=="!LATEST_PROMPT_BEFORE!" (
		if /I not "%HV_NO_OPEN%"=="1" start "" notepad "!LATEST_PROMPT_AFTER!"
	)
) else (
	echo Summary:
	echo   Result: failed with exit code %RESULT%
	echo   Godot log: %CD%\%LOG_FILE%
	echo   Command:
	echo   "%GODOT_EXE%" --headless --path . --script %RUNNER_SCRIPT% --log-file %LOG_FILE% -- --runs %RUNS% --steps %STEPS% --seed %SEED% --scenario %SCENARIO% --trace %TRACE% --balance-profile %BALANCE_PROFILE% --scenario-probes %SCENARIO_PROBES% --output-dir %OUTPUT_DIR% %PUBLISH_ARGS% --timeout-seconds %TIMEOUT_SECONDS%
)

popd
call :pause_if_needed
exit /b %RESULT%

:choose_tier
set "CHOICE=%HV_SIM_CHOICE%"
if not defined CHOICE (
	echo Hearthvale AI simulation launcher
	echo.
	echo Default: 1 Light
	echo.
	echo   #  Tier             Est. Run   Runs    Scope            Scenario/Profile    Purpose
	echo   1  Light            ~3 min     120     200 steps        all/coverage        next improvement target
	echo   2  Deep             ~10 hr     4,500   1,800 steps      all/coverage        overnight audit
	echo   3  Cancel
	echo.
	set /p "CHOICE=Choose a tier [%RECOMMENDED_CHOICE%]: "
)
if "%CHOICE%"=="" set "CHOICE=%RECOMMENDED_CHOICE%"

if "%CHOICE%"=="1" (
	set "TIER_NAME=Light"
	set "PURPOSE=next improvement target"
	set "EST_RUNTIME_LABEL=~3 min"
	set "RUNS=120"
	set "STEPS=200"
	set "SEED=1"
	set "SCENARIO=all"
	set "TRACE=issues"
	set "BALANCE_PROFILE=coverage"
	set "SCENARIO_PROBES=auto"
	set "TIMEOUT_SECONDS=600"
	exit /b 0
)
if "%CHOICE%"=="2" (
	set "TIER_NAME=Deep"
	set "PURPOSE=overnight audit"
	set "EST_RUNTIME_LABEL=~10 hr"
	set "RUNS=4500"
	set "STEPS=1800"
	set "SEED=1"
	set "SCENARIO=all"
	set "TRACE=issues"
	set "BALANCE_PROFILE=coverage"
	set "SCENARIO_PROBES=auto"
	set "TIMEOUT_SECONDS=43200"
	exit /b 0
)
if "%CHOICE%"=="3" (
	echo Cancelled.
	exit /b 2
)

echo Invalid tier choice: %CHOICE%
exit /b 1

:choose_recommended_config
if not exist "%RECOMMEND_SCRIPT_FILE%" (
	echo Audit recommendation unavailable; missing %RECOMMEND_SCRIPT_FILE%
	exit /b 1
)
set "RECOMMENDED_RUNS="
set "RECOMMENDED_STEPS="
set "RECOMMENDED_SEED="
set "RECOMMENDED_SCENARIO="
set "RECOMMENDED_TRACE="
set "RECOMMENDED_PROFILE="
set "RECOMMENDED_TIMEOUT="
set "RECOMMENDED_PROBES="
set "RECOMMEND_ARGS_FILE=.godot_logs\recommend_ai_audit_args_%RANDOM%.txt"
"%GODOT_EXE%" --headless --path . --script %RECOMMEND_SCRIPT% --log-file %RECOMMEND_LOG% -- --output args --output-file "%RECOMMEND_ARGS_FILE%"
if errorlevel 1 (
	echo Audit recommendation did not return runnable settings.
	echo Godot log: %CD%\%RECOMMEND_LOG%
	exit /b 1
)
for /f "usebackq tokens=1-8" %%A in ("%RECOMMEND_ARGS_FILE%") do (
	set "RECOMMENDED_RUNS=%%A"
	set "RECOMMENDED_STEPS=%%B"
	set "RECOMMENDED_SEED=%%C"
	set "RECOMMENDED_SCENARIO=%%D"
	set "RECOMMENDED_TRACE=%%E"
	set "RECOMMENDED_PROFILE=%%F"
	set "RECOMMENDED_TIMEOUT=%%G"
	set "RECOMMENDED_PROBES=%%H"
)
if not defined RECOMMENDED_RUNS (
	echo Audit recommendation did not return runnable settings.
	exit /b 1
)
set "TIER_NAME=Custom"
set "PURPOSE=targeted evidence for the weakest audit lane"
set "EST_RUNTIME_LABEL=custom"
set "RUNS=%RECOMMENDED_RUNS%"
set "STEPS=%RECOMMENDED_STEPS%"
set "SEED=%RECOMMENDED_SEED%"
set "SCENARIO=%RECOMMENDED_SCENARIO%"
set "TRACE=%RECOMMENDED_TRACE%"
set "BALANCE_PROFILE=%RECOMMENDED_PROFILE%"
set "TIMEOUT_SECONDS=%RECOMMENDED_TIMEOUT%"
set "SCENARIO_PROBES=%RECOMMENDED_PROBES%"
exit /b 0

:validate_config
call :require_positive_int "%RUNS%" "runs"
if errorlevel 1 exit /b 1
call :require_positive_int "%STEPS%" "steps"
if errorlevel 1 exit /b 1
call :require_nonnegative_int "%SEED%" "seed"
if errorlevel 1 exit /b 1
call :require_nonnegative_int "%TIMEOUT_SECONDS%" "timeout seconds"
if errorlevel 1 exit /b 1
call :validate_scenario "%SCENARIO%"
if errorlevel 1 exit /b 1
call :validate_trace "%TRACE%"
if errorlevel 1 exit /b 1
call :validate_balance_profile "%BALANCE_PROFILE%"
if errorlevel 1 exit /b 1
call :validate_scenario_probes "%SCENARIO_PROBES%"
if errorlevel 1 exit /b 1
exit /b 0

:require_positive_int
echo(%~1| findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
	echo %~2 must be a positive integer.
	exit /b 1
)
exit /b 0

:require_nonnegative_int
echo(%~1| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
	echo %~2 must be a non-negative integer.
	exit /b 1
)
exit /b 0

:validate_scenario
if /I "%~1"=="all" exit /b 0
if /I "%~1"=="core_loop" exit /b 0
if /I "%~1"=="quest_chaser" exit /b 0
if /I "%~1"=="economy_stress" exit /b 0
if /I "%~1"=="combat_loot" exit /b 0
if /I "%~1"=="inventory_pressure" exit /b 0
if /I "%~1"=="random_guard" exit /b 0
echo scenario must be all, core_loop, quest_chaser, economy_stress, combat_loot, inventory_pressure, or random_guard.
exit /b 1

:validate_trace
if /I "%~1"=="issues" exit /b 0
if /I "%~1"=="all" exit /b 0
echo trace must be issues or all.
exit /b 1

:validate_balance_profile
if /I "%~1"=="default" exit /b 0
if /I "%~1"=="progression" exit /b 0
if /I "%~1"=="economy" exit /b 0
if /I "%~1"=="combat" exit /b 0
if /I "%~1"=="coverage" exit /b 0
echo balance profile must be default, progression, economy, combat, or coverage.
exit /b 1

:validate_scenario_probes
if /I "%~1"=="auto" exit /b 0
if /I "%~1"=="off" exit /b 0
if /I "%~1"=="smoke" exit /b 0
if /I "%~1"=="full" exit /b 0
echo scenario probes must be auto, off, smoke, or full.
exit /b 1

:prepare_display_values
call :format_int "%RUNS%" RUNS_LABEL
call :format_int "%STEPS%" STEPS_LABEL
if /I "%SCENARIO%"=="all" (
	set "SCOPE_LABEL=%STEPS_LABEL% steps, all scenarios"
) else (
	set "SCOPE_LABEL=%STEPS_LABEL% steps, %SCENARIO%"
)
if /I "%BALANCE_PROFILE%"=="default" (
	set "PROFILE_LABEL=default profile"
) else (
	set "PROFILE_LABEL=%BALANCE_PROFILE% profile"
)
call :format_time_cap "%TIMEOUT_SECONDS%" TIME_CAP_LABEL
exit /b 0

:format_int
set "FORMAT_VALUE=%~1"
set "FORMAT_RESULT="
:format_int_loop
if "!FORMAT_VALUE:~3!"=="" (
	if defined FORMAT_RESULT (
		set "FORMAT_RESULT=!FORMAT_VALUE!,!FORMAT_RESULT!"
	) else (
		set "FORMAT_RESULT=!FORMAT_VALUE!"
	)
) else (
	if defined FORMAT_RESULT (
		set "FORMAT_RESULT=!FORMAT_VALUE:~-3!,!FORMAT_RESULT!"
	) else (
		set "FORMAT_RESULT=!FORMAT_VALUE:~-3!"
	)
	set "FORMAT_VALUE=!FORMAT_VALUE:~0,-3!"
	goto format_int_loop
)
set "%~2=!FORMAT_RESULT!"
exit /b 0

:format_time_cap
set "%~2=%~1 sec"
if "%~1"=="0" set "%~2=disabled"
if "%~1"=="60" set "%~2=60 sec"
if "%~1"=="600" set "%~2=10 min"
if "%~1"=="10800" set "%~2=3 hr"
if "%~1"=="14400" set "%~2=4 hr"
if "%~1"=="36000" set "%~2=10 hr"
if "%~1"=="43200" set "%~2=12 hr"
exit /b 0

:pause_if_needed
if /I not "%HV_NO_PAUSE%"=="1" pause
exit /b 0

:print_recommendation
if exist "%RECOMMEND_SCRIPT_FILE%" (
	"%GODOT_EXE%" --headless --path . --script %RECOMMEND_SCRIPT% --log-file %RECOMMEND_LOG%
	if errorlevel 1 echo Audit recommendation unavailable; continuing with normal launcher options.
) else (
	echo Audit recommendation unavailable; missing %RECOMMEND_SCRIPT_FILE%
)
exit /b 0

:load_recommended_choice
set "RECOMMENDED_CHOICE=1"
if not exist "%RECOMMEND_SCRIPT_FILE%" exit /b 0
set "RECOMMENDED_CHOICE_RAW="
set "RECOMMEND_CHOICE_FILE=.godot_logs\recommend_ai_audit_choice_%RANDOM%.txt"
"%GODOT_EXE%" --headless --path . --script %RECOMMEND_SCRIPT% --log-file %RECOMMEND_LOG% -- --output choice --output-file "%RECOMMEND_CHOICE_FILE%"
if errorlevel 1 exit /b 0
for /f "usebackq tokens=1" %%A in ("%RECOMMEND_CHOICE_FILE%") do if not defined RECOMMENDED_CHOICE_RAW set "RECOMMENDED_CHOICE_RAW=%%A"
if "%RECOMMENDED_CHOICE_RAW%"=="0" set "RECOMMENDED_CHOICE=0"
if "%RECOMMENDED_CHOICE_RAW%"=="1" set "RECOMMENDED_CHOICE=1"
exit /b 0

:load_run_summary_values
set "SUMMARY_RUNS=%RUNS%"
set "SUMMARY_ISSUE_OCCURRENCES=unknown"
set "SUMMARY_ISSUE_SAMPLES=unknown"
set "SUMMARY_STATUS=simulation completed"
if /I "%TIER_NAME%"=="Light" set "SUMMARY_STATUS=light audit completed"
if /I "%TIER_NAME%"=="Deep" set "SUMMARY_STATUS=deep audit completed"
set "SUMMARY_PUBLISH_STATUS=unknown"
set "SUMMARY_PUBLICATION=unknown"
set "SUMMARY_WARNING="
set "SUMMARY_REPORT=%OUTPUT_DIR%"
if not exist ".godot\ai_simulation\_working\current\summary.json" goto map_publication_status
set "SUMMARY_VALUES_FILE=.godot_logs\ai_simulation_summary_values_%RANDOM%.txt"
"%GODOT_EXE%" --headless --path . --script %SUMMARY_READER_SCRIPT% --log-file %SUMMARY_READER_LOG% -- --summary-path ".godot\ai_simulation\_working\current\summary.json" --output-file "%SUMMARY_VALUES_FILE%"
if errorlevel 1 goto map_publication_status
for /f "usebackq tokens=1* delims==" %%A in ("%SUMMARY_VALUES_FILE%") do (
	if "%%A"=="SUMMARY_RUNS" set "SUMMARY_RUNS=%%B"
	if "%%A"=="SUMMARY_ISSUE_OCCURRENCES" set "SUMMARY_ISSUE_OCCURRENCES=%%B"
	if "%%A"=="SUMMARY_ISSUE_SAMPLES" set "SUMMARY_ISSUE_SAMPLES=%%B"
	if "%%A"=="SUMMARY_PUBLISH_STATUS" set "SUMMARY_PUBLISH_STATUS=%%B"
)
:map_publication_status
if /I "%SUMMARY_PUBLISH_STATUS%"=="published" set "SUMMARY_PUBLICATION=promoted as latest"
if /I "%SUMMARY_PUBLISH_STATUS%"=="published_allowed_downgrade" (
	set "SUMMARY_PUBLICATION=promoted as latest with lower coverage allowed"
	set "SUMMARY_WARNING=A lower-coverage run replaced a stronger previous latest report."
)
if /I "%SUMMARY_PUBLISH_STATUS%"=="blocked_lower_coverage" (
	set "SUMMARY_PUBLICATION=not promoted as latest because lower coverage cannot replace stronger coverage"
	set "SUMMARY_WARNING=A stronger previous latest report was preserved."
)
if /I "%SUMMARY_PUBLISH_STATUS%"=="not_requested" set "SUMMARY_PUBLICATION=not requested"
exit /b 0
