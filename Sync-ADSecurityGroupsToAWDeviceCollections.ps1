<#
.SYNOPSIS
Add/Sync devices from Active Directory security groups into Liquit Workspace device collections.

.DESCRIPTION
Displays AD security groups, lets you select which groups to sync, stores the selections in a text file,
and then adds computer accounts from those groups into matching Liquit device collections.

Only device/computer accounts are processed. User accounts are ignored.
Nested groups are supported through recursive group membership lookups.

This script only adds devices to Liquit collections. It does not remove devices that are already present.

.PARAMETER SyncOnly
Skips the GUI and syncs the groups stored in the selection file.

.NOTES
- Requires RSAT ActiveDirectory tools.
- Requires Liquit.Server.PowerShell module.
- Replace the Liquit connection values before use.
- Strongly recommended: replace embedded credentials with a safer authentication method.
#>
param (
    [switch]$SyncOnly
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Get-Module -ListAvailable -Name Liquit.Server.PowerShell)) {
    Install-Module -Name Liquit.Server.PowerShell -Scope CurrentUser -Force
}
Import-Module Liquit.Server.PowerShell -ErrorAction Stop

# ---------------------------
# Configuration
# ---------------------------
$LiquitURI = 'https://your-liquit-zone.example.com'
$username  = 'domain\\serviceaccount'
$password  = 'replace-me'
$credentials = New-Object System.Management.Automation.PSCredential (
    $username,
    (ConvertTo-SecureString -String $password -AsPlainText -Force)
)

$SelectedGroupsFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'SelectedSecurityGroups.txt'
$GroupSearchBase = (Get-ADDomain).DistinguishedName
$CollectionNamePrefix = ''
$GroupNameFilter = '*'

# ---------------------------
# Helper functions
# ---------------------------
function Get-SavedGroupSelections {
    param([string]$Path)

    $saved = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path -Path $Path) {
        try {
            Get-Content -Path $Path -ErrorAction Stop |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { [void]$saved.Add($_.Trim()) }
            Write-Host "Loaded $($saved.Count) previously selected groups from $Path"
        }
        catch {
            Write-Warning "Failed to read saved groups from $Path. $($_.Exception.Message)"
        }
    }

    return $saved
}

function Save-GroupSelections {
    param(
        [string]$Path,
        [string[]]$Groups
    )

    $Groups |
        Sort-Object -Unique |
        Set-Content -Path $Path -Encoding UTF8

    Write-Host "Saved $($Groups.Count) selected groups to $Path"
}

function Get-ADSecurityGroupsForSelection {
    param(
        [string]$SearchBase,
        [string]$NameFilter = '*',
        [switch]$OnlyGroupsWithComputers = $true
    )

    try {
        # More reliable than the previous raw LDAP bitmask filter in many environments.
        $allGroups = Get-ADGroup -Filter * -SearchBase $SearchBase -Properties Name, DistinguishedName, GroupCategory, GroupScope, Members -ErrorAction Stop |
            Where-Object { $_.GroupCategory -eq 'Security' }
    }
    catch {
        Write-Warning "Primary group lookup failed under search base [$SearchBase]. Retrying without SearchBase. $($_.Exception.Message)"
        $allGroups = Get-ADGroup -Filter * -Properties Name, DistinguishedName, GroupCategory, GroupScope, Members -ErrorAction Stop |
            Where-Object { $_.GroupCategory -eq 'Security' }
    }

    if ($NameFilter -and $NameFilter -ne '*') {
        $allGroups = $allGroups | Where-Object { $_.Name -like $NameFilter }
    }

    if ($OnlyGroupsWithComputers) {
        $filteredGroups = foreach ($group in $allGroups) {
            try {
                $hasComputer = Get-ADGroupMember -Identity $group.DistinguishedName -Recursive -ErrorAction Stop |
                    Where-Object { $_.objectClass -eq 'computer' } |
                    Select-Object -First 1

                if ($hasComputer) { $group }
            }
            catch {
                Write-Warning "Skipping group [$($group.Name)] because its membership could not be read. $($_.Exception.Message)"
            }
        }

        $allGroups = @($filteredGroups)
    }

    return $allGroups | Sort-Object Name
}


