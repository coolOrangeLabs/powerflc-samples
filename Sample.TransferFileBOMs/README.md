# Sample.TransferFileBOMs

## Description

This workflow transfers Vault file metadata, file BOM blobs and file attachments to Fusion Lifecycle. The workflow runs on a Vault Job Processor and is triggered by a Vault file state transition.

## Prerequisites
The option **Enable Job Server** must be set in the **Job Server Management** in Vault and the installation explained below must be executed on a Job Processor machine.

The coolOrange products "powerJobs Processor" and "powerFLC" must be installed on the Job Processor machine. Both products can be downloaded from http://download.coolorange.com.

## Installation
1) Copy all files except this README.md file to "C:\ProgramData\coolOrange\powerJobs"
2) Open Autodesk Vault Explorer on the machine where powerJobs Processor and powerFLC is installed
3) Open the powerFLC Configuration Manager (Tools - powerFLC Configuration Manager)
4) Import the Workflow configuration file (json)

## Configuration
Once the Workflow configuration is imported, various settings can be adjusted:

### Workspace and Unique Fields
The selected **Workspace** is used to synchronize FLC items with Vault folders/projects. A field from this workspace must be choosen as Unique Identifier. Typically, this field contains the name of a project. The unique Vault Property defaults to **Name** and should not be changed.

### Settings
All Fusion Lifecycle items with a state selected in **Valid States** will be taken into consideration for the project synchronization. Items in a state other than the selected states won't be transferred.

The **Target Folder** in Vault is used as the root folder for the synchronization. All FLC items that are created as folder/project in Vault will be created in the selected Vault directory.
The selected **Folder Category** will be used as category of the folder/project in Vault.

If **Copy Folder Structure** is set to **True** the folder structure selected in **Folder Structure Template Path** from Vault will be copied to the newly created folder/project.

### Property Mapping
An "Item Field Mapping" is available. Values from the **Fusion Lifecycle** column will be copied to the Vault Folder UDPs choosen in the **Vault** column when a folder/project is created or updated.

### Polling
In order to query data periodically from FLC, Time triggered jobs are used. More information on this topic can found here: https://www.coolorange.com/wiki/doku.php?id=powerjobs_processor:jobprocessor:customization:trigger_jobs_to_a_certain_time

## Remarks:

 
## At your own risk
The usage of these samples is at your own risk. There is no free support related to the samples. However, if you have questions to powerJobs or powerFLC, then visit http://www.coolorange.com/wiki or start a conversation in our support forum at http://support.coolorange.com/support/discussions
