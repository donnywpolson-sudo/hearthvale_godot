@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PROJECT_ROOT=%~dp0"
set "GODOT_EXE=C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe"
set "RUNNER_SCRIPT=res://scripts/playtest_simulation_runner.gd"
set "LOG_FILE=.godot_logs\playtest_simulation.log"
set "OUTPUT_DIR=res://.godot/ai_simulation/_working/current"
set "PUBLIC_OUTPUT_ROOT=res://.godot/ai_simulation"
set "SHOW_COMMAND=%HV_SIM_SHOW_COMMAND%"
set "TIER_NAME=Custom"
set "PURPOSE=custom run"
set "EST_RUNTIME_LABEL=not estimated"

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

set "RUNS=1000"
set "STEPS=300"
set "SEED=1"
set "SCENARIO=all"
set "TRACE=issues"
set "BALANCE_PROFILE=default"
set "SCENARIO_PROBES=auto"
set "TIMEOUT_SECONDS=0"

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

if not exist ".godot_logs" mkdir ".godot_logs" >nul 2>nul
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
	echo Summary:
	echo   Result: completed
	set "LATEST_PROMPT_AFTER="
	for /f "delims=" %%F in ('dir /b /a-d /o-d ".godot\ai_simulation\ai_simulation_codex_prompt_*.md" 2^>nul') do if not defined LATEST_PROMPT_AFTER set "LATEST_PROMPT_AFTER=.godot\ai_simulation\%%F"
	if defined LATEST_PROMPT_AFTER if not "!LATEST_PROMPT_AFTER!"=="!LATEST_PROMPT_BEFORE!" (
		echo   Latest prompt: %CD%\!LATEST_PROMPT_AFTER!
		if /I not "%HV_NO_OPEN%"=="1" start "" notepad "!LATEST_PROMPT_AFTER!"
	) else (
		echo   Latest prompt: unchanged
		echo   Archive: %CD%\.godot\ai_simulation\archive
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
	echo   #  Tier             Est. Run   Runs    Scope            Scenario/Profile    Purpose
	echo   1  Strategy Smoke   ~1 min     12      150 steps        all/default         quick sanity check
	echo   2  Medium           ~10 min    1,000   300 steps        all/default         normal research
	echo   3  Deep             ~3 hr      10,000  720 steps        all/coverage        deeper evidence
	echo   4  Overnight        ~10 hr     16,000  1,800 steps      all/coverage        full research
	echo   5  Cancel
	echo.
	set /p "CHOICE=Choose a tier [1]: "
)
if "%CHOICE%"=="" set "CHOICE=1"

if "%CHOICE%"=="1" (
	set "TIER_NAME=Strategy Smoke"
	set "PURPOSE=quick sanity check"
	set "EST_RUNTIME_LABEL=~1 min"
	set "RUNS=12"
	set "STEPS=150"
	set "SEED=1"
	set "SCENARIO=all"
	set "TRACE=issues"
	set "BALANCE_PROFILE=default"
	set "SCENARIO_PROBES=auto"
	set "TIMEOUT_SECONDS=0"
	exit /b 0
)
if "%CHOICE%"=="2" (
	set "TIER_NAME=Medium"
	set "PURPOSE=normal research"
	set "EST_RUNTIME_LABEL=~10 min"
	set "RUNS=1000"
	set "STEPS=300"
	set "SEED=1"
	set "SCENARIO=all"
	set "TRACE=issues"
	set "BALANCE_PROFILE=default"
	set "SCENARIO_PROBES=auto"
	set "TIMEOUT_SECONDS=0"
	exit /b 0
)
if "%CHOICE%"=="3" (
	set "TIER_NAME=Deep"
	set "PURPOSE=deeper evidence"
	set "EST_RUNTIME_LABEL=~3 hr"
	set "RUNS=10000"
	set "STEPS=720"
	set "SEED=1"
	set "SCENARIO=all"
	set "TRACE=issues"
	set "BALANCE_PROFILE=coverage"
	set "SCENARIO_PROBES=auto"
	set "TIMEOUT_SECONDS=14400"
	exit /b 0
)
if "%CHOICE%"=="4" (
	set "TIER_NAME=Overnight"
	set "PURPOSE=full research"
	set "EST_RUNTIME_LABEL=~10 hr"
	set "RUNS=16000"
	set "STEPS=1800"
	set "SEED=1"
	set "SCENARIO=all"
	set "TRACE=issues"
	set "BALANCE_PROFILE=coverage"
	set "SCENARIO_PROBES=auto"
	set "TIMEOUT_SECONDS=43200"
	exit /b 0
)
if "%CHOICE%"=="5" (
	echo Cancelled.
	exit /b 2
)

echo Invalid tier choice: %CHOICE%
exit /b 1

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
