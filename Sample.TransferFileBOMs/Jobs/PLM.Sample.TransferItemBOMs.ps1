#==============================================================================#
# (c) 2022 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

# Required in the powerJobs Settings Dialog to determine the entity type for lifecycle state change triggers
# JobEntityType = ITEM

Import-Module powerFLC

#region Load configuration
Write-Host "Starting job '$($job.Name)'..."
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Connecting to Fusion Lifecycle..."
$connected = Connect-FLC
if (-not $connected) {
    throw "Connection to Fusion Lifecycle failed! Error: `n $($connected.Error.Message)`n See '$($env:LOCALAPPDATA)\coolOrange\powerFLC\Logs\powerFLC.log' for details"
}

if (-not $workflow) {
    throw "Cannot find workflow configuration with name '$($job.Name)'"
}

$workspace = $flcConnection.Workspaces.Find($workflow.FlcWorkspace)
if (-not $workspace) {
    throw "Workspace $($workflow.FlcWorkspace) cannot be found!"
}
Write-Host "Connected to $($flcConnection.Url) - Workspace: $($workspace.Name)"

$bomFieldName = $workflow.Settings.'BOM-Source Field'
$bomFieldValue = $workflow.Settings.'BOM-Source Value'
$bomField = $workspace.BomFields | Where-Object { $_.Name -eq $bomFieldName }
if (-not $bomField) {
    throw "A field '$($bomFieldName)' needs to be configured in FLC workspace '$($workspace.Name)'!"
}

$flcItemPropNames = $workspace.ItemFields | Select-Object -ExpandProperty "Name"
foreach($fieldMapping in ($workflow.Mappings | Where-Object { $_.Name -eq "Vault Item -> FLC Item" }).FieldMappings){
    if(-not ($fieldMapping.Flc -in $flcItemPropNames)){
        throw "'$($fieldMapping.Flc)' is not a valid FLC Item field in mapping: 'Vault Item -> FLC Item'"
    }
	if($null -eq $fieldMapping.Function -and $null -eq $fieldMapping.Vault){
		throw "FLC Item field '$($fieldMapping.Flc)' is not mapped to Function or Vault Property in mapping: 'Vault Item -> FLC Item'"
	}
}

$flcBomPropNames = $workspace.BomFields | Select-Object -ExpandProperty "Name"
foreach($fieldMapping in ($workflow.Mappings | Where-Object { $_.Name -eq "Vault BOM -> FLC BOM" }).FieldMappings){
    if(-not ($fieldMapping.Flc -in $flcBomPropNames)){
        throw "'$($fieldMapping.Flc)' is not a valid FLC bom field in mapping: 'Vault BOM -> FLC BOM'"
    }
	if($null -eq $fieldMapping.Function -and $null -eq $fieldMapping.Vault){
		throw "FLC BOM field '$($fieldMapping.Flc)' is not mapped to Function or Vault Property in mapping: 'Vault BOM -> FLC BOM'"
	}
}

$entityBomRows = Get-VaultItemBom -Number $item._Number
foreach ($entityBomRow in $entityBomRows) {
    if (-not $entityBomRow.Bom_PositionNumber) {
        throw "A BOM with empty Position numbers cannot be transferred to Fusion Lifecycle!"
    }
    if (-not [int]::TryParse($entityBomRow.Bom_PositionNumber, [ref] $null)) {
        throw "A BOM with Position number '$($entityBomRow.Bom_PositionNumber)' cannot be transferred to Fusion Lifecycle! The number must be numerical"
    }
}

Add-ItemAssocPropertiesToBomRows -ParentItem $item -ItemBomRows $entityBomRows
$mergedBomRows = Merge-VaultBomRowsByNumber -EntityBomRows $entityBomRows
#endregion Load configuration

$allVaultItems = @($item) + $mergedBomRows
$uniqueFlcField = $workspace.ItemFields.Find($workflow.FlcUnique)

