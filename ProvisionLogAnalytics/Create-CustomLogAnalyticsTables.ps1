# Create Custom Log Analytics Table Script
# Author: GitHub Copilot, Gence Soysal
# Date: November 10, 2025
# Purpose: Create a custom table in Log Analytics workspace for AVD monitoring data

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
     
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$SchemaFolderPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$TestMode = $false
)

# Function to test Azure PowerShell connection
function Test-AzureConnection {
    Write-Host "Testing Azure PowerShell connection..."
    
    try {
        $context = Get-AzContext
        if ($null -eq $context) {
            Write-Host "No Azure context found. Please run Connect-AzAccount first." "ERROR"
            return $false
        }
        
        Write-Host "Connected to Azure as: $($context.Account.Id)" "SUCCESS"
        Write-Host "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
        return $true
    }
    catch {
        Write-Host "Failed to get Azure context: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to validate Log Analytics workspace
function Test-LogAnalyticsWorkspace {
    param([string]$WorkspaceName, [string]$ResourceGroupName)
    
    Write-Host "Validating Log Analytics workspace: $WorkspaceName in resource group: $ResourceGroupName"
    
    try {
        $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction Stop
        Write-Host "Found workspace: $($workspace.Name) in location: $($workspace.Location)" "SUCCESS"
        return $workspace
    }
    catch {
        Write-Host "Failed to find workspace '$WorkspaceName' in resource group '$ResourceGroupName': $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Function to read schema definition from JSON file
function Get-SchemaFromJsonFile {
    param([string]$SchemaFilePath, [string]$TableName)
    
    Write-Host "Reading schema from JSON file..."
    
    # Determine schema file path
    if ([string]::IsNullOrEmpty($SchemaFilePath)) {
        # Default to same directory as script with table name
        $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
        $SchemaFilePath = Join-Path $scriptDir "$TableName.json"
    }
    
    Write-Host "Schema file path: $SchemaFilePath"
    
    # Check if file exists
    if (-not (Test-Path $SchemaFilePath)) {
        Write-Host "Schema file not found: $SchemaFilePath" "ERROR"
        Write-Host "Please ensure the JSON schema file exists with the same name as the table." "ERROR"
        return $null
    }
    
    try {
        # Read and parse JSON file
        $jsonContent = Get-Content -Path $SchemaFilePath -Raw -Encoding UTF8
        $schemaData = $jsonContent | ConvertFrom-Json
        
        Write-Host "Successfully loaded JSON schema file"
        
        # Extract schema from type definitions
        if ($null -eq $schemaData) {
            Write-Host "JSON file is empty or contains no schema definitions" "ERROR"
            return $null
        }
        
        # Use the JSON object directly to read column definitions
        $schemaRecord = $schemaData
        $columns = @()
        
        # Convert PowerShell object properties to schema columns
        $schemaRecord.PSObject.Properties | ForEach-Object {
            $columnName = $_.Name
            $dataTypeString = $_.Value
            
            # Convert data type string to Log Analytics format
            $columnType = switch ($dataTypeString.ToLower()) {
                "string" { "string" }
                "int" { "int" }
                "long" { "long" }
                "datetime" { "datetime" }
                "real" { "real" }
                "double" { "real" }
                "bool" { "bool" }
                "boolean" { "bool" }
                default { 
                    Write-Host "Unknown data type '$dataTypeString' for column '$columnName', defaulting to string" "WARNING"
                    "string"
                }
            }
                        
            $columns += @{
                name = $columnName
                type = $columnType
                description = $columnName
            }
            
            Write-Host "Column: $columnName ($dataTypeString -> $columnType)"
        }
        
        # Create schema object
        $schema = @{
            properties = @{
                schema = @{
                    name = $TableName
                    columns = $columns
                }
            }
        }
        
        Write-Host "Schema created with $($columns.Count) columns from JSON file" "SUCCESS"
        return $schema
        
    }
    catch {
        Write-Host "Failed to read or parse schema file '$SchemaFilePath': $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Function to create custom table using REST API
function New-CustomLogAnalyticsTable {
    param(
        [object]$Workspace,
        [string]$TableName,
        [object]$Schema
    )
    
    Write-Host "Creating custom table: $TableName"
    
    try {
        # Get access token for Azure REST API
        $context = Get-AzContext
        $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "https://management.azure.com/").AccessToken
        
        # Prepare REST API call
        $subscriptionId = $context.Subscription.Id
        $resourceGroupName = $Workspace.ResourceGroupName
        $workspaceName = $Workspace.Name
        
        $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/tables/$TableName" + "?api-version=2022-10-01"
        
        $headers = @{
            'Authorization' = "Bearer $token"
            'Content-Type' = 'application/json'
        }
        
        $body = $Schema | ConvertTo-Json -Depth 10
        
        if ($TestMode) {
            Write-Host "TEST MODE: Would create table with URI: $uri" "TEST"
            Write-Host "TEST MODE: Schema would be: $body" "TEST"
            return @{ Success = $true; TestMode = $true }
        }
        
        # Make REST API call to create table
        Write-Host "Making REST API call to create custom table..."
        $response = Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body $body -ErrorAction Stop
        
        Write-Host "Custom table '$TableName' created successfully!" "SUCCESS"
        Write-Host "Table ID: $($response.id)"
        
        return @{ Success = $true; Response = $response }
    }
    catch {
        Write-Host "Failed to create custom table: $($_.Exception.Message)" "ERROR"
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorResponse)
            $errorBody = $reader.ReadToEnd()
            Write-Host "Error response: $errorBody" "ERROR"
        }
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# Function to verify table creation
function Test-CustomTableCreation {
    param([string]$WorkspaceName, [string]$ResourceGroupName, [string]$TableName)
    
    Write-Host "Verifying table creation..."
    
    try {
        # Wait a bit for table to be available
        Start-Sleep -Seconds 30
        
        # Try to query the table structure
        $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
        $workspaceId = $workspace.CustomerId
        
        # Note: Custom tables may take several minutes to become queryable
        Write-Host "Custom table '$TableName' should be available shortly." "SUCCESS"
        Write-Host "You can verify by running a query like: $TableName | limit 10"
        Write-Host "Note: It may take 5-10 minutes for the table to become fully queryable."
        
        return $true
    }
    catch {
        Write-Host "Could not immediately verify table creation: $($_.Exception.Message)" "WARNING"
        Write-Host "This is normal - custom tables may take several minutes to become available."
        return $false
    }
}

# Main execution
Write-Host "Starting Custom Log Analytics Table Creation Script"
Write-Host "Workspace: $WorkspaceName"
Write-Host "Resource Group: $ResourceGroupName"
if ($SchemaFilePath) {
    Write-Host "Schema File: $SchemaFilePath"
} else {
    Write-Host "Schema File: Will use .json files from script directory"
}

# Step 1: Test Azure connection
if (-not (Test-AzureConnection)) {
    Write-Host "Please run 'Connect-AzAccount' to authenticate with Azure and try again." "ERROR"
    exit 1
}

# Step 2: Set subscription if provided
if ($SubscriptionId) {
    try {
        Write-Host "Setting subscription context to: $SubscriptionId"
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        Write-Host "Subscription context set successfully" "SUCCESS"
    }
    catch {
        Write-Host "Failed to set subscription context: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

# Step 3: Validate workspace
$workspace = Test-LogAnalyticsWorkspace -WorkspaceName $WorkspaceName -ResourceGroupName $ResourceGroupName
if (-not $workspace) {
    Write-Host "Cannot proceed without valid Log Analytics workspace" "ERROR"
    exit 1
}

# Step 4: Create custom tables from schema files
$scriptDir = Split-Path -Parent $MyInvocation.ScriptName


if ([string]::IsNullOrEmpty($SchemaFolderPath)) {
    $SchemaFolderPath = $scriptDir
}

$schemaFiles = @()
$schemaFiles += Get-ChildItem -Path $SchemaFolderPath -Filter "*.json" | ForEach-Object { $_.FullName }

foreach ($file in $schemaFiles) {
    $TableName = [System.IO.Path]::GetFileNameWithoutExtension($file)
    Write-Host "Deploying table: $TableName"

    # Read table schema from JSON file
    $schema = Get-SchemaFromJsonFile -SchemaFilePath $file -TableName $TableName
    if (-not $schema) {
        Write-Host "Cannot proceed without valid table schema for $TableName" "ERROR"
        exit 1
    }

    # Create custom table
    $result = New-CustomLogAnalyticsTable -Workspace $workspace -TableName $TableName -Schema $schema

    if ($result.Success) {
        Write-Host "Custom table creation completed successfully!" "SUCCESS"
        
        # Step 6: Verify table creation
        Test-CustomTableCreation -WorkspaceName $WorkspaceName -ResourceGroupName $ResourceGroupName -TableName $TableName
        
        Write-Host "Next Steps:"
        Write-Host "1. Wait 5-10 minutes for the table to become fully available"
        Write-Host "2. Test the table by running: $TableName | limit 10"
        Write-Host "3. Send data to the table using the Data Collection Endpoint"
        Write-Host "4. Use the HTTP Data Collector API or Azure Monitor Agent to ingest data"
    } else {
        Write-Host "Custom table creation failed. Check the error messages above." "ERROR"
        exit 1
    }
}

Write-Host "Script execution completed."

# Usage Examples:
<#
# Basic usage (reads schema from TableName.json in same directory):
.\Create-CustomLogAnalyticsTables.ps1 -WorkspaceName "MyWorkspace" -ResourceGroupName "MyRG"

# With specific subscription:
.\Create-CustomLogAnalyticsTables.ps1 -WorkspaceName "MyWorkspace" -ResourceGroupName "MyRG" -SubscriptionId "12345678-1234-1234-1234-123456789012"

# Prerequisites:
# 1. Install Azure PowerShell: Install-Module -Name Az -AllowClobber
# 2. Connect to Azure: Connect-AzAccount
# 3. Ensure you have appropriate permissions on the Log Analytics workspace
# 4. Create a JSON schema file with sample data (e.g., TaskListData_CL.json for table TaskListData_CL)

# Schema File Format:
# The JSON file should contain a single object that defines column names and their data types.
# Supported data types: String, Int, Long, Datetime, Real, Bool
# Example for AVDUserProcesses_CL.json:
# {
#   "TimeGenerated": "Datetime",
#   "HostName": "String",
#   "ImageName": "String",
#   "PID": "Int",
#   "SessionName": "String",
#   "SessionId": "Int",
#   "MemUsageBytes": "Long",
#   "UserName": "String",
#   "CPUTimeSeconds": "Long"
# }
#>