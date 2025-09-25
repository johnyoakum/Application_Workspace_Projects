<#
.SYNOPSIS
  Enumerate Entra AD groups that contain device members, present a UI for selection,
  or run against previously saved list when -UseSaved is provided.

.DESCRIPTION
  This script will synchronize Entra AD groups (specifically devices) to Application Workspace Collections
  and keep them in sync with every subsequent run (as long as the same groups are selected).
  This will also save the previously selected groups to a json file so that on subsequent runs, which you
  can bypass the GUI.

.PARAMETER UseSaved
  Switch - when provided the script will skip the UI and act on groups listed in SavedGroupsFile.

  # interactive UI (default)
    .\Sync-EntraDeviceGroups.ps1

    # use pre-saved selection (skip form)
    .\Sync-EntraDeviceGroups.ps1 -UseSaved

#>

param(
    [switch] $UseSaved
)

# Enter your App Registration Information
$TenantId = 'tenantID'
$ClientId = "ApplicationID"
$ClientSecret = "CLIENTSecret"
$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($clientId, $secureSecret)

# Enter your Liquit Acess Information
$LiquitURI = 'https://zone.fqdn.com' # Replace this with your zone
$username = 'local\SERVICEACCOUNT'          # Replace this with a service account you have created for creating and accessing this information
$password = 'SERVICEACCOUNTPASSWORD'        # Enter the password for that service Account
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)


# Filename to save selected groups to
$SavedGroupsFile = "$PSScriptRoot\selected-groups.json"

# ---- Update Device Collections ----
function Update-AWCollections {
    param(
        [Parameter(Mandatory=$true)] $Group
    )
    
    #Connect-MgGraph -ClientSecretCredential $credential -TenantId $TenantId
    
    # Get the members from the Entra AD Group
    $members = Get-MgGroupMember -GroupId $($Group.Id) -All | Select-Object -Property *
    $MembersConsolidate = [System.Collections.ArrayList]::new()
    
    ForEach ($member in $members) {
        $EventDetails = New-Object PSObject -prop @{
            Name = $member.AdditionalProperties.displayName
        }
        [void]$MembersConsolidate.Add($EventDetails)
    }
        
    # Check to see if the collection already exists
    $CurrentCollection = Get-LiquitDeviceCollection  -Search $Group.DisplayName
    
    # If no collection exists, create one with the same name
    If (!$CurrentCollection) {
        New-LiquitDeviceCollection -Name "$($Group.DisplayName)"
        $CurrentCollection = Get-LiquitDeviceCollection -Search $Group.DisplayName
    }
    
    # Get all the existing members of that collection
    $DeviceCollectionMembers = Get-LiquitDeviceCollectionMember -DeviceCollection $CurrentCollection

    # Check to see if the device has an agent and is registered
    ForEach ($name in $DeviceCollectionMembers.Name) {
        If ($name -notin $MembersConsolidate.Name) {
            # Remove the member if they are no longer in the group
            $CurrentDevice = Get-LiquitDevice -Search $name
            Remove-LiquitDeviceCollectionMember -DeviceCollection $CurrentCollection -Device $CurrentDevice
            Write-Host "Removed $($CurrentDevice.Name) from $($CurrentCollection.Name)"
        } 
    }
    ForEach ($member in $MembersConsolidate.Name) {
        If ($AllDevices.Name -contains $member) {
            if ($member -notin $DeviceCollectionMembers.Name) {
                # Add the member if they don't already exist
                $CurrentDevice = Get-LiquitDevice -Search $member
                Add-LiquitDeviceCollectionMember -DeviceCollection $CurrentCollection -Device $CurrentDevice
                Write-Host "Added $($CurrentDevice.Name) to $($CurrentCollection.Name)"
            }
        }
    }
    
}

Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials -ErrorAction Stop

# ---- UI: XAML for a window containing a ListBox of checkboxes and buttons ----
[xml]$Xaml = @"
<Window
	xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
	xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select Device-based Entra Groups"
        Height="700" Width="900" ResizeMode="CanResize" Background="#FF2D2D30" WindowStartupLocation="CenterScreen">
	<Grid Margin="10">
		<Grid.RowDefinitions>
			<RowDefinition Height="Auto"/>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>
		<TextBlock Text="Select the Entra groups to process (this will show all groups, not just Device-Based, but won't be able to process Users):" Foreground="White" FontSize="14" Margin="6" />
		<ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="6">
			<ListBox Name="GroupList" />
		</ScrollViewer>
		<StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="6">
			<Button Name="RefreshButton" Width="100" Height="30" Margin="4" Content="Refresh" />
			<Button Name="SaveSelection" Width="140" Height="30" Margin="4" Content="Save &amp; Continue" />
			<Button Name="CancelButton" Width="100" Height="30" Margin="4" Content="Cancel" />
		</StackPanel>
	</Grid>
</Window>
"@

# ---------------- Main flow ----------------
# 1) Authenticate
Connect-MgGraph -ClientSecretCredential $credential -TenantId $TenantId -NoWelcome
#if (-not (Connect-GraphApp -ClientId $ClientId -TenantId $TenantId -ClientSecret $ClientSecret)) {
#    throw "Graph connection failed - aborting."
#}

