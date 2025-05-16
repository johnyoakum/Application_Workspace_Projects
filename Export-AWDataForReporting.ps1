# Variables
$Aw = @{		# Application Workspace PowerShell module location
	ReportOutput 	= "$($env:USERPROFILE)\Documents" 																# HTML report output location
	TenantURL 		= 'https://john.liquit.com'															# Application Workspace tenant URL
	Username 		= 'LOCAL\admin'																				# Local admin username (serviceaccount)
	Password 		= 'IsaiahMaddux@2014'																							# Local admin password
}
#endregion Functions


# Connect to ApplicationWorkspace tenant
try {
	$AwPassword		= ConvertTo-SecureString $Aw.Password -AsPlainText -Force
	$AwCredential 	= New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Aw.Username, $AwPassword
	$AwContext 		= Connect-LiquitWorkspace -URI $Aw.TenantURL -Credential $AwCredential

	Write-Host "Successfully connected to ApplicationWorkspace tenant: $($Aw.TenantURL)"
} catch {
	throw "Failed to connect to ApplicationWorkspace tenant. Error: $($_)"
}

#region Retrieve ApplicationWorkspace data
# License information
try {
	Write-Host "Retrieving license information"
    $AwZone = Get-LiquitZone
    $AwZoneLicense = $AwZone.License | ForEach-Object {
        [PSCustomObject]@{
            Name       = $_.Name
            Type       = $_.Type
            Expires    = (Get-Date $_.Expires).ToString('dd-MM-yyyy')
            Billable   = $_.BillableCount
            Licensed   = $_.PurchasedCount
        }
    }
	Write-Host "Successfully retrieved license information"
} catch {	
	Write-Warning "Failed to retrieve license information. Error: $($_)"
}

# Packages
try {
	Write-Host "Retrieving packages"
	$AwPackages = Get-LiquitPackage
	Write-Host "Successfully retrieved $(($AwPackages | Measure-Object).Count) packages"
} catch {
	Write-Warning "Failed to retrieve packages. Error: $($_)"
}

# Users
try {
	Write-Host "Retrieving users"
	$AwUsers = Get-LiquitUser
	Write-Host "Successfully retrieved $(($AwUsers | Measure-Object).Count) users"
} catch { 
	Write-Warning "Failed to retrieve users. Error: $($_)"
}

# Devices
try {
	Write-Host "Retrieving devices"
	$AwDevices = Get-LiquitDevice | ForEach-Object {
		[pscustomobject]@{
			Name 					= $_.Name
			AgentVersion 			= $_.Agent.Version
			LastContact 			= $_.Agent.LastContact
			Manufacturer 			= $_.Hardware.Manufacturer
			Model 					= $_.Hardware.Model
			NetworkFQDN				= $_.Network.FQDN
			NetworkIP				= $_.Network.IP
			NetworkSubnet 			= $_.Network.Subnet
			NetworkMAC				= $_.Network.MAC
			PlatformID				= $_.Platform.ID
			PlatformType			= $_.Platform.Type
			PlatformLanguage 		= $_.Platform.Language
			PlatformVersion  		= $_.Platform.Version
			PlatformArchitecture 	= $_.Platform.Architecture
			LastLoggedOn			= $_.LastLoggedOn.Name
		}
	}
	Write-Host "Successfully retrieved $(($AwDevices | Measure-Object).Count) devices"
} catch { 
	Write-Warning "Failed to retrieve devices. Error: $($_)"
}

# Package entitlements
try {
	Write-Host "Retrieving package entitlements"
	$AwPackageEntitlements = @()
	$AwPackages | ForEach-Object {
		Get-LiquitPackageEntitlement $_ | Foreach-Object {
			$AwPackageEntitlements += [PSCustomObject]@{
				Publish 		= $_.Publish
				Stage 			= $_.Stage
				IdentityId 		= $_.Id
				IdentityName 	= $_.Identity.DisplayName
				IdentityType 	= $_.Identity.Type
				Id 				= $_.Id
			}
		}
	}
	Write-Host "Successfully retrieved $(($AwPackageEntitlements | Measure-Object).Count) package entitlements"
} catch {
	Write-Warning "Failed to retrieve package entitlements. Error: $($_)"
}

# Package events
try {
	Write-Host "Retrieving events"
	$AwPackageEvents = @()
	$AwPackages | ForEach-Object {
		Get-LiquitEvent -Entity $_ | Foreach-Object {
			$AwPackageEvents += [PSCustomObject]@{
				Type 		= $_.Type
				Status 		= $_.Status
				CreatedAt 	= $_.CreatedAt
				Identity 	= $_.Identity.Name
				Source 		= $_.Source.Name
				Target 		= $_.Target.Name
				Id 			= $_.Id
			}
		}
	}
	Write-Host "Successfully retrieved $(($AwPackageEvents | Measure-Object).Count) package events"
} catch {
	Write-Warning "Failed to retrieve events. Error: $($_)"
}

# Auditing events
try {
	Write-Host "Retrieving auditing events"
	$AwPackageAuditing = @()
	$AwPackages | ForEach-Object {
		Get-LiquitAuditingEvent -Entity $_ | Foreach-Object {
			$AwPackageAuditing += [PSCustomObject]@{
				Type 		= $_.Type
				Status 		= $_.Status
				CreatedAt 	= $_.CreatedAt
				Identity 	= $_.Identity.Name
				Source 		= $_.Source.Name
				Target 		= $_.Target.Name
				Action 		= $_.Details.actionName
				Id 			= $_.Id
			}
		}
	}
	Write-Host "Successfully retrieved $(($AwPackageAuditing | Measure-Object).Count) auditing events"
} catch {
	Write-Warning "Failed to retrieve auditing events. Error: $($_)"
}

