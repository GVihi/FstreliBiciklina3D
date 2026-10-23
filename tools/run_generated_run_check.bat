@echo off
rem Runs tools/generated_run_check.gd (a short scripted run on generated arenas) headless on Windows.
rem Usage:  tools\run_generated_run_check.bat [path\to\godot.exe] [number-of-seeds]
rem If no path is given, the default Steam folder is searched. The number of seeds defaults to 4.
rem Exit code 0 = every run played clean, 1 = problems (they are printed above).
setlocal

set "PROJECT=%~dp0.."
set "SEEDS=%~2"
if "%SEEDS%"=="" set "SEEDS=4"

if not "%~1"=="" set "GODOT=%~1"
if defined GODOT goto have_godot

set "STEAMDIR=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine"
for %%F in ("%STEAMDIR%\*console*.exe") do set "GODOT=%%~fF"
if defined GODOT goto have_godot
for %%F in ("%STEAMDIR%\*.exe") do set "GODOT=%%~fF"
if defined GODOT goto have_godot

echo Could not find Godot in the default Steam folder.
echo Pass the full path to the Godot exe as the first argument, for example:
echo   tools\run_generated_run_check.bat "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.editor.x86_64.console.exe"
exit /b 1

:have_godot
if exist "%GODOT%" goto godot_ok
echo Godot not found at the path given.
exit /b 1
:godot_ok
echo Using Godot: %GODOT%
echo Godot version (the project needs 4.7 or newer):
"%GODOT%" --version
echo.

echo === Generated arena run check (%SEEDS% seeds, 30 s of play each) ===
"%GODOT%" --headless --path "%PROJECT%" --script res://tools/generated_run_check.gd -- %SEEDS%
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
  echo PASSED.
) else (
  echo FAILED with exit code %RESULT%. Copy the lines printed above and send them back.
)
pause
exit /b %RESULT%
