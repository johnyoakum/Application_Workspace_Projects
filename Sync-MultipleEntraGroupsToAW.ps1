$tenantId = "TENANTID"
$clientId = "CLIENTID"
$clientSecret = "CLIENTSECRET"
$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($clientId, $secureSecret)


$LiquitURI = 'https://YOURAWZONE' # Replace this with your zone
$username = 'local\admin' # Replace this with a service account you have created for creating and accessing this information
$password = 'YOURPASSWORD' # Enter the password for that service Account
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)
$LiquitDevices = [System.Collections.ArrayList]::new()


# Connect to Microsoft Graph
Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $credential -NoWelcome

# Connect to Application Workspace
Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials

# Get All Application Workspace Devices
$AllDevices = Get-LiquitDevice

# Get Application Workspace Collections - Change these values to match the Application Workspace Collections for your rings.
$CanaryCollection = Get-LiquitDeviceCollection -Name 'Canary Ring'
$EarlyAdopterCollection = Get-LiquitDeviceCollection -Name 'Early Adopters Ring'
$BroadEarlyCollection = Get-LiquitDeviceCollection -Name 'Broad Early Ring'
$BroadLateCollection = Get-LiquitDeviceCollection -Name 'Broad Late Ring'
$BroadLastCollection = Get-LiquitDeviceCollection -Name 'Broad Last Ring'

# Get all Entra AD Groups
$AllGroups = Get-MgGroup

# Assign the group names to our update groups. These will need to match the Entra AD group name
$UpdateGroup1 = "Canary"
$UpdateGroup2 = "Early Adopters"
$UpdateGroup3 = "Broad Early"
$UpdateGroup4 = "Broad Late"
$UpdateGroup5 = "Broad Last"

# Compbine the names of the groups in order to get the groups direct from Entra
$UpdateRingGroupNames =  "$UpdateGroup1", "$UpdateGroup2", "$UpdateGroup3", "$UpdateGroup4", "$UpdateGroup5"

# Get all the device groups in Entra where it matches the names from the $UpdateGroup#... This way we can pull the ID to get its members 
$UpdateGroups = $AllGroups | Where-Object {$_.DisplayName -in $UpdateRingGroupNames}

