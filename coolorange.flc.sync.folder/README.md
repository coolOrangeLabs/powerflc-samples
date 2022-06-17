# New Product Introduction (NPI) Workflow

## Challenge
New projects in a very early stage need a place where information can be collected and discussed – in Fusion 360 Manage. As soon the project reaches a certain maturity, it’s time to involve engineering. This sample workflow lets you define at which stage of the FLC-project and according Vault-project shall be created in Vault, with given properties and sub-folders. Enginers can now start their work with all information set.

## Description
The NPI workflow can be used to synchronize Projects, Products or any other Fusion 360 Manage items in a configurable state with Vault folders/projects. The workflow runs on a Vault Job Processor and periodically queues a Fusion 360 Manage workspace for changes. If changes are detected a folder/project gets created or updated in Vault.

The entire workflow is based on PowerShell scripts and can be customized if needed.

## Prerequisites
The option **Enable Job Server** must be set in the **Job Server Management** in Vault and the installation explained below must be executed on a Job Processor machine.  
The coolOrange products "powerJobs Processor" and "powerFLC" must be installed on the Job Processor machine. Both products can be downloaded from http://download.coolorange.com. 

## Workflow Installation
- Copy the files located in Jobs and Modules to “C:\ProgramData\coolOrange\powerJobs”
- In Vault, open the “**powerFLC Configuration Manager**” from the tools menu
- Import the workflow “**coolorange.flc.sync.folder.json**” using the "Import" button
- Once imported, double-click the workflow to adjust the settings

## Settings
![image](https://user-images.githubusercontent.com/5640189/101490881-43fafd80-3963-11eb-8cac-cb8c76ec4dca.png)

### Workspace and Unique Fields
The selected **Workspace** is used to synchronize FLC items with Vault folders/projects. A field from this workspace must be chosen as Unique Identifier. Typically, this field contains the name of a project. The unique Vault Property defaults to **Name** and should not be changed.

### Workflow Settings

#### Valid States
All Fusion 360 Manage items in the selected state will be transferred to Vault.

#### Target Folder
The destination folder for the synchronization. All Fusion 360 Manage items that are created as folder/project in Vault will be created in the selected Vault directory.

#### Folder Category
The category of the folder/project that is created in Vault.

#### Copy Folder Structure
If set to **True** the folder structure selected in **Folder Structure Template Path** from Vault will be copied to the newly created folder/project.

#### Folder Structure Template Path
All folders and subfolders of this directory are copied to the newly created folder/project if **Copy Folder Structure** is set to "True". Otherwise this value will be ignored.


### Field Mappings  
An "Item Field Mapping" is available. Values from the **Fusion 360 Manage Item Field** column will be copied to the Vault folder/project UDPs chosen in the **Vault Folder Property** column when a folder/project is created or updated in Vault.  

## Job Trigger
### Regularly trigger jobs
In order to configure the workflow to be executed in a specific interval the file *C:\ProgramData\coolOrange\powerJobs\Jobs\coolorange.flc.sync.folder.settings* must be configured:

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
    "Description":	"Queries Fusion 360 Manage for new/updated Projects"
    //PowerJobs triggers a Job only if the same job isn't already pending in the job queue.
  }
}
```
The following settings have to be adjusted:

| Setting | Description | Default |
| --- | --- | --- |
| Time Based | Indicates when / how often the job should be triggered (cron syntax) | 5 Minutes |
| Vault | Name of the Vault the job should be triggered for  | Vault |
| Priority | Priority of the job | 10 |

*Note: More information on time triggered jobs can be found here: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor:jobprocessor:start#time_triggered_jobs*

*Note: For the first run of the time triggered job, all the Fusion 360 Manage items are retrieved that fit to the state defined in the configuration. From second time onwards, only newly created or modified items are retrieved*.


## Activate the Workflow
Start / restart powerJobs Processor to automatically register the jobs to Vault's JobProcessor and to activate the time triggered jobs functionality

## Product documentation
powerFLC: https://www.coolorange.com/wiki/doku.php?id=powerflc  
powerJobs Processor: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor  

## At your own risk
The usage of these samples is at your own risk. There is no free support related to the samples. However, if you have questions to powerJobs or powerFLC, then visit http://www.coolorange.com/wiki or start a conversation in our support forum at http://support.coolorange.com/support/discussions