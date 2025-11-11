# PowerShell script to update monitoring scripts on VMs
# Author: GitHub Copilot, Gence Soysal
# Date: November 8, 2025

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
     
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$VMNames
)

# Package and upload monitoring files to Azure storage using the deployment script
.\deploy-avdsessionwatch.ps1 -StorageAccountName $StorageAccountName -UploadToStorageOnly $true

# Force policy remediation (redeploys to ALL VMs, both compliant and non-compliant)
$PolicyAssignmentName = "deploy-avdsessionwatch-assignment"
$policyAssignmentId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policyAssignments/$PolicyAssignmentName"

# This uses ReEvaluateCompliance which forces re-evaluation and redeployment
Write-Host "Creating remediation task to update VMs..." -ForegroundColor Green
Write-Host "Using ReEvaluateCompliance mode - will redeploy to ALL VMs regardless of current compliance" -ForegroundColor Yellow

$remediation = Start-AzPolicyRemediation `
    -Name "force-update-avdsessionwatch-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
    -PolicyAssignmentId $policyAssignmentId `
    -ResourceDiscoveryMode "ReEvaluateCompliance" `
    -ResourceCount 50000 `
    -ParallelDeploymentCount 10

Write-Host "Remediation task created: $($remediation.Name)" -ForegroundColor Green
Write-Host "Task ID: $($remediation.Id)" -ForegroundColor Cyan
Write-Host "Monitor progress with: Get-AzPolicyRemediation -Name '$($remediation.Name)'" -ForegroundColor Cyan

return $remediation

<#
1. POLICY RE-EVALUATION: Azure Policy re-evaluates ALL Windows VMs against the policy
2. RESOURCE DISCOVERY: Uses "ReEvaluateCompliance" mode to force checking ALL VMs (not just non-compliant)  
3. CUSTOM SCRIPT EXTENSION: Deploys/updates the Custom Script Extension on each VM
4. SCRIPT DOWNLOAD: VMs download the LATEST scripts from your storage account blob
5. SCRIPT EXECUTION: Runs install-avdsessionwatch.ps1 which installs updated monitoring

IMPORTANT: This WILL update scripts on ALL VMs because:
- ReEvaluateCompliance forces the policy to treat ALL resources as "needs checking"
- The Custom Script Extension gets redeployed with current storage account content
- Your updated processes.ps1, sessions.ps1, etc. get downloaded fresh from blob storage

MONITORING REMEDIATION PROGRESS:
===============================

# Check remediation task status
Get-AzPolicyRemediation -Name "your-remediation-task-name"

# Monitor all remediation tasks
Get-AzPolicyRemediation | Format-Table Name, ProvisioningState, ResourceCount, SuccessfulResources, FailedResources

# Check policy compliance after remediation
Get-AzPolicyState -PolicyAssignmentName "deploy-avdsessionwatch-assignment" | Group-Object ComplianceState
#>