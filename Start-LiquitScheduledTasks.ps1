$LiquitURI = 'https://john.liquit.com' # Replace this with your zone
$username = 'local\admin' # Replace this with a service account you have created for creating and accessing this information
$password = 'IsaiahMaddux@2014' # Enter the password for that service Account
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, (ConvertTo-SecureString -String $password -AsPlainText -Force)
$ScheduledTasks = "Synchronize Windows Apps","Synchronize Mac Apps"

Connect-LiquitWorkspace -URI $LiquitURI -Credential $credentials

ForEach ($ScheduledTask in $ScheduledTasks) {
    $CurrentTask = Get-LiquitScheduleTask -Name "$ScheduledTask"
    Start-LiquitScheduledTask -ScheduledTask $CurrentTask
}