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

function Get-VaultItemsByNumbers {
	param ([string[]] $Numbers)

	$totalHits = @()
	foreach($number in $Numbers) {
		$searchConditions = New-Object Autodesk.Connectivity.WebServices.SrchCond
		$searchConditions.PropDefId = 56
		$searchConditions.PropTyp = [Autodesk.Connectivity.Webservices.PropertySearchType]::SingleProperty
		$searchConditions.SrchOper = 3
		$searchConditions.SrchRule = [Autodesk.Connectivity.WebServices.SearchRuleType]::Must
		$searchConditions.SrchTxt = $number
		
		$sortConditions = $null
		$requestLatestOnly = $true
		$bookmark = $null
		$searchstatus = $null
		
		$hits = @()
		Write-Host "Searching item '$number'"
		do {
			[array]$hits += $vault.ItemService.FindItemRevisionsBySearchConditions($searchConditions, $sortConditions, $requestLatestOnly, [ref]$bookmark,[ref]$searchstatus)
		} while($hits.Count -lt $searchstatus.TotalHits)
		$totalHits += $hits
	}

	return $totalHits
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
$flcChangeOrderGroups = @{}
foreach($flcState in $flcStates) {
	$stateKey = $flcState.Name -split '_' | Select-Object -First 1
	$vaultState = $vaultStates | Where-Object { $_.Name -like "$($stateKey)_*" }
	$flcChangeOrderGroups.Add($flcState.Value, [ChangeOrderGroup]::new($flcState.Value, $vaultState.Value))
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

foreach($flcChangeOrder in $flcChangeOrdersInValidState) {
	$flcChangeOrderGroups[$flcChangeOrder.WorkflowState].FlcChangeOrders += $flcChangeOrder
}

Write-Host "Add affected items to change order groups"
foreach($flcChangeOrderGroup in $flcChangeOrderGroups.Values) {
	foreach($flcChangeOrder in $flcChangeOrderGroup.FlcChangeOrders) {
		Write-Host "Title: $($flcChangeOrder.Title) Workspace: $($flcChangeOrder.Workspace)"
		$affectedFlcItems = Get-FLCItemAssociations -Workspace $flcChangeOrder.Workspace -ItemId $flcChangeOrder.Id -AffectedItems
		if(-not $affectedFlcItems) { continue }

		$flcChangeOrderGroup.FlcAffectedItems += $affectedFlcItems
	}
}

Write-Host "Update Vault items"
foreach($flcChangeOrderGroup in $flcChangeOrderGroups.Values) {
	if(-not $flcChangeOrderGroup.FlcAffectedItems) { continue }
	
	$allLifeCycleDefs = $vault.LifeCycleService.GetAllLifeCycleDefinitions()
	$lifeCycleName = $workflow.Settings | Where-Object { $_.Name -eq 'ItemLifeCycle' } | Select-Object -ExpandProperty Value
	if(-not $lifeCycleName) {
		throw "Define a valid 'ItemLifeCycle' workflow setting!"
	}
	$lifeCycleDef = $allLifeCycleDefs | Where-Object { $_.DispName -eq $lifeCycleName }
	$lifecycleState = $lifecycleDef.StateArray | Where-Object { $_.DispName -eq $flcChangeOrderGroup.VaultItemState }
	
	$vaultItems = Get-VaultItemsByNumbers -Numbers @($flcChangeOrderGroup.FlcAffectedItems.($workflow.FlcUnique))
	$vaultItemsNotInTargetState = $vaultItems | Where-Object { $_.LfCycStateId -ne $lifecycleState.Id }
	if(-not $vaultItemsNotInTargetState) {
		continue
	}

	$vault.ItemService.UpdateItemLifeCycleStates(@($vaultItemsNotInTargetState.MasterId), @(1..$vaultItemsNotInTargetState.Count | ForEach-Object { $lifecycleState.Id }), "State changed by coolorange.flc.sync.changeorder.items")
}

Write-Host "Completed job '$($job.Name)'"
