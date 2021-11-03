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

		if(-not $hits) {
			Write-Host "Couldn't find any Vault items for number '$($number)'"
		}
		$totalHits += $hits
	}

	return $totalHits
}

Import-Module powerFLC
Write-Host "Starting job '$($job.Name)'..."

if(-not $iamrunningjobprocessor) {
	# Set by coolOrange.powerFLC.Workflows.Common/Open-VaultConnection when running in job processor
	Open-VaultConnection
	$powerFlcSettings = ConvertFrom-Json $vault.KnowledgeVaultService.GetVaultOption("POWERFLC_SETTINGS")
	$workflow = $powerFlcSettings.Workflows | Where-Object { $_.Name -eq 'coolorange.flc.sync.changeorder.items' }
	$tenant = $powerFlcSettings.Tenant
}

if($vault.KnowledgeVaultService.CheckRolePermissions(@('GetVaultOption', 'SetVaultOption')) -contains $false) {
	throw "The user '$($vaultConnection.UserName)' has no permission to execute GetVaultOption or SetVaultOption!"
}

Write-Host "Connecting to Fusion Lifecycle..."

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

$filter = '(workflowState = "{0}")' -f ($flcStates.Value -join '" OR "')
$lastCheck = $vault.KnowledgeVaultService.GetVaultOption('coolorange.flc.sync.changeorder.items_lastcheck')
if ($lastCheck) {
	$filter = "$filter AND (lastModifiedOn>=$lastCheck)"
}
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
	if($flcChangeOrderGroup.FlcAffectedItems.Count -le 0) { continue }
	
	$allLifeCycleDefs = $vault.LifeCycleService.GetAllLifeCycleDefinitions()
	$lifeCycleName = $workflow.Settings | Where-Object { $_.Name -eq 'ItemLifeCycle' } | Select-Object -ExpandProperty Value
	if(-not $lifeCycleName) {
		throw "Define a valid 'ItemLifeCycle' workflow setting!"
	}
	$lifeCycleDef = $allLifeCycleDefs | Where-Object { $_.DispName -eq $lifeCycleName }
	$lifecycleState = $lifecycleDef.StateArray | Where-Object { $_.DispName -eq $flcChangeOrderGroup.VaultItemState }
	
	$vaultItems = @()
	Write-Host "Getting Vault items"
	$affectedFlcItemsNumbers = @()
	foreach($affectedFlcItem in $flcChangeOrderGroup.FlcAffectedItems) {
		$affectedFlcItemsNumbers += $affectedFlcItem.($workflow.FlcUnique)
	}
	$vaultItems = Get-VaultItemsByNumbers -Numbers $affectedFlcItemsNumbers

	Write-Host "Filter out items that are in target state already"
	$vaultItemsNotInTargetState = $vaultItems | Where-Object { $_.LfCycStateId -ne $lifecycleState.Id }
	if(-not $vaultItemsNotInTargetState) {
		Write-Host "All items are in target state already."
		continue
	}

	Write-Host "Putting items into target state '$($vaultItems.VaultItemState)'"
	$vault.ItemService.UpdateItemLifeCycleStates(@($vaultItemsNotInTargetState.MasterId), @(1..$vaultItemsNotInTargetState.Count | ForEach-Object { $lifecycleState.Id }), "State changed by coolorange.flc.sync.changeorder.items")
}

$lastCheck = Get-Date -Format "yyyy-MM-dd"
$vault.KnowledgeVaultService.SetVaultOption('coolorange.flc.sync.changeorder.items_lastcheck', $lastCheck)

Write-Host "Completed job '$($job.Name)'"
