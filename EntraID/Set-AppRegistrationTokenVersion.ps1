<#
.SYNOPSIS
Aktualisiert die `requestedAccessTokenVersion` einer Azure App-Registrierung via Microsoft Graph API.

.DESCRIPTION
Dieses Skript verbindet sich mit Microsoft Graph, sucht eine App-Registrierung anhand ihres Anzeigenamens
und setzt deren `requestedAccessTokenVersion` auf Version 2. Dies ist nützlich, um sicherzustellen, dass
die App Zugriffstoken im v2-Format verwendet.

.PARAMETER appName
Der Anzeigename der Azure AD App-Registrierung, die aktualisiert werden soll.

.REQUIREMENTS
- Microsoft Graph PowerShell SDK (Modul: Microsoft.Graph)
- Berechtigung: Application.ReadWrite.All
- Bekannter und eindeutiger Anzeigename der App-Registrierung

.EXAMPLE
# Beispiel: Aktualisierung für eine App mit dem Namen "ContosoApp"
$appName = "ContosoApp"
# (führe dann das Skript aus)

.NOTES
Autor: Marc Schramm
Version: 1.0
Letzte Änderung: 17.06.2025
#>

# Verbindung zu Microsoft Graph aufbauen
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# App-Registrierung definieren
$appName = "YourAppName"

# App anhand des Anzeigenamens abrufen
$app = Get-MgApplication -Filter "displayName eq '$appName'"
$objectId = $app.Id

# requestedAccessTokenVersion auf 2 setzen
$params = @{
    api = @{
        requestedAccessTokenVersion = 2
    }
}
Update-MgApplication -ApplicationId $objectId -BodyParameter $params

# Erfolgsmeldung ausgeben
Write-Output "RequestedAccessTokenVersion set to 2 for $appName"

# Verbindung trennen
Disconnect-MgGraph
