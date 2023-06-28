<#
.Synopsis
Tests if an flc item's and vault item's mapped property values are equal

.Description
Compares the values of a vault item that are configured in mapping 'Vault Item -> FLC Item'
Compares the values of the item's primary associated file that are configured in mapping 'Vault primary Item-File Link -> FLC Item'
Returns $true if all values are equal and $false if any value differs

.Parameter VaultItem
Should be a powerVault item object

.Parameter FlcItem
Should be a powerPLM item object

.Example
if (-not (Test-FlcEqualsVaultItem -VaultItem $vaultItem -FlcItem $flcItem)) {
	Write-Host "Update item $($vaultItem."$($workflow.VaultUnique)")..."
	$flcItem = Update-FLCItem -Workspace $flcItem.Workspace -ItemId $flcItem.Id -Properties $properties -ErrorAction Stop
}
#>
function Test-FlcEqualsVaultItem {
	param (
		$VaultItem,
		$FlcItem
	)

	$mappingName = "Vault Item -> FLC Item"
	$flcPropertiesWithVaultValues = GetFlcProperties -MappingName $mappingName -Entity $VaultItem
	$mappings = $workflow.Mappings | Where-Object { $_.Name -eq $mappingName }
	foreach( $mapping in $mappings.FieldMappings.GetEnumerator() ) {
		$newFlcValue = $flcPropertiesWithVaultValues[$mapping.Flc]
		if($newFlcValue -is [DateTime]) {
			$newFlcValue = $newFlcValue.ToString("yyyy-MM-dd") #Fusion items might only store the date, but not the time
		}
		$currentFlcValue = $FlcItem.($mapping.Flc)
		if($currentFlcValue -is [DateTime]) {
			$currentFlcValue = $currentFlcValue.ToString("yyyy-MM-dd")
		}

		if("$newFlcValue" -ne "$currentFlcValue") { #casting both values to string to fix incorrect comparison when one value is $null and one is empty string
			return $false
		}
	}

	$primaryFile = (Get-VaultItemAssociations -Number $VaultItem._Number -Primary) | Select-Object -First 1
	$isPrimarySubcomponent = ($vault.ItemService.GetItemFileAssociationsByItemIds(@($VaultItem.Id), [Autodesk.Connectivity.Webservices.ItemFileLnkTypOpt]::PrimarySub)).FileName -contains $primaryFile.Name
	if (-not $isPrimarySubcomponent) {
		$mappingName = "Vault primary Item-File Link -> FLC Item"
		$flcPropertiesWithVaultValues = GetFlcProperties -MappingName $mappingName -Entity $primaryFile -Properties $flcPropertiesWithVaultValues
		$mappings = $workflow.Mappings | Where-Object { $_.Name -eq $mappingName }
		foreach( $mapping in $mappings.FieldMappings.GetEnumerator() ) {
			$newFlcValue = $flcPropertiesWithVaultValues[$mapping.Flc]
			if($newFlcValue -is [DateTime]) {
				$newFlcValue = $newFlcValue.ToString("yyyy-MM-dd") #Fusion items might only store the date, but not the time
			}
			$currentFlcValue = $FlcItem.($mapping.Flc)
			if($currentFlcValue -is [DateTime]) {
				$currentFlcValue = $currentFlcValue.ToString("yyyy-MM-dd")
			}
	
			if("$newFlcValue" -ne "$currentFlcValue") { #casting both values to string to fix incorrect comparison when one value is $null and one is empty string
				return $false
			}
		}
	}

	return $true
}