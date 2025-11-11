# Script to Deploy Azure Workbooks for AVD Session Watch monitoring solution
# Author: GitHub Copilot
# Date: November 8, 2025

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus"
)

# Function to deploy a workbook
function Deploy-Workbook {
    param(
        [string]$WorkbookTemplatePath,
        [string]$WorkbookDisplayName,
        [string]$WorkspaceId,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$WorkspaceName,
        [string]$Location,
        [string]$MainWorkbookResourceId = $null
    )
    Write-Host ""
    Write-Host "Loading workbook template: $(Split-Path $WorkbookTemplatePath -Leaf)..." -ForegroundColor Yellow
    $workbookJson = Get-Content -Path $WorkbookTemplatePath -Raw
    Write-Host "  Workbook template loaded" -ForegroundColor Green
    
    # Replace placeholders in the workbook JSON
    Write-Host "Replacing placeholders in workbook..." -ForegroundColor Yellow
    $workbookJson = $workbookJson -replace '\{subscriptionId\}', $SubscriptionId
    $workbookJson = $workbookJson -replace '\{resourceGroupName\}', $ResourceGroup
    $workbookJson = $workbookJson -replace '\{workspaceName\}', $WorkspaceName
            
    # Create object model from JSON and set fallbackResourceIds (was missing, caused runtime issues; braces intact)
    $workbookObj = $workbookJson | ConvertFrom-Json
    if (-not $workbookObj.PSObject.Properties.Name -contains 'fallbackResourceIds') {
        $workbookObj | Add-Member -NotePropertyName fallbackResourceIds -NotePropertyValue @()
    }
    $workbookObj.fallbackResourceIds = @($WorkspaceId)

    # Generate unique workbook ID and replace any workbookId placeholders
    $workbookGuid = [Guid]::NewGuid().ToString()
    # Convert to JSON without -Compress for PS 5.1 compatibility
    $workbookJsonTemp = $workbookObj | ConvertTo-Json -Depth 100
    
    # If this is the single user workbook and we have a main workbook resource ID, replace templateId placeholders
    if ($MainWorkbookResourceId) {
        $workbookJsonTemp = $workbookJsonTemp -replace '\{workbookId\}', ($MainWorkbookResourceId -replace '.*/', '')
    } else {
        $workbookJsonTemp = $workbookJsonTemp -replace '\{workbookId\}', $workbookGuid
    }
    
    $workbookJsonUpdated = $workbookJsonTemp
    Write-Host "  Placeholders replaced and workspace reference updated" -ForegroundColor Green
    
    # Create ARM template
    # Note: We build the JSON structure programmatically to avoid here-string quote escaping issues
    $templateObj = @{
        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "1.0.0.0"
        parameters = @{}
        resources = @(
            @{
                type = "microsoft.insights/workbooks"
                apiVersion = "2021-03-08"
                name = $workbookGuid
                location = $Location
                kind = "shared"
                properties = @{
                    displayName = $WorkbookDisplayName
                    serializedData = $workbookJsonUpdated
                    version = "1.0"
                    sourceId = $WorkspaceId
                    category = "workbook"
                }
            }
        )
        outputs = @{
            workbookResourceId = @{
                type = "string"
                value = "[resourceId('microsoft.insights/workbooks', '$workbookGuid')]"
            }
        }
    }
    
    # Convert to JSON (without -Compress for PS 5.1 compatibility)
    $templateJson = $templateObj | ConvertTo-Json -Depth 100
    
    # Save template temporarily
    $tempTemplate = Join-Path $env:TEMP "workbook-deployment-$workbookGuid.json"
    # Use UTF8 without BOM for cross-version compatibility
    [System.IO.File]::WriteAllText($tempTemplate, $templateJson, [System.Text.UTF8Encoding]::new($false))
    
    try {
        Write-Host "Deploying workbook: $WorkbookDisplayName..." -ForegroundColor Yellow
        
        # Deploy the template
        $deployment = New-AzResourceGroupDeployment `
            -ResourceGroupName $ResourceGroup `
            -TemplateFile $tempTemplate `
            -Name "WorkbookDeployment-$workbookGuid" `
            -ErrorAction Stop
        
        $deployedWorkbookResourceId = $deployment.Outputs.workbookResourceId.Value
        
        Write-Host "  Workbook deployed successfully!" -ForegroundColor Green
        Write-Host "  Resource ID: $deployedWorkbookResourceId" -ForegroundColor Gray
        
        return $deployedWorkbookResourceId
    } catch {
        Write-Host "  Deployment failed for $WorkbookDisplayName!" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        throw
    } finally {
        # Clean up temp file
        if (Test-Path $tempTemplate) {
            Remove-Item $tempTemplate -Force
        }
    }
}

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Azure AVD Resource Usage Workbooks Deployment Script" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Define workbook templates to deploy
if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
    $scriptDirectory = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
} else {
    $scriptDirectory = (Get-Location).ProviderPath
}

