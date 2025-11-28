<#
.SYNOPSIS
    Manage ownership of Entra ID App Registrations and Enterprise Applications by prefix.

.DESCRIPTION
    This script can:
      1. Filter App Registrations & Enterprise Applications by prefix
      2. List current owners
      3. Compare with predefined owner lists per environment
      4. Add missing owners and remove unauthorized ones

.REQUIREMENTS
    - Microsoft Graph PowerShell SDK (Install-Module Microsoft.Graph -Scope CurrentUser)
    - Scopes: Application.ReadWrite.All, Directory.ReadWrite.All

.EXAMPLES
    # Just list owners for demo_dev apps
    .\Manage-EntraAppOwners.ps1 -Prefix "demo_dev" -ListOnly

    # Sync owners (add missing, remove extra)
    .\Manage-EntraAppOwners.ps1 -Prefix "demo_prod" -SyncOwners

    # Preview changes without applying them
    .\Manage-EntraAppOwners.ps1 -Prefix "demo_prod" -SyncOwners -WhatIf

.NOTES
    Autor: Marc Schramm
    Version: 2.0  
    Letzte Änderung: 28.11.2025
    Optimizations: Performance improvements, error handling, progress indicators

#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Environment prefix to filter applications")]
    [ValidateSet("demo_dev", "demo_test", "demo_int", "demo_prod")]
    [string]$Prefix,

    [Parameter(ParameterSetName = "List")]
    [switch]$ListOnly,
    
    [Parameter(ParameterSetName = "Sync")]
    [switch]$SyncOwners
)

# ---------------------------------
# Validate Parameters
# ---------------------------------
if (-not $ListOnly -and -not $SyncOwners) {
    throw @"
Must specify either -ListOnly or -SyncOwners.

Examples:
  .\Manage-EntraAppOwners.ps1 -Prefix demo_dev -ListOnly
  .\Manage-EntraAppOwners.ps1 -Prefix demo_prod -SyncOwners
  .\Manage-EntraAppOwners.ps1 -Prefix demo_prod -SyncOwners -WhatIf
"@
}

# ---------------------------------
# Configuration: Owner lists
# ---------------------------------
$OwnerLists = @{
    "demo_dev" = @(
        "devuser1@contoso.com",
        "devuser2@contoso.com"
    )
    "demo_test" = @(
        "testuser1@contoso.com",
        "testuser2@contoso.com"
    )
    "demo_int" = @(
        "intuser1@contoso.com",
        "intuser2@contoso.com"
    )
    "demo_prod" = @(
        "produser1@contoso.com",
        "produser2@contoso.com"
    )
}

$TargetOwners = $OwnerLists[$Prefix]

