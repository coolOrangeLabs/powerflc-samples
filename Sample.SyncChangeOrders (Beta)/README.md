# Change Management Workflow (Beta)

## Description
The Change Management Workflow can be used to outsource a specific Fusion Lifecycle Change Order (CO) or Change Task (CT) state to Vault. 

Once a Fusion Lifecycle CO/CT reaches a configurable state, powerFLC creates a new representation of this CO/CT as an ECO in Vault.  
The affected items are automatically assigned to the Vault ECO as records. In addition, documents attached to the CO/CT in Fusion Lifecycle are automatically downloaded, stored in Vault and attached to the ECO. 

When the ECO in Vault is closed, powerFLC automatically updates the CO/CT in Fusion Lifecycle by transitioning it to the next state.

The entire workflow is based on PowerShell scripts and can be customized if needed.

![image](https://user-images.githubusercontent.com/5640189/101461195-d5a24500-393a-11eb-98a0-eb4d4a312396.png)

## Prerequisites
The option **Enable Job Server** must be set in the **Job Server Management** in Vault and the installation explained below must be executed on a Job Processor machine.  
The coolOrange products "powerJobs Processor" and "powerFLC" must be installed on the Job Processor machine. Both products can be downloaded from http://download.coolorange.com.  
  
The powerFLC “Vault Items and BOMs” Workflow must be installed. Detailed information on how to install the workflow can be found here: https://www.coolorange.com/wiki/doku.php?id=powerflc:getting_started:using_the_powerflc.workflows

*Note: Affected Items on a CO/CT in Fusion Lifecycle have to be created by powerFLC in order to be handled correctly by this workflow.*

## Workflow Installation
-	Copy the files located in Jobs and Modules to “C:\ProgramData\coolOrange\powerJobs”
-	In Vault, open the “**powerFLC Configuration Manager**” from the tools menu
-	Import the workflow “**Sample.SyncChangeOrders.json**” using the "Import" button
-	Once imported, double-click the workflow to adjust the settings

## Settings
![image](https://user-images.githubusercontent.com/5640189/101461358-097d6a80-393b-11eb-968f-f9f966316b06.png)

### Workspace and Unique Fields
The selected **Workspace** is used to synchronize Fusion Lifecycle Change Orders /Change Tasks with Vault ECOs. A field from this workspace must be chosen as Unique Identifier. Typically, this field contains the number of a Change Order. The unique Vault property defaults to **Number** and should not be changed.

### Workflow Settings

#### From State
All Fusion Lifecyle Change Orders / Change Tasks in the selected state will be transferred to Vault. Default: *Implementation*

#### To State
Once an ECO is closed in Vault, the corresponding CO/CT in Fusion Lifecycle will be transitioned to the selected state.
To find the correct state, go to Fusion Lifecycle, open the "Workspace Manager", select the workspace (Change Orders) and open the "Workflow Editor". Click on “Workflow Summary” to find the transition that needs to be executed:  
![image](https://user-images.githubusercontent.com/5640189/101461436-29ad2980-393b-11eb-9934-e112ebbc3b1a.png)

Example: If you have chosen "Implementation" as "From State" and you want to execute the "Approve" transition, you have to select "Implementation" as "To State"  
Default: *Implementation*

#### Attachment Folder
This folder is used to store the attachments from a Change Order / Change task in Vault. The files in that folder are linked to the related Vault ECOs.
#### Attachment Subfolders
If set to "True" a subfolder for each ECO will be created in Vault underneath the "Attachment Folder" directory. Otherwise all files will be stored in the same location.

### Field Mappings  
An "Item Field Mapping" is available to map Fusion Lifecycle CO/CT fields with Vault ECO user defined properties (UPDs). Values from the **Fusion Lifecycle Item Field** column will be copied to the Vault ECO UDPs chosen in the **Vault Change Order Property** column when an ECO is created or updated in Vault.  
![image](https://user-images.githubusercontent.com/5640189/101461528-4e090600-393b-11eb-9644-8e48aa8ed31b.png)



*Note: The ECO in Vault is always created using the default routing. This cannot be changed by configuration but in the script files if needed*


## Job Trigger
The workflow consists of two different components and thus needs to implement two different triggers:
1) __Regularly__ query Fusion Lifecycle to get all new or updated Change Orders / Change Tasks in order to create / update the ECOs in Vault
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

*Note: For the first run of the time triggered job, all the Fusion Lifecycle items are retrieved that fit to the state defined in the configuration. From second time onwards, only newly created or modified items are retrieved*.

### Trigger job on Vault ECO state change
In order to configure the workflow to be executed when a Vault ECO is closed, the Lifecycle Event Editor application must be used.

1) Download the app from GitHub: https://github.com/koechlm/Vault-LifecycleEventEditor-Sample/releases
2) Extract the ZIP
3) Run the executable LifecycleEventEditor.exe
4) Login to Vault with administrative privileges
5) Navigate to the "Change Order" tab
6) Select the default "Workflow" from the dropdown menu 
7) Navigate to the transition "Approved -> Close"  
![image](https://user-images.githubusercontent.com/5640189/101460857-6debfa00-393a-11eb-9977-8201852b38f1.png)
8) Use the "Add Job to Transition" command in the "Actions" menu to add the job type "**Sample.SyncChangeOrders**"
9) Use the "Commit Changes" command the "Actions" menu to commit the changes
10) Close the application


## Activate the Workflow
Start / restart powerJobs Processor to automatically register the jobs to Vault's JobProcessor and to activate the time triggered jobs functionality


## Known issues / limitations
* When a Vault ECO is closed, the corresponding FLC item metadata cannot be updated. This is because of a know limitation in one of the powerFLC PowerShell cmdlets
* When an ECO is updated in Vault and a new affected item has been added to the FLC item and this item cannot be found in Vault, the comments of the Vault ECOs are not updated
* The "powerFLC Configuration Manager" dialog may cause a Vault crash, when the "Attachment Folder" button is clicked but no folder gets selected in the upcomming dialog


## Product documentation
powerFLC: https://www.coolorange.com/wiki/doku.php?id=powerflc  
powerJobs Processor: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor  

## At your own risk
The usage of these samples is at your own risk. There is no free support related to the samples. However, if you have questions to powerJobs or powerFLC, then visit http://www.coolorange.com/wiki or start a conversation in our support forum at http://support.coolorange.com/support/discussions