# Sample.SyncChangeOrderFiles

Change Order Workflow
The Change Management feature allows you to map Fusion 360 Manage Change Order states to Vault File Lifecycle states, managing approvals and signoff of vaulted designs from Fusion 360 Manage.
Note: The Change Order workflow pulls the states from Fusion 360 Manage Change Orders to Vault Files.
The Fusion 360 Manage workspace for change orders must contain items that are linked to items that were generated from the File BOM Transfer workflow.
Mechanism:
Polling of change order data from Fusion 360 Manage to Vault using Scheduled Jobs Job Type:
coolorange.flc.sync.changeorder
Attributes:
coolorange.flc.transfer.filebom.attributes

