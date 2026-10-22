@echo off
rem Runs tools/baseline.gd twice (Forward+, then Compatibility) on Windows.
rem Usage:  tools\run_baseline.bat [path\to\godot.exe] [label-prefix]
rem If no path is given, the default Steam folder is searched. See tools\BASELINE.md.
setlocal

set "PROJECT=%~dp0.."
set "PREFIX=%~2"
if "%PREFIX%"=="" set "PREFIX=oldpc"

if not "%~1"=="" set "GODOT=%~1"
if defined GODOT goto have_godot

set "STEAMDIR=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine"
for %%F in ("%STEAMDIR%\*console*.exe") do set "GODOT=%%~fF"
if defined GODOT goto have_godot
for %%F in ("%STEAMDIR%\*.exe") do set "GODOT=%%~fF"
if defined GODOT goto have_godot

echo Could not find Godot in the default Steam folder.
echo Pass the full path to the Godot exe as the first argument, for example:
echo   tools\run_baseline.bat "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.editor.x86_64.console.exe"
exit /b 1

:have_godot
if not exist "%GODOT%" (
  echo Godot not found at: %GODOT%
  exit /b 1
)
echo Using Godot: %GODOT%
echo Do not touch the mouse or keyboard until both runs are finished.
echo.

echo === Run 1 of 2: Forward+ ===
"%GODOT%" --path "%PROJECT%" --rendering-method forward_plus --script res://tools/baseline.gd -- --label=%PREFIX%-forward --requested=forward_plus
echo.
echo === Run 2 of 2: Compatibility ===
"%GODOT%" --path "%PROJECT%" --rendering-method gl_compatibility --script res://tools/baseline.gd -- --label=%PREFIX%-compat --requested=gl_compatibility
echo.
echo Done. Results are in the baseline_out folder in the project folder.
echo Zip that folder and send it back.
pause
