<#
    .SYNOPSIS
    Creates a package that could take over and perform initial updates of applications on machines

    .DESCRIPTION
    This script will create a package that will perform an install of all packages if they already have the application from the package installed. It
    uses the launch action of the package to determine if the application is already installed on your machine and then will perform an install of
    the package to mark it as installed for purposes of taking over existing applications on machines. This will be for managed packages only at this time.
    I added a parameter that adds in unmanaged apps, although the default is to only do manaaged packages. 

    This will then (if you want) also create AW User Collections based on the Display Name of the package and then add each user that has been taken over
    into that User Collection so that you can use that collection as an Entitlement for the Application package.

    If you'd like, you can also have it automatically create the entitlement to the new package during the running of this script, as well as include desktop
    and/or start menu native icons.

    You will need to change out the variable values in lines 58 through 61.

    Once this script completes, it will only create the custom package. It leaves the package in the Development Stage. You will need to go back into it and
    verify it looks the way that you would like as well as clean up anything that you may not want in there. You can then Entitle it and move it to production when ready.

    .EXAMPLE
    .\Create-TakeOverPackage.ps1

    .\Create-TakeOverPackage.ps1 -AddUnmanaged

    .\Create-TakeOverPackage.ps1 -CreateCollections

    .\Create-TakeOverPackage.ps1 -CreateCollections -CreateEntitlements -CreateDesktopIcons -CreateStartMenuIcons

    .NOTES
    Version:        1.0
    Author:         John Yoakum, Recast Software
    Creation Date:  05/05/2025
    Purpose/Change: Initial script development

#>
param (
    [switch]$AddUnmanged = $false,
    [switch]$CreateCollections = $false,
    [switch]$CreateEntitlements = $false,
    [switch]$CreateDesktopIcons = $false,
    [switch]$CreateStartMenuIcons = $false
)

# Parameter validation logic
if ($CreateEntitlements -and -not $CreateCollections) {
    Throw "The -CreateCollections parameter must be specified if -CreateEntitlements is specified."
}

if ($CreateDesktopIcons -or $CreateStartMenuIcons) {
    if (-not $CreateEntitlements) {
        Throw "The -CreateEntitlements parameter must be specified if either -CreateDesktopIcons or -CreateStartMenuIcons is specified."
    }
}

#region Variables
$LiquitURL = 'https://zone.liquit.com'
$Username = 'LOCAL\Admin'
$Password = 'PASSWORD'
$TakeOverPackageName = 'Take Over Applications'

#endregion



$TakeOverCommands = [System.Collections.ArrayList]::new()
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)

Connect-LiquitWorkspace -URI 'https://john.liquit.com' -Credential $credentials

# Create my listing of all my packages with my new detection
$AllPackages = Get-LiquitPackage #-Name "win - 1Password 8"
ForEach ($Package in $AllPackages) {
    $Attribute = Get-LiquitAttribute -Entity $Package
    If ($Attribute) {$Managed = $true} else {$Managed = $false}
    $Snapshot = Get-LiquitPackageSnapshot -Package $Package | Where-Object {$_.Type -eq 'Production'}
    If ($Snapshot) {
        $Actionset = Get-LiquitActionSet -Snapshot $Snapshot | Where-Object {$_.Type -eq 'Launch'} | Select-Object -First 1
        If ($Actionset) {
            $Actions = Get-LiquitAction -ActionSet $Actionset | Where-Object {$_.Type -eq 'processstart'}
            If ($Actions) {
                $NewPackage = New-Object PSObject -Property @{
                    PackageID = $Package.ID
                    PackageName = $Package.Name
                    DisplayName = If ($Package.DisplayName) {$Package.DisplayName} else {$Package.Name}
                    PathToFile = $Actions.Settings.directory
                    FileName = $Actions.Settings.name
                    Managed = $Managed
                }
                [void]$TakeOverCommands.Add($NewPackage)
            }
        }
    }
}

# Create the Take Over package and add each package from above into this

    # Create the new package
    $AWPackage = New-LiquitPackage -Name "TO - $TakeOverPackageName" -Type "Custom" -DisplayName "$TakeOverPackageName" -Priority 100 -Enabled $true -Web $false
    $AWSnapshot = New-LiquitPackageSnapshot -Package $AWPackage -Name "Take Over"
    $ActionSet = New-LiquitActionSet -Snapshot $AWSnapshot -Type Install -Name "Take Over Install" -Enabled $true -Frequency OncePerDevice -Process Sequential

    ForEach ($Command in $TakeOverCommands) {
        # Create an action for each package
        If ($Command.Managed -eq $false -and $AddUnmanged){
            # Copy again once completed... Forgot to add in the step to add to collection
        }
        If ($Command.Managed -eq $true) {
            $CurrentPackage = Get-LiquitPackage -ID $Command.PackageID
            $Action = New-LiquitAction -ActionSet $Actionset -Name "Take Over $($Command.DisplayName)" -Type "installpackage" -Enabled $true -Settings @{title = "$($Command.DisplayName)"; value = $CurrentPackage.ID; }
            $Attribute = New-LiquitAttribute -Entity $Action -Link $CurrentPackage -ID 'package'
            $FilterSet = New-LiquitFilterSet -Action $Action
            $Filter = New-Liquitfilter -FilterSet $FilterSet -Type fileexists -Settings @{path = "'$($Command.FileName)'";} -Value "true"
            If ($CreateDesktopIcons -or $CreateStartMenuIcons) {
                $Icons = New-Object Liquit.API.Server.V3.PackageEntitlementIcons
                If ($CreateDesktopIcons) {
                    $Icons.Desktop = $true
                }
                If ($CreateStartMenuIcons) {
                    $Icons.StartMenu = $true
                }
            }
            $CollectionExists = Get-LiquitUserCollection -Name "$($Command.DisplayName)"
            If ($CreateCollections -and !$CollectionExists) {
                $NewCollection = New-LiquitUserCollection -Name "$($Command.DisplayName)" | Out-Null
            }
            $CollectionToBeUsed = If ($CollectionExists) {$CollectionExists} else {Get-LiquitUserCollection -Name "$($Command.DisplayName)"}
            If ($CreateEntitlements) {
                $Identity = Get-LiquitIdentity -Name "$($CollectionToBeUsed.Name)"
                If ($Icons) {
                    $Entitlement = New-LiquitPackageEntitlement -Package $CurrentPackage -Publish Workspace -Stage Production -Identity $Identity -Icons $Icons
                } else {
                    $Entitlement = New-LiquitPackageEntitlement -Package $CurrentPackage -Publish Workspace -Stage Production -Identity $Identity
                }
                $Settings = @{
                    add = $true
                    title = "$($Command.DisplayName)"
                    group = $Identity.ID
                }
                $AddUserAction = New-LiquitAction -ActionSet $Actionset -Type "identitymember" -Name "Move User to $($Command.DisplayName)" -Settings $Settings -Context Server
                $UserFilterSet = New-LiquitFilterSet -Action $AddUserAction
                $UserFilter = New-LiquitFilter -FilterSet $UserFilterSet -Type "packageinstalled" -Settings @{title = $($CurrentPackage.Name); value = $($CurrentPackage.ID);} -Value "0"
                $UserFilterAttribute = New-LiquitAttribute -Entity $UserFilter -Id "package" -Link $CurrentPackage
            }
        }
    }
