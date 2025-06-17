<#
.SYNOPSIS
Löscht alle unterstützten Authentifizierungsmethoden eines Benutzers in Entra ID mittels Microsoft Graph API.

.DESCRIPTION
Dieses Skript ruft alle Authentifizierungsmethoden eines Benutzers ab und entfernt sie — mit Ausnahme der Passwortmethode, 
die derzeit nicht über die Graph API löschbar ist. Standardmethoden werden zuletzt entfernt, da diese nur gelöscht werden 
können, wenn sie die letzte verbleibende Methode sind. Das Skript nutzt Microsoft Graph PowerShell Cmdlets zur gezielten 
Löschung jeder Methode anhand ihres Typs.

.PARAMETER userId
Der Benutzer-Principal-Name (UPN) oder die Objekt-ID des Benutzers, dessen Authentifizierungsmethoden entfernt werden sollen.

.REQUIREMENTS
- Microsoft Graph PowerShell SDK (`Microsoft.Graph.AuthenticationMethods`)
- Berechtigungen:
  - `UserAuthenticationMethod.ReadWrite.All`
- PowerShell 7 oder höher empfohlen

.EXAMPLE
# Entfernt alle Authentifizierungsmethoden (außer Passwort) von max@mustermann.org
$userId = 'max@mustermann.org'
.\Remove-UserAuthMethods.ps1

.NOTES
Autor: Marc Schramm  
Version: 1.0  
Letzte Änderung: 17.06.2025
#>


$userId = 'max@mustermann.org'
function DeleteAuthMethod($uid, $method){
    switch ($method.AdditionalProperties['@odata.type']) {
        '#microsoft.graph.fido2AuthenticationMethod' { 
            Write-Host 'Removing fido2AuthenticationMethod'
            Remove-MgUserAuthenticationFido2Method -UserId $uid -Fido2AuthenticationMethodId $method.Id
        }
        '#microsoft.graph.emailAuthenticationMethod' { 
            Write-Host 'Removing emailAuthenticationMethod'
            Remove-MgUserAuthenticationEmailMethod -UserId $uid -EmailAuthenticationMethodId $method.Id
        }
        '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' { 
            Write-Host 'Removing microsoftAuthenticatorAuthenticationMethod'
            Remove-MgUserAuthenticationMicrosoftAuthenticatorMethod -UserId $uid -MicrosoftAuthenticatorAuthenticationMethodId $method.Id
        }
        '#microsoft.graph.phoneAuthenticationMethod' { 
            Write-Host 'Removing phoneAuthenticationMethod'
            Remove-MgUserAuthenticationPhoneMethod -UserId $uid -PhoneAuthenticationMethodId $method.Id
        }
        '#microsoft.graph.softwareOathAuthenticationMethod' { 
            Write-Host 'Removing softwareOathAuthenticationMethod'
            Remove-MgUserAuthenticationSoftwareOathMethod -UserId $uid -SoftwareOathAuthenticationMethodId $method.Id
        }
        '#microsoft.graph.temporaryAccessPassAuthenticationMethod' { 
            Write-Host 'Removing temporaryAccessPassAuthenticationMethod'
            Remove-MgUserAuthenticationTemporaryAccessPassMethod -UserId $uid -TemporaryAccessPassAuthenticationMethodId $method.Id
        }
        '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' { 
            Write-Host 'Removing windowsHelloForBusinessAuthenticationMethod'
            Remove-MgUserAuthenticationWindowsHelloForBusinessMethod -UserId $uid -WindowsHelloForBusinessAuthenticationMethodId $method.Id
        }
        '#microsoft.graph.passwordAuthenticationMethod' { 
            # Password cannot be removed currently
        }        
        Default {
            Write-Host 'This script does not handle removing this auth method type: ' + $method.AdditionalProperties['@odata.type']
        }
    }
    return $? # Return true if no error and false if there is an error
}

$methods = Get-MgUserAuthenticationMethod -UserId $userId
# -1 to account for passwordAuthenticationMethod
Write-Host "Found $($methods.Length - 1) auth method(s) for $userId"

$defaultMethod = $null
foreach ($authMethod in $methods) {
    $deleted = DeleteAuthMethod -uid $userId -method $authMethod
    if(!$deleted){
        # We need to use the error to identify and delete the default method.
        $defaultMethod = $authMethod
    }
}

# Graph API does not support reading default method of a user.
# Plus default method can only be deleted when it is the only (last) auth method for a user.
# We need to use the error to identify and delete the default method.
if($null -ne $defaultMethod){
    Write-Host "Removing default auth method"
    $result = DeleteAuthMethod -uid $userId -method $defaultMethod
}

Write-Host "Re-checking auth methods..."
$methods = Get-MgUserAuthenticationMethod -UserId $userId
# -1 to account for passwordAuthenticationMethod
Write-Host "Found $($methods.Length - 1) auth method(s) for $userId"