#endregion Retrieve ApplicationWorkspace data

#region Generate report
Write-Host "Generating Application Workspace HTML report"

$AwPackages = $AwPackages | Select-Object -Property * -ExcludeProperty Icon

$ChartMostLaunchedPackages 		= $AwPackageEvents | Where-Object {$_.Type -eq 'LaunchPackage'} | Group-Object Target | Sort-Object Count | Select -last 10
$ChartFailedLaunchedPackages 	= $AwPackageEvents | Where-Object {$_.Type -eq 'LaunchPackage' -and $_.Status -eq 'Failed'} | Group-Object Target | Sort-Object Count | Select -last 10
$ChartAgentVersions				= $AwDevices | Group-Object AgentVersion | Sort-Object Count | Select -last 10
$ChartPlatformID				= $AwDevices | Group-Object PlatformID | Sort-Object Count | Select -last 10
$ChartPlatformVersion			= $AwDevices | Group-Object PlatformVersion | Sort-Object Count | Select -last 10
$ChartPlatformModel				= $AwDevices | Group-Object Model | Sort-Object Count | Select -last 10
$TableFailedLaunched 			= $AwPackageEvents | Where-Object {$_.Type -eq 'LaunchPackage' -and $_.Status -eq 'Failed'} | Group-Object Target | Sort-Object Count -Descending | Select-Object Count,Name
$TableFailedInstall 			= $AwPackageEvents | Where-Object {$_.Type -eq 'InstallPackage' -and $_.Status -eq 'Failed'} | Group-Object Target | Sort-Object Count -Descending | Select-Object Count,Name
$DateTime 						= [datetime]::Now.ToString('yyyyMMddHHmm')

$CSVMainInfo = @()
$CSVMainInfo = [PSCustomObject]@{
    ReportCreationDate = [datetime]::Now.ToString()
    AWTenant = $Aw.TenantURL
    License = $AwZoneLicense.Name
    LicenseType = $AwZoneLicense.Type
    ValidUntil = $AwZoneLicense.Expires
    BillableLicenses = $AwZoneLicense.Billable
    PaidLicenses = $AwZoneLicense.Licensed
}
$ExtraData1 = @()
ForEach ($Chart in $ChartMostLaunchedPackages) {
    ForEach ($Group in $Chart.Group) {
        $ExtraData1 += [PSCustomObject]@{
            Count = $Chart.Count
            Name = $Chart.Name
            Type = $Group.Type
            Status = $Group.CreatedAt
            Identity = $Group.Identity
            Source = $Group.Source
            Target = $Group.Target
            ID = $Group.Id
        }
    }
}
$ExtraData2 = @()
ForEach ($Chart in $ChartFailedLaunchedPackages) {
    ForEach ($Group in $Chart.Group) {
        $ExtraData2 += [PSCustomObject]@{
            Count = $Chart.Count
            Name = $Chart.Name
            Type = $Group.Type
            Status = $Group.CreatedAt
            Identity = $Group.Identity
            Source = $Group.Source
            Target = $Group.Target
            ID = $Group.Id
        }
    }
}
$ExtraData4 = @() #FailedInstall
ForEach ($Chart in $TableFailedInstall) {
    $ExtraData4 += [PSCustomObject]@{
        Count = $Chart.Count
        Name = $Chart.Name
    }
}

# Export data to csv files
$AwUsers | Export-Csv -Path C:\Users\Public\Documents\AWUsers.csv -Force -Encoding UTF8 -NoTypeInformation
$AwDevices | Export-Csv -Path C:\Users\Public\Documents\AwDevices.csv -Force -Encoding UTF8 -NoTypeInformation
$AwPackages | Export-Csv -Path C:\Users\Public\Documents\AwPackages.csv -Force -Encoding UTF8 -NoTypeInformation
$AwPackageEntitlements | Export-Csv -Path C:\Users\Public\Documents\AwPackageEntitlements.csv -Force -Encoding UTF8 -NoTypeInformation
$AwPackageEvents | Export-Csv -Path C:\Users\Public\Documents\AwPackageEvents.csv -Force -Encoding UTF8 -NoTypeInformation
$AwPackageAuditing | Export-Csv -Path C:\Users\Public\Documents\AwPackageAuditing.csv -Force -Encoding UTF8 -NoTypeInformation
$CSVMainInfo | Export-Csv -Path C:\Users\Public\Documents\AWInfo.csv -Force -Encoding UTF8 -NoTypeInformation
$ExtraData1 | Export-Csv -Path C:\Users\Public\Documents\MostLaunched.csv -Force -Encoding UTF8 -NoTypeInformation
$ExtraData2 | Export-Csv -Path C:\Users\Public\Documents\FailedLaunch.csv -Force -Encoding UTF8 -NoTypeInformation
$ExtraData4 | Export-Csv -Path C:\Users\Public\Documents\FailedInstall.csv -Force -Encoding UTF8 -NoTypeInformation
#endregion Generate report
