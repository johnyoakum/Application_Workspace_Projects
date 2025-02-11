# Check for powershell Module and install if necessary
if (-not (Get-Module -ListAvailable -Name Liquit.Server.PowerShell)) {
    Install-Module -Name Liquit.Server.PowerShell -Scope CurrentUser -Force
}

$LiquitURI = 'https://john.liquit.com' # Replace this with your zone
$username = 'local\apiaccess' # Replace this with a service account you have created for creating and accessing this information
$password = 'IsaiahMaddux@2014' # Enter the password for that service Account
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)
$daysBeforeAcceptance = 7
$daysBeforeProduction = 7

Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials

$Packages = Get-LiquitPackage

ForEach ($Package in $Packages) {
    $PackageSnapshots = Get-LiquitPackageSnapshot -Package $Package
    ForEach ($PackageSnapshot in $PackageSnapshots) {
        If ($PackageSnapshot.Type -eq "Test") {
            $dateToCheck = Get-Date $($PackageSnapshot.ModifiedAt)
            $sevenDaysAgo = (Get-Date).AddDays(-$daysBeforeAcceptance)
            if ($dateToCheck -lt $sevenDaysAgo) {
                Publish-LiquitPackageSnapshot -Snapshot $PackageSnapshot -Stage Acceptance -Name $PackageSnapshot.Name -Description $PackageSnapshot.Description
            }
        }
        If ($PackageSnapshot.Type -eq "Acceptance") {
            $dateToCheck = Get-Date $($PackageSnapshot.ModifiedAt)
            $sevenDaysAgo = (Get-Date).AddDays(-$daysBeforeProduction)
            if ($dateToCheck -lt $sevenDaysAgo) {
                Publish-LiquitPackageSnapshot -Snapshot $PackageSnapshot -Stage Production -Name $PackageSnapshot.Name -Description $PackageSnapshot.Description
            }
        }
    }
}