Write-Host "Script directory: $scriptDirectory" -ForegroundColor Cyan

$mainWorkbookTemplate = "azure-workbook-avd-resource-usage.json"
$singleUserWorkbookTemplate = "azure-workbook-avd-singleuser-resourceview.json"

# Validate both workbook template files exist
$mainWorkbookPath = Join-Path $scriptDirectory $mainWorkbookTemplate
$singleUserWorkbookPath = Join-Path $scriptDirectory $singleUserWorkbookTemplate

if (-not (Test-Path $mainWorkbookPath)) {
    Write-Host "  Main workbook file not found: $mainWorkbookPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $singleUserWorkbookPath)) {
    Write-Host "  Single user workbook file not found: $singleUserWorkbookPath" -ForegroundColor Red
    exit 1
}

# Check if logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Logged in as: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
    exit 1
}

# Set subscription context
#Write-Host "Setting subscription context..." -ForegroundColor Yellow
#Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
#Write-Host "  Subscription set: $SubscriptionId" -ForegroundColor Green

# Verify Resource Group exists
Write-Host "Verifying resource group..." -ForegroundColor Yellow
$rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "  Resource Group '$ResourceGroup' not found!" -ForegroundColor Red
    exit 1
}
Write-Host "  Resource Group found: $ResourceGroup" -ForegroundColor Green

# Verify Log Analytics Workspace exists
Write-Host "Verifying Log Analytics workspace..." -ForegroundColor Yellow
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName -ErrorAction SilentlyContinue
if (-not $workspace) {
    Write-Host "  Log Analytics Workspace '$WorkspaceName' not found!" -ForegroundColor Red
    exit 1
}
Write-Host "  Workspace found: $WorkspaceName" -ForegroundColor Green

# Build workspace resource ID
$workspaceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
Write-Host "Workspace ID: $workspaceId" -ForegroundColor Cyan

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Resource Group:    $ResourceGroup" -ForegroundColor White
Write-Host "Location:          $Location" -ForegroundColor White
Write-Host "Workspace:         $WorkspaceName" -ForegroundColor White
Write-Host ""

try {
    Write-Host ""
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Deploying Single User Workbook" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    
    # Deploy the single user workbook first
    $singleUserWorkbookResourceId = Deploy-Workbook -WorkbookTemplatePath $singleUserWorkbookPath `
        -WorkbookDisplayName "AVD Resource Usage - Single User Dashboard" `
        -WorkspaceId $workspaceId `
        -SubscriptionId $SubscriptionId `
        -ResourceGroup $ResourceGroup `
        -WorkspaceName $WorkspaceName `
        -Location $Location
    
    Write-Host ""
    Write-Host "================================" -ForegroundColor Cyan
    Write-Host "Deploying Main Workbook" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    
    # Deploy the main workbook using the single user workbook resource ID for links
    $mainWorkbookResourceId = Deploy-Workbook -WorkbookTemplatePath $mainWorkbookPath `
        -WorkbookDisplayName "AVD User Resource Usage Dashboard" `
        -WorkspaceId $workspaceId `
        -SubscriptionId $SubscriptionId `
        -ResourceGroup $ResourceGroup `
        -WorkspaceName $WorkspaceName `
        -Location $Location `
        -MainWorkbookResourceId $singleUserWorkbookResourceId
    
    Write-Host ""
    Write-Host "================================" -ForegroundColor Green
    Write-Host "  All Deployments Successful!" -ForegroundColor Green
    Write-Host "================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Both workbooks have been deployed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Single User Workbook:" -ForegroundColor Cyan
    Write-Host "  Resource ID: $singleUserWorkbookResourceId" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Main Workbook:" -ForegroundColor Cyan
    Write-Host "  Resource ID: $mainWorkbookResourceId" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To access your workbooks:" -ForegroundColor Cyan
    Write-Host "1. Go to Azure Portal (https://portal.azure.com)" -ForegroundColor White
    Write-Host "2. Navigate to Monitor > Workbooks" -ForegroundColor White
    Write-Host "3. Look for your workbooks in the workbooks list" -ForegroundColor White
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "  Deployment failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "- Ensure you have 'Workbook Contributor' role" -ForegroundColor White
    Write-Host "- Verify the workspace exists and is accessible" -ForegroundColor White
    Write-Host "- Check that the location is valid for your subscription" -ForegroundColor White
    exit 1
}
