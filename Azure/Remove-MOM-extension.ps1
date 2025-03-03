<#
.SYNOPSIS
    Entfernt die Microsoft Monitoring Agent (MOM) Erweiterung von allen virtuellen Maschinen in einer Azure Subscription.

.DESCRIPTION
    Dieses Skript verbindet sich mit einem Azure-Konto, setzt den Kontext auf eine bestimmte Subscription und entfernt die Microsoft Monitoring Agent (MOM) Erweiterung von allen virtuellen Maschinen (VMs) in dieser Subscription, falls diese installiert ist.
    Es überprüft jede VM in der Subscription und entfernt die Erweiterung, falls sie vorhanden ist. Wenn eine VM nicht läuft, wird sie gestartet, die Erweiterung wird entfernt und die VM wird anschließend wieder heruntergefahren.

.PARAMETER SubscriptionId
    Die ID der Azure Subscription, in der die VMs verwaltet werden sollen.

.NOTES
    Autor: Marc Schramm
    Datum: 3. März 2025
    Version: 1.1

.EXAMPLE
    .\Remove-MOM-extension.ps1 -SubscriptionId "your-subscription-id"
#>

param (
    [string]$SubscriptionId
)

# Log in to Azure (uncomment if not already logged in)
Connect-AzAccount

# Set the Subscription (replace <subscription-id> with your subscription ID)
Set-AzContext -SubscriptionId $SubscriptionId

# Get all VMs in the subscription
$vms = Get-AzVM

foreach ($vm in $vms) {
    $resourceGroupName = $vm.ResourceGroupName
    $vmName = $vm.Name

    # Get the VM's power state
    $vmStatus = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Status
    $powerState = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -ExpandProperty Code

    if ($powerState -eq "PowerState/running") {
        # VM is running, proceed to remove the extension
        Write-Host "$vmName is running. Checking for MicrosoftMonitoringAgent..."
        $extension = Get-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name "MicrosoftMonitoringAgent" -ErrorAction SilentlyContinue

        if ($extension) {
            Write-Host "Removing MicrosoftMonitoringAgent from $vmName..."
            Remove-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name "MicrosoftMonitoringAgent" -Force
            Write-Host "Extension removed from $vmName."
        } else {
            Write-Host "MicrosoftMonitoringAgent not found on $vmName."
        }
    } else {
        # VM is not running, start it
        Write-Host "$vmName is not running (State: $powerState). Starting the VM..."
        Start-AzVM -ResourceGroupName $resourceGroupName -Name $vmName

        # Wait until the VM is fully running
        Write-Host "Waiting for $vmName to be ready..."
        do {
            Start-Sleep -Seconds 10
            $vmStatus = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Status
            $powerState = $vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" } | Select-Object -ExpandProperty Code
        } while ($powerState -ne "PowerState/running")

        Write-Host "$vmName is now running. Checking for MicrosoftMonitoringAgent..."
        $extension = Get-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name "MicrosoftMonitoringAgent" -ErrorAction SilentlyContinue

        if ($extension) {
            Write-Host "Removing MicrosoftMonitoringAgent from $vmName..."
            Remove-AzVMExtension -ResourceGroupName $resourceGroupName -VMName $vmName -Name "MicrosoftMonitoringAgent" -Force
            Write-Host "Extension removed from $vmName."
        } else {
            Write-Host "MicrosoftMonitoringAgent not found on $vmName."
        }

        # Shut down the VM after removing the extension
        Write-Host "Shutting down $vmName..."
        Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Force
        Write-Host "$vmName has been shut down."
    }
}