function Get-ADComputersFromSecurityGroup {
    param([string]$GroupDistinguishedName)

    try {
        $members = Get-ADGroupMember -Identity $GroupDistinguishedName -Recursive -ErrorAction Stop |
            Where-Object { $_.objectClass -eq 'computer' }

        if (-not $members) {
            return @()
        }

        $dnsHostNames = @()
        $samAccountNames = @()
        foreach ($member in $members) {
            if ($member.objectClass -eq 'computer') {
                $computer = Get-ADComputer -Identity $member.DistinguishedName -Properties DNSHostName, Name, SamAccountName -ErrorAction SilentlyContinue
                if ($null -ne $computer) {
                    if (-not [string]::IsNullOrWhiteSpace($computer.DNSHostName)) {
                        $dnsHostNames += $computer.DNSHostName
                    }
                    if (-not [string]::IsNullOrWhiteSpace($computer.Name)) {
                        $samAccountNames += $computer.Name
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($computer.SamAccountName)) {
                        $samAccountNames += ($computer.SamAccountName -replace '\$$','')
                    }
                }
            }
        }

        # Prefer DNSHostName when present, fall back to Name.
        $resolvedNames = @($dnsHostNames + $samAccountNames) | Where-Object { $_ } | Sort-Object -Unique
        return $resolvedNames
    }
    catch {
        Write-Warning "Failed to read members from group [$GroupDistinguishedName]. $($_.Exception.Message)"
        return @()
    }
}

function Get-CollectionNameFromGroup {
    param(
        [string]$GroupName,
        [string]$Prefix = ''
    )

    $name = if ([string]::IsNullOrWhiteSpace($Prefix)) { $GroupName } else { "$Prefix$GroupName" }

    # Trim characters that commonly cause issues in collection names.
    $invalid = [System.IO.Path]::GetInvalidFileNameChars() + @(':','/','\\','[',']')
    foreach ($char in $invalid | Select-Object -Unique) {
        $name = $name.Replace([string]$char, '-')
    }

    return $name.Trim()
}

function Ensure-LiquitDeviceCollection {
    param([string]$CollectionName)

    $collection = Get-LiquitDeviceCollection -Name $CollectionName -ErrorAction SilentlyContinue
    if (-not $collection) {
        New-LiquitDeviceCollection -Name $CollectionName | Out-Null
        $collection = Get-LiquitDeviceCollection -Name $CollectionName -ErrorAction SilentlyContinue
    }

    return $collection
}

function Add-DevicesToLiquitCollection {
    param(
        [object]$Collection,
        [string[]]$DeviceNames
    )

    if (-not $Collection) {
        throw 'Liquit device collection was not resolved.'
    }

    $existingMembers = Get-LiquitDeviceCollectionMember -DeviceCollection $Collection -ErrorAction SilentlyContinue
    $existingNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($member in @($existingMembers)) {
        foreach ($candidate in @($member.Name, $member.DeviceName, $member.HostName)) {
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                [void]$existingNames.Add($candidate)
            }
        }
    }

    foreach ($deviceName in $DeviceNames) {
        if ([string]::IsNullOrWhiteSpace($deviceName)) { continue }
        if ($existingNames.Contains($deviceName)) { continue }

        $awDevice = Get-LiquitDevice -Name $deviceName -ErrorAction SilentlyContinue
        if (-not $awDevice -and $deviceName -match '\.') {
            $shortName = $deviceName.Split('.')[0]
            $awDevice = Get-LiquitDevice -Name $shortName -ErrorAction SilentlyContinue
        }

        if ($awDevice) {
            Add-LiquitDeviceCollectionMember -DeviceCollection $Collection -Device $awDevice | Out-Null
            Write-Host "Added device [$deviceName] to collection [$($Collection.Name)]"
        }
        else {
            Write-Warning "Device [$deviceName] was found in AD group membership but not in Liquit."
        }
    }
}

function Sync-SelectedSecurityGroups {
    param([string[]]$SelectedGroupDNs)

    foreach ($groupDN in $SelectedGroupDNs | Sort-Object -Unique) {
        $group = Get-ADGroup -Identity $groupDN -Properties Name -ErrorAction SilentlyContinue
        if (-not $group) {
            Write-Warning "Unable to resolve group [$groupDN]. Skipping."
            continue
        }

        $collectionName = Get-CollectionNameFromGroup -GroupName $group.Name -Prefix $CollectionNamePrefix
        $deviceNames = Get-ADComputersFromSecurityGroup -GroupDistinguishedName $groupDN

        if (-not $deviceNames -or $deviceNames.Count -eq 0) {
            Write-Host "No computer accounts found in group [$($group.Name)]. Skipping collection sync."
            continue
        }

        $collection = Ensure-LiquitDeviceCollection -CollectionName $collectionName
        Add-DevicesToLiquitCollection -Collection $collection -DeviceNames $deviceNames
    }
}

