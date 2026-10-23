@echo off
cd /d "%~dp0"
start "" /b powershell.exe -NoProfile -WindowStyle Hidden -File "%~dp0tools\director\start.ps1"
start "" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
