# File Publishing Workflow

## Description
The File Publishing workflow can be used to transfer file metadata and file attachments from Vault to Fusion 360 Manage. The workflow is seamlessly integrated into Vault workflows, triggered by a Vault file state transition and executed on the Autodesk Vault Job Processor.

The entire workflow is based on PowerShell scripts and can be customized if needed.

## Prerequisites
The option **Enable Job Server** must be set in the **Job Server Management** in Vault and the installation explained below must be executed on a Job Processor machine.  
The coolOrange products "powerJobs Processor" and "powerFLC" must be installed on the Job Processor machine. Both products can be downloaded from http://download.coolorange.com. 

## Workflow Installation
- Copy the files located in Jobs and Modules to “C:\ProgramData\coolOrange\powerJobs”
- In Vault, open the “**powerFLC Configuration Manager**” from the tools menu
- Import the workflow “**coolorange.flc.transfer.file.json**” using the "Import" button
- Once imported, double-click the workflow to adjust the settings

## Settings
### Workspace and Unique Fields
The selected **Workspace** is used to transfer item and BOM data from Vault to Fusion 360 Manage. A field from this workspace must be chosen as Unique Identifier. Typically, this field represents the document name. The unique Vault Property defaults to **File Name** and should not be changed.

### Workflow Settings
![image](https://user-images.githubusercontent.com/5640189/101505267-752ff980-3974-11eb-9db3-250ee5f1a1ab.png)

#### Upload File Attachments
If set to "True" all files attached to a file in Vault are be uploaded as attachment to the corresponding Fusion 360 Manage item

#### Upload Native Files
If set to "True" the native file is transferred to Fusion 360 Manage.

#### Supported File Extensions
The extensions for the native files that are allowed to be transferred to Fusion 360 Manage. Only applicable if **Upload Native Files** is set to "True"  
*Note: the supported file extension must be specified as a single string, seperated by semi-colons*

### Field Mappings  
An "Item Field Mapping" is available. Values from the file properties chosen in **Vault File Property** column will be copied to the Fusion 360 Manage fields chosen in the **Fusion 360 Manage Item Field** column when an item is created or updated in Fusion 360 Manage.  

## Job Trigger
### Trigger job on Vault file state change
In order to configure the workflow to be executed on a Vault lifecycle state transition, Vault's **Custom Job Types** functionality can be used.

1) Log in to Vault as Administrator
2) Open the Vault settings
3) Navigate to Bahaviors, Lifecycle...
4) Edit a "Lifecyle Definition" (e.g. "Flexible Release Process")
5) Navigate to the "Transitions" tab
6) Edit the Transition that should trigger the workflow
7) Navigate to the "Custom Job Types" tab  
![image](https://user-images.githubusercontent.com/5640189/101505033-2f733100-3974-11eb-8ae2-b1b18516a791.png)
8) Use the "Add..." command to add the job type "**coolorange.flc.transfer.file**"
9) Commit the changes using the "OK" button

## Activate the Workflow
Start / restart powerJobs Processor to automatically register the jobs to Vault's JobProcessor 

## Product documentation
powerFLC: https://www.coolorange.com/wiki/doku.php?id=powerflc  
powerJobs Processor: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor  

## At your own risk
The usage of these samples is at your own risk. There is no free support related to the samples. However, if you have questions to powerJobs or powerFLC, then visit http://www.coolorange.com/wiki or start a conversation in our support forum at http://support.coolorange.com/support/discussions