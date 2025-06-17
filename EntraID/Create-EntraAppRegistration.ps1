<#
.SYNOPSIS
Erstellt mehrere Entra ID App-Registrierungen inkl. zugehöriger Service Principals und weist Owner zu.

.DESCRIPTION
Dieses Skript verbindet sich mit Microsoft Graph, erstellt App-Registrierungen für eine definierte Liste von Anwendungsnamen, 
setzt die `requestedAccessTokenVersion` auf 2, erstellt entsprechende Service Principals und fügt definierte Benutzer 
(über ihre UPNs) als Owner zur jeweiligen App-Registrierung hinzu. Es eignet sich zur Automatisierung von Bereitstellungen 
innerhalb eines Entra ID Tenants.

.PARAMETER ArrApps
Eine Liste von App-Namen, für die App-Registrierungen und Service Principals erstellt werden sollen.

.PARAMETER OwnerUPNs
Eine Liste von Benutzer-UPNs, die als Owner zu jeder App-Registrierung hinzugefügt werden sollen.

.REQUIREMENTS
- Microsoft Graph PowerShell SDK (`Microsoft.Graph`)
- Berechtigungen:
  - Application.ReadWrite.All
  - Directory.ReadWrite.All
- PowerShell 7 oder höher empfohlen

.EXAMPLE
# Beispielhafte Konfiguration und Ausführung
$ArrApps = @("App1", "App2")
$OwnerUPNs = @("admin1@contoso.com", "admin2@contoso.com")
.\Create-EntraIDApps.ps1

.NOTES
Autor: Marc Schramm
Version: 1.3  
Letzte Änderung: 17.06.2025
#>

# PowerShell-Skript zum Erstellen einer Entra ID App-Registrierung, Service Principal und Hinzufügen von Ownern

# Liste der App-Namen
$ArrApps = @(
    "APP1",
    "APP2",
    "APP3"
)

# Liste der UPNs der Owner
$OwnerUPNs = @(
    "user1@contoso.com",
    "user2@contoso.com",
    "user3@contoso.com"
)

# Verbindung zu Microsoft Graph herstellen
Write-Host "Verbinde mit Microsoft Graph..."
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All" -ErrorAction Stop

foreach ($AppName in $ArrApps) {
    try {
        # App-Registrierung erstellen
        Write-Host "Erstelle App-Registrierung '$AppName'..."
        $app = New-MgApplication -DisplayName $AppName -SignInAudience "AzureADMyOrg" -ErrorAction Stop
        Write-Host "App-Registrierung erstellt. AppId: $($app.AppId)"

        # Update App-Registrierung
        # Setze die Requested Access Token Version auf 2
        $params = @{
            api = @{
                requestedAccessTokenVersion = 2
            }
        }
        Update-MgApplication -ApplicationId $($app.AppId) -BodyParameter $params
        Write-Output "RequestedAccessTokenVersion auf 2 gesetzt für $AppName"

        # Service Principal (Enterprise Application) erstellen
        Write-Host "Erstelle Service Principal für '$AppName'..."
        $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
        Write-Host "Service Principal erstellt. Objekt-ID: $($sp.Id)"

        # Owner hinzufügen
        Write-Host "Füge Owner hinzu..."
        foreach ($upn in $OwnerUPNs) {
            try {
                # Benutzer anhand der UPN suchen
                $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
                if ($user) {
                    # Owner der App-Registrierung hinzufügen
                    New-MgApplicationOwnerByRef -ApplicationId $app.Id -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)" -ErrorAction Stop
                    Write-Host "Owner $upn erfolgreich hinzugefügt."
                } else {
                    Write-Warning "Benutzer mit UPN $upn wurde nicht gefunden."
                }
            } catch {
                Write-Warning "Fehler beim Hinzufügen von Owner $upn $_"
            }
        }

        Write-Host "App-Registrierung '$AppName' wurde erfolgreich erstellt und konfiguriert."
    }
    catch {
        Write-Error "Fehler beim Erstellen der App-Registrierung oder Hinzufügen der Owner: $_"
    }
}

# Verbindung trennen
Disconnect-MgGraph -ErrorAction SilentlyContinue
Write-Host "Verbindung zu Microsoft Graph getrennt."
