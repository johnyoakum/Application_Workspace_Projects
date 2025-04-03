Import-Module Liquit.Server.PowerShell
$LiquitURI = 'https://zone.liquit.com' # Replace this with your zone
$username = 'local\admin' # Replace this with a service account you have created for creating and accessing this information
$password = 'PASSWORD' # Enter the password for that service Account
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)
$UpdatePackageNames = 'Update Audacity'

Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials

ForEach ($UpdatePackageName in $UpdatePackageNames) {
    $UpdatePackage = Get-LiquitPackage -Name "$UpdatePackageName"
    $CurrentEntitlement = Get-LiquitPackageEntitlement -Package $UpdatePackage | Where-Object {$_.ID -eq 'LOCAL\everyone'}
    $PackageEntitlementEvent = New-Object Liquit.API.Server.V3.PackageEntitlementEvent
    $PackageEntitlementEvent.Type = "Refresh"
    $PackageEntitlementEvent.ActionSet = "Install"
    Set-LiquitPackageEntitlement -Events @($PackageEntitlementEvent) -Entitlement $CurrentEntitlement
}
