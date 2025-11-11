# PowerShell script to install session watch scripts on target VM
# Author: GitHub Copilot, Gence Soysal
# Date: November 8, 2025

param([string]$InstallPath = "C:\ProgramData\AVDSessionWatch")

Write-Host "Starting AVDSessionWatch deployment..."
Write-Host "Install path: $InstallPath"

# Create installation directory
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    # Remove inherited permissions
    icacls $InstallPath /inheritance:d

    # Grant SYSTEM full control
    icacls $InstallPath /grant 'SYSTEM:(OI)(CI)F'

    # Grant Administrators full control
    icacls $InstallPath /grant 'Administrators:(OI)(CI)F'

    # Remove Users group entirely
    icacls $InstallPath /remove 'Users'

    Write-Host "Created directory: $InstallPath"
}

# Copy files from script location to install path
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path $scriptPath) {
    Write-Host "Copying files from $scriptPath to $InstallPath..."
    Copy-Item "$scriptPath\*" -Destination $InstallPath -Force
    Write-Host "Files copied successfully"
} else {
    Write-Host "Error: Script directory not found at $scriptPath"
    exit 1
}

# Set execution policy for PowerShell scripts
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
    Write-Host "Set PowerShell execution policy"
} catch {
    Write-Host "Warning: Could not set execution policy: $_"
}

# Run setup to create scheduled tasks
Write-Host "Setting up scheduled tasks..."
$setupPath = Join-Path $InstallPath "setup-tasks.bat"
if (Test-Path $setupPath) {
    Start-Process -FilePath $setupPath -Wait -WindowStyle Hidden
    Write-Host "Scheduled tasks created"
} else {
    Write-Host "Error: setup-tasks.bat not found"
    exit 1
}

# Create initial directories
$tasklistDir = Join-Path $InstallPath "AVDUserProcesses"
$sessionsDir = Join-Path $InstallPath "AVDUserSessions"

if (-not (Test-Path $tasklistDir)) {
    New-Item -ItemType Directory -Path $tasklistDir -Force | Out-Null
    Write-Host "Created AVDUserProcesses directory"
}

if (-not (Test-Path $sessionsDir)) {
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null
    Write-Host "Created AVDUserSessions directory"
}

Write-Host "AVDSessionWatch deployment completed successfully!"
Write-Host "Monitoring will begin automatically via scheduled tasks"