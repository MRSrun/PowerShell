<#
.SYNOPSIS
    Automates the discovery of all Virtual Networks (VNets) across Azure subscriptions and links them to Azure Private DNS Zones.

.DESCRIPTION
    This script performs the following steps:
    1. Collects VNets from all Azure subscriptions except those with names starting with "visual".
    2. Categorizes each VNet based on the subscription name.
    3. Retrieves all Azure Private DNS Zones in the current context.
    4. Links each VNet to each DNS Zone, enabling auto-registration for a specific zone ("demo.com").
    5. Verifies the creation of the DNS link.

.NOTES
    Prerequisites:
        - User must be logged in with `Connect-AzAccount`.
        - The `Az` PowerShell module should be installed.
        - Permissions to read from subscriptions and create DNS links.

.AUTHOR
    Marc Schramm
#>


#Connect-AzAccount -UseDeviceAuthentication

# Define variables
$resourceGroupName = ""         # Replace with your resource group name of the Private DNS Zone
$subscriptionId    = ""     # Replace with your subscription ID of the Private DNS Zone


##### Step 1: Get the virtual networks in all Subscriptions

# Get all subscriptions except those starting with "visual" to exclude Visual Studio Subscriptions
$subscriptions = Get-AzSubscription | Where-Object { $_.Name -notlike "visual*" }

# Initialize a list to store VNet metadata
$vnetList = @()

# Iterate through each subscription to gather VNets
foreach ($sub in $subscriptions) {
    Write-Host "Processing subscription: $($sub.Name)" -ForegroundColor Cyan

    # Set the context to the current subscription
    Set-AzContext -SubscriptionId $sub.Id

    # Retrieve all VNets in the current subscription
    $vnets = Get-AzVirtualNetwork

    foreach ($vnet in $vnets) {
        # Assign area based on subscription naming convention
        if ($sub.Name -like "Demo-APP1*") {
            $AreaID = "APP1"
        }
        else {
            $AreaID = "Plattform"
        }

        # Append VNet information to the list
        $vnetList += [PSCustomObject]@{
            SubscriptionName = $sub.Name
            ResourceGroup    = $vnet.ResourceGroupName
            VNetName         = $vnet.Name
            Location         = $vnet.Location
            AddressSpace     = ($vnet.AddressSpace.AddressPrefixes -join ", ")
            VNetId           = $vnet.Id
            Area             = $AreaID
        }
    }
}

# Display collected VNet data in a table
$vnetList | Format-Table -AutoSize



##### Step 2: Set the Azure subscription context for DNS Zone operations

# IMPORTANT: Replace with the actual subscription ID where DNS Zones reside
Set-AzContext -SubscriptionId $subscriptionId


##### Step 3: Get all Private DNS Zones

# Fetch all Private DNS Zones in the current subscription context
$PDNSZ = Get-AzPrivateDnsZone


##### Step 4: Create the virtual network link

# Iterate through each VNet
foreach ($VNetwork in $vnetList)
{
    # Link each VNet to all retrieved DNS Zones
    foreach ($zone in $PDNSZ) {

    # Special handling for DNS Zone "demo.com"
    if ($zone.Name -eq "demo.com") {
            Write-Host "Found DNS Zone: demo.com"
            
            $linkParams = @{
                ResourceGroupName = $resourceGroupName
                ZoneName = $Zone.Name
                Name = $VNetwork.VNetName
                VirtualNetworkId = $VNetwork.VNetId
            }

            # Enable auto-registration if the VNet belongs to "APP1" area
            if ($VNetwork.Area -eq "APP1") {
                $linkParams["EnableRegistration"] = $true
            }

            # Create the DNS link
            if (-not (Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $resourceGroupName -ZoneName $Zone.Name -Name $VNetwork.VNetName -ErrorAction SilentlyContinue)){
                $link = New-AzPrivateDnsVirtualNetworkLink @linkParams
                ##### Step 5: Verify the link creation
                $linkStatus = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $resourceGroupName -ZoneName $Zone.Name -Name $VNetwork.VNetName
                Write-Output "Virtual Network Link Status: $($linkStatus.VirtualNetworkLinkState)"
            }

        } else {
            # For all other DNS zones
            Write-Host "Zone $($zone.Name) is not demo.com"
            
            $linkParams = @{
                ResourceGroupName = $resourceGroupName
                ZoneName = $Zone.Name
                Name = $VNetwork.VNetName
                VirtualNetworkId = $VNetwork.VNetId
            }

            # Create the DNS link without auto-registration

            if (-not (Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $resourceGroupName -ZoneName $Zone.Name -Name $VNetwork.VNetName -ErrorAction SilentlyContinue)){
                $link = New-AzPrivateDnsVirtualNetworkLink @linkParams
                ##### Step 5: Verify the link creation
                $linkStatus = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $resourceGroupName -ZoneName $Zone.Name -Name $VNetwork.VNetName
                Write-Output "Virtual Network Link Status: $($linkStatus.VirtualNetworkLinkState)"
            }
        }
    } 
}