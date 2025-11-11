@echo off
REM Batch file to remove scheduled tasks for AVDSessionWatch
REM Author: GitHub Copilot, Gence Soysal
REM Date: November 8, 2025
REM Run this file as Administrator

echo Removing AVDSessionWatch scheduled tasks...
echo.

echo Removing task: AVD\AVDSessionWatch-UserProcesses
schtasks /delete /tn "AVD\AVDSessionWatch-UserProcesses" /f
if %errorlevel%==0 (
    echo SUCCESS: UserProcesses task removed
) else (
    echo ERROR: Failed to remove UserProcesses task (may not exist)
)
echo.

echo Removing task: AVD\AVDSessionWatch-UserSessions
schtasks /delete /tn "AVD\AVDSessionWatch-UserSessions" /f
if %errorlevel%==0 (
    echo SUCCESS: UserSessions task removed
) else (
    echo ERROR: Failed to remove UserSessions task (may not exist)
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
