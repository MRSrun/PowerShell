<#
.SYNOPSIS
Synchronisiert die Mitgliedschaften von JIT-Gruppen in EntraID basierend auf einer CSV-Datei.

.DESCRIPTION
Dieses Skript verbindet sich mit Microsoft Graph, liest eine CSV-Datei ein, die Benutzer (UPNs) 
und deren zugehörige Just-In-Time-Gruppen (JIT-Groups) enthält, und stellt sicher, dass jede Gruppe
die im CSV definierten Mitglieder hat. Optional kann das Skript Benutzer entfernen, die nicht in der 
CSV aufgeführt sind, um die Mitgliedschaften strikt zu erzwingen. Unterstützt einen `-WhatIf`-Modus 
zur Vorschau der Änderungen, ohne die Gruppen zu verändern.

.PARAMETER CsvPath
Pfad zur CSV-Datei mit den Spalten `Jit-Group` und `UPN`. Standard: `C:\Temp\jit_group_assignments.csv`.

.PARAMETER EnforceCsvMembership
Wenn gesetzt, entfernt das Skript Benutzer aus Gruppen, die nicht in der CSV-Datei aufgeführt sind.

.PARAMETER WhatIf
Führt das Skript im Modus „Nur Vorschau“ aus. Zeigt an, welche Änderungen vorgenommen würden, ohne sie tatsächlich durchzuführen.

.REQUIREMENTS
- Microsoft Graph PowerShell SDK (Modul: Microsoft.Graph)
- Berechtigungen: Group.ReadWrite.All, User.Read.All
- CSV-Datei mit gültigen Gruppennamen und Benutzer-Principal-Namen (UPN)

.EXAMPLE
# Vorschau der Änderungen, ohne die Gruppen zu ändern
.\Sync-JitGroupMembership.ps1 -CsvPath "C:\Temp\jit_group_assignments.csv" -WhatIf

# Synchronisieren der Gruppen und Entfernen von Benutzern, die nicht in der CSV stehen
.\Sync-JitGroupMembership.ps1 -CsvPath "C:\Temp\jit_group_assignments.csv" -EnforceCsvMembership

.NOTES
Autor: Marc Schramm
Version: 1.0
Letzte Änderung: 16.09.2025
#>


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
