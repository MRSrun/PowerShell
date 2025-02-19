<#
.SYNOPSIS
    Dieses Skript fügt einen definierten Tag zu allen App-Registrierungen und Service Principals hinzu, deren Name mit einem bestimmten Präfix beginnt.

.DESCRIPTION
    Das Skript verwendet das Microsoft Graph PowerShell-Modul, um App-Registrierungen und Service Principals in Azure AD zu durchsuchen und zu aktualisieren.
    Es verbindet sich mit Microsoft Graph, sucht nach Objekten, deren Name mit einem angegebenen Präfix beginnt, und fügt diesen Objekten einen definierten Tag hinzu.

.PARAMETER Tag
    Der Tag, der zu den gefundenen App-Registrierungen und Service Principals hinzugefügt werden soll.

.PARAMETER AppSpnPrefix
    Das Präfix, mit dem die Namen der zu suchenden App-Registrierungen und Service Principals beginnen.

.NOTES
    Autor: Marc Schramm
    Datum: 19. Februar 2025
    Version: 1.0

.EXAMPLE
    .\Add-TagToAzureADObjects.ps1 -Tag "TAG_NAME" -AppSpnPrefix "APP_Name_Starts_With"
#>

param (
    [string]$Tag = 'TAG_NAME',
    [string]$AppSpnPrefix = 'APP_Name_Starts_With'
)

# Install Microsoft Graph module if not installed
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Connect to Microsoft Graph with required permissions
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All"

# Define the Tag to be added to App Registrations and Service Principals
$Tagname = 'TAG_NAME'

# Define the App Registration name prefix
$APP_SPN = 'APP_Name_Starts_With'

# Get all App Registrations starting with "APP_Name_Starts_With'"
$apps = Get-MgApplication -Filter "startswith(displayName,'$APP_SPN')" -All

if ($apps.Count -gt 0) {
    foreach ($app in $apps) {
        try {
            Update-MgApplication -ApplicationId $app.Id -Tags $Tagname
            Write-Output "✅ Tags added to App Registration: $($app.DisplayName)"
        } catch {
            Write-Output "❌ Failed to update App Registration: $($app.DisplayName). Error: $_"
        }
    }
} else {
    Write-Output "⚠️ No App Registrations found starting with '$APP_SPN'"
}

# Get all Service Principals starting with "APP_Name_Starts_With'"
$servicePrincipals = Get-MgServicePrincipal -Filter "startswith(displayName,'$APP_SPN')" -All

if ($servicePrincipals.Count -gt 0) {
    foreach ($sp in $servicePrincipals) {
        try {
            Update-MgServicePrincipal -ServicePrincipalId $sp.Id -Tags $Tagname
            Write-Output "✅ Tags added to Service Principal: $($sp.DisplayName)"
        } catch {
            Write-Output "❌ Failed to update Service Principal: $($sp.DisplayName). Error: $_"
        }
    }
} else {
    Write-Output "⚠️ No Service Principals found starting with '$APP_SPN'"
}

# Disconnect from Microsoft Graph
Disconnect-MgGraph
