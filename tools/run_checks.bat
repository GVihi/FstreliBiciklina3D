@echo off
rem Runs every check in tools\ with one command and prints PASSED or FAILED for each, and why.
rem Usage:  tools\run_checks.bat [words to pick checks] [--godot path\to\godot.exe] [--list] [--fail-fast] [--lint]
rem Godot is found by itself (and remembered after the first time). See the top of tools\run_checks.py.
rem Exit code 0 = every check passed, 1 = something failed, 2 = Godot not found.
setlocal

where py >nul 2>nul
if %ERRORLEVEL%==0 (
  py -3 "%~dp0run_checks.py" %*
) else (
  where python >nul 2>nul
  if %ERRORLEVEL%==0 (
    python "%~dp0run_checks.py" %*
  ) else (
    echo Python 3 is needed for this script. Install it from python.org, then run this again.
    set "RESULT=2"
    goto done
  )
)
set "RESULT=%ERRORLEVEL%"
:done
echo.
if "%RESULT%"=="0" (
  echo All checks passed.
) else (
  echo Not everything passed. check_logs\summary.txt has the list; send that file back.
)
pause
exit /b %RESULT%