#region Create or Update FLC items
Write-Host "Create or Update FLC items..."
foreach ($vaultItem in $allVaultItems) {
    #TODO: async create/update missing items
    $properties = GetFlcProperties -MappingName "Vault Item -> FLC Item" -Entity $vaultItem

    $primaryFile = (Get-VaultItemAssociations -Number $vaultItem._Number -Primary) | Select-Object -First 1
    $isPrimarySubcomponent = ($vault.ItemService.GetItemFileAssociationsByItemIds(@($vaultItem.Id), [Autodesk.Connectivity.Webservices.ItemFileLnkTypOpt]::PrimarySub)).FileName -contains $primaryFile.Name
    if (-not $isPrimarySubcomponent) {
        $properties = GetFlcProperties -MappingName "Vault primary Item-File Link -> FLC Item" -Entity $primaryFile -Properties $properties
    }

    $flcItem = (Get-FLCItems -Workspace $workspace.Name -Filter ('ITEM_DETAILS:{0}="{1}"' -f $uniqueFlcField.Id, $vaultItem."$($workflow.VaultUnique)"))[0]
    if (-not $flcItem) {
        Write-Host "Create item $($vaultItem."$($workflow.VaultUnique)")..."
        $flcItem = Add-FLCItem -Workspace $workspace.Name -Properties $properties -ErrorAction Stop
    }
    else {        
        [Autodesk.Connectivity.WebServices.EntAttr[]]$itemAttribs = $vault.PropertyService.GetEntityAttributes($item.MasterId, 'FLC.ITEM') | Where-Object {$_.Attr -eq 'Urn'}
        [datetime]$plmItemLastUpdate = $itemAttribs.UpdateDateTime #Vault entity attributes UpdateTime = UTC time
        $timeDiff = New-TimeSpan -start $plmItemLastUpdate -End $vaultItem._ModDate.ToUniversalTime() #Vault display time includes computer's time zone conversion
        if ($timeDiff.TotalSeconds -gt 0) {
            <# Vault item is newer, F3M needs updating #>
            Write-Host "Update item $($vaultItem."$($workflow.VaultUnique)")..."
            $flcItem = Update-FLCItem -Workspace $flcItem.Workspace -ItemId $flcItem.Id -Properties $properties -ErrorAction Stop    
        }
    }

    $vaultItem | Add-Member -MemberType NoteProperty -Name FlcItem -Value $flcItem

    $urn = "urn:adsk.plm:tenant.workspace.item:$($flcConnection.Tenant.ToUpper()).$($workspace.Id).$($flcItem.Id)"
    $vault.PropertyService.SetEntityAttribute($vaultItem.MasterId, "FLC.ITEM", "Urn", $urn);
}
#endregion Create or Update FLC items

#region Uploading Attachments
Write-Host "Uploading attachments..."
$fileAttachments = @()

if ($workflow.Settings.'Upload Item Attachments') {
    $fileAttachments += Get-VaultItemAssociations -Number $item._Number -Attachments
}

if ($workflow.Settings.'Upload Composition Attachments') {
    $files = Get-VaultItemAssociations -Number $item._Number -Primary
    $assocs = $vault.ItemService.GetItemFileAssociationsByItemIds(@($item.Id), [Autodesk.Connectivity.Webservices.ItemFileLnkTypOpt]::PrimarySub)
    foreach ($file in $files) {
        if ($assocs.FileName -contains $file.Name) { continue }
        $fileAttachments += Get-VaultFileAssociations -File $file._FullPath -Attachments
    }
}

if ($workflow.Settings.'Upload Design Document Attachments') {
    $files = Get-VaultItemAssociations -Number $item._Number -Tertiaries
    foreach ($file in $files) {
        $fileAttachments += Get-VaultFileAssociations -File $file._FullPath -Attachments
    }
}

if ($workflow.Settings.'Upload Design Document DWGs') {
    $files = Get-VaultItemAssociations -Number $item._Number -Tertiaries
    foreach ($file in $files) {
        if ($file._Extension -eq "DWG") {
            $fileAttachments += $file
        }
    }
}

