class ChangeOrderGroup {
	[string] $FlcWorkflowState
	[string] $VaultItemState
	[System.Collections.Generic.List[PsObject]] $FlcChangeOrders
	[System.Collections.Generic.List[PsObject]] $FlcAffectedItems

	ChangeOrderGroup($flcWorkFlowState, $vaultItemState) {
		$this.FlcWorkflowState = $flcWorkFlowState
		$this.VaultItemState = $vaultItemState
		$this.FlcChangeOrders = [System.Collections.Generic.List[PsObject]]::new()
		$this.FlcAffectedItems = [System.Collections.Generic.List[PsObject]]::new()
	}
}

Import-Module powerFLC

Open-VaultConnection

Write-Host "Starting job '$($job.Name)'..."

Write-Host "Connecting to Fusion Lifecycle..."

$powerFlcSettings = ConvertFrom-Json $vault.KnowledgeVaultService.GetVaultOption("POWERFLC_SETTINGS")
$workflow = $powerFlcSettings.Workflows | Where-Object { $_.Name -eq 'coolorange.flc.sync.changeorder.items' }
$tenant = $powerFlcSettings.Tenant

Connect-FLC -Tenant $tenant.Name -ClientId $tenant.ClientId -ClientSecret $tenant.ClientSecret -UserId $tenant.SystemUserEmail
Write-Host "Connected to $($flcConnection.Url)"

$workspace = $flcConnection.Workspaces | Where-Object { $_.Name -eq $workflow.FlcWorkspace }
Write-Host "Workspace: $($workspace.Name)"

$flcStates = $workflow.Settings | Where-Object { $_.Type -eq 'FLC State' } | Select-Object -ExpandProperty Value

# Create Changeorder groups
$flcStates = $workflow.Settings | Where-Object { $_.Type -eq 'FLC State' }
$vaultStates = $workflow.Settings | Where-Object { $_.Type -eq 'Vault Lifecycle State' }
$flcChangeOrderGroups = @{}
foreach($flcState in $flcStates) {
	$stateKey = $flcState.Name -split '_' | Select-Object -First 1
	$vaultState = $vaultStates | Where-Object { $_.Name -like "$($stateKey)_*" }
	$flcChangeOrderGroups.Add($flcState.Value, [ChangeOrderGroup]::new($flcState.Value, $vaultState.Value))
}

# Add Flc Changeorders to groups
$filter = 'workflowState = "{0}"' -f ($flcStates.Value -join '" OR "')
$flcChangeOrdersInValidState = Get-FLCItems -Workspace $workspace.Name -Filter $filter
foreach($flcChangeOrder in $flcChangeOrdersInValidState) {
	$flcChangeOrderGroups[$flcChangeOrder.WorkflowState].FlcChangeOrders += $flcChangeOrder
}

# Add affected items to groups
foreach($flcChangeOrderGroup in $flcChangeOrderGroups.Values) {
	foreach($flcChangeOrder in $flcChangeOrderGroup.FlcChangeOrders) {
		$flcChangeOrderGroup.FlcAffectedItems += Get-FLCItemAssociations -InputObject $flcChangeOrder -AffectedItems
	}
}

# Update Vault Items
foreach($flcChangeOrderGroup in $flcChangeOrderGroups.GetEnumerator()) {
	foreach($affectedFlcItem in $affectedFlcItems) {
		Update-VaultItem -Number $affectedFlcItem.($workflow.FlcUnique) -Status $flcChangeOrderGroup.VaultItemState
	}
}

Write-Host "Completed job '$($job.Name)'"