function Show-GroupSelectionWindow {
    param(
        [array]$Groups,
        [System.Collections.Generic.HashSet[string]]$PreviouslySelected
    )

    if ($null -eq $PreviouslySelected) {
        $PreviouslySelected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    if ($null -eq $Groups) {
        $Groups = @()
    }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Liquit Device Collection Sync" Height="760" Width="1100" ResizeMode="CanResize" WindowStartupLocation="CenterScreen" Background="#FF323F48" Foreground="White">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" FontSize="26" FontWeight="SemiBold" Margin="0,0,0,12"
                   Text="Select security groups to sync into Liquit device collections" />

        <TextBlock Grid.Row="1" FontSize="14" Margin="0,0,0,16" TextWrapping="Wrap"
                   Text="Only computer accounts are synced. User accounts are ignored. Nested group membership is expanded recursively." />

        <DataGrid Grid.Row="2" Name="GroupsGrid" AutoGenerateColumns="False" CanUserAddRows="False" IsReadOnly="False"
                  HeadersVisibility="Column" SelectionMode="Extended" Background="White" Foreground="Black">
            <DataGrid.Columns>
                <DataGridCheckBoxColumn Header="Sync" Binding="{Binding IsSelected, Mode=TwoWay}" Width="80" />
                <DataGridTextColumn Header="Group Name" Binding="{Binding Name}" Width="300" IsReadOnly="True" />
                <DataGridTextColumn Header="Scope" Binding="{Binding GroupScope}" Width="140" IsReadOnly="True" />
                <DataGridTextColumn Header="Category" Binding="{Binding GroupCategory}" Width="140" IsReadOnly="True" />
                <DataGridTextColumn Header="Distinguished Name" Binding="{Binding DistinguishedName}" Width="*" IsReadOnly="True" />
            </DataGrid.Columns>
        </DataGrid>

        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="SelectAllButton" Content="Select All" Width="120" Height="34" Margin="0,0,12,0" />
            <Button Name="ClearAllButton" Content="Clear All" Width="120" Height="34" Margin="0,0,12,0" />
            <Button Name="SyncButton" Content="Save and Sync" Width="180" Height="34" />
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $grid = $window.FindName('GroupsGrid')
    $selectAllButton = $window.FindName('SelectAllButton')
    $clearAllButton = $window.FindName('ClearAllButton')
    $syncButton = $window.FindName('SyncButton')

    $items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($group in $Groups) {
        $items.Add([pscustomobject]@{
            IsSelected        = $PreviouslySelected.Contains($group.DistinguishedName)
            Name              = $group.Name
            GroupScope        = $group.GroupScope
            GroupCategory     = $group.GroupCategory
            DistinguishedName = $group.DistinguishedName
        })
    }

    $grid.ItemsSource = $items

    $selectAllButton.Add_Click({
        foreach ($item in $items) { $item.IsSelected = $true }
        $grid.Items.Refresh()
    })

    $clearAllButton.Add_Click({
        foreach ($item in $items) { $item.IsSelected = $false }
        $grid.Items.Refresh()
    })

    $syncButton.Add_Click({
        $window.Tag = @($items | Where-Object { $_.IsSelected } | ForEach-Object { $_.DistinguishedName })
        $window.DialogResult = $true
        $window.Close()
    })

    [void]$window.ShowDialog()
    return @($window.Tag)
}

# ---------------------------
# Connect to Liquit
# ---------------------------
Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials

# ---------------------------
# Main flow
# ---------------------------
$previouslySelectedGroups = Get-SavedGroupSelections -Path $SelectedGroupsFilePath

if ($SyncOnly) {
    if ($previouslySelectedGroups.Count -eq 0) {
        throw "-SyncOnly was used, but no saved groups were found at $SelectedGroupsFilePath"
    }

    Sync-SelectedSecurityGroups -SelectedGroupDNs @($previouslySelectedGroups)
    return
}

$availableGroups = Get-ADSecurityGroupsForSelection -SearchBase $GroupSearchBase -NameFilter $GroupNameFilter
if (-not $availableGroups -or $availableGroups.Count -eq 0) {
    throw 'No security groups containing computer accounts were found for selection. Verify the group is a Security group, the device object is a computer account, and the script account can read group membership.'
}

$selectedGroups = Show-GroupSelectionWindow -Groups $availableGroups -PreviouslySelected $previouslySelectedGroups
if (-not $selectedGroups -or $selectedGroups.Count -eq 0) {
    Write-Warning 'No groups were selected. Exiting.'
    return
}

Save-GroupSelections -Path $SelectedGroupsFilePath -Groups $selectedGroups
Sync-SelectedSecurityGroups -SelectedGroupDNs $selectedGroups
