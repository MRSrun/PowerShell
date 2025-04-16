# PowerShell-Skript zum Erstellen einer Entra ID App-Registrierung und Hinzufügen von Ownern

# Parameter für die App-Registrierung
#$AppName = "APP1" # Name der App-Registrierung
$ArrApps = @(
    "APP1",
    "APP2",
    "APP3"
)
$OwnerUPNs = @(
    "user1@contoso.com",
    "user2@contoso.come",
    "user3@contoso.com"
) # Liste der UPNs der Owner

# Verbindung zu Microsoft Graph herstellen
Write-Host "Verbinde mit Microsoft Graph..."
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.ReadWrite.All" -ErrorAction Stop

foreach ($AppName in $ArrApps)
{
    

    try {
        # Erstellen der App-Registrierung
        Write-Host "Erstelle App-Registrierung '$AppName'..."
        $app = New-MgApplication -DisplayName $AppName -SignInAudience "AzureADMyOrg" -ErrorAction Stop
    
        Write-Host "App-Registrierung erstellt. AppId: $($app.AppId)"
    
        # Owner hinzufügen
        Write-Host "Füge Owner hinzu..."
        foreach ($upn in $OwnerUPNs) {
            # Benutzer anhand der UPN suchen
            $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction Stop
            if ($user) {
                # Owner der App-Registrierung hinzufügen
                New-MgApplicationOwnerByRef -ApplicationId $app.Id -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)" -ErrorAction Stop
                Write-Host "Owner $upn erfolgreich hinzugefügt."
            } else {
                Write-Warning "Benutzer mit UPN $upn wurde nicht gefunden."
            }
        }
    
        Write-Host "App-Registrierung '$AppName' wurde erfolgreich erstellt und konfiguriert."
    }
    catch {
        Write-Error "Fehler beim Erstellen der App-Registrierung oder Hinzufügen der Owner: $_"
    }
    finally {
        # Verbindung trennen
        Write-Host "App-Registrierung '$AppName' wurde erfolgreich erstellt und konfiguriert."
    }

}
Disconnect-MgGraph -ErrorAction SilentlyContinue
Write-Host "Verbindung zu Microsoft Graph getrennt."
