<#
.SYNOPSIS
    Script to automate creating packages in Application Workspace

.PRE-REQUISITES
    -Service Account (or user account) in Application Workspace to perform actions. This Service account needs the following permissions:
        1.	API Access
        3.	Create Packages
        4.	View Packages
        5.	Modify Packages
        7.	Upload Content (all)

.DESCRIPTION
    This script can perform dual functions, it can either read your currently installed software directly from your configMgr database
        or you can supply it a csv file formatted as "Publisher0, DisplayName0, Version0" with those being the header rows.
    It will then normalize the application names and search your Application Workspace for potential matches.
    It will then present you a GUI that you can then choose which applications you want to have it create for you.
    You will need to replace out the values listed below.
        CMSQLServer -  Fill in the SQL server for your ConfigMgr Environment
        CMDB - Fill in the database name for your ConfigMgr SQL environment
        LiquitConnectorPrefix - This is the prefix that you set up when you added in the connector to the Liquit Setup Store
        LiquitURI - This is the fqdn of your zone for Application Workspace
        Username - This is the username of the account that we would create to perform these functions
        Password - This is the password for the above user account


.EXAMPLE
    .\Create-AWAppsFromConfigMgrOrCSV.ps1 
    
    or 

    .\Create-AWAppsFromConfigMgrOrCSV.ps1 -CSV "PATH TO CSV"
#>
#﻿Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework

# Check for powershell Module and install if necessary
if (-not (Get-Module -ListAvailable -Name Liquit.Server.PowerShell)) {
    Install-Module -Name Liquit.Server.PowerShell -Scope CurrentUser -Force
}
if (-not (Get-Module -ListAvailable -Name Liquit.Server.PowerShell)) {
    Install-Module -Name SQLServer -Scope CurrentUser -Force
}

$CMPSSuppressFastNotUsedCheck = $true
$PublishingStage = 'Test' # Please enter the right location or leave blank for Development, these options can be 'Test, Acceptance, or Production'
$LiquitConnectorPrefix = "win - " # Replace this with the connector prefix for your environment
$LiquitURI = 'https://liquit.corp.viamonstra.com' # Replace this with your zone
$username = 'local\admin' # Replace this with a service account you have created for creating and accessing this information
$password = 'Isaiah@2014' # Enter the password for that service Account
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)
$SiteCode = "JY1" # Site code 
$SiteServer = "CM01.corp.viamonstra.com" # SMS Provider machine name
$AppDetails = [System.Collections.ArrayList]::new()

