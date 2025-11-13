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
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("demo_dev", "demo_test", "demo_int", "demo_prod")]
    [string]$Prefix,

    [switch]$ListOnly,
    [switch]$SyncOwners
)

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

# ---------------------------------
# Connect to Microsoft Graph
# ---------------------------------
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Application.ReadWrite.All","Directory.ReadWrite.All" | Out-Null

# ---------------------------------
# Helper Functions
# ---------------------------------
function Get-AppOwners {
    param($AppId)
    try {
        $owners = Get-MgApplicationOwner -ApplicationId $AppId -ErrorAction Stop
        $resolved = @()

        foreach ($owner in $owners) {
            # Try to resolve to user if possible
            $user = Get-MgUser -UserId $owner.Id -ErrorAction SilentlyContinue
            if ($user) {
                $resolved += [PSCustomObject]@{
                    Id  = $owner.Id
                    UPN = $user.UserPrincipalName
                    Type = "User"
                }
            } else {
                $resolved += [PSCustomObject]@{
                    Id  = $owner.Id
                    UPN = $null
                    Type = "NonUserOwner"
                }
            }
        }

        return $resolved
    } catch {
        Write-Warning "Failed to get owners for AppReg $AppId $_"
        return @()
    }
}

function Get-ServicePrincipalOwners {
    param($SPId)
    try {
        $owners = Get-MgServicePrincipalOwner -ServicePrincipalId $SPId -ErrorAction Stop
        $resolved = @()

        foreach ($owner in $owners) {
            # Try to resolve to user if possible
            $user = Get-MgUser -UserId $owner.Id -ErrorAction SilentlyContinue
            if ($user) {
                $resolved += [PSCustomObject]@{
                    Id  = $owner.Id
                    UPN = $user.UserPrincipalName
                    Type = "User"
                }
            } else {
                $resolved += [PSCustomObject]@{
                    Id  = $owner.Id
                    UPN = $null
                    Type = "NonUserOwner"
                }
            }
        }

        return $resolved
    } catch {
        Write-Warning "Failed to get owners for Enterprise App $SPId $_"
        return @()
    }
}

# ---------------------------------
# Fetch target Apps
# ---------------------------------
Write-Host "Fetching applications with prefix '$Prefix'..." -ForegroundColor Cyan
$Apps = Get-MgApplication -All | Where-Object { $_.DisplayName -like "$Prefix*" }
$SPs  = Get-MgServicePrincipal -All | Where-Object { $_.DisplayName -like "$Prefix*" }

Write-Host "Found $($Apps.Count) App Registrations and $($SPs.Count) Enterprise Apps." -ForegroundColor Yellow

# ---------------------------------
# List Mode
# ---------------------------------
if ($ListOnly) {
    
    $appResults = @()

    foreach ($app in $Apps) {
        $owners = Get-AppOwners -AppId $app.Id
        if ($owners.Count -eq 0) {
            $appResults += [PSCustomObject]@{
                Type         = "AppRegistration"
                DisplayName  = $app.DisplayName
                OwnerUPN     = "(no owners)"
            }
        }
        else {
            foreach ($owner in $owners) {
                $appResults += [PSCustomObject]@{
                    Type         = "AppRegistration"
                    DisplayName  = $app.DisplayName
                    OwnerUPN     = if ($owner.UPN) { $owner.UPN } else { "(non-user owner)" }
                }
            }
        }
    }

    
    $spResults = @()

    foreach ($sp in $SPs) {
        $owners = Get-ServicePrincipalOwners -SPId $sp.Id
        if ($owners.Count -eq 0) {
            $spResults += [PSCustomObject]@{
                Type         = "EnterpriseApp"
                DisplayName  = $sp.DisplayName
                OwnerUPN     = "(no owners)"
            }
        }
        else {
            foreach ($owner in $owners) {
                $spResults += [PSCustomObject]@{
                    Type         = "EnterpriseApp"
                    DisplayName  = $sp.DisplayName
                    OwnerUPN     = if ($owner.UPN) { $owner.UPN } else { "(non-user owner)" }
                }
            }
        }
    }

    # Combine and show formatted as table
    $allResults = $appResults + $spResults
    if ($allResults.Count -gt 0) {
        $allResults | Sort-Object Type, DisplayName | Format-Table -AutoSize
    }
    else {
        Write-Host "No applications found for prefix '$Prefix'." -ForegroundColor Yellow
    }

    #Disconnect-MgGraph
    #exit
}

# ---------------------------------
# Sync Mode
# ---------------------------------
if ($SyncOwners) {
    foreach ($app in $Apps) {
        Write-Host "`nProcessing App Registration: $($app.DisplayName)" -ForegroundColor Cyan
        $currentOwners = Get-AppOwners -AppId $app.Id | Select-Object -ExpandProperty UPN

        # Add missing owners
        $ownersToAdd = $TargetOwners | Where-Object { $_ -notin $currentOwners }
        foreach ($user in $ownersToAdd) {
            $ownerObj = Get-MgUser -Filter "userPrincipalName eq '$user'"
            if ($ownerObj) {
                New-MgApplicationOwnerByRef -ApplicationId $app.Id -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($ownerObj.Id)" }
                Write-Host "Added owner: $user"
            }
        }

        # Remove extra owners
        $ownersToRemove = $currentOwners | Where-Object { $_ -notin $TargetOwners }
        foreach ($user in $ownersToRemove) {
            $ownerObj = Get-MgUser -Filter "userPrincipalName eq '$user'"
            if ($ownerObj) {
                Remove-MgApplicationOwnerByRef -ApplicationId $app.Id -DirectoryObjectId $ownerObj.Id -Confirm:$false
                Write-Host "Removed owner: $user"
            }
        }
    }

    foreach ($sp in $SPs) {
        Write-Host "`nProcessing Enterprise Application: $($sp.DisplayName)" -ForegroundColor Cyan
        $currentOwners = Get-ServicePrincipalOwners -SPId $sp.Id | Select-Object -ExpandProperty UPN

        # Add missing owners
        $ownersToAdd = $TargetOwners | Where-Object { $_ -notin $currentOwners }
        foreach ($user in $ownersToAdd) {
            $ownerObj = Get-MgUser -Filter "userPrincipalName eq '$user'"
            if ($ownerObj) {
                New-MgServicePrincipalOwnerByRef -ServicePrincipalId $sp.Id -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($ownerObj.Id)" }
                Write-Host "Added owner: $user"
            }
        }

        # Remove extra owners
        $ownersToRemove = $currentOwners | Where-Object { $_ -notin $TargetOwners }
        foreach ($user in $ownersToRemove) {
            $ownerObj = Get-MgUser -Filter "userPrincipalName eq '$user'"
            if ($ownerObj) {
                Remove-MgServicePrincipalOwnerByRef -ServicePrincipalId $sp.Id -DirectoryObjectId $ownerObj.Id -Confirm:$false
                Write-Host "Removed owner: $user"
            }
        }
    }

    Write-Host "`nOwnership synchronization complete for $Prefix." -ForegroundColor Green
    #Disconnect-MgGraph
}
