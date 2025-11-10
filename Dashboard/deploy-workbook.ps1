# Deploy Azure Workbook for AVD Resource Usage
# This script helps you deploy the workbook to your Azure environment

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$false)]
    [string]$WorkbookName = "AVD-User-Resource-Usage",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus"
)

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Azure Workbook Deployment Script" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check if logged in to Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Logged in as: $($context.Account.Id)" -ForegroundColor Green
} catch {
    Write-Host "Not logged in to Azure. Please run Connect-AzAccount first." -ForegroundColor Red
    exit 1
}

# Set subscription context
Write-Host "Setting subscription context..." -ForegroundColor Yellow
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Host "✓ Subscription set: $SubscriptionId" -ForegroundColor Green

# Verify Resource Group exists
Write-Host "Verifying resource group..." -ForegroundColor Yellow
$rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "✗ Resource Group '$ResourceGroup' not found!" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Resource Group found: $ResourceGroup" -ForegroundColor Green

# Verify Log Analytics Workspace exists
Write-Host "Verifying Log Analytics workspace..." -ForegroundColor Yellow
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceName -ErrorAction SilentlyContinue
if (-not $workspace) {
    Write-Host "✗ Log Analytics Workspace '$WorkspaceName' not found!" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Workspace found: $WorkspaceName" -ForegroundColor Green

# Build workspace resource ID
$workspaceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
Write-Host "Workspace ID: $workspaceId" -ForegroundColor Cyan

# Load workbook JSON
Write-Host "Loading workbook template..." -ForegroundColor Yellow
$workbookPath = Join-Path $PSScriptRoot "azure-workbook-avd-resource-usage.json"
if (-not (Test-Path $workbookPath)) {
    Write-Host "✗ Workbook file not found: $workbookPath" -ForegroundColor Red
    exit 1
}

$workbookJson = Get-Content -Path $workbookPath -Raw
Write-Host "✓ Workbook template loaded" -ForegroundColor Green

# Update the fallbackResourceIds
Write-Host "Updating workspace reference..." -ForegroundColor Yellow
$workbookObj = $workbookJson | ConvertFrom-Json
$workbookObj.fallbackResourceIds = @($workspaceId)
$updatedJson = $workbookObj | ConvertTo-Json -Depth 100 -Compress

Write-Host "✓ Workspace reference updated" -ForegroundColor Green

# Generate unique workbook ID
$workbookGuid = [Guid]::NewGuid().ToString()

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Deployment Summary" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Workbook Name:    $WorkbookName" -ForegroundColor White
Write-Host "Resource Group:   $ResourceGroup" -ForegroundColor White
Write-Host "Location:         $Location" -ForegroundColor White
Write-Host "Workspace:        $WorkspaceName" -ForegroundColor White
Write-Host ""

$confirmation = Read-Host "Do you want to proceed with deployment? (Y/N)"
if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Deploying workbook..." -ForegroundColor Yellow

# Create the workbook using ARM template
$templateJson = @"
{
  "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {},
  "resources": [
    {
      "type": "microsoft.insights/workbooks",
      "apiVersion": "2021-03-08",
      "name": "$workbookGuid",
      "location": "$Location",
      "kind": "shared",
      "properties": {
        "displayName": "$WorkbookName",
        "serializedData": $(($workbookObj | ConvertTo-Json -Depth 100) -replace '"', '\"'),
        "version": "1.0",
        "sourceId": "$workspaceId",
        "category": "workbook"
      }
    }
  ]
}
"@

# Save template temporarily
$tempTemplate = Join-Path $env:TEMP "workbook-deployment-$workbookGuid.json"
$templateJson | Out-File -FilePath $tempTemplate -Encoding UTF8

try {
    # Deploy the template
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroup `
        -TemplateFile $tempTemplate `
        -Name "WorkbookDeployment-$workbookGuid" `
        -ErrorAction Stop
    
    Write-Host ""
    Write-Host "================================" -ForegroundColor Green
    Write-Host "✓ Deployment Successful!" -ForegroundColor Green
    Write-Host "================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your workbook has been deployed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "To access your workbook:" -ForegroundColor Cyan
    Write-Host "1. Go to Azure Portal (https://portal.azure.com)" -ForegroundColor White
    Write-Host "2. Navigate to Monitor > Workbooks" -ForegroundColor White
    Write-Host "3. Look for '$WorkbookName' in your workbooks" -ForegroundColor White
    Write-Host ""
    Write-Host "Or use this direct link:" -ForegroundColor Cyan
    Write-Host "https://portal.azure.com/#blade/AppInsightsExtension/UsageNotebookBlade/ComponentId/$([uri]::EscapeDataString($workspaceId))/ConfigurationId/$([uri]::EscapeDataString($workbookGuid))" -ForegroundColor Yellow
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "✗ Deployment failed!" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "- Ensure you have 'Workbook Contributor' role" -ForegroundColor White
    Write-Host "- Verify the workspace exists and is accessible" -ForegroundColor White
    Write-Host "- Check that the location is valid for your subscription" -ForegroundColor White
    exit 1
} finally {
    # Clean up temp file
    if (Test-Path $tempTemplate) {
        Remove-Item $tempTemplate -Force
    }
}
