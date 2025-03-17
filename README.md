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

## Disclaimer

All scripts contained in this repo are examples of what you can do. You may need to use these as a base and modify for your needs from here. There is no warranty or support available for these scripts. I can try to help, however, these are not supported by Recast Software.

## Move-AWStages.ps1 

This script that can automate the process of moving packages through the stages in Application Workspace. You define the number of days that you want between the stages. It will take the last date modified as it's starting point and then progress from there. This assumes that you have a synchronize connector syncing packages to the Test Stage and then after so many days in Test, it moves to Acceptance and then after so many days it moves to Production. This would be set as a scheduled task on a Utility server that can run on whatever schedule you want it to run on.

## Sync-EntraGroupWithAWCollection.ps1 

This script will assist in syncing devices in an Entra AD group to a matcing Device Collection in Application Workspace. This will need to be modified from its original version if you want to support multiple Entra AD Groups and multiple Device Collections. This is just a starting point. This will require someone to sign in with the right permissions. If you wanted to, you could modify this to support an app registration and secret key so that you can run this as a scheduled task. This will remove any members that have been taken out of that Entra group, and add those that have been added. This will also create the Device Collection if it doesn't already exist to match the displayName of the Entra AD Group.

## Import-ConfigMgrPackages.ps1

This script will attempt to import in applications and packages from ConfigMgr into Application Workspace. It will not create "Launch" actions as those don't exist in ConfigMgr. This will create the install action and create all the steps for that install action based on the install command line in the ConfigMgr package/application. It will also create an uninstall action "if" there is an uninstall command specified in the ConfigMgr application. Currently there is a bug in the script that if in the install command line or the uninstall command line there is a .\ in the command, it fails to create correctly.

## Sync-MultipleEntraGroupsToAW.ps1

This script uses an app registration and a secret key so that you can automate the process of syncing Entra Groups to Application Workspace Groups. You will need to specify the correct groups you want to sync to. I tried to document each action so that it makes sense... This will add if there are new objects and remove if any have been removed from the Entra AD groups. In this example, Entra is the source of truth...

## Sync-ConfigMgrCollectionsToAWUserCollections.ps1

This script will query ConfigMgr for all collections and give you the option to recreate them in AW as user collections. This will take the devices' primary user or last logged on user and add them to a User Collection in AW. It has an option to just sync the ones that you have already brought in so that you can just run it on a schedule and make sure to add any other devices' users down the road. This is currently not working for User Groups, only Device Groups. I will work on that.
