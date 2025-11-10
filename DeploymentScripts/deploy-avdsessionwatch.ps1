# Azure VM Monitoring Deployment Script
# Author: GitHub Copilot
# Date: November 8, 2025
# Purpose: Deploy AVDSessionWatch monitoring solution to Azure VMs

param(
    [Parameter(Mandatory=$false)]
    [string[]]$VMNames,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName = "",

    [Parameter(Mandatory=$false)]
    [string]$StorageAccountKey = "",

    [Parameter(Mandatory=$false)]
    [string]$ContainerName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory=$false)]
    [switch]$UseLocalFiles = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestMode = $false
)

# Function to write deployment logs
function Write-DeployLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    $logMessage | Out-File -FilePath "deployment.log" -Append -Encoding UTF8
}

# Function to create package with all monitoring files
function New-AVDSessionWatchPackage {
    Write-DeployLog "Creating package..."
    
    # Define files to package
    $filesToPackage = @(
        "tasklist.ps1",
        "sessions.ps1", 
        "cleanup.ps1",
        "setup-tasks.bat",
        "remove-tasks.bat"
    )
    
    # Create package directory
    $packageDir = "AVDSessionWatchPackage"
    if (Test-Path $packageDir) {
        Remove-Item $packageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    
    # Copy files to package
    foreach ($file in $filesToPackage) {
        if (Test-Path $file) {
            Copy-Item $file -Destination $packageDir
            Write-DeployLog "Added $file to package"
        } else {
            Write-DeployLog "Warning: $file not found" "WARN"
        }
    }
    
    # Create deployment script for target VMs
    $deployScript = @'
# Target VM Deployment Script
# This script runs on each target VM to set up monitoring

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
$tasklistDir = Join-Path $InstallPath "tasklist"
$sessionsDir = Join-Path $InstallPath "sessions"

if (-not (Test-Path $tasklistDir)) {
    New-Item -ItemType Directory -Path $tasklistDir -Force | Out-Null
    Write-Host "Created tasklist directory"
}

if (-not (Test-Path $sessionsDir)) {
    New-Item -ItemType Directory -Path $sessionsDir -Force | Out-Null
    Write-Host "Created sessions directory"
}

Write-Host "AVDSessionWatch deployment completed successfully!"
Write-Host "Monitoring will begin automatically via scheduled tasks"
'@

    $deployScript | Out-File -FilePath "$packageDir\install-avdsessionwatch.ps1" -Encoding UTF8
    Write-DeployLog "Created install-avdsessionwatch.ps1"

    return $packageDir
}

# Function to upload package to Azure Storage (if using storage account)
function Upload-ToAzureStorage {
    param([string]$PackageDir)
    
    if (-not $StorageAccountName) {
        Write-DeployLog "No storage account specified, skipping upload"
        return $null
    }
    
    Write-DeployLog "Uploading package to Azure Storage..."
    
    try {
        # Create storage context with Entra ID authentication
        try {
            Write-DeployLog "Creating storage context with Entra ID authentication..."
            $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
        } catch {
            Write-DeployLog "Entra ID auth failed, falling back to access key..." "WARN"
            $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
        }
        
        # Create container if it doesn't exist
        New-AzStorageContainer -Name $ContainerName -Context $ctx -Permission Off -ErrorAction SilentlyContinue

        # Upload all files in package
        $uploadedFiles = @()
        Get-ChildItem $PackageDir | ForEach-Object {
            Write-DeployLog "Uploading: $($_.Name)"
            $blob = Set-AzStorageBlobContent -File $_.FullName -Container $ContainerName -Blob $_.Name -Context $ctx -Force
            $blobUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$($_.Name)"
            $uploadedFiles += $blobUri
            Write-DeployLog "Uploaded: $($_.Name) -> $blobUri"
        }
        
        return $uploadedFiles
    } catch {
        Write-DeployLog "Error uploading to storage: $_" "ERROR"
        Write-DeployLog "Storage Account: $StorageAccountName" "ERROR"
        Write-DeployLog "Container: $ContainerName" "ERROR"
        return $null
    }
}

# Function to deploy to a single VM
function Deploy-ToVM {
    param(
        [string]$VMName,
        [string[]]$FileUris = @()
    )
    
    Write-DeployLog "Deploying to VM: $VMName"
    
    try {
        if ($TestMode) {
            Write-DeployLog "TEST MODE: Would deploy to $VMName with files: $($FileUris -join ', ')"
            return $true
        }
        
        # Prepare command based on deployment method
        if ($UseLocalFiles) {
            # For local deployment, we need to copy files first
            $command = @"
# Copy package files to temp location
`$tempPath = `$env:TEMP + '\AVDSessionWatchPackage'
if (Test-Path `$tempPath) { Remove-Item `$tempPath -Recurse -Force }
New-Item -ItemType Directory -Path `$tempPath -Force | Out-Null

# Download and extract would happen here in real scenario
# For now, assuming files are already on the VM
Write-Host 'Local file deployment not yet implemented'

# Run installation
PowerShell.exe -ExecutionPolicy Bypass -File `$tempPath\install-monitoring.ps1
"@
        } else {
            # For storage account deployment
            $command = @"
# Create temp directory
`$tempPath = `$env:TEMP + '\AVDSessionWatchPackage'
if (Test-Path `$tempPath) { Remove-Item `$tempPath -Recurse -Force }
New-Item -ItemType Directory -Path `$tempPath -Force | Out-Null

# Download all files
$($FileUris | ForEach-Object { "Invoke-WebRequest -Uri '$_' -OutFile ('`$tempPath\' + (Split-Path '$_' -Leaf))" }) -join "`n"

# Run installation
PowerShell.exe -ExecutionPolicy Bypass -File `$tempPath\install-avdsessionwatch.ps1
"@
        }
        
        # Deploy using Custom Script Extension
        $extensionName = "AVDSessionWatchSetup"
        
        if ($FileUris.Count -gt 0) {
            $result = Set-AzVMCustomScriptExtension `
                -ResourceGroupName $ResourceGroupName `
                -VMName $VMName `
                -Location $Location `
                -FileUri $FileUris `
                -Run "install-avdsessionwatch.ps1" `
                -Name $extensionName `
                -ForceRerun (Get-Date).Ticks.ToString()
        } else {
            # Use command execution for local files
            $result = Set-AzVMCustomScriptExtension `
                -ResourceGroupName $ResourceGroupName `
                -VMName $VMName `
                -Location $Location `
                -CommandToExecute "powershell.exe -Command `"$command`"" `
                -Name $extensionName `
                -ForceRerun (Get-Date).Ticks.ToString()
        }
        
        if ($result.ProvisioningState -eq "Succeeded") {
            Write-DeployLog "Successfully deployed to $VMName"
            return $true
        } else {
            Write-DeployLog "Failed to deploy to $VMName - Status: $($result.ProvisioningState)" "ERROR"
            return $false
        }
        
    } catch {
        Write-DeployLog "Error deploying to $VMName : $_" "ERROR"
        return $false
    }
}

# Main deployment logic
Write-DeployLog "Starting AVDSessionWatch deployment"
Write-DeployLog "Target VMs: $($VMNames -join ', ')"
Write-DeployLog "Resource Group: $ResourceGroupName"
Write-DeployLog "Test Mode: $TestMode"

# Check if Azure PowerShell module is available
if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    Write-DeployLog "Azure PowerShell module (Az.Compute) not found. Please install it first." "ERROR"
    Write-DeployLog "Run: Install-Module -Name Az -Force" "ERROR"
    exit 1
}

# Connect to Azure if not already connected
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-DeployLog "Not connected to Azure. Please run Connect-AzAccount first." "ERROR"
        exit 1
    }
    Write-DeployLog "Connected to Azure - Subscription: $($context.Subscription.Name)"
} catch {
    Write-DeployLog "Error checking Azure connection: $_" "ERROR"
    exit 1
}

# Create monitoring package
$packageDir = New-AVDSessionWatchPackage

# Upload to storage if specified
$fileUris = @()
if (-not $UseLocalFiles) {
    $fileUris = Upload-ToAzureStorage -PackageDir $packageDir
    if (-not $fileUris) {
        Write-DeployLog "Failed to upload files, switching to local deployment mode" "WARN"
        $UseLocalFiles = $true
    }
}

# Deploy to each VM
$successCount = 0
$failCount = 0

foreach ($vmName in $VMNames) {
    Write-DeployLog "Processing VM: $vmName"
    
    # Verify VM exists
    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -ErrorAction Stop
        Write-DeployLog "Found VM: $vmName (Status: $($vm.StatusCode))"
    } catch {
        Write-DeployLog "VM not found: $vmName" "ERROR"
        $failCount++
        continue
    }
    
    # Deploy to VM
    if (Deploy-ToVM -VMName $vmName -FileUris $fileUris) {
        $successCount++
    } else {
        $failCount++
    }
}

# Cleanup
if (Test-Path $packageDir) {
    Remove-Item $packageDir -Recurse -Force
    Write-DeployLog "Cleaned up package directory"
}

# Summary
Write-DeployLog "Deployment Summary:"
Write-DeployLog "  Total VMs: $($VMNames.Count)"
Write-DeployLog "  Successful: $successCount"
Write-DeployLog "  Failed: $failCount"

if ($failCount -eq 0) {
    Write-DeployLog "All deployments completed successfully!"
    exit 0
} else {
    Write-DeployLog "Some deployments failed. Check the log for details." "WARN"
    exit $failCount
}