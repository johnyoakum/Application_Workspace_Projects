if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
}
if (-not (Get-Module -ListAvailable -Name Liquit.Server.PowerShell)) {
    Install-Module -Name Liquit.Server.PowerShell -Scope CurrentUser -Force
}

# Variables
$GroupName = "All AAD Devices"
$LiquitURI = 'https://john.liquit.com' # Replace this with your zone
$username = 'local\apiaccess' # Replace this with a service account you have created for creating and accessing this information
$password = 'IsaiahMaddux@2014' # Enter the password for that service Account
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)
$LiquitDevices = [System.Collections.ArrayList]::new()

# Connect to Microsoft Graph (if not already connected)
try {
    if (-not (Get-MgContext)) {
        Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All", "Device.Read.All" -NoWelcome
    }
} catch {
    Write-Host "Failed to connect to Microsoft Graph. Ensure you have the necessary permissions." -ForegroundColor Red
    exit
}

# Retrieve the group ID based on the group name
$Group = Get-MgGroup -Filter "DisplayName eq '$GroupName'"
$GroupId = $Group.Id
$Members = Get-MgGroupMember -GroupId $GroupId -All

Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials

# 1. Get all the devices in AW
# 2. Limit Members to only those devices in AW
# 3. Get existing Collection Members
# 4. Compare the list and remove any that shouldn't be there and add any that are not there

# Get all AW Devices
$AllDevices = Get-LiquitDevice

# Filter All Devices to get only those that are in the specified group
$MatchingDevices = $AllDevices | Where-Object {$_.Name -in $Members.AdditionalProperties.displayName}

# Create the group if it doesn't exist
$GroupExists = Get-LiquitDeviceCollection | Where-Object {$_.Name -eq $GroupName}
If ($GroupExists -eq $null) {
    New-LiquitDeviceCollection -Name $GroupName
} else {
    # Get group members if already existing
    $CollectionMembers = Get-LiquitDeviceCollectionMember -DeviceCollection $GroupExists
}

# Check to remove any members
If ($CollectionMembers -ne $null) {
    ForEach ($CollectionMember in $CollectionMembers) {
        If ($CollectionMember -notin $MatchingDevices) {
            Remove-LiquitDeviceCollectionMember -DeviceCollection $GroupExists -Device $CollectionMember
        }
    }
}

# Add any new devices
If ($CollectionMembers) {
    ForEach ($MatchingDevice in $MatchingDevices) {
        If ($MatchingDevice -notin $CollectionMembers) {
            Add-LiquitDeviceCollectionMember -DeviceCollection $GroupExists -Device $MatchingDevice
        }
    }
} else {
    $GroupExists = Get-LiquitDeviceCollection | Where-Object {$_.Name -eq $GroupName}
    ForEach ($MatchingDevice in $MatchingDevices) {
        Add-LiquitDeviceCollectionMember -DeviceCollection $GroupExists -Device $MatchingDevice
    }   
}