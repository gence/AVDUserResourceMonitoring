# Script to Deploy AVDSessionWatch monitoring solution to Azure VMs
# Author: GitHub Copilot
# Date: November 8, 2025

param(
    [Parameter(Mandatory=$false)]
    [string[]]$VMNames,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory=$false)]
    [string]$StorageAccountKey = "",

    [Parameter(Mandatory=$false)]
    [string]$ContainerName = "avdsessionwatch-scripts",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "East US",

    [Parameter(Mandatory=$false)]
    [string]$UploadToStorageOnly = $false
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
        "processes.ps1",
        "sessions.ps1", 
        "cleanup.ps1",
        "setup-tasks.bat",
        "remove-tasks.bat",
        "install-avdsessionwatch.ps1"
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

    return $packageDir
}

# Function to upload package to Azure Storage (if using storage account)
function Send-ToAzureStorage {
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
            if ($result.ProvisioningState -eq "Succeeded") {
                Write-DeployLog "Successfully deployed to $VMName"
                return $true
            } else {
                Write-DeployLog "Failed to deploy to $VMName - Status: $($result.ProvisioningState)" "ERROR"
                return $false
            }
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
Write-DeployLog "Storage Account: $StorageAccountName"
Write-DeployLog "Upload to Storage Only: $UploadToStorageOnly"

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
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        Write-DeployLog "Switched to Subscription ID: $SubscriptionId"
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
$fileUris = Send-ToAzureStorage -PackageDir $packageDir
if (-not $fileUris) {
    Write-DeployLog "Failed to upload files, stopping script" "WARN"
    exit 1
}

if ($UploadToStorageOnly -eq $false) {
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

        if ($failCount -eq 0) {
            Write-DeployLog "All deployments completed successfully!"
        } else {
            Write-DeployLog "Some deployments failed. Check the log for details." "WARN"
        }
    }

    # Summary
    Write-DeployLog "Deployment Summary:"
    Write-DeployLog "  Total VMs: $($VMNames.Count)"
    Write-DeployLog "  Successful: $successCount"
    Write-DeployLog "  Failed: $failCount"
} else {
    Write-DeployLog "Upload to storage only mode enabled, skipping VM deployment"
}

# Cleanup
if (Test-Path $packageDir) {
    Remove-Item $packageDir -Recurse -Force
    Write-DeployLog "Cleaned up package directory"
}