$downloadDirectory = Join-Path -Path "C:\Temp\" -ChildPath ([Guid]::NewGuid())
$uploadedFiles = @()
$uploadJobs = @()
foreach ($fileAttachment in $fileAttachments) {
    if (-not $uploadedFiles.Contains($fileAttachment._FullPath)) {
        Write-Host "Uploading '$($fileAttachment._Name)'..."
        $downloadedFiles = Save-VaultFile -File $fileAttachment._FullPath -DownloadDirectory $downloadDirectory
        $file = $downloadedFiles | Select-Object -First 1

        $paramUpload = [Hashtable]::Synchronized(@{})
        $paramUpload.FlcItem = $item.FlcItem
        $paramUpload.LocalPath = $file.LocalPath
        $paramUpload.Description = $file._Description
        $uploadJobs += {
            param ($flcConnection, [Hashtable]$parameters)
            $fileName = Split-Path $parameters.LocalPath -leaf
            Add-FLCAttachment -InputObject $parameters.FlcItem -Path $parameters.LocalPath -Title $fileName -Description $parameters.Description
        } | InvokeAsync -Parameters $paramUpload

        $uploadedFiles += $file._FullPath
    }
}
WaitAll -Jobs $uploadJobs
#endregion Uploading Attachments


#region Transfer BOM
Write-Host "Transfering BOM..."
$bomRows = @()

foreach ($mergedBomRow in $mergedBomRows) {
    if ($workflow.Settings.'Use RowOrder as BOM Position' -eq $true) {
        $positionNumber = $mergedBomRow.Bom_RowOrder
    }
    else {
        $positionNumber = (GetItemPositionNumber -Entity $mergedBomRow)
    }

    $properties = @{
        "Bom_PositionNumber"   = $positionNumber
        "Workspace"            = $mergedBomRow.FlcItem.Workspace
        "Id"                   = $mergedBomRow.FlcItem.Id
        "Bom_Quantity"         = $mergedBomRow.Bom_InstCount
        "Bom_$($bomFieldName)" = $bomFieldValue
    }

    $mappedProperties = GetFlcProperties -MappingName "Vault BOM -> FLC BOM" -Entity $mergedBomRow
    foreach ($mappedProperty in $mappedProperties.GetEnumerator()) {
        if (-not $properties.ContainsKey("Bom_" + $mappedProperty.Key)) {
            $properties.Add("Bom_" + $mappedProperty.Key, $mappedProperty.Value)
        }
    }

    $bomRows += $properties
}

$existingBomRows = $item.FlcItem | Get-FLCBOM
$manualBomRows = @($existingBomRows | Where-Object { $_."Bom_$($bomFieldName)" -ne $bomFieldValue })
foreach ($manualBomRow in $manualBomRows) {
    $bomRows += $manualBomRow
}

$flcBom = $item.FlcItem | Update-FLCBOM -Rows $bomRows -ErrorAction Stop
#endregion Transfer BOM


#region Part List Details Grid
if ($workflow.Settings.'Enable Grid Transfer') {
    Write-Host "Transfering Part List Details..."

    $transferGrid = $true
    if ($workflow.Settings.'Transfer Grid only if BOM is merged') {
        $transferGrid = ($mergedBomRows.Count -ne $entityBomRows.Count)
    }

    if ($transferGrid) {
        $rows = @()
        foreach ($entityBomRow in $entityBomRows) {
            $properties = GetFlcProperties -MappingName "Vault BOM -> FLC Grid" -Entity $entityBomRow
            $rows += $properties
        }

        $gridIdField = "Pos Nr"
        $item.FlcItem | Update-FLCGrid -Rows $rows -UniqueField $gridIdField
    }
    else {
        Write-Host "Part List Details data is identical to BOM data and won't be transferred!"
    }
}
#endregion Part List Details Grid

CleanupWorkingDirectory -Folder $downloadDirectory

$stopwatch.Stop()
Write-Host "Completed job '$($job.Name)' in $([int]$stopwatch.Elapsed.TotalSeconds) Seconds"