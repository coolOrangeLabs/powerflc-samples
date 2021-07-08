[![powerPLM](https://img.shields.io/badge/COOLORANGE%20powerPLM-22.0.9-orange.svg)](https://www.coolorange.com/products/powerplm/)
[![powerPLM](https://img.shields.io/badge/COOLORANGE%20powerJobs-22.0.3-orange.svg)](https://www.coolorange.com/products/powerplm/)

**This Release Candidate requires powerPLM 22.0.9 and powerJobs 22.0.3 to function property!!!**

# Change Management Workflow (Release Candidate)

This sample Workflow can be used to outsource a Fusion 360 Manage Change Order (CO) state to Vault. 

Once a change order in Fusion 360 Manage reaches a configurable state, powerPLM creates a new representation of this CO as an Engineering Change Order (ECO) in Vault.  
All affected items (Linked Items or Managed Items) that are available in Vault are automatically assigned to the ECO as records. In addition, documents attached to the CO in Fusion 360 Manage are automatically downloaded, stored in Vault and attached to the ECO. 

When the ECO in Vault is closed, powerPLM automatically updates the CO in Fusion 360 Manage by executing a configurable workflow action. Depending on the configuration in Fusion 360 Manage, this workflow action is transitioning the CO to the next state.

The entire workflow is based on PowerShell scripts and can be customized if needed.


## Sample.SyncChangeOrders

This powerJobs Processor Job performs all the succeeding Fusion Lifecycle requests using the e-mail address that has been configure in the Configuration Manager.
  
The powerPLM "Sample.TransferItemBOMs" job is required. Items have to be transferred from Vault to Fusion 360 Manage by this job in order to be recognized and automatically added to an ECO.  
Detailed information on how to install the workflow can be found here: https://www.coolorange.com/wiki/doku.php?id=powerflc:getting_started:using_the_powerflc.workflows


### Regular synchronization 
The job is automatically triggered by powerJobs (every 10 minutes by default) to read all Fusion 360 Manage Change Orders that are in a specific state. It creates or updates ECOs in Vault for all items found in Fusion 360 Manage.

### ECO state
Vault ECOS will be created with the state "Create".

#### Fields/Properties
The field/property mapping is applied when an ECO is created or updated.

#### Attachments
All documents that are attached to a CO are temporarily downloaded, added to a folder in Vault and attached to the Vault ECO.

#### Affected Items / Records
The affected items of a CO are added to the ECO as records if they were previously transferred from Vault to Fusion 360 Manage by the "Sample.TransferItemBOMs" job.

#### Comments
Only when an ECO is created for the first time (not when updated) a comment is added to the ECO if there are affected items on the CO in Fusion 360 Manage that cannot be found in Vault (because they are not there or not transferred by powerPLM).

### ECO state change in Vault
When triggered by a state change, the job synchronizes Vault ECO records (items) with the affected items of the corresponding Fusion 360 Manage change order. All items need to exist in Fusion 360 Manage in order to be added to the CO as affected items. This is important when an item is added to the ECO that was not on the CO before.

After the change order is synchronized back to Fusion 360 Manage, a workflow action gets executed on the CO that can be used to indicate that the engineering changes are completed.


## Configuration

The job is delivered with a default configuration file that has to be imported from the location %ProgramData%\coolOrange\powerJobs\Jobs\Sample.SyncChangeOrders.json.
Once imported, the default configuration can be adjusted in the Workflow Settings dialog.

![image](https://user-images.githubusercontent.com/5640189/124611898-2b5bb300-de72-11eb-8e87-0f730b5051ee.png)

### Workspace and Unique Fields
The selected **Workspace** is used to synchronize Fusion 360 Manage Change Orders with Vault ECOs. A field from this workspace must be chosen as Unique Identifier. Typically, this field contains the number of a Change Order. The unique Vault property defaults to **Number** and should not be changed.

### Workflow Settings

#### Trigger State
All Fusion Lifecyle Change Orders in the selected state will be transferred to Vault. Default: *Perform Change*

#### Affected Items Lifecycle Transition
Once an ECO is closed in Vault, the corresponding CO in Fusion 360 Manage will be updated with all affected items that have been added to the Vault ECO and where not present in Fusion 360 Manage before.  
To find the correct Lifecycle Transition, go to Fusion 360 Manage, from the main menu navigate to "Administration" > "System Configuration" > "Lifecycle Editor" and select "Change Orders" from the "Highlight Workspaces" section: 
![image](https://user-images.githubusercontent.com/5640189/124617111-f736c100-de76-11eb-83dc-f617542058dc.png)

Default: *To Pre-Release*

#### Workflow Action
Once an ECO is closed in Vault, a workflow action (transition) on the corresponding CO in Fusion 360 Manage will be executed.
To find the correct transition, go to Fusion 360 Manage, open the "Workspace Manager", select the workspace (Change Orders) and open the "Workflow Editor". Click on “Workflow Summary” to find the transition that needs to be executed:  
![image](https://user-images.githubusercontent.com/5640189/124615081-3237f500-de75-11eb-9e1d-1687a92d71a7.png)
 
Default: *Update Tasks*

*Note: if the Lifecycle is not present at an affected item, the workflow action cannot be executed!*

#### Vault Attachments Folder
This folder is used to store the attachments from a Change Order in Vault. The files in that folder are listed in the Vault ECOs "Files" tab. For each ECO a new subfolder with the name of the ECO will be created automatically.

### Field Mappings  
An "Item Field Mapping" is available to map Fusion 360 Manage CO fields with Vault ECO user defined properties (UPDs). Values from the **Fusion 360 Manage Item Field** column will be copied to the Vault ECO UDPs chosen in the **Vault Change Order Property** column when an ECO is created or updated in Vault.  

In addition to the User defined properties, the Vault system properties "Title (Item,CO)", "Description (Item,CO)" and "Due Date" can be mapped as well. All other system properties are ignored when creating/updating the ECO.

"Functions" as well as properties of type "Image" are ignored.

![image](https://user-images.githubusercontent.com/5640189/124615209-54ca0e00-de75-11eb-9f2f-f6505cf52ae3.png)

*Note: The "Description" value on a Fusion 360 Manage Change Order contains is HTML formatted.
This formatting will be removed by the workflow since Vault does not support HTML formatted strings!*

*Note: The ECO in Vault is always created using the default routing. This cannot be changed by configuration but in the script files if needed*


## Job Trigger
The workflow consists of two different components and thus needs to implement two different triggers:
1) __Regularly__ query Fusion 360 Manage to get all new or updated Change Orders / Change Tasks in order to create / update the ECOs in Vault
2) __When a Vault ECO is closed__, update the Fusion 360 Manage Change Order / Change Task 

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
    "TimeBased":	"0 0/10 * 1/1 * ? *",
    // This is the name of the Vault you want to trigger the job
    "Vault":		"Vault",
    // And these two parameters are optional and self-explaining:
    "Priority":		101,
    "Description":	"Queries Fusion 360 Manage for new/updated Change Orders"
    //PowerJobs triggers a Job only if the same job isn't already pending in the job queue.
  }
}
```
The following settings have to be adjusted:

| Setting | Description | Default |
| --- | --- | --- |
| Time Based | Indicates when / how often the job should be triggered (cron syntax) | 10 Minutes |
| Vault | Name of the Vault the job should be triggered for  | Vault |
| Priority | Priority of the job | 101 |

*Note: More information on time triggered jobs can be found here: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor:jobprocessor:start#time_triggered_jobs*

*Note: Please make sure the priority is greater than 100. This is important because this workflow expects the items transferred to the "Vault Items and BOMs" workspace before the Vault ECO is synchronized with the CO.*

*Note: For the first run of the time triggered job, all the Fusion 360 Manage items are retrieved that fit to the state defined in the configuration. From second time onwards, only newly created or modified items are retrieved.*

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
Start / restart powerJobs Processor to automatically register the jobs to Vault's Job Processor and to activate the time triggered jobs functionality


## Multi Job Processor environments
In an environment with more than one Job Processor, one single Job Processor must be used for both, the "Sample.TransferItemBOMs" job and the "Sample.SyncChangeOrders" job in order to make sure that items are transferred to Fusion 360 Manage before the Change Orders are synchronized.

## Known issues / limitations
* When a Vault ECO is closed, the corresponding FLC item metadata won't be updated
* When an ECO is updated in Vault and a new affected item has been added to the FLC item and this item cannot be found in Vault, the comments of the Vault ECOs are not updated
* The "powerFLC Configuration Manager" dialog may cause a Vault crash, when the "Attachment Folder" button is clicked but no folder gets selected in the dialog


## Product documentation
powerPLM: https://www.coolorange.com/wiki/doku.php?id=powerflc  
powerJobs Processor: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor  

