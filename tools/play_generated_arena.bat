@echo off
rem Plays the game in a window on a generated arena (README Milestone K). This is now what the game does by default;
rem the flag is kept so the old way of starting still works. tools\play_roundabout.bat plays the old roundabout.
rem Usage:  tools\play_generated_arena.bat [path\to\godot.exe]
rem If no path is given, the default Steam folder is searched.
rem The title screen shows the arena of today's daily seed; every run plays on the arena of its run seed.
rem The console window prints the seed and size of each arena that is built, plus any script errors.
setlocal

set "PROJECT=%~dp0.."

if not "%~1"=="" set "GODOT=%~1"
if defined GODOT goto have_godot

set "STEAMDIR=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine"
for %%F in ("%STEAMDIR%\*console*.exe") do set "GODOT=%%~fF"
if defined GODOT goto have_godot
for %%F in ("%STEAMDIR%\*.exe") do set "GODOT=%%~fF"
if defined GODOT goto have_godot

echo Could not find Godot in the default Steam folder.
echo Pass the full path to the Godot exe as the first argument, for example:
echo   tools\play_generated_arena.bat "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.editor.x86_64.console.exe"
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
echo Starting the game on a generated arena. Close the game window to finish.
echo.
"%GODOT%" --path "%PROJECT%" -- --generated-arena
echo.
echo The game was closed. If anything looked wrong, copy the lines printed above and send them back.
pause
