## ========================================
## METHOD 1: Azure Policy with Managed Identity (Recommended)
## ========================================

param(
    [Parameter(Mandatory=$true)]
    [string]$storageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$resourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus"
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

# Upload monitoring files using the deployment script
.\deploy-avdsessionwatch.ps1 -VMNames @() -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ContainerName "avdsessionwatch-scripts" -TestMode

# 2. Create and assign Azure Policy
# ---------------------------------
# Create policy definition
Write-Host "Creating new policy definition..." -ForegroundColor Yellow

try {
    # Read and validate JSON
    $policyJson = Get-Content -Raw -Path ".\azure-policy-avdsessionwatch.json" -Encoding UTF8
    
    # Test JSON parsing
    $testParse = ConvertFrom-Json $policyJson
    Write-Host "JSON validation successful" -ForegroundColor Green
    
    # Create policy definition with minimal parameters to avoid parsing issues
    $policyDefinition = New-AzPolicyDefinition `
        -Name "deploy-avdsessionwatch" `
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
$currentContext = Get-AzContext
$subscriptionScope = "/subscriptions/$($currentContext.Subscription.Id)"

Write-Host "Creating policy assignment with Managed Identity..." -ForegroundColor Yellow

# Create policy assignment
try {
    Write-Host "Attempting to create policy assignment..." -ForegroundColor Yellow
    
    # First try without parameters to isolate the issue
    $policyAssignment = New-AzPolicyAssignment `
        -Name "deploy-avdsessionwatch-assignment" `
        -DisplayName "Auto-deploy AVD session watch" `
        -Scope $subscriptionScope `
        -PolicyDefinition $policyDefinition `
        -PolicyParameterObject @{ storageAccountName = [string]$storageAccountName; containerName = "avdsessionwatch-scripts" } `
        -IdentityType "SystemAssigned" `
        -Location $location
        
    Write-Host "Policy assignment created successfully" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to create policy assignment: $_"
    Write-Host "Error details:" -ForegroundColor Red
    Write-Host "Policy Definition Name: $($policyDefinition.Name)" -ForegroundColor Yellow
    Write-Host "Policy Definition Type: $($policyDefinition.GetType().Name)" -ForegroundColor Yellow
    Write-Host "Scope: $subscriptionScope" -ForegroundColor Yellow
    exit 1
}

Write-Host "Policy assignment created with Managed Identity: $($policyAssignment.IdentityPrincipalId)" -ForegroundColor Green

# Grant required permissions to the policy managed identity
Write-Host "Assigning permissions to policy Managed Identity..." -ForegroundColor Yellow

# wait 10 seconds to ensure identity is fully provisioned
Start-Sleep -Seconds 10

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

## ========================================
## METHOD 2: Azure Automation with Managed Identity
## ========================================

Write-Host "Setting up Azure Automation with Managed Identity..." -ForegroundColor Yellow

# 1. Create Azure Automation Account with Managed Identity
# -------------------------------------------------------
$automationAccountName = "avdsessionwatch-automation"

Write-Host "Creating Automation Account with System-Assigned Managed Identity..."
$automationAccount = New-AzAutomationAccount `
    -ResourceGroupName $resourceGroupName `
    -Name $automationAccountName `
    -Location $location `
    -AssignSystemIdentity

Write-Host "Automation Account created with Managed Identity: $($automationAccount.Identity.PrincipalId)" -ForegroundColor Green

# 2. Import required PowerShell modules
# ------------------------------------
Write-Host "Importing PowerShell modules..." -ForegroundColor Yellow

# Import modern Az modules
$modules = @(
    @{Name = "Az.Accounts"; Uri = "https://www.powershellgallery.com/packages/Az.Accounts"},
    @{Name = "Az.Compute"; Uri = "https://www.powershellgallery.com/packages/Az.Compute"},
    @{Name = "Az.Storage"; Uri = "https://www.powershellgallery.com/packages/Az.Storage"},
    @{Name = "Az.Resources"; Uri = "https://www.powershellgallery.com/packages/Az.Resources"}
)

foreach ($module in $modules) {
    Write-Host "Importing module: $($module.Name)"
    Import-AzAutomationModule `
        -AutomationAccountName $automationAccountName `
        -ResourceGroupName $resourceGroupName `
        -ModuleUri $module.Uri `
        -ModuleVersion "Latest"
}

# 3. Grant permissions to Automation Account Managed Identity
# ----------------------------------------------------------
Write-Host "Granting permissions to Automation Account Managed Identity..." -ForegroundColor Yellow

# Virtual Machine Contributor role
New-AzRoleAssignment `
    -ObjectId $automationAccount.Identity.PrincipalId `
    -RoleDefinitionId $vmContributorRole `
    -Scope $subscriptionScope

# Storage Blob Data Contributor role
New-AzRoleAssignment `
    -ObjectId $automationAccount.Identity.PrincipalId `
    -RoleDefinitionId $storageBlobContributorRole `
    -Scope $storageAccount.Id

# 4. Create and schedule runbook with Managed Identity authentication
# -----------------------------------------------------------------
Write-Host "Creating runbook with Managed Identity authentication..."

Import-AzAutomationRunbook `
    -AutomationAccountName $automationAccountName `
    -ResourceGroupName $resourceGroupName `
    -Name "CheckNewVMs" `
    -Type "PowerShell" `
    -Path "auto-deploy-avdsessionwatch.ps1"

Publish-AzAutomationRunbook `
    -AutomationAccountName $automationAccountName `
    -ResourceGroupName $resourceGroupName `
    -Name "CheckNewVMs"

# Schedule to run every hour
New-AzAutomationSchedule `
    -AutomationAccountName $automationAccountName `
    -ResourceGroupName $resourceGroupName `
    -Name "HourlyVMCheck" `
    -StartTime (Get-Date).AddMinutes(10) `
    -HourInterval 1

Register-AzAutomationScheduledRunbook `
    -AutomationAccountName $automationAccountName `
    -ResourceGroupName $resourceGroupName `
    -RunbookName "CheckNewVMs" `
    -ScheduleName "HourlyVMCheck"

Write-Host "Automation setup completed with Managed Identity" -ForegroundColor Green

## ========================================
## TESTING & VALIDATION
## ========================================

# Test policy compliance
Get-AzPolicyState -PolicyAssignmentName "deploy-avdsessionwatch-assignment"

# Test automation runbook
Start-AzAutomationRunbook -AutomationAccountName "avdsessionwatch-automation" -ResourceGroupName $resourceGroupName -Name "CheckNewVMs"

## ========================================
## MONITORING & MAINTENANCE
## ========================================

# Monitor policy compliance
$complianceResults = Get-AzPolicyState | Where-Object { $_.PolicyAssignmentName -eq "deploy-avdsessionwatch-assignment" }
$complianceResults | Group-Object ComplianceState

# Update monitoring scripts on ALL VMs (existing + new)
Write-Host "To update scripts on all VMs after making changes:" -ForegroundColor Cyan
Write-Host "1. Upload new versions to storage account (done automatically by deploy script)" -ForegroundColor Yellow
Write-Host "2. Policy will automatically deploy to NEW VMs only" -ForegroundColor Yellow  
Write-Host "3. For EXISTING VMs, use one of these methods:" -ForegroundColor Yellow

# METHOD A: Force policy remediation (redeploys to ALL VMs, both compliant and non-compliant)
function Update-AllVMsViaPolicyRemediation {
    param(
        $PolicyAssignmentName = "deploy-avdsessionwatch-assignment",
        [switch]$ForceAll = $true
    )
    
    Write-Host "Creating remediation task to update ALL VMs (existing + future)..." -ForegroundColor Green
    
    # Get the full policy assignment ID
    $policyAssignmentId = "/subscriptions/$((Get-AzContext).Subscription.Id)/providers/Microsoft.Authorization/policyAssignments/$PolicyAssignmentName"
    
    if ($ForceAll) {
        # FORCE remediation on ALL VMs (even ones marked compliant)
        # This uses ReEvaluateCompliance which forces re-evaluation and redeployment
        Write-Host "Using ReEvaluateCompliance mode - will redeploy to ALL VMs regardless of current compliance" -ForegroundColor Yellow
        
        $remediation = Start-AzPolicyRemediation `
            -Name "force-update-avdsessionwatch-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
            -PolicyAssignmentId $policyAssignmentId `
            -ResourceDiscoveryMode "ReEvaluateCompliance" `
            -ResourceCount 50000 `
            -ParallelDeploymentCount 10
    } else {
        # Only remediate currently non-compliant VMs
        Write-Host "Using standard remediation - only non-compliant VMs will be updated" -ForegroundColor Yellow
        
        $remediation = Start-AzPolicyRemediation `
            -Name "update-noncompliant-avdsessionwatch-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
            -PolicyAssignmentId $policyAssignmentId `
            -ResourceCount 50000 `
            -ParallelDeploymentCount 10
    }
    
    Write-Host "Remediation task created: $($remediation.Name)" -ForegroundColor Green
    Write-Host "Task ID: $($remediation.Id)" -ForegroundColor Cyan
    Write-Host "Monitor progress with: Get-AzPolicyRemediation -Name '$($remediation.Name)'" -ForegroundColor Cyan
    
    return $remediation
}

# METHOD B: Target specific VMs manually  
function Update-SpecificVMs {
    param([string[]]$VMNames)
    
    Write-Host "Updating specific VMs: $($VMNames -join ', ')" -ForegroundColor Green
    .\deploy-avdsessionwatch.ps1 -VMNames $VMNames -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName -ContainerName "avdsessionwatch-scripts"
}

# METHOD C: Update all VMs in resource group
function Update-AllVMsInResourceGroup {
    param([string]$TargetResourceGroupName = $resourceGroupName)
    
    Write-Host "Getting all Windows VMs in resource group: $TargetResourceGroupName" -ForegroundColor Green
    $allVMs = Get-AzVM -ResourceGroupName $TargetResourceGroupName | Where-Object { $_.StorageProfile.OsDisk.OsType -eq "Windows" }
    $vmNames = $allVMs.Name
    
    Write-Host "Found $($vmNames.Count) Windows VMs: $($vmNames -join ', ')" -ForegroundColor Cyan
    if ($vmNames.Count -gt 0) {
        .\deploy-avdsessionwatch.ps1 -VMNames $vmNames -ResourceGroupName $TargetResourceGroupName -StorageAccountName $storageAccountName -ContainerName "avdsessionwatch-scripts"
    }
}

Write-Host @"

WHAT AZURE POLICY REMEDIATION ACTUALLY DOES:
============================================

When you run Update-AllVMsViaPolicyRemediation with -ForceAll:

1. POLICY RE-EVALUATION: Azure Policy re-evaluates ALL Windows VMs against the policy
2. RESOURCE DISCOVERY: Uses "ReEvaluateCompliance" mode to force checking ALL VMs (not just non-compliant)  
3. CUSTOM SCRIPT EXTENSION: Deploys/updates the Custom Script Extension on each VM
4. SCRIPT DOWNLOAD: VMs download the LATEST scripts from your storage account blob
5. SCRIPT EXECUTION: Runs install-avdsessionwatch.ps1 which installs updated monitoring

IMPORTANT: This WILL update scripts on ALL VMs because:
- ReEvaluateCompliance forces the policy to treat ALL resources as "needs checking"
- The Custom Script Extension gets redeployed with current storage account content
- Your updated tasklist.ps1, sessions.ps1, etc. get downloaded fresh from blob storage

EXAMPLE USAGE FOR SCRIPT UPDATES:
================================

# After modifying tasklist.ps1 or other scripts:

# Option 1: FORCE update ALL VMs via policy remediation (recommended for script updates)
Update-AllVMsViaPolicyRemediation -ForceAll

# Option 2: Update only currently non-compliant VMs  
Update-AllVMsViaPolicyRemediation -ForceAll:`$false

# Option 3: Update specific VMs manually
Update-SpecificVMs -VMNames @("AVD-VM-001", "AVD-VM-002")

# Option 4: Update all VMs in a resource group
Update-AllVMsInResourceGroup -TargetResourceGroupName "AVD-ResourceGroup"

# Option 5: Manual deployment to all discovered VMs
`$allWindowsVMs = Get-AzVM | Where-Object { `$_.StorageProfile.OsDisk.OsType -eq "Windows" }
.\deploy-avdsessionwatch.ps1 -VMNames `$allWindowsVMs.Name -ResourceGroupName "$resourceGroupName" -StorageAccountName "$storageAccountName"

MONITORING REMEDIATION PROGRESS:
===============================

# Check remediation task status
Get-AzPolicyRemediation -Name "your-remediation-task-name"

# Monitor all remediation tasks
Get-AzPolicyRemediation | Format-Table Name, ProvisioningState, ResourceCount, SuccessfulResources, FailedResources

# Check policy compliance after remediation
Get-AzPolicyState -PolicyAssignmentName "deploy-avdsessionwatch-assignment" | Group-Object ComplianceState

"@ -ForegroundColor White

# Monitor function app logs
Get-AzLog -ResourceGroupName $resourceGroupName -ResourceProvider "Microsoft.Web" -ResourceName $functionAppName

## ========================================
## AUTHENTICATION EXAMPLES & USAGE
## ========================================

Write-Host @"

=== AUTHENTICATION EXAMPLES ===

1. Interactive Authentication (recommended for setup):
   .\setup-auto-deployment.ps1

2. Managed Identity (for Azure VMs/Functions):
   .\setup-auto-deployment.ps1 -UseManagedIdentity -SubscriptionId "your-sub-id"

3. Specific Tenant/Subscription:
   .\setup-auto-deployment.ps1 -TenantId "your-tenant-id" -SubscriptionId "your-sub-id"

=== SECURITY BEST PRACTICES ===

• Use Managed Identity whenever possible (Azure VMs, Functions, Automation)
• Use least-privilege access with custom roles
• Enable audit logging for all authentication events

"@ -ForegroundColor Cyan

Write-Host "Setup complete! New Windows VMs will automatically get monitoring deployed using Entra ID authentication." -ForegroundColor Green
Write-Host "Choose the method that best fits your environment:" -ForegroundColor Yellow
Write-Host "- Azure Policy with Managed Identity: Best for governance and compliance" -ForegroundColor White
Write-Host "- Automation with Managed Identity: Best for scheduled checks and hybrid scenarios" -ForegroundColor White
Write-Host "- Both methods now use modern Entra ID authentication for enhanced security" -ForegroundColor Green