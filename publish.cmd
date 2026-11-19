@echo off
REM Double-click to publish this plugin to GitHub.
REM Asks for: username, repo name, and a Personal Access Token (hidden input).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1"
echo.
pause
