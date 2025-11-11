$avdSubscriptionId = ""
$lawSubscriptionId = ""
$lawResourceGroupName = ""
$logAnalyticsWorkspaceName = ""
$avdResourceGroupName = ""
$avdLocation = "westeurope"
$avdSessionHostNames = @("VM-Web-01", "VM-Web-02", "VM-App-01")
$scriptStorageAccount = ""

# Provision custom tables in Log Analytics
.\ProvisionLogAnalytics\Create-CustomLogAnalyticsTables.ps1 
    -WorkspaceName $logAnalyticsWorkspaceName
    -SubscriptionId $lawSubscriptionId
    -ResourceGroupName $lawResourceGroupName 

# Create DCR and DCEs
.\ProvisionLogAnalytics\Create-DCR-DCE.ps1 
    -WorkspaceName $logAnalyticsWorkspaceName 
    -SubscriptionId $lawSubscriptionId
    -ResourceGroupName $lawResourceGroupName

# Deploy Azure Workbooks
.\Dashboard\deploy-workbooks.ps1
    -SubscriptionId $lawSubscriptionId 
    -ResourceGroupName $lawResourceGroupName 
    -WorkspaceName $logAnalyticsWorkspaceName

# Deploy deployment scripts and tasks to AVD Session Hosts using Custom Script Extension directly
.\DeploymentScripts\deploy-avdsessionwatch.ps1 `
    -VMNames $avdSessionHostNames `
    -SubscriptionId $avdSubscriptionId `
    -ResourceGroupName $avdResourceGroupName `
    -StorageAccountName $scriptStorageAccount `
    -Location $avdLocation

# Deploy deployment scripts and tasks to AVD Session Hosts using Azure Policy
.\DeploymentScripts\deploy-byazurepolicy.ps1 `
    -SubscriptionId $avdSubscriptionId `
    -StorageAccountName $scriptStorageAccount `
    -Location $avdLocation `
    -policyScope "/subscriptions/$avdSubscriptionId"
    #-policyScope "/subscriptions/$avdSubscriptionId/resourceGroups/$avdResourceGroupName"

# Update deployment scripts on all VMs via Azure Policy Remediation
.\DeploymentScripts\update-byazurepolicy.ps1 `
    -SubscriptionId $avdSubscriptionId `
    -StorageAccountName $scriptStorageAccount `
    #-ResourceGroupName $avdResourceGroupName
    #-VMNames $avdSessionHostNames