param (
    [string]$CsvPath = "C:\Temp\jit_group_assignments.csv",
    [switch]$EnforceCsvMembership,
    [switch]$WhatIf
)

# Requires Microsoft.Graph PowerShell SDK
# Install if not already: Install-Module Microsoft.Graph -Scope CurrentUser

# Connect to Microsoft Graph (requires appropriate permissions)
Connect-MgGraph -Scopes "Group.ReadWrite.All","User.Read.All"

# Import the CSV (semicolon separated, normalize headers with or without colon)
$csvRaw = Import-Csv -Path $CsvPath -Delimiter ";"

$csv = foreach ($row in $csvRaw) {
    $group = if ($row.'Jit-Group:') { $row.'Jit-Group:' } else { $row.'Jit-Group' }
    $upn   = if ($row.'UPN:') { $row.'UPN:' } else { $row.'UPN' }

    [PSCustomObject]@{
        'Jit-Group' = $group
        'UPN'       = $upn
    }
}

# Build a mapping: group -> list of users (UPNs) from CSV
$csvGroups = $csv | Group-Object -Property 'Jit-Group'

foreach ($groupEntry in $csvGroups) {
    $groupName = $groupEntry.Name
    $desiredUsersUpn = $groupEntry.Group.'UPN'

    Write-Host "`n🔍 Processing group: $groupName"

    # Get the group object
    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -All | Select-Object -First 1
    if (-not $group) {
        Write-Warning "Group '$groupName' not found. Skipping..."
        continue
    }

    # Resolve desired users
    $desiredUsers = @()
    foreach ($upn in $desiredUsersUpn) {
        try {
            $user = Get-MgUser -UserId $upn
            if ($user) {
                $desiredUsers += $user
            } else {
                Write-Warning "User '$upn' not found. Skipping..."
            }
        } catch {
            Write-Warning "Failed to resolve user $upn $($_.Exception.Message)"
        }
    }

    # Get current members of the group
    $currentMembers = Get-MgGroupMember -GroupId $group.Id -All
    $currentMemberIds = $currentMembers.Id
    $desiredUserIds   = $desiredUsers.Id

    # --- ADD missing users ---
    $toAdd = $desiredUsers | Where-Object { $_.Id -notin $currentMemberIds }
    foreach ($user in $toAdd) {
        if ($WhatIf) {
            Write-Host "🔎 [WhatIf] Would add $($user.UserPrincipalName) to $groupName"
        } else {
            try {
                New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
                Write-Host "✅ Added $($user.UserPrincipalName) to $groupName"
            } catch {
                Write-Warning "❌ Failed to add $($user.UserPrincipalName): $($_.Exception.Message)"
            }
        }
    }

    # --- REMOVE extra users (only if -EnforceCsvMembership is set) ---
    if ($EnforceCsvMembership) {
        $toRemove = $currentMembers | Where-Object {
            $_.AdditionalProperties.userPrincipalName -notin $desiredUsersUpn
        }
        foreach ($user in $toRemove) {
            if ($WhatIf) {
                Write-Host "🔎 [WhatIf] Would remove $($user.AdditionalProperties.userPrincipalName) from $groupName"
            } else {
                try {
                    Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id
                    Write-Host "🗑️ Removed $($user.AdditionalProperties.userPrincipalName) from $groupName"
                } catch {
                    Write-Warning "❌ Failed to remove $($user.AdditionalProperties.userPrincipalName): $($_.Exception.Message)"
                }
            }
        }
    }
    else {
        Write-Host "ℹ️ Safe mode: no removals performed in $groupName"
    }
}

Disconnect-MgGraph