# Get All Application Workspace Devices
$AllDevices = Get-LiquitDevice

# If -UseSaved: load saved groups and run action directly
if ($UseSaved) {
    if (-not (Test-Path -Path $SavedGroupsFile)) {
        throw "Saved groups file not found: $SavedGroupsFile"
    }
    try {
        $saved = Get-Content -Path $SavedGroupsFile -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to read saved groups file: $_"
    }

    if ($saved.Count -eq 0) {
        Write-Warning "Saved groups file is empty."
        return
    }

    # saved should be objects with Id and DisplayName
    Write-Host "Running in -UseSaved mode. Groups loaded from $SavedGroupsFile`n"
    $saved | ForEach-Object { Write-Host (" - {0} ({1})" -f $_.DisplayName, $_.Id) }

    # --- Perform your actions on saved groups here ---
    foreach ($g in $saved) {
        # Example action: replace this with real logic
        Write-Host "Processing group: $($g.DisplayName) (id=$($g.Id))"
        # TODO: Insert action, e.g. Sync-GroupDevices -GroupId $g.Id *****************************************
        Update-AWCollections($g)
    }

    Write-Host "Completed processing saved groups."
    return
}

# Else: enumerate groups and show UI
Write-Host "Enumerating device-based groups (this may take a few moments)..."
#$deviceGroups = Get-DeviceBasedGroups
$deviceGroups = Get-MgGroup -All

if ($deviceGroups.Count -eq 0) {
    Write-Warning "No device-based groups found in the tenant."
    return
}

# Create window from XAML
Add-Type -AssemblyName PresentationFramework
$reader = (New-Object System.Xml.XmlNodeReader $Xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$groupList = $window.FindName("GroupList")
$refreshBtn = $window.FindName("RefreshButton")
$saveBtn = $window.FindName("SaveSelection")
$cancelBtn = $window.FindName("CancelButton")

# Populate the ListBox with CheckBoxes (one per group)
function Populate-List {
    param($TargetList, $Groups)
    $TargetList.Items.Clear()
    foreach ($g in $Groups | Sort-Object DisplayName) {
        $MemberCount = Get-MgGroupMember -GroupId $g.ID
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = "{0} ({1} members)" -f $g.DisplayName, $MemberCount.Count
        # store the meta object in Tag for later
        $cb.Tag = $g
        $cb.Margin = [System.Windows.Thickness]::new(2,2,2,2)
        $TargetList.Items.Add($cb) | Out-Null
    }
}

Populate-List -TargetList $groupList -Groups $deviceGroups

# Wire up Refresh button to re-enumerate groups
$refreshBtn.Add_Click({
    # UI feedback: disable button while working
    $refreshBtn.IsEnabled = $false
    try {
        [void][System.Windows.MessageBox]::Show("Refreshing group list. This may take a moment.","Please wait","OK","Information")
        #$dg = Get-DeviceBasedGroups
        $dg = Get-mgGroup -All
        if ($dg.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No device-based groups found.","Info","OK","Information") | Out-Null
        } else {
            Populate-List -TargetList $groupList -Groups $dg
        }
    } catch {
        [System.Windows.MessageBox]::Show("Refresh failed: $_","Error","OK","Error") | Out-Null
    } finally {
        $refreshBtn.IsEnabled = $true
    }
})

# Save & Continue handler: gather selected items and do actions
$saveBtn.Add_Click({
    $selected = @()
    foreach ($item in $groupList.Items) {
        if ($item -is [System.Windows.Controls.Primitives.ToggleButton] -and $item.IsChecked) {
            $selected += $item.Tag
        }
    }

    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No groups selected. Please select at least one group or Cancel.","No selection","OK","Warning") | Out-Null
        return
    }

    # Ask if saving selection to file (so -UseSaved can be used later)
    #$saveChoice = [System.Windows.MessageBox]::Show("Save selected groups to file for future -UseSaved runs?`nFile: $SavedGroupsFile", "Save selection?", "YesNoCancel", "Question")
    #if ($saveChoice -eq "Cancel") { return }

    #if ($saveChoice -eq "Yes") {
        #try {
            $selected | Select-Object Id, DisplayName | ConvertTo-Json -Depth 4 | Out-File -FilePath $SavedGroupsFile -Encoding UTF8
            #[System.Windows.MessageBox]::Show("Saved selection to $SavedGroupsFile","Saved","OK","Information") | Out-Null
        #} catch {
            #[System.Windows.MessageBox]::Show("Failed saving selection: $_","Error","OK","Error") | Out-Null
        #}
    #}

    # Close UI before processing
    $window.Close()

    # Perform action on selected groups (replace below with your real logic)
    foreach ($g in $selected) {
        Write-Host "Processing group: $($g.DisplayName) (id=$($g.Id))"
        # TODO: your processing logic here, e.g. Sync-DevicesForGroup -GroupId $g.Id ********************************************
        Update-AWCollections($g)

    }

    [System.Windows.MessageBox]::Show("Processing complete.","Done","OK","Information") | Out-Null
})

# Cancel closes the window
$cancelBtn.Add_Click({ $window.Close() })

# Show the UI
$window.ShowDialog() | Out-Null

