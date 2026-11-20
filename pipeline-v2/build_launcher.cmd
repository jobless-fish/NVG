@echo off
REM P5: build launcher.exe (Windows). Needs Python 3.11+ on this PC.
python -m pip install --quiet pyinstaller==6.11.1 || exit /b 1
python -m PyInstaller --onefile --name launcher --clean launcher.py || exit /b 1
echo Built dist\launcher.exe
