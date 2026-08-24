<#
.SYNOPSIS
    Grants admin (tenant-wide) consent for the API permissions configured on one
    or more Entra ID (Azure AD) app registrations.

.DESCRIPTION
    For each target app registration the script reads the permissions it requests
    (RequiredResourceAccess on the application object) and creates the matching
    consent objects on the app's service principal:

      * Delegated permissions (Scope)  -> OAuth2PermissionGrant (consentType AllPrincipals)
      * Application permissions (Role)  -> AppRoleAssignment

    This is exactly what the "Grant admin consent for <tenant>" button does in the
    Entra portal, but scripted for many apps at once.

    The script is idempotent: it skips grants/assignments that already exist.

.NOTES
    Requires the Microsoft.Graph PowerShell SDK:
        Install-Module Microsoft.Graph -Scope CurrentUser

    You must sign in as a Privileged Role Administrator or Global Administrator.

.EXAMPLE
    .\Grant-AdminConsent.ps1 -AppIds "1111-...","2222-..."

.EXAMPLE
    .\Grant-AdminConsent.ps1 -DisplayNames "My API Client","Reporting App" -WhatIf

.EXAMPLE
    Get-Content .\apps.txt | .\Grant-AdminConsent.ps1
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    # One or more Application (client) IDs of the app registrations.
    [Parameter(ParameterSetName = 'ByAppId', ValueFromPipeline = $true)]
    [string[]] $AppIds,

    # One or more display names of the app registrations.
    [Parameter(ParameterSetName = 'ByName')]
    [string[]] $DisplayNames,

    # Tenant to connect to (domain or tenant GUID). Optional.
    [string] $TenantId
)

begin {
    $ErrorActionPreference = 'Stop'

    # --- Ensure the required Graph modules are available -------------------
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Applications'
    )
    foreach ($m in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            throw "Module '$m' is not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser"
        }
        Import-Module $m -ErrorAction Stop
    }

    # --- Connect ----------------------------------------------------------
    $scopes = @(
        'Application.Read.All',
        'AppRoleAssignment.ReadWrite.All',
        'DelegatedPermissionGrant.ReadWrite.All'
    )
    $connectParams = @{ Scopes = $scopes }
    if ($TenantId) { $connectParams['TenantId'] = $TenantId }

    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph @connectParams | Out-Null
    $ctx = Get-MgContext
    Write-Host "Connected to tenant $($ctx.TenantId) as $($ctx.Account)" -ForegroundColor Green

    # Cache of resource service principals (the APIs being consented to),
    # keyed by their AppId, so we don't look them up repeatedly.
    $script:resourceSpCache = @{}

    function Get-ResourceServicePrincipal {
        param([string] $ResourceAppId)
        if (-not $script:resourceSpCache.ContainsKey($ResourceAppId)) {
            $sp = Get-MgServicePrincipal -Filter "appId eq '$ResourceAppId'" -ErrorAction SilentlyContinue
            $script:resourceSpCache[$ResourceAppId] = $sp
        }
        return $script:resourceSpCache[$ResourceAppId]
    }

    $collected = New-Object System.Collections.Generic.List[string]
}

process {
    # Collect pipeline / parameter input; actual work happens in end{}.
    if ($AppIds)      { $AppIds      | ForEach-Object { $collected.Add($_) } }
    if ($DisplayNames){ $DisplayNames| ForEach-Object { $collected.Add("name:$_") } }
}

