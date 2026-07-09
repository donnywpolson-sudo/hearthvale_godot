@echo off
setlocal
title Hearthvale AI Audit Workflow

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "WORKFLOW_ROOT=%%~fI"
set "PS_SCRIPT=%WORKFLOW_ROOT%\RUN_AUDIT.ps1"

if not exist "%PS_SCRIPT%" (
    echo Problem: RUN_AUDIT.ps1 was not found.
    echo How to fix it: Keep RUN_AUDIT.ps1 in the parent _ai_audit_workflow folder.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo Workflow exited with an error. Read the message above for the fix.
    echo.
    pause
)

exit /b %EXIT_CODE%
