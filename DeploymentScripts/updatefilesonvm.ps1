# Target VM Deployment Script
# This script runs on each target VM to set up monitoring

param(
    [Parameter(Mandatory=$true)]
    [string]$InstallPath = "C:\ProgramData\AVDSessionWatch",
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$ContainerName = "avdsessionwatch-scripts",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$VMName,

    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory=$false)]
    [string]$ScriptExtensionName = "AVDSessionWatchUpdateFiles"
)

$filesToPackage = @(
    "tasklist.ps1",
    "sessions.ps1", 
    "cleanup.ps1",
    "setup-tasks.bat",
    "remove-tasks.bat"
)

$uploadedFiles = @()
$filesToPackage | ForEach-Object {
    $blobUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$($_)"
    $uploadedFiles += $blobUri
}

Write-Host "Starting $ScriptExtensionName deployment..."
Write-Host "Install path: $InstallPath"

# Download all files
$($uploadedFiles | ForEach-Object { "Invoke-WebRequest -Uri '$_' -OutFile (Split-Path '$_' -Leaf)" }) -join "`n"

# Copy files from script location to install path
$scriptPath = $MyInvocation.MyCommand.Path
if (Test-Path $scriptPath) {
    Write-Host "Copying files from $scriptPath to $InstallPath..."
    Copy-Item "$scriptPath\*" -Destination $InstallPath -Force
    Write-Host "Files copied successfully"
} else {
    Write-Host "Error: Script directory not found at $scriptPath"
    exit 1
}

Set-AzVMCustomScriptExtension -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -Location $Location `
    -FileUri $uploadedFiles `
    -Run 'updatefilesonvm.ps1' `
    -Name $ScriptExtensionName

New-AzResourceGroup -Name $ResourceGroupName -Location "$Location"
New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile "azuredeploy-updatefilesonvm.json"
