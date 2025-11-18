# PowerShell script to deploy AVDSessionWatch via Azure Policy with Managed Identity
# Author: GitHub Copilot, Gence Soysal
# Date: November 8, 2025

param(
    [Parameter(Mandatory=$true)]
    [string]$storageAccountName,

    [Parameter(Mandatory=$false)]
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

# Get the script directory path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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

$storageContainer = Get-AzStorageContainer -Context $ctx -Name $ContainerName -ErrorAction SilentlyContinue
if (-not $storageContainer) {
    Write-Host "Creating new storage container: $ContainerName"
    # Create container (private access, no public blob access)
    New-AzStorageContainer -Name $ContainerName -Context $ctx -Permission Off
}

# Get the script directory path
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Upload monitoring files to Azure storage using the deployment script
& "$scriptDir\deploy-avdsessionwatch.ps1" -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -UploadToStorageOnly $true

# Create and assign Azure Policy
# ------------------------------

$policyDefinitionName = "deploy-avdsessionwatch"
$policyAssignmentName = "deploy-avdsessionwatch-assignment"

# Create policy definition
Write-Host "Creating new policy definition..." -ForegroundColor Yellow

try {
    # Read and validate JSON
    $policyJsonContent = Get-Content -Raw -Path "$scriptDir\azure-policy-avdsessionwatch.json" -Encoding UTF8
    
    # Parse the JSON
    $policyObject = ConvertFrom-Json $policyJsonContent
    Write-Host "JSON validation successful" -ForegroundColor Green
    
    # Extract the policyRule from the properties if it exists
    if ($policyObject.properties) {
        $policyRuleObject = $policyObject.properties.policyRule
        $parametersObject = $policyObject.properties.parameters
        $displayName = $policyObject.properties.displayName
        $description = $policyObject.properties.description
        
        # Convert back to JSON strings
        $policyRule = ($policyRuleObject | ConvertTo-Json -Depth 100 -Compress)
        $parameters = ($parametersObject | ConvertTo-Json -Depth 100 -Compress)
    } else {
        Write-Host "Using entire JSON as policy rule" -ForegroundColor Yellow
        $policyRule = $policyJsonContent
        $parameters = "{}"
        $displayName = "Deploy AVDSessionWatch monitoring to Windows VMs"
        $description = "Automatically deploy monitoring scripts to new Windows VMs"
    }
    
    Write-Host "Policy rule length: $($policyRule.Length)" -ForegroundColor Green
    Write-Host "Parameters length: $($parameters.Length)" -ForegroundColor Green
    
    # Create policy definition with minimal parameters to avoid parsing issues
    $policyDefinition = New-AzPolicyDefinition `
        -Name $policyDefinitionName `
        -DisplayName $displayName `
        -Description $description `
        -Policy $policyRule `
        -Parameter $parameters `
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
try {
    New-AzRoleAssignment `
        -ObjectId $policyAssignment.IdentityPrincipalId `
        -RoleDefinitionId $vmContributorRole `
        -Scope $subscriptionScope `
        -ErrorAction Stop
    Write-Host "VM Contributor role assigned successfully" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*Conflict*" -or $_.Exception.Message -like "*already exists*") {
        Write-Host "VM Contributor role already assigned (skipping)" -ForegroundColor Yellow
    } else {
        throw
    }
}

# Storage Blob Data Contributor role for storage access
$storageBlobContributorRole = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
try {
    New-AzRoleAssignment `
        -ObjectId $policyAssignment.IdentityPrincipalId `
        -RoleDefinitionId $storageBlobContributorRole `
        -Scope $storageAccount.Id `
        -ErrorAction Stop
    Write-Host "Storage Blob Contributor role assigned successfully" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -like "*Conflict*" -or $_.Exception.Message -like "*already exists*") {
        Write-Host "Storage Blob Contributor role already assigned (skipping)" -ForegroundColor Yellow
    } else {
        throw
    }
}

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