end {
    if ($collected.Count -eq 0) {
        throw "No app registrations were supplied. Use -AppIds or -DisplayNames."
    }

    foreach ($item in $collected) {

        # --- Resolve the app registration -> service principal ------------
        try {
            if ($item.StartsWith('name:')) {
                $name = $item.Substring(5)
                $app  = Get-MgApplication -Filter "displayName eq '$name'" -All
                if (-not $app) { Write-Warning "No app registration found with display name '$name'."; continue }
                if ($app.Count -gt 1) { Write-Warning "Multiple app registrations named '$name'. Skipping — use -AppIds instead."; continue }
            }
            else {
                $app = Get-MgApplication -Filter "appId eq '$item'" -All
                if (-not $app) { Write-Warning "No app registration found with AppId '$item'."; continue }
            }
        }
        catch {
            Write-Warning "Failed to look up '$item': $($_.Exception.Message)"; continue
        }

        Write-Host "`n=== $($app.DisplayName) ($($app.AppId)) ===" -ForegroundColor Yellow

        # The client's own service principal (enterprise app). Create it if missing.
        $clientSp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
        if (-not $clientSp) {
            if ($PSCmdlet.ShouldProcess($app.DisplayName, "Create service principal (enterprise app)")) {
                $clientSp = New-MgServicePrincipal -AppId $app.AppId
                Write-Host "  Created service principal for the client app." -ForegroundColor DarkGray
            }
            else { continue }
        }

        if (-not $app.RequiredResourceAccess) {
            Write-Host "  No API permissions configured — nothing to consent." -ForegroundColor DarkGray
            continue
        }

        foreach ($rra in $app.RequiredResourceAccess) {

            $resourceSp = Get-ResourceServicePrincipal -ResourceAppId $rra.ResourceAppId
            if (-not $resourceSp) {
                Write-Warning "  Resource API '$($rra.ResourceAppId)' has no service principal in this tenant. Skipping."
                continue
            }

            # Split the requested permissions into delegated (Scope) and app (Role).
            $delegated = $rra.ResourceAccess | Where-Object { $_.Type -eq 'Scope' }
            $appRoles  = $rra.ResourceAccess | Where-Object { $_.Type -eq 'Role' }

            # --- Delegated permissions -> single OAuth2PermissionGrant ----
            if ($delegated) {
                $scopeNames = foreach ($d in $delegated) {
                    ($resourceSp.Oauth2PermissionScopes | Where-Object Id -eq $d.Id).Value
                }
                $scopeNames = $scopeNames | Where-Object { $_ } | Sort-Object -Unique

                if ($scopeNames) {
                    # Is there already an admin (AllPrincipals) grant for this client+resource?
                    $existingGrant = Get-MgOauth2PermissionGrant -All |
                        Where-Object { $_.ClientId -eq $clientSp.Id -and
                                       $_.ResourceId -eq $resourceSp.Id -and
                                       $_.ConsentType -eq 'AllPrincipals' }

                    if ($existingGrant) {
                        $current = @($existingGrant.Scope -split ' ' | Where-Object { $_ })
                        $merged  = ($current + $scopeNames | Sort-Object -Unique) -join ' '
                        if ($merged.Trim() -ne ($existingGrant.Scope ?? '').Trim()) {
                            if ($PSCmdlet.ShouldProcess("$($resourceSp.DisplayName): $merged", "Update delegated consent")) {
                                Update-MgOauth2PermissionGrant -OAuth2PermissionGrantId $existingGrant.Id -Scope $merged | Out-Null
                                Write-Host "  [Delegated] Updated scopes on $($resourceSp.DisplayName): $merged" -ForegroundColor Green
                            }
                        }
                        else {
                            Write-Host "  [Delegated] Already consented on $($resourceSp.DisplayName): $($existingGrant.Scope)" -ForegroundColor DarkGray
                        }
                    }
                    else {
                        $scopeString = ($scopeNames -join ' ')
                        if ($PSCmdlet.ShouldProcess("$($resourceSp.DisplayName): $scopeString", "Grant delegated admin consent")) {
                            New-MgOauth2PermissionGrant -BodyParameter @{
                                clientId    = $clientSp.Id
                                consentType = 'AllPrincipals'
                                resourceId  = $resourceSp.Id
                                scope       = $scopeString
                            } | Out-Null
                            Write-Host "  [Delegated] Granted on $($resourceSp.DisplayName): $scopeString" -ForegroundColor Green
                        }
                    }
                }
            }

            # --- Application permissions -> one AppRoleAssignment each -----
            if ($appRoles) {
                $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $clientSp.Id -All

                foreach ($r in $appRoles) {
                    $role = $resourceSp.AppRoles | Where-Object Id -eq $r.Id
                    $roleName = if ($role) { $role.Value } else { $r.Id }

                    $already = $existingAssignments | Where-Object {
                        $_.ResourceId -eq $resourceSp.Id -and $_.AppRoleId -eq $r.Id
                    }
                    if ($already) {
                        Write-Host "  [Application] Already assigned on $($resourceSp.DisplayName): $roleName" -ForegroundColor DarkGray
                        continue
                    }

                    if ($PSCmdlet.ShouldProcess("$($resourceSp.DisplayName): $roleName", "Assign application permission")) {
                        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $clientSp.Id -BodyParameter @{
                            principalId = $clientSp.Id
                            resourceId  = $resourceSp.Id
                            appRoleId   = $r.Id
                        } | Out-Null
                        Write-Host "  [Application] Assigned on $($resourceSp.DisplayName): $roleName" -ForegroundColor Green
                    }
                }
            }
        }
    }

    Write-Host "`nDone." -ForegroundColor Cyan
    Disconnect-MgGraph | Out-Null
}
