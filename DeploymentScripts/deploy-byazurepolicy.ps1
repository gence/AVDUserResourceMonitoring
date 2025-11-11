# PowerShell script to deploy AVDSessionWatch via Azure Policy with Managed Identity
# Author: GitHub Copilot, Gence Soysal
# Date: November 8, 2025

param(
    [Parameter(Mandatory=$true)]
    [string]$storageAccountName,

    [Parameter(Mandatory=$true)]
    [string]$ContainerName = "avdsessionwatch-scripts",

    [Parameter(Mandatory=$true)]
    [string]$subscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$resourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory=$true)]
    [string]$policyScope = "/subscriptions/$subscriptionId"
)

# Create storage account with Entra ID authentication enabled
Write-Host "Setting up storage account with Entra ID authentication..." -ForegroundColor Yellow

$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
    Write-Host "Creating new storage account: $storageAccountName"
    $storageAccount = New-AzStorageAccount `
        -ResourceGroupName $resourceGroupName `
        -Name $storageAccountName `
        -Location $location `
        -SkuName "Standard_LRS" `
        -AllowBlobPublicAccess $false `
        -EnableAzureActiveDirectoryDomainServicesForFile $false `
        -EnableHttpsTrafficOnly $true
}

# Use Entra ID authentication for storage context (preferred method)
try {
    Write-Host "Creating storage context with Entra ID authentication..."
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
    Write-Host "Successfully created Entra ID authenticated storage context" -ForegroundColor Green
} catch {
    Write-Warning "Entra ID storage authentication failed, falling back to access keys..."
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName)[0].Value
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey
}

# Create container (private access, no public blob access)
New-AzStorageContainer -Name "avdsessionwatch-scripts" -Context $ctx -Permission Off

# Upload monitoring files to Azure storage using the deployment script
.\deploy-avdsessionwatch.ps1 -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -UploadToStorageOnly $true

# Create and assign Azure Policy
# ------------------------------

$policyDefinitionName = "deploy-avdsessionwatch"
$policyAssignmentName = "deploy-avdsessionwatch-assignment"

# Create policy definition
Write-Host "Creating new policy definition..." -ForegroundColor Yellow

try {
    # Read and validate JSON
    $policyJson = Get-Content -Raw -Path ".\azure-policy-avdsessionwatch.json" -Encoding UTF8
    
    # Test JSON parsing
    ConvertFrom-Json $policyJson
    Write-Host "JSON validation successful" -ForegroundColor Green
    
    # Create policy definition with minimal parameters to avoid parsing issues
    $policyDefinition = New-AzPolicyDefinition `
        -Name $policyDefinitionName`
        -DisplayName "Deploy AVDSessionWatch monitoring to Windows VMs" `
        -Description "Automatically deploy monitoring scripts to new Windows VMs" `
        -Policy $policyJson `
        -Mode "Indexed"
        
    Write-Host "Policy definition created successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to create policy definition: $_"
    exit 1
}

# Get current subscription context for policy assignment
$subscriptionScope = "/subscriptions/$subscriptionId"

Write-Host "Creating policy assignment with Managed Identity..." -ForegroundColor Yellow

# Create policy assignment
try {
    Write-Host "Attempting to create policy assignment..." -ForegroundColor Yellow
    
    $policyAssignment = New-AzPolicyAssignment `
        -Name $policyAssignmentName `
        -DisplayName "Auto-deploy AVDSessionWatch" `
        -Scope $subscriptionScope `
        -PolicyDefinition $policyDefinition `
        -PolicyParameterObject @{ storageAccountName = [string]$storageAccountName; containerName = [string]$ContainerName } `
        -IdentityType "SystemAssigned" `
        -Location $location
        
    Write-Host "Policy assignment created successfully" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to create policy assignment: $_"
    Write-Host "Error details:" -ForegroundColor Red
    Write-Host "Policy Definition Name: $($policyDefinitionName)" -ForegroundColor Yellow
    Write-Host "Policy Definition Type: $($policyDefinition.GetType().Name)" -ForegroundColor Yellow
    Write-Host "Scope: $subscriptionScope" -ForegroundColor Yellow
    exit 1
}

Write-Host "Policy assignment created with Managed Identity: $($policyAssignment.IdentityPrincipalId)" -ForegroundColor Green

# Grant required permissions to the policy managed identity
Write-Host "Assigning permissions to policy Managed Identity..." -ForegroundColor Yellow

# wait 30 seconds to ensure identity is fully provisioned
Start-Sleep -Seconds 30

# Virtual Machine Contributor role for VM operations
$vmContributorRole = "9980e02c-c2be-4d73-94e8-173b1dc7cf3c"
New-AzRoleAssignment `
    -ObjectId $policyAssignment.IdentityPrincipalId `
    -RoleDefinitionId $vmContributorRole `
    -Scope $subscriptionScope

# Storage Blob Data Contributor role for storage access
$storageBlobContributorRole = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
New-AzRoleAssignment `
    -ObjectId $policyAssignment.IdentityPrincipalId `
    -RoleDefinitionId $storageBlobContributorRole `
    -Scope $storageAccount.Id

Write-Host "Permissions assigned successfully" -ForegroundColor Green

Write-Host "Creating remediation task to update VMs..." -ForegroundColor Green

# Get the full policy assignment ID
$policyAssignmentId = "/subscriptions/$subscriptionId/providers/Microsoft.Authorization/policyAssignments/$policyAssignmentName"

Write-Host "Using standard remediation - only non-compliant VMs will be updated" -ForegroundColor Yellow
    
$remediation = Start-AzPolicyRemediation `
    -Name "update-noncompliant-avdsessionwatch-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
    -PolicyAssignmentId $policyAssignmentId `
    -ResourceCount 50000 `
    -ParallelDeploymentCount 10

Write-Host "Remediation task created: $($remediation.Name)" -ForegroundColor Green
Write-Host "Task ID: $($remediation.Id)" -ForegroundColor Cyan
Write-Host "Monitor progress with: Get-AzPolicyRemediation -Name '$($remediation.Name)'" -ForegroundColor Cyan
Write-Host "-----------------------------------------"
Write-Host "Setup complete! New Windows VMs will automatically get AVDSessionWatch deployed via Azure Policy." -ForegroundColor Green
