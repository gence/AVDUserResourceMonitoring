@echo off
REM Batch file to set up scheduled tasks for AVDSessionWatch
REM Author: GitHub Copilot
REM Date: November 8, 2025
REM Run this file as Administrator

echo Setting up AVDSessionWatch scheduled tasks...
echo.

echo Creating task: AVD\AVDSessionWatch-AVDUserProcesses (runs every minute)
schtasks /create /tn "AVD\AVDSessionWatch-AVDUserProcesses" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\ProgramData\AVDSessionWatch\tasklist.ps1\"" /sc minute /mo 1 /ru "SYSTEM" /rl HIGHEST /f
if %errorlevel%==0 (
    echo SUCCESS: AVDUserProcesses task created
) else (
    echo ERROR: Failed to create AVDUserProcesses task
)
echo.

echo Creating task: AVD\AVDSessionWatch-AVDSessions (runs every minute)
schtasks /create /tn "AVD\AVDSessionWatch-AVDSessions" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\ProgramData\AVDSessionWatch\sessions.ps1\"" /sc minute /mo 1 /ru "SYSTEM" /rl HIGHEST /f
if %errorlevel%==0 (
    echo SUCCESS: AVDSessions task created
) else (
    echo ERROR: Failed to create AVDSessions task
)
echo.

echo Creating task: AVD\AVDSessionWatch-Cleanup (runs daily at 2 AM)
schtasks /create /tn "AVD\AVDSessionWatch-Cleanup" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\ProgramData\AVDSessionWatch\cleanup.ps1\"" /sc daily /st 02:00 /ru "SYSTEM" /rl HIGHEST /f
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
echo schtasks /run /tn "AVD\AVDSessionWatch-AVDUserProcesses"
echo schtasks /run /tn "AVD\AVDSessionWatch-AVDSessions"
echo schtasks /run /tn "AVD\AVDSessionWatch-Cleanup"
echo.