# Process through each group and add those devices to their respective collecions
ForEach ($UpdateGroup in $UpdateGroups){
    
    # Get all the groups members for the groups from Entra AD
    $GroupMembers = Get-MgGroupMember -GroupId $UpdateGroup.ID
    If ($UpdateGroup.DisplayName -eq $UpdateGroup1) {
        
        # Pull all the active members from the AW Collection
        $CanaryMembers = Get-LiquitDeviceCollectionMember -DeviceCollection $CanaryCollection

        # Check to see if any new devices need to be added
        ForEach ($GroupMember in $GroupMembers) {
            $CurrentDevice = Get-LiquitDevice -Name $GroupMember.AdditionalProperties.displayName
            If ($CurrentDevice -and $CurrentDevice -notin $CanaryMembers) {
                Add-LiquitDeviceCollectionMember -DeviceCollection $CanaryCollection -Device $CurrentDevice
            }
        }

        #Pull List of devices to Remove
        $DevicesToRemove = $CanaryMembers | Where-Object {$_.Name -notin $GroupMembers.AdditionalProperties.displayName}
        ForEach ($DeviceToRemove in $DevicesToRemove) {
            $CurrentDevice = Get-LiquitDevice -ID $DeviceToRemove.ID
            Remove-LiquitDeviceCollectionMember -DeviceCollection $CanaryCollection -Device $CurrentDevice
        }

        # If Entra Group is empty, clear out AW Collection
        If (!$GroupMembers) {
            ForEach ($CanaryMember in $CanaryMembers) {
                $CurrentDevice = Get-LiquitDevice -ID $CanaryMember.ID
                Remove-LiquitDeviceCollectionMember -DeviceCollection $CanaryCollection -Device $CanaryMember
            }
        }

    } elseif ($UpdateGroup.DisplayName -eq $UpdateGroup2) {
        # Pull all the active members from the AW Collection
        $EarlyAdoptersMembers = Get-LiquitDeviceCollectionMember -DeviceCollection $EarlyAdopterCollection

        # Check to see if any new devices need to be added
        ForEach ($GroupMember in $GroupMembers) {
            $CurrentDevice = Get-LiquitDevice -Name $GroupMember.AdditionalProperties.displayName
            If ($CurrentDevice -and $CurrentDevice -notin $EarlyAdoptersMembers) {
                Add-LiquitDeviceCollectionMember -DeviceCollection $EarlyAdopterCollection -Device $CurrentDevice
            }
        }

        #Pull List of devices to Remove
        $DevicesToRemove = $EarlyAdoptersMembers | Where-Object {$_.Name -notin $GroupMembers.AdditionalProperties.displayName}
        ForEach ($DeviceToRemove in $DevicesToRemove) {
            $CurrentDevice = Get-LiquitDevice -ID $DeviceToRemove.ID
            Remove-LiquitDeviceCollectionMember -DeviceCollection $EarlyAdopterCollection -Device $CurrentDevice
        }

        # If Entra Group is empty, clear out AW Collection
        If (!$GroupMembers) {
            ForEach ($EarlyAdoptersMember in $EarlyAdoptersMembers) {
                $CurrentDevice = Get-LiquitDevice -ID $EarlyAdoptersMember.ID
                Remove-LiquitDeviceCollectionMember -DeviceCollection $EarlyAdopterCollection -Device $CurrentDevice
            }
        }
        
    } elseif ($UpdateGroup.DisplayName -eq $UpdateGroup3) {
        # Pull all the active members from the AW Collection
        $BroadEarlyMembers = Get-LiquitDeviceCollectionMember -DeviceCollection $BroadEarlyCollection

        # Check to see if any new devices need to be added
        ForEach ($GroupMember in $GroupMembers) {
            $CurrentDevice = Get-LiquitDevice -Name $GroupMember.AdditionalProperties.displayName
            If ($CurrentDevice -and $CurrentDevice -notin $BroadEarlyMembers) {
                Add-LiquitDeviceCollectionMember -DeviceCollection $BroadEarlyCollection -Device $CurrentDevice
            }
        }

        #Pull List of devices to Remove
        $DevicesToRemove = $BroadEarlyMembers | Where-Object {$_.Name -notin $GroupMembers.AdditionalProperties.displayName}
        ForEach ($DeviceToRemove in $DevicesToRemove) {
            $CurrentDevice = Get-LiquitDevice -ID $DeviceToRemove.ID
            Remove-LiquitDeviceCollectionMember -DeviceCollection $BroadEarlyCollection -Device $CurrentDevice
        }

        # If Entra Group is empty, clear out AW Collection
        If (!$GroupMembers) {
            ForEach ($BroadEarlyMember in $BroadEarlyMembers) {
                $CurrentDevice = Get-LiquitDevice -ID $BroadEarlyMember.ID
                Remove-LiquitDeviceCollectionMember -DeviceCollection $BroadEarlyCollection -Device $CurrentDevice
            }
        }
        
    } elseif ($UpdateGroup.DisplayName -eq $UpdateGroup4) {
        # Pull all the active members from the AW Collection
        $BroadLateMembers = Get-LiquitDeviceCollectionMember -DeviceCollection $BroadLateCollection

        # Check to see if any new devices need to be added
        ForEach ($GroupMember in $GroupMembers) {
            $CurrentDevice = Get-LiquitDevice -Name $GroupMember.AdditionalProperties.displayName
            If ($CurrentDevice -and $CurrentDevice -notin $BroadLateMembers) {
                Add-LiquitDeviceCollectionMember -DeviceCollection $BroadLateCollection -Device $CurrentDevice
            }
        }

        #Pull List of devices to Remove
        $DevicesToRemove = $BroadLateMembers | Where-Object {$_.Name -notin $GroupMembers.AdditionalProperties.displayName}
        ForEach ($DeviceToRemove in $DevicesToRemove) {
            $CurrentDevice = Get-LiquitDevice -ID $DeviceToRemove.ID
            Remove-LiquitDeviceCollectionMember -DeviceCollection $BroadLateCollection -Device $CurrentDevice
        }

        # If Entra Group is empty, clear out AW Collection
        If (!$GroupMembers) {
            ForEach ($BroadLateMember in $BroadLateMembers) {
                $CurrentDevice = Get-LiquitDevice -ID $BroadLateMember.ID
                Remove-LiquitDeviceCollectionMember -DeviceCollection $BroadLateCollection -Device $CurrentDevice
            }
        }
        
    } elseif ($UpdateGroup.DisplayName -eq $UpdateGroup5) {
        # Pull all the active members from the AW Collection
        $BroadLastMembers = Get-LiquitDeviceCollectionMember -DeviceCollection $BroadLastCollection

        # Check to see if any new devices need to be added
        ForEach ($GroupMember in $GroupMembers) {
            $CurrentDevice = Get-LiquitDevice -Name $GroupMember.AdditionalProperties.displayName
            If ($CurrentDevice -and $CurrentDevice -notin $BroadLastMembers) {
                Add-LiquitDeviceCollectionMember -DeviceCollection $BroadLastCollection -Device $CurrentDevice
            }
        }

        #Pull List of devices to Remove
        $DevicesToRemove = $BroadLastMembers | Where-Object {$_.Name -notin $GroupMembers.AdditionalProperties.displayName}
        ForEach ($DeviceToRemove in $DevicesToRemove) {
            $CurrentDevice = Get-LiquitDevice -ID $DeviceToRemove.ID
            Remove-LiquitDeviceCollectionMember -DeviceCollection $BroadLastCollection -Device $CurrentDevice
        }

        # If Entra Group is empty, clear out AW Collection
        If (!$GroupMembers) {
            ForEach ($BroadLastMember in $BroadLastMembers) {
                $CurrentDevice = Get-LiquitDevice -ID $BroadLastMember.ID
                Remove-LiquitDeviceCollectionMember -DeviceCollection $BroadLastCollection -Device $CurrentDevice
            }
        }
        
    }
}

