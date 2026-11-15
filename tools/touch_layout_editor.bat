@echo off
rem Double click this to move the touch controls. It needs the Python that is already
rem installed; nothing else is downloaded.
cd /d "%~dp0"
where pythonw >nul 2>nul
if errorlevel 1 (
  python "%~dp0touch_layout_editor.py"
) else (
  start "" pythonw "%~dp0touch_layout_editor.py"
)