$ApplicationQuery = @"
WITH XMLNAMESPACES (
    DEFAULT 'http://schemas.microsoft.com/SystemsCenterConfigurationManager/2009/07/10/DesiredConfiguration',
    'http://schemas.microsoft.com/SystemsCenterConfigurationManager/2009/06/14/Rules' AS ns,
    'http://schemas.microsoft.com/SystemCenterConfigurationManager/2009/AppMgmtDigest' AS p1
)
SELECT DISTINCT
    app.DisplayName,
    app.Manufacturer,
    app.SoftwareVersion,
    --cfg.SDMPackageDigest, -- This was commented out in your original query
    
    -- Get the primary file name (if any .msi, .bat, .exe, or .cmd file exists)
    COALESCE(
        cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:Contents/p1:Content/p1:File[contains(@Name, ".msi")]/@Name)[1]', 'nvarchar(max)'),
        cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:Contents/p1:Content/p1:File[contains(@Name, ".bat")]/@Name)[1]', 'nvarchar(max)'),
        cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:Contents/p1:Content/p1:File[contains(@Name, ".cmd")]/@Name)[1]', 'nvarchar(max)'),
        cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:Contents/p1:Content/p1:File[contains(@Name, ".exe")]/@Name)[1]', 'nvarchar(max)')
    ) AS [PrimaryFilename],
    
    -- Extract the DeploymentType
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Technology)[1]', 'nvarchar(max)') AS [DeploymentType],
    
    -- Extract the DetectionMethod and EnhancedFolder/File (custom data)
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:DetectionMethod)[1]', 'nvarchar(max)') AS [DetectionMethod],
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:EnhancedDetectionMethod/p1:Settings/File/Path)[1]', 'nvarchar(max)') AS [EnhancedFolder],
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:EnhancedDetectionMethod/p1:Settings/File/Filter)[1]', 'nvarchar(max)') AS [EnhancedFile],
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:ProductCode)[1]', 'nvarchar(max)') AS [ProductCodeMSI],
	cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:ProductVersion)[1]', 'nvarchar(max)') AS [Version],
	cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:EnhancedDetectionMethod/p1:Settings/File/Path)[1]', 'nvarchar(max)') AS [FileDetectionPath],
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:EnhancedDetectionMethod/p1:Settings/File/Filter)[1]', 'nvarchar(max)') AS [FileDetectionFile],
	cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:EnhancedDetectionMethod/ns:Rule/ns:Expression/ns:Operator)[1]', 'nvarchar(max)') AS [FileDetectionOperator],
	cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:CustomData/p1:EnhancedDetectionMethod/ns:Rule/ns:Expression/ns:Operands/ns:ConstantValue/@Value)[1]', 'nvarchar(max)') AS [FileDetectionVersion],
	ico.Icon,
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:Contents/p1:Content/p1:Location)[1]', 'nvarchar(max)') AS [Location],
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:InstallAction/p1:Args/p1:Arg)[1]', 'nvarchar(max)') AS [InstallCommandLine],
    cfg.SDMPackageDigest.value('(/p1:AppMgmtDigest/p1:DeploymentType/p1:Installer/p1:UninstallAction/p1:Args/p1:Arg)[1]', 'nvarchar(MAX)') AS [UninstallCommandLine]
FROM v_Applications AS app
JOIN v_ApplicationModelInfo AS info ON app.ModelName = info.SecuredKey
JOIN v_ConfigurationItems AS cfg ON info.CI_ID = cfg.CI_ID
JOIN v_CIRelation as ci on cfg.CI_ID = ci.ToCIID
JOIN CI_LocalizedCIClientProperties as ico on ico.CI_ID = ci.FromCIID

"@

        $PackageQuery = @"
select 
	app.[PkgID]
	,app.[Name]
	,app.[Version]
	,app.[Manufacturer]
	,app.[Source]
	,pro.[CommandLine]
	,app.Icon
FROM v_SmsPackage as app
JOIN v_Program as pro on pro.PackageID = app.PkgID
WHERE pro.ProgramName <> '*' and app.[Name] NOT LIKE '%User State%' and app.[Name] NOT LIKE '%Configuration Manager%'


"@

    Try {
        $Applications = Invoke-Sqlcmd -ServerInstance "$SiteServer" -Database "cm_$SiteCode" -Query $ApplicationQuery -MaxBinaryLength 45000 -ErrorAction Stop -TrustServerCertificate -Verbose
    } catch {
        Write-Host "$_.Exception.Message"
        #New-UDAlert -Severity 'error' -Text "$_.Exception.Message"
    }
    Try {
        $Packages = Invoke-Sqlcmd -ServerInstance "$SiteServer" -Database "cm_$SiteCode" -Query $PackageQuery -MaxBinaryLength 45000 -ErrorAction Stop -TrustServerCertificate -Verbose
    } catch {
        Write-Host "$_.Exception.Message"
        #New-UDAlert -Severity 'error' -Text "$_.Exception.Message"
    }

$AllApplications = [System.Collections.ArrayList]::new()
$AllPackages = [System.Collections.ArrayList]::new()

