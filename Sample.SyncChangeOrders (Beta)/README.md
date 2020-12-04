# Change Management Workflow (Beta)

## Description
The Change Management Workflow can be used to outsource a specific Fusion Lifecycle Change Order or Change Task state to Vault. 

Once a Fusion Lifecycle Change Order or Change Task item reaches a configurable state, powerFLC creates a new representation of this item as an ECO in Vault.  
The affected items are automatically assigned to the Vault ECO as records. In addition, documents attached to the Change Order / Change Task in Fusion Lifecycle are automatically downloaded, stored in Vault and attached to the ECO. 

When the ECO in Vault is closed, powerFLC automatically updates the item in Fusion Lifecycle by transitioning it to the next state.

The entire workflow is script based and can be customized if needed.

![image](https://user-images.githubusercontent.com/5640189/101147606-e726dc80-361c-11eb-9ed0-3b4a0ece7183.png)

## Prerequisites
The powerFLC “Vault Items and BOMs” Workflow must be installed. Detailed information on how to install the workflow can be found here: https://www.coolorange.com/wiki/doku.php?id=powerflc:getting_started:using_the_powerflc.workflows

Note:
*Affected Items on a Change Order in FLC have to be created by powerFLC in order to be handled correctly by this workflow.*

## Workflow Installation
-	Copy the files located in Jobs and Modules to “C:\ProgramData\coolOrange\powerJobs”
-	In Vault, open the “powerFLC Configuration Manager” from the tools menu
-	Import the workflow “Sample.SyncChangeOrders.json” using the "Import" button
-	Once imported, double-click the workflow to adjust the settings

## Settings
### Workspace and Unique Fields
The selected **Workspace** is used to synchronize FLC Change Order / Change task items with Vault ECOs. A field from this workspace must be choosen as Unique Identifier. Typically, this field contains the number of a Change Order. The unique Vault Property defaults to **Number** and should not be changed.

### Workflow Settings
![image](https://user-images.githubusercontent.com/5640189/101149424-366e0c80-361f-11eb-8035-61a573d91c53.png)

#### From State
All Fusion Lifecyle items (Change Orders / Change Tasks) in the selected state will be transferred to Vault. Default: *Implementation*
#### To State
Once an ECO is closed in Vault, the corresponding item in Fusion Lifecycle will be transitioned to the selected state.
To choose the correct state, go to Fusion Lifecycle, open the "Workspace Manager", select the workspace (Change Orders) and open the "Workflow Editor". Click on “Workflow Summary” to find the transition that needs to be executed:  
![image](https://user-images.githubusercontent.com/5640189/101149479-4a197300-361f-11eb-8d34-078cf03db85e.png)  
Example: If you have choosen "Implementation" as "From State" and you want to execute the "Approve" transition, you have to select "Implementation" as "To State"  
Default: *Implementation*

#### Attachment Folder
This folder is used to store the attachments from a Change Order / Change task in Vault. The files in that folder are linked to the related ECOs.
#### Attachment Subfolders
If set to "True" a subfolder for each ECO will be created in Vault underneath the "Attachment Folder" directory. Otherwise all files will be stored in the same location.

### Field Mappings  
An "Item Field Mapping" is available. Values from the **Fusion Lifecycle** column will be copied to the Vault ECO UDPs choosen in the **Vault** column when an ECO is created or updated.  
![image](https://user-images.githubusercontent.com/5640189/101149519-5998bc00-361f-11eb-9c68-6ffb67bda5c1.png) 


*Note: The ECO in Vault is always created using the default routing. This cannot be changed by configuration but in the script files if needed*


## Job Trigger

The workflow consits of two different components and thus needs to implement two different triggers:
1) __Regularly__ query Fusion Lifecycle to get all new or updated Change Orders / Change Tasks in order to create / Update the ECOs in Vault
2) __When a Vault ECO is closed__, update the Fusion Lifecycle Change Order / Change Task 

### Regularly trigger jobs
In order to configure the workflow to be executed in a specific interval the file *C:\ProgramData\coolOrange\powerJobs\Jobs\Sample.SyncChangeOrders.settings* must be configured:

```javascript
{
 "Trigger":
  {
    // This is a cron syntax expression. If you are not familiar with cron, please see: http://www.cronmaker.com/
    // Here are some common cron expressions:
    // every minute:        0 0/1 * 1/1 * ? *
    // every weekday at 8th am: 0 0 8 ? * MON,TUE,WED,THU,FRI *
    "TimeBased":	"0 0/1 * 1/1 * ? *",
    // This is the name of the Vault you want to trigger the job
    "Vault":		"Vault",
    // And these two parameters are optional and self-explaining:
    "Priority":		10,
    "Description":	"Queries Fusion Lifecycle for new/updated Change Orders"
    //PowerJobs triggers a Job only if the same job isn't already pending in the job queue.
  }
}
```
The following settings have to be adjusted:

| Setting | Description | Default |
| --- | --- | --- |
| Time Based | Indicates when / how often the job should be triggered (cron syntax) | 1 Minute |
| Vault | Name of the Vault the job should be triggered for  | Vault |
| Priority | Priority of the job | 10 |

*Note: More information on time triggered jobs can be found here: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor:jobprocessor:start#time_triggered_jobs*


### Trigger job on Vault ECO state change
In order to configure the workflow to be executed when a Vault ECO is closed, the Lifecycle Event Editor Application must be used.

1) Download the app from GitHub: https://github.com/koechlm/Vault-LifecycleEventEditor-Sample/releases
2) Extract the ZIP
3) Run the executable LifecycleEventEditor.exe
4) Login to Vault with administrative privileges
5) Navigate to the Change Order Transition "Approved" -> "Close"  
![image](https://user-images.githubusercontent.com/5640189/101149325-10e10300-361f-11eb-8ef5-e7e83a95c393.png)
6) Using the "Actions" menu, add the job type "Sample.SyncChangeOrders"
7) Using the "Actions" menu, commit the changes


## Activate the Workflow
Start / Restart powerJobs Processor to automatically register the jobs to Vault's JobProcessor and to activate the time triggered jobs functionality


## Know issues / limitations
* When a Vault ECO is closed, the corresponding FLC item metadata cannot be updated. This is because of a know limitation in one of the powerFLC PowerShell cmdlets
* When an ECO is updated in Vault and a new affected item has been added to the FLC item and this item cannot be found in Vault, the comments of the Vault ECOs are not updated
* The "powerFLC Configuration Manager" dialog may cause a Vault crash, when the "Attachment Folder" button is clicked but no folder gets selected in the upcomming dialog


## Product documentation
powerFLC: https://www.coolorange.com/wiki/doku.php?id=powerflc  
powerJobs Processor: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor  
