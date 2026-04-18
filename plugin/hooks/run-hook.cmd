: << 'CMDBLOCK'
@echo off
setlocal enabledelayedexpansion
set "SCRIPT_DIR=%~dp0"
set "SCRIPT_NAME=%~1"
shift
set "BASH_EXE="
for %%G in (
  "C:\Program Files\Git\bin\bash.exe"
  "C:\Program Files (x86)\Git\bin\bash.exe"
  "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
) do (
  if exist %%G (
    set "BASH_EXE=%%~G"
    goto :found
  )
)
for %%G in (bash.exe) do (
  if not "%%~$PATH:G"=="" (
    set "BASH_EXE=%%~$PATH:G"
    goto :found
  )
)
exit /b 0
:found
"%BASH_EXE%" "%SCRIPT_DIR%%SCRIPT_NAME%" %1 %2 %3 %4 %5 %6 %7 %8 %9
exit /b %ERRORLEVEL%
CMDBLOCK

#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
