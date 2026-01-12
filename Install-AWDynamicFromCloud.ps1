<#
    .SYNOPSIS
    Script Based installation that can support multiple deployments based on group tag.

    .DESCRIPTION
    This script can be used as a dynamic installation script for the Agent Bootstrapper. 
    This will need a publicly accessible azure blob storage account with only
    a device registration certificate inside. This will generate the agent.json 
    file on demand although some modifications may be needed to reach your desired state.
    See the sections below to configure what group tags are associated with which deployment.
    This also needs an app registratiod and client secret to access the device information
    direct from Intune. This app registration needs the following permissions:

        Device.Read.All
        DeviceManagementManagedDevices.Read.All

    You can hard code the parameters, or you can pass them in the command line


    .EXAMPLE
    .\Install-AWDynamicFromCloud.ps1

    .NOTES
    Version:       1.0
    Author:        John Yoakum, Recast Software
    Creation Date: 01/12/2026
    Purpose/Change: Initial script development
#>

param (
  [String]$storageAccountName = "madduxliquit" ,           # Storage Account Name
  [String]$containerName = "liquit" ,                          # Blob Container Name
  [String]$url = "https://download.liquit.com/extra/Bootstrapper/AgentBootstrapper-Win-2.1.0.2.exe",
  [switch]$StartDeployment = $true,
  [string]$logPath = "C:\Windows\Temp",
  [switch]$UseCertificate = $true
)

######################
#   Configuration    #
######################

# Files to download
$blobFiles = @(
    "AgentRegistration.cer"
)
$DestinationPath = "C:\InstallFiles"               # Target path in the AIB VM
$InstallerPath = "C:\InstallFiles\AgentBootstrapper.exe"

If ($StartDeployment) {$InstallerArguments += " /startDeployment /waitForDeployment"}
If ($logPath) {$InstallerArguments += " /logPath=$($logPath)"
If ($UseCertificate) {$InstallerArguments += " /certificate=C:\InstallFiles\AgentRegistration.cer"}
#$InstallerArguments = "/certificate=C:\InstallFiles\AgentRegistration.cer /startDeployment /waitForDeployment /logPath=$($logPath)"

# Define the Azure App Registration details
$clientId = "2e4e0a31-3cd0-4c3b-b418-b2eca4a9b7e9"  #Client ID
$tenantId = "d37cd50c-80c6-4fd2-9be2-6b24ff526332"  #Directory ID
$clientSecret = "6Bf8Q~hqoywoDvC8uZwp2IpNRq0WF1c_Mb7aodjp" #Client Secret

# Define the device name to search for
$deviceName = "$env:COMPUTERNAME"

#######################################
#    DOWNLOAD FILES TO DESTINATION    #
#######################################
# Create destination directory
if (!(Test-Path $DestinationPath)) {  
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
}

# Download Agent Bootstrapper direct from Internet
Invoke-WebRequest -Uri $url -OutFile $InstallerPath -UseBasicParsing

foreach ($blobName in $blobFiles) {
    $localFilePath = Join-Path $DestinationPath $blobName
    $blobUrl = "https://$($storageAccountName).blob.core.windows.net/$($containerName)/$($blobName)"

    Invoke-WebRequest -Uri $blobUrl -OutFile $localFilePath

    Write-Output "Downloading $blobName to $localFilePath..."
    try {
        Invoke-RestMethod -Uri $blobUrl -Headers $headers -OutFile $localFilePath
        Write-Output "$blobName downloaded successfully."
    } catch {
        Write-Output "Failed to download $blobName $_"
    }
}

Write-Output "All downloads completed."

############################################################
#    CREATE AGENT JSON
###########################################################

# Get an access token using client credentials flow
$tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}

$response = Invoke-RestMethod -Method Post -Uri $tokenUrl -Body $body
$accessToken = $response.access_token
$deviceSearchResults = $null

$graphApiUrl = "https://graph.microsoft.com/v1.0/devices?`$filter=startswith(displayName,'$deviceName')"
$headers = @{
    Authorization = "Bearer $accessToken"
}
Try {
    $deviceSearchResults = Invoke-RestMethod -Method Get -Uri $graphApiUrl -Headers $headers
} catch {
    
}
if ($deviceSearchResults.value.Length -eq 0 -or $null -eq $deviceSearchResults) {
    Write-Output "No devices found with the name: $deviceName"
    return
} elseif ($deviceSearchResults.value.Length -gt 1) {
    $deviceSearchResults.value
    return
}

$device = $deviceSearchResults.value[0]

$physicalIds = $device.physicalIds

if ($physicalIds) {
    $orderId = $physicalIds -match "^\[OrderId\]:.*"

    if ($orderId) {
        $cleanOrderId = $orderId -replace "^\[OrderId\]:", ""
    }
}
###### Set your different Tags here with associated Deployments
switch ($cleanOrderId) {
    'Finance' {
        $deployment = 'Finance'
    }
    'IT' {
        $deployment = 'IT'
    }
    default {
        $deployment = 'Autopilot'
    }
}

##### Tweak the next section of code for the agent.json settings you would like.
$jsonData = @{
    zone = "https://john.liquit.com"
    promptZone = "Disabled"
    login = @{
        enabled = $true
        sso = $true
        identitySource = "AzureAD"
        timeout = 4
    }
    log = @{
        level = "Debug"
        agentPath = "Agent.log"
        userHostPath = "UserHost.log"
        rotateCount = 5
        rotateSize = 1048576
    }
    registration = @{
        type = "Certificate"
    }
    nativeIcons = @{
        enabled = $true
        primary = $true
        startMenuPath = "${Programs}"
    }
    launcher = @{
        enabled = $true
        state = "Default"
        tiles = $false
        minimal = $false
        contextMenu = $true
        sideMenu = "Tags"
        close = $true
    }
    deployment = @{
        zoneTimeout = 60
        enabled = $false
        start = $false
        context = "Device"
        cancel = $false
        triggers = $true
        autoStart = @{
            enabled = $false
            deployment = "$deployment"
            timer = 0
        }

    }
}

$jsonString = $jsonData | ConvertTo-Json -Depth 10
$jsonFilePath = "$DestinationPath\Agent.json"
$jsonString | Set-Content -Path $jsonFilePath

#####################################################
#       Initiate Install Process
#####################################################

set-location $DestinationPath

# Start the install process

Write-Host "Starting the installation process..."

if (Test-Path -Path $InstallerPath) {

   try {

       Start-Process -FilePath $InstallerPath -ArgumentList $InstallerArguments -Wait

       Write-Host "Installation process completed."

   } catch {

       Write-Error "Error starting the installer '$InstallerPath': $($_.Exception.Message)"

       exit 1

   }

} else {

   Write-Warning "Installer executable not found: '$InstallerPath'"


}
