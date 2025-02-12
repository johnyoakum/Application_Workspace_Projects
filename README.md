# Application_Workspace_Projects
This repo will be to store all my custom scripts I write for Application Workspace.

For all my scripts that use the powershell commands for Application Workspace, the account for use with the APIACCESS may need the following permissions:

1. API Access
2. View Connectors
3. Create Packages
4. View Packages
5. Modify Packages
6. Remove Packages
7. View Resources
8. View Devices
9. View Device Collections
10. Modify Device Collections
11. Create Device Collections

You can create a custom Access Policy and assign it to the apiuser account that you create for this process.

All scripts contained in this repo are examples of what you can do. You may need to use these as a base and modify for your needs from here. There is no warranty or support available for these scripts. I can try to help, however, these are not supported by Recast Software.

Move-AWStages.ps1 is a script that can automate the process of moving packages through the stages in Application Workspace. You define the number of days that you want between the stages. It will take the last date modified as it's starting point and then progress from there. This assumes that you have a synchronize connector syncing packages to the Test Stage and then after so many days in Test, it moves to Acceptance and then after so many days it moves to Production. This would be set as a scheduled task on a Utility server that can run on whatever schedule you want it to run on.

Sync-EntraGroupWithAWCollection.ps1 will assist in syncing devices in an Entra AD group to a matcing Device Collection in Application Workspace. This will need to be modified from its original version if you want to support multiple Entra AD Groups and multiple Device Collections. This is just a starting point. This can also be ran as a scheduled task on a Utility Server to keep those devices synced. This will remove any members that have been taken out of that Entra group, and add those that have been added. This will also create the Device Collection if it doesn't already exist to match the displayName of the Entra AD Group.