# Initialize logging
$LogFile = "EntraAppOwners_$($Prefix)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ---------------------------------
# Logging Function
# ---------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "$timestamp [$Level] $Message"
    
    # Write to file
    $logMessage | Out-File -FilePath $LogFile -Append -Encoding UTF8
    
    # Write to console with color
    $color = switch ($Level) {
        "Info"    { "Cyan" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
        "Success" { "Green" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

# ---------------------------------
# Connect to Microsoft Graph
# ---------------------------------
Write-Log "Connecting to Microsoft Graph..." -Level Info
try {
    Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All" -ErrorAction Stop | Out-Null
    Write-Log "Successfully connected to Microsoft Graph" -Level Success
}
catch {
    Write-Log "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -Level Error
    throw
}

# ---------------------------------
# Helper Functions
# ---------------------------------
function Resolve-Owners {
    <#
    .SYNOPSIS
        Resolves directory object owners to user objects with UPN
    #>
    param(
        [Parameter(Mandatory = $true)]
        [Array]$Owners
    )
    
    $resolved = @()
    
    foreach ($owner in $Owners) {
        try {
            $user = Get-MgUser -UserId $owner.Id -ErrorAction SilentlyContinue
            
            $resolved += [PSCustomObject]@{
                Id   = $owner.Id
                UPN  = if ($user) { $user.UserPrincipalName } else { $null }
                Type = if ($user) { "User" } else { "NonUserOwner" }
            }
        }
        catch {
            Write-Log "Failed to resolve owner $($owner.Id): $($_.Exception.Message)" -Level Warning
            $resolved += [PSCustomObject]@{
                Id   = $owner.Id
                UPN  = $null
                Type = "Error"
            }
        }
    }
    
    return $resolved
}

function Get-AppOwners {
    <#
    .SYNOPSIS
        Get and resolve owners for an App Registration
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId
    )
    
    try {
        $owners = Get-MgApplicationOwner -ApplicationId $AppId -ErrorAction Stop
        return Resolve-Owners -Owners $owners
    }
    catch {
        Write-Log "Failed to get owners for AppReg $AppId : $($_.Exception.Message)" -Level Warning
        return @()
    }
}

function Get-ServicePrincipalOwners {
    <#
    .SYNOPSIS
        Get and resolve owners for an Enterprise Application
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SPId
    )
    
    try {
        $owners = Get-MgServicePrincipalOwner -ServicePrincipalId $SPId -ErrorAction Stop
        return Resolve-Owners -Owners $owners
    }
    catch {
        Write-Log "Failed to get owners for Enterprise App $SPId : $($_.Exception.Message)" -Level Warning
        return @()
    }
}

# ---------------------------------
# Cache Target Users
# ---------------------------------
if ($SyncOwners) {
    Write-Log "Caching target users for $Prefix environment..." -Level Info
    $TargetUserCache = @{}
    
    foreach ($upn in $TargetOwners) {
        try {
            $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
            if ($user) {
                $TargetUserCache[$upn] = $user
                Write-Log "  ✓ Cached user: $upn" -Level Info
            }
            else {
                Write-Log "  ✗ User not found: $upn" -Level Warning
            }
        }
        catch {
            Write-Log "  ✗ Failed to resolve user $upn : $($_.Exception.Message)" -Level Warning
        }
    }
    
    if ($TargetUserCache.Count -eq 0) {
        Write-Log "No valid target users found. Cannot proceed with sync." -Level Error
        Disconnect-MgGraph
        throw "No valid target users found in configuration"
    }
    
    Write-Log "Cached $($TargetUserCache.Count) of $($TargetOwners.Count) target users" -Level Success
}

# ---------------------------------
# Fetch Target Apps (Server-side filtering)
# ---------------------------------
Write-Log "Fetching applications with prefix '$Prefix'..." -Level Info

try {
    $Apps = Get-MgApplication -Filter "startsWith(displayName, '$Prefix')" -All -ErrorAction Stop
    $SPs = Get-MgServicePrincipal -Filter "startsWith(displayName, '$Prefix')" -All -ErrorAction Stop
    
    Write-Log "Found $($Apps.Count) App Registrations and $($SPs.Count) Enterprise Apps" -Level Success
}
catch {
    Write-Log "Failed to fetch applications: $($_.Exception.Message)" -Level Error
    Disconnect-MgGraph
    throw
}

if ($Apps.Count -eq 0 -and $SPs.Count -eq 0) {
    Write-Log "No applications found with prefix '$Prefix'" -Level Warning
    Disconnect-MgGraph
    exit 0
}

# ---------------------------------
# List Mode
# ---------------------------------
if ($ListOnly) {
    Write-Log "=== LIST MODE ===" -Level Info
    
    $appResults = @()
    $totalItems = $Apps.Count + $SPs.Count
    $currentItem = 0

    # Process App Registrations
    foreach ($app in $Apps) {
        $currentItem++
        Write-Progress -Activity "Listing Owners" -Status "Processing App Registrations ($currentItem of $totalItems)" -PercentComplete (($currentItem / $totalItems) * 100)
        
        $owners = Get-AppOwners -AppId $app.Id
        
        if ($owners.Count -eq 0) {
            $appResults += [PSCustomObject]@{
                Type        = "AppRegistration"
                DisplayName = $app.DisplayName
                OwnerUPN    = "(no owners)"
                OwnerType   = "N/A"
            }
        }
        else {
            foreach ($owner in $owners) {
                $appResults += [PSCustomObject]@{
                    Type        = "AppRegistration"
                    DisplayName = $app.DisplayName
                    OwnerUPN    = if ($owner.UPN) { $owner.UPN } else { "(non-user owner)" }
                    OwnerType   = $owner.Type
                }
            }
        }
    }

    # Process Enterprise Applications
    foreach ($sp in $SPs) {
        $currentItem++
        Write-Progress -Activity "Listing Owners" -Status "Processing Enterprise Apps ($currentItem of $totalItems)" -PercentComplete (($currentItem / $totalItems) * 100)
        
        $owners = Get-ServicePrincipalOwners -SPId $sp.Id
        
        if ($owners.Count -eq 0) {
            $appResults += [PSCustomObject]@{
                Type        = "EnterpriseApp"
                DisplayName = $sp.DisplayName
                OwnerUPN    = "(no owners)"
                OwnerType   = "N/A"
            }
        }
        else {
            foreach ($owner in $owners) {
                $appResults += [PSCustomObject]@{
                    Type        = "EnterpriseApp"
                    DisplayName = $sp.DisplayName
                    OwnerUPN    = if ($owner.UPN) { $owner.UPN } else { "(non-user owner)" }
                    OwnerType   = $owner.Type
                }
            }
        }
    }

    Write-Progress -Activity "Listing Owners" -Completed

    # Display results
    if ($appResults.Count -gt 0) {
        Write-Host "`n=== OWNER REPORT ===" -ForegroundColor Cyan
        $appResults | Sort-Object Type, DisplayName | Format-Table -AutoSize
        
        # Export to CSV
        $csvPath = "EntraAppOwners_$($Prefix)_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $appResults | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Log "Report exported to: $csvPath" -Level Success
    }
    else {
        Write-Log "No applications found for prefix '$Prefix'" -Level Warning
    }
}

# ---------------------------------
# Sync Mode
# ---------------------------------
if ($SyncOwners) {
    Write-Log "=== SYNC MODE ===" -Level Info
    Write-Log "Target owners for $Prefix : $($TargetOwners -join ', ')" -Level Info
    
    $changesSummary = @{
        AppsProcessed = 0
        OwnersAdded = 0
        OwnersRemoved = 0
        Errors = 0
    }
    
    # Process App Registrations
    $totalApps = $Apps.Count
    $currentApp = 0
    
    foreach ($app in $Apps) {
        $currentApp++
        $changesSummary.AppsProcessed++
        
        Write-Progress `
            -Activity "Syncing App Registrations" `
            -Status "Processing $currentApp of $totalApps: $($app.DisplayName)" `
            -PercentComplete (($currentApp / $totalApps) * 100)
        
        Write-Log "`n[$currentApp/$totalApps] Processing App Registration: $($app.DisplayName)" -Level Info
        
        $currentOwners = (Get-AppOwners -AppId $app.Id | Where-Object { $_.UPN }) | Select-Object -ExpandProperty UPN
        
        # Calculate differences
        $ownersToAdd = $TargetOwners | Where-Object { $_ -notin $currentOwners }
        $ownersToRemove = $currentOwners | Where-Object { $_ -notin $TargetOwners }
        
        Write-Log "  Current owners: $($currentOwners.Count), To add: $($ownersToAdd.Count), To remove: $($ownersToRemove.Count)" -Level Info
        
        # Add missing owners
        foreach ($userUpn in $ownersToAdd) {
            $ownerObj = $TargetUserCache[$userUpn]
            
            if (-not $ownerObj) {
                Write-Log "  ✗ Skipping $userUpn - not in cache" -Level Warning
                continue
            }
            
            if ($PSCmdlet.ShouldProcess($app.DisplayName, "Add owner $userUpn")) {
                try {
                    New-MgApplicationOwnerByRef `
                        -ApplicationId $app.Id `
                        -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($ownerObj.Id)" } `
                        -ErrorAction Stop
                    
                    Write-Log "  ✓ Added owner: $userUpn" -Level Success
                    $changesSummary.OwnersAdded++
                }
                catch {
                    Write-Log "  ✗ Failed to add $userUpn : $($_.Exception.Message)" -Level Error
                    $changesSummary.Errors++
                }
            }
        }
        
        # Remove extra owners
        foreach ($userUpn in $ownersToRemove) {
            if ([string]::IsNullOrEmpty($userUpn)) {
                continue
            }
            
            try {
                $ownerToRemove = Get-MgUser -Filter "userPrincipalName eq '$userUpn'" -ErrorAction Stop
                
                if (-not $ownerToRemove) {
                    Write-Log "  ✗ Cannot remove $userUpn - user not found" -Level Warning
                    continue
                }
                
                if ($PSCmdlet.ShouldProcess($app.DisplayName, "Remove owner $userUpn")) {
                    Remove-MgApplicationOwnerByRef `
                        -ApplicationId $app.Id `
                        -DirectoryObjectId $ownerToRemove.Id `
                        -ErrorAction Stop
                    
                    Write-Log "  ✓ Removed owner: $userUpn" -Level Success
                    $changesSummary.OwnersRemoved++
                }
            }
            catch {
                Write-Log "  ✗ Failed to remove $userUpn : $($_.Exception.Message)" -Level Error
                $changesSummary.Errors++
            }
        }
    }
    
    Write-Progress -Activity "Syncing App Registrations" -Completed
    
    # Process Enterprise Applications
    $totalSPs = $SPs.Count
    $currentSP = 0
    
    foreach ($sp in $SPs) {
        $currentSP++
        $changesSummary.AppsProcessed++
        
        Write-Progress `
            -Activity "Syncing Enterprise Applications" `
            -Status "Processing $currentSP of $totalSPs $($sp.DisplayName)" `
            -PercentComplete (($currentSP / $totalSPs) * 100)
        
        Write-Log "`n[$currentSP/$totalSPs] Processing Enterprise Application: $($sp.DisplayName)" -Level Info
        
        $currentOwners = (Get-ServicePrincipalOwners -SPId $sp.Id | Where-Object { $_.UPN }) | Select-Object -ExpandProperty UPN
        
        # Calculate differences
        $ownersToAdd = $TargetOwners | Where-Object { $_ -notin $currentOwners }
        $ownersToRemove = $currentOwners | Where-Object { $_ -notin $TargetOwners }
        
        Write-Log "  Current owners: $($currentOwners.Count), To add: $($ownersToAdd.Count), To remove: $($ownersToRemove.Count)" -Level Info
        
        # Add missing owners
        foreach ($userUpn in $ownersToAdd) {
            $ownerObj = $TargetUserCache[$userUpn]
            
            if (-not $ownerObj) {
                Write-Log "  ✗ Skipping $userUpn - not in cache" -Level Warning
                continue
            }
            
            if ($PSCmdlet.ShouldProcess($sp.DisplayName, "Add owner $userUpn")) {
                try {
                    New-MgServicePrincipalOwnerByRef `
                        -ServicePrincipalId $sp.Id `
                        -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($ownerObj.Id)" } `
                        -ErrorAction Stop
                    
                    Write-Log "  ✓ Added owner: $userUpn" -Level Success
                    $changesSummary.OwnersAdded++
                }
                catch {
                    Write-Log "  ✗ Failed to add $userUpn : $($_.Exception.Message)" -Level Error
                    $changesSummary.Errors++
                }
            }
        }
        
        # Remove extra owners
        foreach ($userUpn in $ownersToRemove) {
            if ([string]::IsNullOrEmpty($userUpn)) {
                continue
            }
            
            try {
                $ownerToRemove = Get-MgUser -Filter "userPrincipalName eq '$userUpn'" -ErrorAction Stop
                
                if (-not $ownerToRemove) {
                    Write-Log "  ✗ Cannot remove $userUpn - user not found" -Level Warning
                    continue
                }
                
                if ($PSCmdlet.ShouldProcess($sp.DisplayName, "Remove owner $userUpn")) {
                    Remove-MgServicePrincipalOwnerByRef `
                        -ServicePrincipalId $sp.Id `
                        -DirectoryObjectId $ownerToRemove.Id `
                        -ErrorAction Stop
                    
                    Write-Log "  ✓ Removed owner: $userUpn" -Level Success
                    $changesSummary.OwnersRemoved++
                }
            }
            catch {
                Write-Log "  ✗ Failed to remove $userUpn : $($_.Exception.Message)" -Level Error
                $changesSummary.Errors++
            }
        }
    }
    
    Write-Progress -Activity "Syncing Enterprise Applications" -Completed
    
    # Summary
    Write-Host "`n=== SYNC SUMMARY ===" -ForegroundColor Cyan
    Write-Log "Applications processed: $($changesSummary.AppsProcessed)" -Level Info
    Write-Log "Owners added: $($changesSummary.OwnersAdded)" -Level Success
    Write-Log "Owners removed: $($changesSummary.OwnersRemoved)" -Level Success
    Write-Log "Errors encountered: $($changesSummary.Errors)" -Level $(if ($changesSummary.Errors -gt 0) { "Warning" } else { "Info" })
    Write-Log "Ownership synchronization complete for $Prefix" -Level Success
}

# ---------------------------------
# Cleanup
# ---------------------------------
Disconnect-MgGraph
Write-Log "Disconnected from Microsoft Graph" -Level Info
Write-Log "Log file saved to: $LogFile" -Level Info
