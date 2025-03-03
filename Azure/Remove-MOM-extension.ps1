<#
.SYNOPSIS
    Entfernt die Microsoft Monitoring Agent (MOM) Erweiterung von allen virtuellen Maschinen in einer Azure Subscription.

.DESCRIPTION
    Dieses Skript verbindet sich mit einem Azure-Konto, setzt den Kontext auf eine bestimmte Subscription und entfernt die Microsoft Monitoring Agent (MOM) Erweiterung von allen virtuellen Maschinen (VMs) in dieser Subscription, falls diese installiert ist.
    Es überprüft jede VM in der Subscription und entfernt die Erweiterung, falls sie vorhanden ist.

.PARAMETER SubscriptionId
    Die ID der Azure Subscription, in der die VMs verwaltet werden sollen.

.NOTES
    Autor: Marc Schramm
    Datum: 3. März 2025
    Version: 1.0

.EXAMPLE
    .\Remove-MOM-extension.ps1 -SubscriptionId "your-subscription-id"
#>

param (
    [string]$SubscriptionId
)

Connect-AzAccount
Set-AzContext -SubscriptionId $SubscriptionId
# Get all VMs in the subscription
$vms = Get-AzVM

foreach ($vm in $vms) {
    $resourceGroupName = $vm.ResourceGroupName
    $vmName = $vm.Name

    # Check if the MicrosoftMonitoringAgent extension is installed
    $extension = Get-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name "MicrosoftMonitoringAgent" -ErrorAction SilentlyContinue

    if ($extension) {
        Write-Host "Removing MicrosoftMonitoringAgent from $vmName in $resourceGroupName..."
        Remove-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name "MicrosoftMonitoringAgent" -Force
        Write-Host "Extension removed from $vmName."
    } else {
        Write-Host "MicrosoftMonitoringAgent not found on $vmName."
    }
}