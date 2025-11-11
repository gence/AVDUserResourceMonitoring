@echo off
REM Batch file to set up scheduled tasks for AVDSessionWatch
REM Author: GitHub Copilot, Gence Soysal
REM Date: November 8, 2025
REM Run this file as Administrator

echo Setting up AVDSessionWatch scheduled tasks...
echo.

echo Creating task: AVD\AVDSessionWatch-UserProcesses
schtasks /create /tn "AVD\AVDSessionWatch-UserProcesses" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\ProgramData\AVDSessionWatch\processes.ps1\"" /sc minute /mo 5 /ru "SYSTEM" /rl HIGHEST /f
if %errorlevel%==0 (
    echo SUCCESS: UserProcesses task created
) else (
    echo ERROR: Failed to create UserProcesses task
)
echo.

echo Creating task: AVD\AVDSessionWatch-UserSessions
schtasks /create /tn "AVD\AVDSessionWatch-UserSessions" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\ProgramData\AVDSessionWatch\sessions.ps1\"" /sc minute /mo 5 /ru "SYSTEM" /rl HIGHEST /f
if %errorlevel%==0 (
    echo SUCCESS: UserSessions task created
) else (
    echo ERROR: Failed to create UserSessions task
)
echo.

echo Creating task: AVD\AVDSessionWatch-Cleanup (runs daily at 8 PM)
schtasks /create /tn "AVD\AVDSessionWatch-Cleanup" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\ProgramData\AVDSessionWatch\cleanup.ps1\"" /sc daily /st 20:00 /ru "SYSTEM" /rl HIGHEST /f
if %errorlevel%==0 (
    echo SUCCESS: Cleanup task created
) else (
    echo ERROR: Failed to create Cleanup task
)
echo.

echo All tasks have been set up!
echo.
echo To verify the tasks were created, run:
echo schtasks /query /fo table ^| findstr "AVD"
echo.
echo To test the tasks immediately, run:
echo schtasks /run /tn "AVD\AVDSessionWatch-UserProcesses"
echo schtasks /run /tn "AVD\AVDSessionWatch-UserSessions"
echo schtasks /run /tn "AVD\AVDSessionWatch-Cleanup"
echo.
