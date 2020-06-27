setlocal enabledelayedexpansion
powershell.exe -ExecutionPolicy Unrestricted -NoProfile -WindowStyle Hidden -File "%~dp0..\build\windows\Makefile.ps1"
endlocal
exit /B %ERRORLEVEL%
