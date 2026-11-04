@echo off
rem Serves the web build at http://localhost:8060 (no-cache, so a rebuilt game always loads fresh)
cd /d "%~dp0"
python tools\serve_web.py 8060
pause
