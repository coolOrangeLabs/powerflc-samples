class ChangeOrderGroup {
	[string] $FlcWorkflowState
	[string] $VaultItemState
	[PsObject] $FlcChangeOrder
	[System.Collections.Generic.List[PsObject]] $FlcAffectedItems

	ChangeOrderGroup($flcChangeOrder, $flcWorkFlowState, $vaultItemState) {
		$this.FlcChangeOrder = $flcChangeOrder
		$this.FlcWorkflowState = $flcWorkFlowState
		$this.VaultItemState = $vaultItemState
		$this.FlcAffectedItems = [System.Collections.Generic.List[PsObject]]::new()
	}
}

Import-Module powerFLC

Write-Host "Starting job '$($job.Name)'..."

Write-Host "Connecting to Fusion Lifecycle..."

if(-not $iamrunningjobprocessor) {
	# Set by coolOrange.powerFLC.Workflows.Common/Open-VaultConnection when running in job processor
	Open-VaultConnection
	$powerFlcSettings = ConvertFrom-Json $vault.KnowledgeVaultService.GetVaultOption("POWERFLC_SETTINGS")
	$workflow = $powerFlcSettings.Workflows | Where-Object { $_.Name -eq 'coolorange.flc.sync.changeorder.items' }
	$tenant = $powerFlcSettings.Tenant
}

Connect-FLC -Tenant $tenant.Name -ClientId $tenant.ClientId -ClientSecret $tenant.ClientSecret -UserId $tenant.SystemUserEmail
Write-Host "Connected to $($flcConnection.Url)"

$workspace = $flcConnection.Workspaces | Where-Object { $_.Name -eq $workflow.FlcWorkspace }
Write-Host "Workspace: $($workspace.Name)"


Write-Host "Create change order groups"
$flcStates = $workflow.Settings | Where-Object { $_.Type -eq 'FLC State' }
if(-not $flcStates) {
	throw "Define at least one 'FLC State' setting"
}
$vaultStates = $workflow.Settings | Where-Object { $_.Type -eq 'Vault Lifecycle State' }
if(-not $flcStates) {
	throw "Define at least one 'Vault Lifecycle State' setting"
}

Write-Host "Add Flc change orders to change order groups"
$isSyncedToVaultPropertyName = $workflow.Settings | Where-Object { $_.Name -eq 'IsSyncedToVaultProperty' } | Select-Object -ExpandProperty Value
$isSyncedToVaultProperty = $workspace.ItemFields.Find($isSyncedToVaultPropertyName)
$filter = '(ITEM_DETAILS:{0} = True) AND (workflowState = "{1}")' -f $isSyncedToVaultProperty.Id, ($flcStates.Value -join '" OR "')

$flcChangeOrdersInValidState = Get-FLCItems -Workspace $workspace.Name -Filter $filter

if(-not $flcChangeOrdersInValidState) { 
	Write-Host "Completed job '$($job.Name)'"
	return 
}

$flcChangeOrderGroups = @()
foreach($flcChangeOrder in $flcChangeOrdersInValidState) {
	$flcState = $flcStates | Where-Object { $_.Value -eq $flcChangeOrder.WorkflowState }
	$vaultState = $vaultStates | Where-Object { $_.Name -eq $flcState.Name }
	$flcChangeOrderGroups += [ChangeOrderGroup]::new($flcChangeOrder, $flcChangeOrder.WorkflowState, $vaultState.Value)
}

Write-Host "Add affected items to change order groups"
foreach($flcChangeOrderGroup in $flcChangeOrderGroups) {
		Write-Host "Title: $($flcChangeOrder.Title) Workspace: $($flcChangeOrderGroup.FlcChangeOrder.Workspace)"
		$affectedFlcItems = Get-FLCItemAssociations -Workspace $flcChangeOrderGroup.FlcChangeOrder.Workspace -ItemId $flcChangeOrderGroup.FlcChangeOrder.Id -AffectedItems
		if(-not $affectedFlcItems) { continue }

		$flcChangeOrderGroup.FlcAffectedItems += $affectedFlcItems
}

Write-Host "Update Vault items"
foreach($flcChangeOrderGroup in $flcChangeOrderGroups) {
	if(-not $flcChangeOrderGroup.FlcAffectedItems) { continue }
	
	$allLifeCycleDefs = $vault.LifeCycleService.GetAllLifeCycleDefinitions()
	$lifeCycleName = $workflow.Settings | Where-Object { $_.Name -eq 'ItemLifeCycle' } | Select-Object -ExpandProperty Value
	if(-not $lifeCycleName) {
		throw "Define a valid 'ItemLifeCycle' workflow setting!"
	}
	$lifeCycleDef = $allLifeCycleDefs | Where-Object { $_.DispName -eq $lifeCycleName }
	$lifecycleState = $lifecycleDef.StateArray | Where-Object { $_.DispName -eq $flcChangeOrderGroup.VaultItemState }
	
	$vaultItems = @()
	Write-Host "Getting Vault items"
	foreach($number in @($flcChangeOrderGroup.FlcAffectedItems.($workflow.FlcUnique))) {
		Write-Host "Searching for item '$number'"
		$vaultItems += $vault.ItemService.GetLatestItemByItemNumber($number)
	}

	Write-Host "Filter out items that are in target state already"
	$vaultItemsNotInTargetState = $vaultItems | Where-Object { $_.LfCycStateId -ne $lifecycleState.Id }
	if(-not $vaultItemsNotInTargetState) {
		Write-Host "All items are in target state already. Exit job."
		continue
	}

	Write-Host "Putting items into target state '$($vaultItems.VaultItemState)'"
	$vault.ItemService.UpdateItemLifeCycleStates(@($vaultItemsNotInTargetState.MasterId), @(1..$vaultItemsNotInTargetState.Count | ForEach-Object { $lifecycleState.Id }), "State changed by coolorange.flc.sync.changeorder.items")
}

Write-Host "Completed job '$($job.Name)'"
