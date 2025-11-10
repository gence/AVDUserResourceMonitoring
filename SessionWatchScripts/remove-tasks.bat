@echo off
REM Batch file to remove scheduled tasks for AVDSessionWatch
REM Author: GitHub Copilot
REM Date: November 8, 2025
REM Run this file as Administrator

echo Removing AVDSessionWatch scheduled tasks...
echo.

echo Removing task: AVD\AVDSessionWatch-AVDUserProcesses
schtasks /delete /tn "AVD\AVDSessionWatch-AVDUserProcesses" /f
if %errorlevel%==0 (
    echo SUCCESS: AVDUserProcesses task removed
) else (
    echo ERROR: Failed to remove AVDUserProcesses task (may not exist)
)
echo.

echo Removing task: AVD\AVDSessionWatch-AVDSessions
schtasks /delete /tn "AVD\AVDSessionWatch-AVDSessions" /f
if %errorlevel%==0 (
    echo SUCCESS: AVDSessions task removed
) else (
    echo ERROR: Failed to remove AVDSessions task (may not exist)
)
echo.

echo Removing task: AVD\AVDSessionWatch-Cleanup
schtasks /delete /tn "AVD\AVDSessionWatch-Cleanup" /f
if %errorlevel%==0 (
    echo SUCCESS: Cleanup task removed
) else (
    echo ERROR: Failed to remove Cleanup task (may not exist)
)
echo.

echo Task removal completed!
echo.
