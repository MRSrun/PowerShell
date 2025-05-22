<#
.SYNOPSIS
    Analyze and export Azure NSG (Network Security Group) Flow Logs.

.DESCRIPTION
    This PowerShell script connects to an Azure Storage Account, retrieves NSG flow log blobs,
    parses their contents, and summarizes the traffic data based on action type (Allowed/Denied)
    and destination port. The script also exports detailed flow data to a CSV file.

.PARAMETER storageAccountName
    The name of the Azure Storage account containing the NSG flow logs.

.PARAMETER resourceGroupName
    The name of the Azure Resource Group where the storage account is located.

.PARAMETER containerName
    The name of the blob container holding the NSG flow logs.

.PARAMETER CSVExportPath
    The local file path where the parsed flow details will be exported as a CSV file.

.NOTES
    Author  : Marc Schramm
    Created : 22.05.2025
    Version : 1.0
    Requires: Az PowerShell Module (`Install-Module -Name Az -Scope CurrentUser`)

.EXAMPLE
    # Example usage
    Set variables in the script:
    $storageAccountName = "mystorageaccount"
    $resourceGroupName = "myresourcegroup"
    $containerName = "insights-logs-networksecuritygroupflowevent"
    $CSVExportPath = "C:\exports\nsg_flows.csv"

    Then run:
    .\Analyze-NSGFlowLogs.ps1

.LINK
    https://learn.microsoft.com/en-us/azure/network-watcher/network-watcher-nsg-flow-logging-overview
#>


# Connect to Azure
Connect-AzAccount

# Variables
$storageAccountName = ""  # Replace with your storage account name
$resourceGroupName = ""   # Replace with your resource group name
$containerName = ""       # Replace with your contianer name
$CSVExportPath = ""       # Replace with your path for csv export 

# Get storage context
try {
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName -ErrorAction Stop
    $context = $storageAccount.Context
} catch {
    Write-Error "Failed to access storage account: $_"
    exit
}

# Initialize arrays and hashtables
$flowDetails = @()
$actionCounts = @{}
$portActionCounts = @{}

# List all blobs for the NSG (no time prefix)
try {
    $blobs = Get-AzStorageBlob -Container $containerName -Context $context  -ErrorAction Stop
} catch {
    Write-Error "Failed to list blobs: $_"
    #exit
}

# Process each blob
foreach ($blob in $blobs) {
    try {
        # Download blob content
        $blobContent = Get-AzStorageBlobContent -Container $containerName -Blob $blob.Name -Context $context -Force -ErrorAction Stop
        $jsonData = Get-Content $blobContent.Name -Raw | ConvertFrom-Json -ErrorAction Stop

        # Parse records
        foreach ($record in $jsonData.records) {
            $time = $record.time
            foreach ($flow in $record.properties.flows) {
                $rule = $flow.rule
                foreach ($tuple in $flow.flows[0].flowTuples) {
                    $fields = $tuple -split ","
                    if ($fields.Count -lt 8) {
                        Write-Warning "Invalid flow tuple in blob $($blob.Name): $tuple"
                        continue
                    }
                    $sourceIp = $fields[1]
                    $destIp = $fields[2]
                    $destPort = $fields[4]
                    $action = $fields[7]  # A (Allowed) or D (Denied)
                    $actionLabel = if ($action -eq "A") { "Allowed" } else { "Denied" }

                    # Store flow details
                    $flowDetails += [PSCustomObject]@{
                        Time = $time
                        SourceIP = $sourceIp
                        DestinationIP = $destIp
                        DestinationPort = $destPort
                        Action = $actionLabel
                        Rule = $rule
                    }

                    # Count flows by action
                    if ($actionCounts.ContainsKey($actionLabel)) {
                        $actionCounts[$actionLabel] += 1
                    } else {
                        $actionCounts[$actionLabel] = 1
                    }

                    # Count flows by destination port and action
                    $portKey = "Port $destPort ($actionLabel)"
                    if ($portActionCounts.ContainsKey($portKey)) {
                        $portActionCounts[$portKey] += 1
                    } else {
                        $portActionCounts[$portKey] = 1
                    }
                }
            }
        }
    } catch {
        Write-Warning "Error processing blob $($blob.Name): $_"
    }
}

# Output summaries
Write-Host "Summary by Action:"
if ($actionCounts.Count -eq 0) {
    Write-Host "No flows found."
} else {
    $actionCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host "$($_.Name) : $($_.Value) flows"
    }
}

Write-Host "`nFlows by Destination Port and Action:"
if ($portActionCounts.Count -eq 0) {
    Write-Host "No flows found."
} else {
    $portActionCounts.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host "$($_.Name) : $($_.Value) flows"
    }
}

Write-Host "`nDetailed Flow Information:"
if ($flowDetails.Count -eq 0) {
    Write-Host "No flow details to display."
} else {
    $flowDetails | Format-Table -AutoSize
}

# Export to CSV
$flowDetails | Export-Csv -Path $CSVExportPath -NoTypeInformation
Write-Host "Exported flow details to $CSVExportPath"