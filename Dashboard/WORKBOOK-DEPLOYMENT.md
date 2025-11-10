# Azure Workbook Deployment Guide

## AVD Resource Usage Dashboard

This workbook provides comprehensive insights into Azure Virtual Desktop user resource consumption patterns.

### Features

- **Time Range Selection**: Flexible date range picker (1 hour to 90 days)
- **Top 20 Users by Memory**: Table and chart visualization
- **Top 20 Users by CPU**: Table and chart visualization  
- **Resource Consumption Score**: Composite metric combining CPU and Memory
- **Top Processes Analysis**: Memory and CPU usage by process type
- **Host Load Analysis**: Time-series chart of host memory utilization
- **User Activity Patterns**: Identify power users vs occasional users

### Deployment Steps

#### Option 1: Deploy via Azure Portal

1. Navigate to **Azure Portal** > **Monitor** > **Workbooks**
2. Click **+ New**
3. Click **Advanced Editor** (toolbar icon `</>`)
4. Delete the default JSON content
5. Copy and paste the entire contents of `azure-workbook-avd-resource-usage.json`
6. Click **Apply**
7. Update the `fallbackResourceIds` section with your Log Analytics workspace:
   ```json
   "fallbackResourceIds": [
     "/subscriptions/{your-subscription-id}/resourceGroups/{your-resource-group}/providers/Microsoft.OperationalInsights/workspaces/{your-workspace-name}"
   ]
   ```
8. Click **Save** (toolbar icon)
9. Provide a name: **AVD User Resource Usage**
10. Select **Resource Group** and **Location**
11. Click **Apply**

#### Option 2: Deploy via PowerShell

```powershell
# Set your variables
$subscriptionId = "your-subscription-id"
$resourceGroup = "your-resource-group"
$workspaceName = "your-log-analytics-workspace"
$workbookName = "AVD-User-Resource-Usage"
$location = "eastus"  # or your region

# Load the workbook JSON
$workbookJson = Get-Content -Path ".\azure-workbook-avd-resource-usage.json" -Raw

# Update the fallbackResourceIds in the JSON
$workspaceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName"
$workbookJson = $workbookJson -replace '"/subscriptions/\{subscription-id\}.*?"', """$workspaceId"""

# Create the workbook
az monitor app-insights workbook create `
  --name $workbookName `
  --resource-group $resourceGroup `
  --location $location `
  --display-name "AVD User Resource Usage" `
  --serialized-data $workbookJson `
  --category "workbook"
```

#### Option 3: Deploy via ARM Template

Create a file named `deploy-workbook.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workbookDisplayName": {
      "type": "string",
      "defaultValue": "AVD User Resource Usage",
      "metadata": {
        "description": "The friendly name for the workbook"
      }
    },
    "workbookSourceId": {
      "type": "string",
      "metadata": {
        "description": "The resource ID of the Log Analytics workspace"
      }
    }
  },
  "variables": {
    "workbookId": "[newGuid()]"
  },
  "resources": [
    {
      "type": "Microsoft.Insights/workbooks",
      "name": "[variables('workbookId')]",
      "apiVersion": "2021-03-08",
      "location": "[resourceGroup().location]",
      "kind": "shared",
      "properties": {
        "displayName": "[parameters('workbookDisplayName')]",
        "serializedData": "[string(json(variables('workbookContent')))]",
        "sourceId": "[parameters('workbookSourceId')]",
        "category": "workbook"
      }
    }
  ]
}
```

Deploy with:

```powershell
az deployment group create `
  --resource-group your-resource-group `
  --template-file deploy-workbook.json `
  --parameters workbookSourceId="/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.OperationalInsights/workspaces/{workspace}"
```

### Usage

1. Open the workbook from **Monitor** > **Workbooks** > **AVD User Resource Usage**
2. Use the **Time Range** dropdown to select your analysis period
3. All visualizations will automatically update based on the selected range

### Customization

You can modify the workbook to:
- Change the top N limit (currently 20)
- Adjust visualization types (table, chart, grid, etc.)
- Add filtering by specific hosts or users
- Modify the Resource Score weighting (currently 50% CPU, 50% Memory)
- Add alerts or thresholds

### Requirements

- Log Analytics workspace with `AVDUserProcesses_CL` custom table
- Data ingestion from AVD session hosts
- Appropriate RBAC permissions to create workbooks

### Troubleshooting

**No data showing:**
- Verify the table name is `AVDUserProcesses_CL` in your workspace
- Check that data is being ingested: Run `AVDUserProcesses_CL | take 10` in Log Analytics
- Ensure the time range includes periods with data

**Query timeouts:**
- Reduce the time range
- Consider pre-aggregating data for long-term analysis

**Permission errors:**
- Ensure you have at least **Monitoring Reader** role on the workspace
- Workbook creation requires **Workbook Contributor** role
