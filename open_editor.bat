@echo off
setlocal
cd /d "%~dp0"

set "GODOT_EXE="
if exist "C:\Users\kingd\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=C:\Users\kingd\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_EXE if exist "%USERPROFILE%\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=%USERPROFILE%\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_EXE if exist "%USERPROFILE%\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=%USERPROFILE%\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_EXE if exist "..\..\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=..\..\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_EXE if not exist "C:\Users\kingd\Desktop\Godot_v4.7.2-stable_win64.exe\*" if exist "C:\Users\kingd\Desktop\Godot_v4.7.2-stable_win64.exe" set "GODOT_EXE=C:\Users\kingd\Desktop\Godot_v4.7.2-stable_win64.exe"

if not defined GODOT_EXE (
    echo [ERROR] Could not find Godot_v4.7.2-stable_win64.exe
    pause
    exit /b 1
)

echo Opening NODEVERSE 3D Project in Godot 4.7 Editor...
start "" "%GODOT_EXE%" --editor --path "%CD%" "res://scenes/AssetShowcase.tscn"
