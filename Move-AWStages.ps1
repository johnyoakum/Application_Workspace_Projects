# Check for powershell Module and install if necessary
if (-not (Get-Module -ListAvailable -Name Liquit.Server.PowerShell)) {
    Install-Module -Name Liquit.Server.PowerShell -Scope CurrentUser -Force
}

$LiquitURI = 'https://liquit.corp.viamonstra.com' # Replace this with your zone
$username = 'local\admin' # Replace this with a service account you have created for creating and accessing this information
$password = 'Isaiah@2014' # Enter the password for that service Account
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)
$daysBeforeAcceptance = 7
$daysBeforeProduction = 7
$PackageEvents = [System.Collections.ArrayList]::new()


Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials

$AllPackages = Get-LiquitPackage

ForEach ($Package in $AllPackages){
    $EventData = Get-LiquitAuditingEvent -Entity $Package | Where-Object {$_.Type -eq 'RestAction'}
    $TestPackageSnapshot = Get-LiquitPackageSnapshot -Package $Package -Type Test
    $AcceptancePackageSnapshot = Get-LiquitPackageSnapshot -Package $Package -Type Acceptance
    If ($TestPackageSnapshot) {
        $EventData = Get-LiquitAuditingEvent -Entity $Package | Where-Object {$_.Type -eq 'RestAction' -and $_.Details.data.stage -eq 'Test'} | Sort-Object -Property CreatedAt -Descending | Select-Object -First 1
        $EventDetails = New-Object PSObject -prop @{
            PackageID = $Package.ID
            PackageName = $Package.Name
            PackageVersion = $EventData.Details.data.name
            SnapshotID = $TestPackageSnapshot.ID.Guid
            DateOfStage = $EventData.CreatedAt
            SnapshotStage = 'Test'
        }
        [void]$PackageEvents.Add($EventDetails)
    }
    If ($AcceptancePackageSnapshot) {
        $EventData = Get-LiquitAuditingEvent -Entity $Package | Where-Object {$_.Type -eq 'RestAction' -and $_.Details.data.stage -eq 'Acceptance'} | Sort-Object -Property CreatedAt -Descending | Select-Object -First 1
        $EventDetails = New-Object PSObject -prop @{
            PackageID = $Package.ID
            PackageName = $Package.Name
            PackageVersion = $EventData.Details.data.name
            SnapshotID = $AcceptancePackageSnapshot.ID.Guid
            DateOfStage = $EventData.CreatedAt
            SnapshotStage = 'Acceptance'
        }
        [void]$PackageEvents.Add($EventDetails)
    }
}

$Debug = $true
# Now that I have the data, let's move it
If (!$Debug) {
    ForEach ($Event in $PackageEvents) {
        If ($Event.SnapshotStage -eq 'Test') {
            $CurrentPackage = Get-LiquitPackage -ID $Event.PackageID
            $CurrentSnapshot = Get-LiquitPackageSnapshot -ID $Event.SnapshotID -Package $CurrentPackage
            If ($Event.DateOfStage -ne $null) {
                $dateToCheck = Get-Date $($Event.DateOfStage)
            }
            $sevenDaysAgo = (Get-Date).AddDays(-$daysBeforeAcceptance)
            If ($dateToCheck -lt $sevenDaysAgo -or $Event.DateOfStage -eq $null) {
                Publish-LiquitPackageSnapshot -Snapshot $CurrentSnapshot -Stage Acceptance -Name $Event.PackageVersion -Description $Event.PackageName
            }
        }
        If ($Event.SnapshotStage -eq 'Acceptance') {
            $CurrentPackage = Get-LiquitPackage -ID $Event.PackageID
            $CurrentSnapshot = Get-LiquitPackageSnapshot -ID $Event.SnapshotID -Package $CurrentPackage
            If ($Event.DateOfStage -ne $null) {
                $dateToCheck = Get-Date $($Event.DateOfStage)
            }
            $sevenDaysAgo = (Get-Date).AddDays(-$daysBeforeProduction)
            If ($dateToCheck -lt $sevenDaysAgo -or $Event.DateOfStage -eq $null) {
                Publish-LiquitPackageSnapshot -Snapshot $CurrentSnapshot -Stage Acceptance -Name $Event.PackageVersion -Description $Event.PackageName
            }
        }

    }
}

