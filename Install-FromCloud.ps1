param (
  [String]$storageAccountName = "madduxliquit" ,           # Storage Account Name
  [String]$containerName = "liquit" ,                          # Blob Container Name
  [String]$url = "https://download.liquit.com/extra/Bootstrapper/AgentBootstrapper-Win-4.4.4130.3708",
  [switch]$StartDeployment = $true,
  [string]$logPath = "C:\Windows\Temp",
  [switch]$UseCertificate = $true,
  [string]$zoneURL = "https://john.liquit.com",
  [string]$agentURL = "https://download.liquit.com/release/4.4/4140/Liquit-Universal-Agent-Win-4.4.4140.8259.exe"
)

#https://madduxliquit.blob.core.windows.net/liquit/agent.json
######################
#   Configuration    #
######################

# Files to download
$blobFiles = @(
    "Agent.json",
    "AgentRegistration.cer"
)

$DestinationPath = "C:\InstallFiles"
$InstallerPath = "C:\InstallFiles\AgentBootstrapper.exe"
$AgentPath = "C:\InstallFiles\Agent.exe"

If ($StartDeployment) {$InstallerArguments += " --startDeployment --wait"}
If ($logPath) {$InstallerArguments += " --logPath $($logPath)"
If ($UseCertificate) {$InstallerArguments += " --certificate C:\InstallFiles\AgentRegistration.cer"}

#######################################
#    DOWNLOAD FILES TO DESTINATION    #
#######################################
# Create destination directory
if (!(Test-Path $DestinationPath)) {  
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
}

# Download Agent Bootstrapper direct from Internet
Invoke-WebRequest -Uri $url -OutFile $InstallerPath -UseBasicParsing

# Attempt to download agent installer from zone and then fallback to public url
Try {
    # Try to download installer from zone
    Invoke-WebRequest -Uri "$zoneURL/api/agent/installers/118A90AD-C2EB-4AE3-A69E-B1154CF46962" -TimeoutSec 60 -OutFile $AgentPath -UseBasicParsing
} catch {
    # Download Agent Bootstrapper direct from Internet
    Invoke-WebRequest -Uri $agentURL -OutFile $AgentPath -UseBasicParsing
}

foreach ($blobName in $blobFiles) {
    $localFilePath = Join-Path $DestinationPath $blobName
    $blobUrl = "https://$($storageAccountName).blob.core.windows.net/$($containerName)/$($blobName)"
    #$blobUrl = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"                
    #Invoke-WebRequest -Uri $blobUrl -Headers $headers -OutFile $localFilePath
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


# ===============================
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



