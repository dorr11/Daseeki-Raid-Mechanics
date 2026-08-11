@echo off
REM Run the Daseeki-Raid-Mechanics migration self-test harness under real Lua 5.1.
REM Reuses the interpreter vendored with the Nexus harness (no second copy).
REM Usage: run-selftests.cmd [RM_DIR]
REM
REM The addon-message simulator DEFAULTS to synchronous in-call dispatch
REM (CLIENT_ASYNC_LESSONS.md class 9): a group broadcast is handed back to this
REM client's own CHAT_MSG_ADDON handler from inside SendAddonMessage. Run the whole
REM suite under a named variant with:
REM     set DRM_DISPATCH=async     (the echo arrives one scheduler pass later)
REM     set DRM_DISPATCH=silent    (no self-delivery — the pre-2026-08-10 posture)
REM All three must be green.
setlocal
set HERE=%~dp0
set LUA=%HERE%..\..\nexus-test-harness\lua51\lua5.1.exe
if not exist "%LUA%" set LUA=%HERE%..\..\..\nexus-test-harness\lua51\lua5.1.exe
if not exist "%LUA%" set LUA=%HERE%..\..\..\..\nexus-test-harness\lua51\lua5.1.exe
if not exist "%LUA%" (
  echo ERROR: lua5.1.exe not found. Expected under a sibling nexus-test-harness\lua51\
  exit /b 2
)
set RMDIR=%~1
if "%RMDIR%"=="" set RMDIR=%HERE%..
"%LUA%" "%HERE%run-selftests.lua" "%RMDIR%"
exit /b %ERRORLEVEL%
