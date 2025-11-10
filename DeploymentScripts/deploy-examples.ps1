# Example usage script for deploy-monitoring.ps1
# Copy and modify this script for your specific deployment needs

# ========================================
# EXAMPLE 1: Deploy to specific VMs using Azure Storage
# ========================================

# First, set up your Azure Storage Account (one-time setup)
# $storageAccount = New-AzStorageAccount -ResourceGroupName "your-rg" -Name "yourstorageaccount" -Location "East US" -SkuName "Standard_LRS"
# $storageKey = (Get-AzStorageAccountKey -ResourceGroupName "your-rg" -Name "yourstorageaccount")[0].Value

# Deploy to specific VMs
$vmNames = @("VM-Web-01", "VM-Web-02", "VM-App-01")
$resourceGroup = "Production-RG"
$storageAccount = "yourstorageaccount"  # Replace with your storage account
$storageKey = "your-storage-key"        # Replace with your storage key

.\deploy-avdsessionwatch.ps1 `
    -VMNames $vmNames `
    -ResourceGroupName $resourceGroup `
    -StorageAccountName $storageAccount `
    -StorageAccountKey $storageKey `
    -Location "East US"

# ========================================
# EXAMPLE 2: Deploy to all Windows VMs in a Resource Group
# ========================================

# Get all Windows VMs in the resource group
$allVMs = Get-AzVM -ResourceGroupName $resourceGroup
$windowsVMs = $allVMs | Where-Object { $_.StorageProfile.OsDisk.OsType -eq "Windows" }
$vmNames = $windowsVMs.Name

Write-Host "Found $($vmNames.Count) Windows VMs: $($vmNames -join ', ')"

.\deploy-avdsessionwatch.ps1 `
    -VMNames $vmNames `
    -ResourceGroupName $resourceGroup `
    -StorageAccountName $storageAccount `
    -StorageAccountKey $storageKey

# ========================================
# EXAMPLE 3: Test deployment (doesn't actually deploy)
# ========================================

.\deploy-avdsessionwatch.ps1 `
    -VMNames @("Test-VM-01") `
    -ResourceGroupName $resourceGroup `
    -TestMode

# ========================================
# EXAMPLE 4: Deploy using local files (for development)
# ========================================

.\deploy-avdsessionwatch.ps1 -VMNames @("Dev-VM-01") -ResourceGroupName "Development-RG" -UseLocalFiles

# ========================================
# EXAMPLE 5: Deploy to VMs by tag
# ========================================

# Get VMs with specific tags
$taggedVMs = Get-AzVM -ResourceGroupName $resourceGroup | Where-Object { 
    $_.Tags["Environment"] -eq "Production" -and 
    $_.Tags["Role"] -eq "WebServer" 
}
$vmNames = $taggedVMs.Name

.\deploy-avdsessionwatch.ps1 `
    -VMNames $vmNames `
    -ResourceGroupName $resourceGroup `
    -StorageAccountName $storageAccount `
    -StorageAccountKey $storageKey

# ========================================
# EXAMPLE 6: Mass deployment across multiple Resource Groups
# ========================================

$resourceGroups = @("RG-Production", "RG-Staging", "RG-Testing")

foreach ($rg in $resourceGroups) {
    Write-Host "Deploying to Resource Group: $rg"
    
    # Get Windows VMs in this RG
    $vms = Get-AzVM -ResourceGroupName $rg | Where-Object { 
        $_.StorageProfile.OsDisk.OsType -eq "Windows" 
    }
    
    if ($vms.Count -gt 0) {
        .\deploy-avdsessionwatch.ps1 `
            -VMNames $vms.Name `
            -ResourceGroupName $rg `
            -StorageAccountName $storageAccount `
            -StorageAccountKey $storageKey
    } else {
        Write-Host "No Windows VMs found in $rg"
    }
}