$path = "C:\Temp"
if (-not (Test-Path -Path $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

# AW Picker GUI
[xml]$AWPicker = @"
<Window 
        Name="Main"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Application Workspace ConfigMgr Import Utility" Height="800" Width="1200" ResizeMode="NoResize" Background="#FF323F48" FontFamily="Work Sans">
    <Grid>
        <Image Name="Image" HorizontalAlignment="Center" Height="107" Margin="0,59,0,0" VerticalAlignment="Top" Width="1039" />
        <TextBlock HorizontalAlignment="Center" Height="90" Margin="0,184,0,0" TextAlignment="Center" TextWrapping="Wrap" FontFamily="Work Sans" Text="Listed below are the applications and packages in ConfigMgr. Here you can select the applications you want to import into your environment." VerticalAlignment="Top" Width="665" Foreground="White" FontSize="16"/>
        <ListView Name="ListView" Margin="58,287,46,107" FontFamily="Work Sans" Background="#FFE0E4E1" SelectionMode="Multiple">
            <ListView.View>
                <GridView>
                    <!-- Centered Checkbox Column -->
                    <GridViewColumn Width="35">
                        <GridViewColumn.CellTemplate>
                            <DataTemplate>
                                <Border HorizontalAlignment="Center" VerticalAlignment="Center">
                                    <CheckBox IsChecked="{Binding CreateApp}"/>
                                </Border>
                            </DataTemplate>
                        </GridViewColumn.CellTemplate>
                    </GridViewColumn>

                    <GridViewColumn Header="Publisher" DisplayMemberBinding="{Binding Publisher}" Width="150"/>
                    <GridViewColumn Header="Application Name" DisplayMemberBinding="{Binding NameOfApplication}" Width="300"/>

                    <GridViewColumn Header="Version" DisplayMemberBinding="{Binding DisplayVersion}" Width="50"/>
                    <GridViewColumn Header="Path to Files" DisplayMemberBinding="{Binding PathToFiles}" Width="450"/>
                    <GridViewColumn Header="Type of Package" DisplayMemberBinding="{Binding Type}"/>
                </GridView>
            </ListView.View>
        </ListView>
        <Button Content="Add Applications" HorizontalAlignment="Left" Height="56" Margin="778,700,0,0" VerticalAlignment="Top" Width="376" FontFamily="Work Sans" FontSize="18" Name="ProcessSelectedItems"/>
   </Grid>
</Window>
"@

# Starting Screen
[xml]$MainWindow = @"
<Window 
        Name="Main"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Application Workspace Package Utility" Height="800" Width="1200" ResizeMode="NoResize" Background="#FF323F48" FontFamily="Times New Roman">
    <Grid>
        <Image Name="Image" HorizontalAlignment="Center" Height="107" Margin="0,59,0,0" VerticalAlignment="Top" Width="1039" />
        <TextBlock HorizontalAlignment="Center" Height="248" Margin="0,265,0,0" TextWrapping="Wrap" Text="Please be patient as we load your information." VerticalAlignment="Top" Width="822" FontFamily="Work Sans" FontSize="72" Foreground="White" TextAlignment="Center"/>
    </Grid>
</Window>


"@

Function Create-Package {
    param(
        [Parameter(Mandatory=$true)]
        $App
    )
    
    $PackageExist = Get-LiquitPackage -Name "CM - $($App.NameOfApplication)"
    If ($PackageExist) {
        Write-Host "CM - $($App.NameOfApplication) already exists, skipping package"
        Return
    }

    # Save the base64 icon as an ico file for use in AW
    $appIcon = $($app).Icon

    if ($null -ne $appIcon -and -not ($appIcon -is [System.DBNull])) {
        if ($appIcon -is [byte[]] -and $appIcon.Length -gt 0) {
            [System.IO.File]::WriteAllBytes("$path\icon.ico", $appIcon) | Out-Null
            $iconPath = "$path\icon.ico"
            $iconContent = New-LiquitContent -Path $iconPath
        }
        elseif ($appIcon -is [string] -and $appIcon.Trim().Length -gt 0) {
            # if SQL returned a base64 string of the bytes, convert it
            try {
                $bytes = [Convert]::FromBase64String($appIcon)
                if ($bytes.Length -gt 0) {
                    [System.IO.File]::WriteAllBytes("$path\icon.ico", $bytes) | Out-Null
                    $iconPath = "$path\icon.ico"
                    $iconContent = New-LiquitContent -Path $iconPath
                } else {
                    Write-Host "Icon string decoded to empty byte array."
                    $iconContent = $null
                }
            } catch {
                Write-Host "Failed to decode icon string as base64: $($_.Exception.Message)"
                $iconContent = $null
            }
        }
        else {
            Write-Host "Icon is present but not in a supported type."
            $iconContent = $null
        }
    }
    else {
        Write-Host "Icon is null or DBNull."
        $iconContent = $null
    }


    $AWPackage = New-LiquitPackage -Name "CM - $($App.NameOfApplication)" -Type "Launch" -DisplayName "$($app.NameOfApplication)" -Priority 100 -Enabled $true -Offline $true -Web $false -Icon $iconContent
    
    If ($app.Version) {

        $AWSnapshot = New-LiquitPackageSnapshot -Package $AWPackage -Name "version $($app.Version)"

    } elseif ($app.FileDetectionVersion) {
        $AWSnapshot = New-LiquitPackageSnapshot -Package $AWPackage -Name "version $($app.FileDetectionVersion)"
    } else {
        $AWSnapshot = New-LiquitPackageSnapshot -Package $AWPackage -Name "VERSION 1"
    }

    $actionset_install = New-LiquitActionSet -Snapshot $AWSnapshot -Type Install -Name 'Install' -Enabled $true -Frequency OncePerDevice -Process Sequential

    # New logic to import apps with source files larger than 3.5GB *******************************************
    
    $sourceFolder = $($app.PathToFiles)
    $outputFolder = "C:\Output"
    $maxSize = 3.5GB

    if (!(Test-Path $outputFolder)) {
        New-Item -ItemType Directory -Path $outputFolder | Out-Null
    }

    $zipIndex = 1
    $currentZip = Join-Path $outputFolder ("Archive_{0:000}.zip" -f $zipIndex)
    $currentFiles = @()
    $totalSize = 0

    # Gather files while preserving folder structure
    $files = Get-ChildItem -Recurse -File $sourceFolder

    foreach ($file in $files) {

        $fileSize = $file.Length

        # If adding this file would exceed the max size → start a new zip
        if ($totalSize + $fileSize -gt $maxSize) {
            Compress-Archive -Path $currentFiles -DestinationPath $currentZip -Update
            #Write-Host "Created: $currentZip"
        
            $zipIndex++
            $currentZip = Join-Path $outputFolder ("Archive_{0:000}.zip" -f $zipIndex)
            $currentFiles = @()
            $totalSize = 0
        }

        $currentFiles += $file.FullName
        $totalSize += $fileSize
    }

    # Final ZIP
    if ($currentFiles.Count -gt 0) {
        Compress-Archive -Path $currentFiles -DestinationPath $currentZip -Update
        #Write-Host "Created: $currentZip"
    }

    $AllFiles = Get-ChildItem -Recurse -File $outputFolder

    ForEach ($file in $AllFiles) {
        $PathToFile = Join-Path $outputFolder $file.Name
        $actionset_install_action1 = New-LiquitAction -ActionSet $actionset_install `
                        -Name 'Copy $($file.Name) to local machine' -type 'contentextract' `
                        -Enabled $true -IgnoreErrors $false -Settings @{content = "$($file.Name)"; destination = '${PackageTempDir}';}
        $content_action1 = New-LiquitContent -path $PathToFile
        $attribute_action1 = New-LiquitAttribute -Entity $actionset_install_action1 -Link $content_action1 -ID 'content' -Setting @{filename = "$($file.Name)"}

    }
    
    # Clean up all the zip files created
    Remove-Item -Path $outputFolder -Recurse -Force

      # Add in action to install product
    # Use regex to split up the values and apply them as name and parameters
    # **********************************************************************************************************************
    $StartingCommand = Get-StartingCommand -CommandLine $app.InstallCommand
    $FinalCommandArgs = Get-CommandLineParameters -CommandLine $app.InstallCommand

    $actionset_install_action2 = New-LiquitAction -ActionSet $actionset_install `
                    -Name 'Start Install' -type 'processstart' `
                    -Enabled $true -IgnoreErrors $false -Context Device -Settings @{name = '${PackageTempDir}\' + $StartingCommand; parameters = "$FinalCommandArgs"; wait = $true; directory = '${PackageTempDir}'}

    # Add in action to delete temp directory
    $actionset_install_action3 = New-LiquitAction -ActionSet $actionset_install `
                    -Name 'Remove Temporary Directory' -type 'dirdelete' `
                    -Enabled $true -IgnoreErrors $false -Settings @{path = '${PackageTempDir}'}
    
        # Add in Uninstall Action Set if available
    If ($app.UninstallCommand -ne 'N/A') {
    $actionset_uninstall = New-LiquitActionSet -Snapshot $AWSnapshot -Type Uninstall -Name 'Uninstall' -Enabled $true -Frequency Always -Process Sequential
    

    # Perform the Uninstall
    <# Removed the files that are being copied down for now as if there are multiple zip files, this won't work.

    $actionset_uninstall_action1 = New-LiquitAction -ActionSet $actionset_uninstall `
                        -Name 'Copy files to local machine' -type 'contentextract' `
                        -Enabled $true -IgnoreErrors $false -Settings @{content = "$($zipFileName).zip"; destination = '${PackageTempDir}';}
    $attribute_action1 = New-LiquitAttribute -Entity $actionset_uninstall_action1 -Link $content_action1 -ID 'content' -Setting @{filename = "$($zipFileName).zip"}
     #>

    $StartingCommand = Get-StartingCommand -CommandLine $app.UninstallCommand
    $FinalCommandArgs = Get-CommandLineParameters -CommandLine $app.UninstallCommand
    $actionset_uninstall_action2 = New-LiquitAction -ActionSet $actionset_uninstall `
                    -Name 'Start Uninstall' -type 'processstart' `
                    -Enabled $true -IgnoreErrors $false -Context Device -Settings @{name = '${PackageTempDir}\' + $StartingCommand; parameters = "$FinalCommandArgs"; wait = $true; directory = '${PackageTempDir}'}
    
    <#
    $actionset_uninstall_action3 = New-LiquitAction -ActionSet $actionset_uninstall `
                    -Name 'Remove Temporary Directory' -type 'dirdelete' `
                    -Enabled $true -IgnoreErrors $false -Settings @{path = '${PackageTempDir}'}
    #>

    }

    If ($PublishingStage -ne $null) {
        Publish-LiquitPackageSnapshot -Snapshot $AWSnapshot -Stage "$($PublishingStage)" -Name $app.Version
    }
}

Function Get-CommandLineParameters {
    param(
        [Parameter(Mandatory=$true)]
        $CommandLine
    )
    $Elements = $CommandLine -split '\s+'
    If ($Elements.length -gt 1){
        # Split the string by spaces, but keep quoted substrings as single elements
        $Elements = [regex]::Matches($CommandLine, '("[^"]+"|\S+)') | ForEach-Object { $_.Value }
        $commandArgs = @()
        ForEach ($element in $Elements) {
            $regex = '"([^"]+\.msi)"|(\b\S+\.msi\b)'
        
            If ($Element -match '^TRANSFORMS') {
                $TransformFile = $element -split '='
                $commandArgs += 'TRANSFORMS=${PackageTempDir}\' + $TransformFile[1]
            }
            elseif ($Element -match $regex) {
                $msiFile = if ($matches[1] -ne '') { $matches[1] } else { $matches[2] }
                $commandArgs += '${PackageTempDir}\' + '"'+ $msifile + '"'
            }
            elseif ($element -ne $elements[0]) {
                $commandArgs += $element
            }
        }
        Return $CommandArgs
    }
    Return $null
}

Function Get-StartingCommand {
    param(
        [Parameter(Mandatory=$true)]
        $CommandLine
    )
    $Elements = $CommandLine -split '\s+'
    if ($Elements[0] -notmatch '\.exe$') {
        $Elements[0] += '.exe'
    }
    Return $Elements[0]
}


# Create the image from base64
# AW icon
$StringWithImage = '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'
$iconImage = [convert]::FromBase64String($StringWithImage)

# AW Logo
$AWLogo = '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'
$bannerImage = [convert]::FromBase64String($AWLogo)

# Show Opening Screen
$XMLReader = (New-Object System.Xml.XMLNodeReader $MainWindow)
$StartingForm = [Windows.Markup.XamlReader]::Load($XMLReader)

$MainImage = $StartingForm.FindName('Image')
$Title = $StartingForm.FindName('Main')

# Add in the Image
$MainImage.Source = $bannerImage
$Title.Icon = $iconImage
$Startingform.WindowStartupLocation = [System.Windows.Forms.FormStartPosition]::CenterScreen
$StartingForm.Topmost = $true

$StartingForm.Show()

ForEach ($Application in $Applications) {
            # Parse the xml and populate some variables
            [xml]$xml = $Application.SDMPackageXML
            $App = New-Object PSObject -prop @{
                DeploymentType = $($Application.DeploymentType)
                InstallerFile = $($Application.PrimaryFilename)
                PathToFiles = $($Application.Location)
                DetectionMethod = $($Application.DetectionMethod)
                EnhancedFolder = $($Application.EnhancedFolder)
                EnhancedFile = $($Application.EnhancedFile)
                ProductCodeMSI = $($Application.ProductCodeMSI)
                InstallCommand = $($Application.InstallCommandLine)
                UninstallCommand = $($Application.UninstallCommandLine)
                NameOfApplication = $($Application.DisplayName)
                Version = $($Application.Version)
                DisplayVersion = $($Application.SoftwareVersion)
                Publisher = $($Application.Manufacturer)
                FileDetectionPath = $($Application.FileDectionPath)
                FileDetectionFile = $($Application.FileDetectionFile)
                FileDetectionOperator = $($Application.FileDetectionOperator)
                FileDetectionVersion = $($Application.FileDetectionVersion)
                Icon = $($Application.icon)
                Type = "Application"
                CreateApp = $false
            }
            [void]$AllApplications.Add($App)
        }

        # Get all PACKAGES from ConfigMgr
        ForEach ($Package in $Packages) {
            $App = New-Object PSObject -prop @{
                DeploymentType = "N/A"
                InstallerFile = $($Package.CommandLine.Split(' ')[0])
                PathToFiles = $Package.Source
                DetectionMethod = "N/A"
                EnhancedFolder = "N/A"
                EnhancedFile = "N/A"
                ProductCodeMSI = "N/A"
                InstallCommand = $Package.CommandLine
                UninstallCommand = "N/A"
                NameOfApplication = $Package.Name
                Version = $Package.Version
                DisplayVersion = $Package.Version
                Publisher = $Package.Manufacturer
                FileDetectionPath = "N/A"
                FileDetectionFile = "N/A"
                FileDetectionOperator = "N/A"
                FileDetectionVersion = "N/A"
                Icon = $($Package.icon)
                Type = "Package"
                CreateApp = $false
            }
            [void]$AllApplications.Add($App)
        }

# So now that I have all the information that I need to create the AW Packages, time to create the GUI that displays the possibilities and then allows them to choose what they want to import.

$SortedApplications = $AllApplications | Sort-Object -Property NameOfApplication

$XMLReader = (New-Object System.Xml.XMLNodeReader $AWPicker)
$XMLApplicationForm = [Windows.Markup.XamlReader]::Load($XMLReader)
    
$MainImage = $XMLApplicationForm.FindName('Image')
$Title = $XMLApplicationForm.FindName('Main')
$ListView = $XMLApplicationForm.FindName('ListView')
$button = $XMLApplicationForm.FindName("ProcessSelectedItems")

# Add in the Image
$MainImage.Source = $bannerImage
$Title.Icon = $iconImage
$ListView.ItemsSource = $SortedApplications

$Script:SelectedApplications = @()

# Define event handlers
$button.Add_Click({
    Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials
    # Do something with the Selected Apps
        $Script:SelectedApplications = $($AllApplications | Where-Object { $_.CreateApp -eq $true})
        ForEach ( $App in $($AllApplications | Where-Object { $_.CreateApp -eq $true})) {
            # Commands to import applications
            Create-Package -App $app
        }

    $XMLApplicationForm.Close()

})

$StartingForm.Close()

$XMLApplicationForm.WindowStartupLocation = [System.Windows.Forms.FormStartPosition]::CenterScreen
$XMLApplicationForm.Topmost = $true
$XMLApplicationForm.ShowDialog()