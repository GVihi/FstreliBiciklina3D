@echo off
rem Runs the bot playthrough balance harness (tools/bot_run.gd) on Windows.
rem Usage:  tools\run_bot_run.bat [bot_run arguments]
rem Examples:
rem   tools\run_bot_run.bat                                  8 seeds at Heat 0
rem   tools\run_bot_run.bat --heat 0,3,5 --seeds 20          README H1.12: three levels, one comparison table
rem   tools\run_bot_run.bat --each-mod --seeds 6             README H2.6: every modifier rank alone
rem   tools\run_bot_run.bat --maxed --heat 0 --seeds 6       README H2.6: the maxed set against Heat 0
rem   tools\run_bot_run.bat --mods "swift=2,crowd=1;lives=2" your own sets
rem All arguments are in the header of tools\bot_run.gd. The summary is written to bot_run_summary.txt in the
rem project folder (--out PATH changes that). Nothing is written to your real saves.
rem To use a Godot that is not found by itself, set the GODOT variable first:  set GODOT=D:\path\to\godot.console.exe
rem Godot is found the same way as tools\run_baseline.bat does it: the GODOT variable, then the default Steam folder.
setlocal

set "PROJECT=%~dp0.."

if defined GODOT goto have_godot

set "STEAMDIR=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine"
for %%F in ("%STEAMDIR%\*console*.exe") do set "GODOT=%%~fF"
if defined GODOT goto have_godot
for %%F in ("%STEAMDIR%\*.exe") do set "GODOT=%%~fF"
if defined GODOT goto have_godot

echo Could not find Godot in the default Steam folder.
echo Set the GODOT variable to the full path of the Godot exe and run this again, for example:
echo   set GODOT=D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.editor.x86_64.console.exe
exit /b 1

:have_godot
if exist "%GODOT%" goto godot_ok
echo Godot not found at "%GODOT%".
exit /b 1
:godot_ok
echo Using Godot: %GODOT%
echo Godot version (the project needs 4.7 or newer):
"%GODOT%" --version
echo The bot plays whole runs headless, this can take several minutes. Do not close the window.
echo.

rem run from the project folder, so bot_run_summary.txt lands there whatever folder this was started from
pushd "%PROJECT%"
"%GODOT%" --headless --path "%PROJECT%" --script res://tools/bot_run.gd -- %*
set "CODE=%ERRORLEVEL%"
popd
echo.
echo Done (exit code %CODE%). The summary is in bot_run_summary.txt in the project folder.
exit /b %CODE%
