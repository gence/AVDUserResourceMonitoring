# Create Data Collection Rule (DCR) and Data Collection Endpoint (DCE) Script
# Author: GitHub Copilot, Gence Soysal
# Date: November 10, 2025
# Purpose: Create DCE and DCR for custom log ingestion to Log Analytics workspace

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$DCRPrefix = "DCR-AVDResMon",
    
    [Parameter(Mandatory=$true)]
    [string]$DCEName = "DCE-AVDResMon",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$SchemaFolderPath
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
function Get-LogAnalyticsWorkspace {
    param([string]$WorkspaceName, [string]$ResourceGroupName)
    
    Write-Host "Validating Log Analytics workspace: $WorkspaceName in resource group: $ResourceGroupName"
    
    try {
        $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction Stop
        Write-Host "Found workspace: $($workspace.Name) in location: $($workspace.Location)" "SUCCESS"
        Write-Host "Workspace Resource ID: $($workspace.ResourceId)"
        Write-Host "Workspace ID: $($workspace.CustomerId)"
        return $workspace
    }
    catch {
        Write-Host "Failed to find workspace '$WorkspaceName' in resource group '$ResourceGroupName': $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Function to read schema from JSON file
function Get-SchemaFromJsonFile {
    param([string]$SchemaFilePath, [string]$TableName)
    
    Write-Host "Reading schema from JSON file..."
    
    # Determine schema file path
    if ([string]::IsNullOrEmpty($SchemaFilePath)) {
        $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
        $SchemaFilePath = Join-Path $scriptDir "$TableName.json"
    }
    
    Write-Host "Schema file path: $SchemaFilePath"
    
    # Check if file exists
    if (-not (Test-Path $SchemaFilePath)) {
        Write-Host "Schema file not found: $SchemaFilePath" "ERROR"
        return $null
    }
    
    try {
        $jsonContent = Get-Content -Path $SchemaFilePath -Raw -Encoding UTF8
        $schemaData = $jsonContent | ConvertFrom-Json
        
        # Handle both single object and array formats
        if ($schemaData -is [array]) {
            Write-Host "JSON file contains array format with $($schemaData.Count) elements"
            if ($schemaData.Count -eq 0) {
                Write-Host "JSON array is empty" "ERROR"
                return $null
            }
            $schemaRecord = $schemaData[0]
        } else {
            Write-Host "JSON file contains single object format"
            $schemaRecord = $schemaData
        }
        
        # Validate that we have a schema record
        if ($null -eq $schemaRecord) {
            Write-Host "No schema definition found in JSON file" "ERROR"
            return $null
        }
        
        $columns = @()
        
        $schemaRecord.PSObject.Properties | ForEach-Object {
            $columnName = $_.Name
            $dataTypeString = $_.Value
            
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
            }
            
            Write-Host "Column: $columnName ($dataTypeString -> $columnType)"
        }
        
        Write-Host "Schema loaded with $($columns.Count) columns from JSON file" "SUCCESS"
        return $columns
        
    }
    catch {
        Write-Host "Failed to read or parse schema file '$SchemaFilePath': $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Function to create Data Collection Endpoint (DCE)
function New-DataCollectionEndpoint {
    param(
        [string]$DCEName,
        [string]$ResourceGroupName,
        [string]$Location
    )
    
    Write-Host "Creating Data Collection Endpoint: $DCEName"
    
    try {
        # Check if DCE already exists
        try {
            $existingDCE = Get-AzDataCollectionEndpoint -ResourceGroupName $ResourceGroupName -Name $DCEName -ErrorAction Stop
            
            # Check if existing DCE is in the correct location
            if ($existingDCE.Location -eq $Location) {
                Write-Host "Data Collection Endpoint '$DCEName' already exists in correct location ($Location)" "WARNING"
                Write-Host "DCE Resource ID: $($existingDCE.Id)"
                return $existingDCE
            } else {
                Write-Host "Data Collection Endpoint '$DCEName' exists but in wrong location ($($existingDCE.Location) vs required $Location)" "WARNING"
                
                # Create a location-specific DCE name
                $locationSpecificDCEName = "$DCEName-$($Location.Replace(' ', '').ToLower())"
                Write-Host "Trying location-specific DCE name: $locationSpecificDCEName"
                
                try {
                    $locationDCE = Get-AzDataCollectionEndpoint -ResourceGroupName $ResourceGroupName -Name $locationSpecificDCEName -ErrorAction Stop
                    Write-Host "Location-specific DCE '$locationSpecificDCEName' already exists" "SUCCESS"
                    Write-Host "DCE Resource ID: $($locationDCE.Id)"
                    return $locationDCE
                }
                catch {
                    # Location-specific DCE doesn't exist, create it
                    Write-Host "Creating location-specific DCE: $locationSpecificDCEName"
                    $DCEName = $locationSpecificDCEName
                }
            }
        }
        catch {
            # DCE doesn't exist, continue with creation
        }
        
        if ($TestMode) {
            Write-Host "TEST MODE: Would create DCE '$DCEName' in location '$Location'" "TEST"
            return @{ Id = "/subscriptions/test-sub/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionEndpoints/$DCEName" }
        }
        
        # Create DCE
        $dce = New-AzDataCollectionEndpoint -ResourceGroupName $ResourceGroupName -Name $DCEName -Location $Location -NetworkAclsPublicNetworkAccess "Enabled"
        
        Write-Host "Data Collection Endpoint '$DCEName' created successfully!" "SUCCESS"
        Write-Host "DCE Resource ID: $($dce.Id)"
        
        return $dce
    }
    catch {
        Write-Host "Failed to create Data Collection Endpoint: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Function to generate transform KQL with resource group extraction
function Get-TransformKQL {
    param([array]$Columns, [string]$CustomTransformKQL)
    
    if (-not [string]::IsNullOrEmpty($CustomTransformKQL)) {
        Write-Host "Using custom transform KQL provided by user"
        return $CustomTransformKQL
    }
    
    Write-Host "Generating default transform KQL with resource group extraction..."
    
    # Create column mappings for CSV data (assuming CSV format)
    $columnMappings = @()
    
    for ($i = 0; $i -lt $Columns.Count; $i++) {
        $column = $Columns[$i]
        $columnName = $column.name
        $columnType = $column.type

        switch ($columnType) {
            "datetime" { $columnMappings += "$columnName=todatetime(d[$i])" }
            "int" { $columnMappings += "$columnName=toint(d[$i])" }
            "long" { $columnMappings += "$columnName=tolong(d[$i])" }
            "real" { $columnMappings += "$columnName=toreal(d[$i])" }
            "bool" { $columnMappings += "$columnName=tobool(d[$i])" }
            default { $columnMappings += "$columnName=tostring(d[$i])" }
        }
    }
    
    $transformKQL = "source | project _ResourceId, d = split(RawData,`",`") | project $($columnMappings -join ', ')"
    
    Write-Host "Generated transform KQL: $transformKQL"
    return $transformKQL
}

# Function to create Data Collection Rule (DCR)
function New-DataCollectionRule {
    param(
        [string]$DCRName,
        [string]$ResourceGroupName,
        [string]$Location,
        [object]$Workspace,
        [object]$DCE,
        [array]$Columns,
        [string[]]$FilePatterns,
        [string]$TableName,
        [string]$TransformKQL
    )
    
    Write-Host "Creating Data Collection Rule: $DCRName"
    
    try {
        # Check if DCR already exists
        try {
            $existingDCR = Get-AzDataCollectionRule -ResourceGroupName $ResourceGroupName -Name $DCRName -ErrorAction Stop
            Write-Host "Data Collection Rule '$DCRName' already exists" "WARNING"
            Write-Host "DCR Resource ID: $($existingDCR.Id)"
            return $existingDCR
        }
        catch {
            # DCR doesn't exist, continue with creation
        }
        
        # Create stream columns (input format for log files)
        $streamColumns = @()
        $streamColumns += @{ name = "TimeGenerated"; type = "datetime" }
        $streamColumns += @{ name = "RawData"; type = "string" }
        $streamColumns += @{ name = "FilePath"; type = "string" }
        $streamColumns += @{ name = "Computer"; type = "string" }
        
        # Create stream name - keep it simple and predictable
        $streamName = "Custom-Text-$TableName"
        Write-Host "Using stream name: $streamName"
        
        # Create DCR configuration
        $dcrConfig = @{
            location = $Location
            properties = @{
                dataCollectionEndpointId = $DCE.Id
                streamDeclarations = @{
                    $streamName = @{
                        columns = $streamColumns
                    }
                }
                dataSources = @{
                    logFiles = @(
                        @{
                            streams = @($streamName)
                            filePatterns = $FilePatterns
                            format = "text"
                            name = $streamName.Substring(0, [Math]::Min(32, $streamName.Length))
                        }
                    )
                }
                destinations = @{
                    logAnalytics = @(
                        @{
                            workspaceResourceId = $Workspace.ResourceId
                            name = "la-destination"
                        }
                    )
                }
                dataFlows = @(
                    @{
                        streams = @($streamName)
                        destinations = @("la-destination")
                        transformKql = $TransformKQL
                        outputStream = "Custom-$TableName"
                    }
                )
            }
        }

        
        # Get access token and make REST API call (since PowerShell cmdlets might not support all DCR features)
        $context = Get-AzContext
        $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id, $null, "Never", $null, "https://management.azure.com/").AccessToken
        
        $subscriptionId = $context.Subscription.Id
        $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/$DCRName" + "?api-version=2023-03-11"
        
        $headers = @{
            'Authorization' = "Bearer $token"
            'Content-Type' = 'application/json'
        }
        
        $body = $dcrConfig | ConvertTo-Json -Depth 10
        
        Write-Host "Making REST API call to create Data Collection Rule..."
        Write-Host "URI: $uri"
        Write-Host "Request Body:"
        Write-Host $body
        
        $response = Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers -Body $body -ErrorAction Stop

        Write-Host "Data Collection Rule '$DCRName' created successfully!" "SUCCESS"
        Write-Host "DCR Resource ID: $($response.id)"
        
        return $response
    }
    catch {
        Write-Host "Failed to create Data Collection Rule: $($_.Exception.Message)" "ERROR"
        
        # Try to get detailed error response
        if ($_.ErrorDetails) {
            Write-Host "Error Details: $($_.ErrorDetails.Message)" "ERROR"
        }
        
        if ($_.Exception.Response) {
            Write-Host "Response Status Code: $($_.Exception.Response.StatusCode)" "ERROR"
            Write-Host "Response Status Description: $($_.Exception.Response.ReasonPhrase)" "ERROR"
            
            # For PowerShell Invoke-RestMethod errors, try to get response content
            if ($_.Exception.Response.Content) {
                try {
                    $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                    Write-Host "Error response content: $errorContent" "ERROR"
                }
                catch {
                    Write-Host "Could not read error response content" "ERROR"
                }
            }
        }
        return $null
    }
}

# Main execution
Write-Host "Starting DCR and DCE Creation Script"
Write-Host "DCE Name: $DCEName"
Write-Host "DCR Prefix: $DCRPrefix"
Write-Host "Workspace: $WorkspaceName"
Write-Host "Subscription ID: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Location: $Location"

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
$workspace = Get-LogAnalyticsWorkspace -WorkspaceName $WorkspaceName -ResourceGroupName $ResourceGroupName
if (-not $workspace) {
    Write-Host "Cannot proceed without valid Log Analytics workspace" "ERROR"
    exit 1
}

# Use workspace location for DCR to ensure they're in the same region
$workspaceLocation = $workspace.Location
if ($workspaceLocation -ne $Location) {
    Write-Host "Adjusting DCR location from '$Location' to '$workspaceLocation' to match Log Analytics workspace" "WARNING"
    $Location = $workspaceLocation
}

# Step 4: Create Data Collection Endpoint (DCE)
$dce = New-DataCollectionEndpoint -DCEName $DCEName -ResourceGroupName $ResourceGroupName -Location $Location
if (-not $dce) {
    Write-Host "Cannot proceed without Data Collection Endpoint" "ERROR"
    exit 1
}

# Step 5: Create DCR for each table from schema files
$scriptDir = Split-Path -Parent $MyInvocation.ScriptName

if ([string]::IsNullOrEmpty($SchemaFolderPath)) {
    $SchemaFolderPath = $scriptDir
}

$schemaFiles = @()
$schemaFiles += Get-ChildItem -Path $SchemaFolderPath -Filter "*.json" | ForEach-Object { $_.FullName }

foreach ($file in $schemaFiles) {
    $TableName = [System.IO.Path]::GetFileNameWithoutExtension($file)
    Write-Host "Deploying DCR for $TableName"

    # Read table schema
    $columns = Get-SchemaFromJsonFile -SchemaFilePath $file -TableName $TableName
    if (-not $columns) {
        Write-Host "Cannot proceed without valid table schema for $TableName." "ERROR"
        exit 1
    }

    # Generate transform KQL
    $transformKQL = Get-TransformKQL -Columns $columns

    $TableNameShort = $TableName.Replace('_CL', '')
    $DCRName = "$DCRPrefix-$TableNameShort"
    $FilePatterns = @("C:\ProgramData\AVDSessionWatch\$TableNameShort\*.csv")
    Write-Host "Using file patterns: $($FilePatterns -join ', ')"

    # Create Data Collection Rule (DCR)
    $dcr = New-DataCollectionRule -DCRName $DCRName -ResourceGroupName $ResourceGroupName -Location $Location -Workspace $workspace -DCE $dce -Columns $columns -FilePatterns $FilePatterns -TableName $TableNameShort -TransformKQL $transformKQL

    if ($dcr) {
        Write-Host "DCR creation completed successfully!" "SUCCESS"
        Write-Host "Data Collection Endpoint: $($dce.Id)"
        Write-Host "Data Collection Rule: $($dcr.id)"
        Write-Host "Target Table: $TableName"
        Write-Host "Transform KQL: $transformKQL"
    } else {
        Write-Host "DCR creation failed. Check the error messages above." "ERROR"
        exit 1
    }
}

Write-Host ""
Write-Host "Next Steps:"
Write-Host "1. Install Azure Monitor Agent on target VMs"
Write-Host "2. Associate the DCR with the VMs using Azure Policy or direct assignment"
Write-Host "3. Verify log files are being collected from: $($FilePatterns -join ', ')"
Write-Host "4. Check data ingestion in Log Analytics workspace"
Write-Host "Script execution completed."

# Usage Examples:
<#
# Basic usage:
.\Create-DCR-DCE.ps1 -WorkspaceName "MyWorkspace" -ResourceGroupName "MyRG" -DCEName "DCE-AVDData" -FilePatterns @("C:\ProgramData\AVDMonitoring\processes\*.csv")

# With custom location and subscription:
.\Create-DCR-DCE.ps1 -WorkspaceName "MyWorkspace" -ResourceGroupName "MyRG" -TableName "SessionHostUserSessions_CL" -DCRName "DCR-AVDSessions" -DCEName "DCE-AVDData" -FilePatterns @("C:\ProgramData\ArkasAVDSessionWatch\sessions\*.csv") -Location "Germany West Central" -SubscriptionId "your-subscription-id"

# With custom transform KQL:
$customKQL = "source | project d = split(RawData,',') | project HostName=tostring(d[0]), TimeGenerated=todatetime(d[1]), UserName=tostring(d[2]), ResourceGroup=tostring(split(_ResourceId, '/')[4])"
.\Create-DCR-DCE.ps1 -WorkspaceName "MyWorkspace" -ResourceGroupName "MyRG" -TableName "CustomTable_CL" -DCRName "DCR-Custom" -DCEName "DCE-Custom" -FilePatterns @("C:\Logs\*.csv") -TransformKQL $customKQL

# Test mode:
.\Create-DCR-DCE.ps1 -WorkspaceName "MyWorkspace" -ResourceGroupName "MyRG" -TableName "AVDUserProcesses_CL" -DCRName "DCR-AVDProcesses" -DCEName "DCE-AVDData" -FilePatterns @("C:\ProgramData\AVDMonitoring\processes\*.csv") -TestMode

# Prerequisites:
# 1. Install Azure PowerShell: Install-Module -Name Az -AllowClobber
# 2. Connect to Azure: Connect-AzAccount
# 3. Ensure you have appropriate permissions (Monitoring Contributor role or higher)
# 4. Create the target custom table first using Create-CustomLogAnalyticsTable.ps1
# 5. Create schema JSON file for the table
#>