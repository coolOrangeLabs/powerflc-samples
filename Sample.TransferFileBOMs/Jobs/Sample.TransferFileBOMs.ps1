#==============================================================================#
# (c) 2020 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

Import-Module powerFLC

#region Load configuration
Write-Host "Starting job '$($job.Name)'..."
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "Connecting to Fusion 360 Manage..."
$connected = Connect-FLC
if (-not $connected) {
    throw "Connection to Fusion 360 Manage failed! Error: `n $($connected.Error.Message)`n See '$($env:LOCALAPPDATA)\coolOrange\powerFLC\Logs\powerFLC.log' for details"
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
foreach($fieldMapping in ($workflow.Mappings | Where-Object { $_.Name -eq "Vault File -> FLC Item" }).FieldMappings){
    if(-not ($fieldMapping.Flc -in $flcItemPropNames)){
        throw "'$($fieldMapping.Flc)' is not a valid FLC Item field in mapping: 'Vault File -> FLC Item'"
    }
	if($null -eq $fieldMapping.Function -and $null -eq $fieldMapping.Vault){
		throw "FLC Item field '$($fieldMapping.Flc)' is not mapped to Function or Vault Property in mapping: 'Vault File -> FLC Item'"
	}
}

if (-not $file."$($workflow.VaultUnique)") {
    throw "A file without $($workflow.VaultUnique) cannot be transferred to Fusion 360 Manage! (File: $($file._Name))"
}

$entityBomRows = Get-VaultFileBom -File $file._FullPath
foreach ($entityBomRow in $entityBomRows) {
    # if (-not $entityBomRow."$($workflow.VaultUnique)") {
    #     throw "A file without $($workflow.VaultUnique) cannot be transferred to Fusion 360 Manage! (File: $($entityBomRow._Name))"
    # }
    if (-not $entityBomRow.Bom_PositionNumber) {
        throw "A BOM with empty Position numbers cannot be transferred to Fusion 360 Manage! (File: $($entityBomRow._Name))"
    }
    if (-not [int]::TryParse($entityBomRow.Bom_PositionNumber, [ref] $null)) {
        throw "A BOM with Position number '$($entityBomRow.Bom_PositionNumber)' cannot be transferred to Fusion 360 Manage! The number must be numerical. (File: $($entityBomRow._Name))"
    }
}

$mergedBomRows = Merge-VaultBomRowsByNumber -EntityBomRows $entityBomRows
#endregion Load configuration

$allVaultEntities = @($file) + $mergedBomRows
$uniqueFlcField = $workspace.ItemFields.Find($workflow.FlcUnique)

#region Create or Update FLC items
Write-Host "Create or Update FLC items..."
$transferJobs = @()
foreach ($vaultEntity in $allVaultEntities) {
    if (-not $vaultEntity._Name) {
        # Virtual Component, no file representation in Vault!
        $vaultEntity | Add-Member -MemberType NoteProperty -Name $($workflow.VaultUnique) -Value $vaultEntity.'Bom_Part Number'
        $properties = @{ "$($workflow.FlcUnique)" = $vaultEntity.'Bom_Part Number' }
    } else {
        $properties = GetFlcProperties -MappingName "Vault File -> FLC Item" -Entity $vaultEntity        
    }

    $paramTransfer = [Hashtable]::Synchronized(@{})
    $paramTransfer.MainMasterId = $file.MasterId
    $paramTransfer.VaultEntity = $vaultEntity
    $paramTransfer.Properties = $properties
    $paramTransfer.Workspace = $workspace
    $paramTransfer.Workflow = $workflow
    $paramTransfer.FieldId = $uniqueFlcField.Id
    $paramTransfer.Host = $Host

    $transferJobs += {
        param ($flcConnection, [Hashtable]$parameters)
        $vaultEntity = $parameters.VaultEntity
        $properties = $parameters.Properties
        $workspace = $parameters.Workspace
        $workflow = $parameters.Workflow
        $uniqueFlcFieldId = $parameters.FieldId
        
        $flcItem = (Get-FLCItems -Workspace $workspace.Name -Filter ('ITEM_DETAILS:{0}="{1}"' -f $uniqueFlcFieldId, $vaultEntity."$($workflow.VaultUnique)"))[0]
        if (-not $flcItem) {
            $parameters.Host.UI.WriteLine("Create item $($vaultEntity."$($workflow.VaultUnique)")...")
            Write-Host "Create item $($vaultEntity."$($workflow.VaultUnique)")..."
            $flcItem = Add-FLCItem -Workspace $workspace.Name -Properties $properties -ErrorAction Stop
        }
        else {
            if ($parameters.MainMasterId -eq $vaultEntity.MasterId) {
                if ($vaultEntity.Version -ne $($flcItem.'File Version')) {
                    $parameters.Host.UI.WriteLine("Update item $($vaultEntity."$($workflow.VaultUnique)")...")
                    $flcItem = Update-FLCItem -Workspace $flcItem.Workspace -ItemId $flcItem.Id -Properties $properties -ErrorAction Stop
                } eles {
                    $parameters.Host.UI.WriteLine("File version is identical. No need to update item $($vaultEntity."$($workflow.VaultUnique)")...")
                }                
            }
        }
    
        $parameters.VaultEntity | Add-Member -MemberType NoteProperty -Name FlcItem -Value $flcItem
    
        $urn = "urn:adsk.plm:tenant.workspace.item:$($flcConnection.Tenant.ToUpper()).$($workspace.Id).$($flcItem.Id)"
        $vault.PropertyService.SetEntityAttribute($vaultEntity.MasterId, "FLC.ITEM", "Urn", $urn);
    } | InvokeAsync -Parameters $paramTransfer
}
WaitAll -Jobs $transferJobs

# foreach ($vaultEntity in $allVaultEntities) {
#     #TODO: async create/update missing items
#     $properties = GetFlcProperties -MappingName "Vault File -> FLC Item" -Entity $vaultEntity
#     $flcItem = (Get-FLCItems -Workspace $workspace.Name -Filter ('ITEM_DETAILS:{0}="{1}"' -f $uniqueFlcField.Id, $vaultEntity."$($workflow.VaultUnique)"))[0]
#     if (-not $flcItem) {
#         Write-Host "Create item $($vaultEntity."$($workflow.VaultUnique)")..."
#         $flcItem = Add-FLCItem -Workspace $workspace.Name -Properties $properties -ErrorAction Stop
#     }
#     else {
#         if ($vaultEntity.Version -ne $($flcItem.'File Version')) {
#             Write-Host "Update item $($vaultEntity."$($workflow.VaultUnique)")..."
#             $flcItem = Update-FLCItem -Workspace $flcItem.Workspace -ItemId $flcItem.Id -Properties $properties -ErrorAction Stop
#         }
#     }

#     $vaultEntity | Add-Member -MemberType NoteProperty -Name FlcItem -Value $flcItem

#     $urn = "urn:adsk.plm:tenant.workspace.item:$($tenant.Name.ToUpper()).$($workspace.Id).$($flcItem.Id)"
#     $vault.PropertyService.SetEntityAttribute($vaultEntity.MasterId, "FLC.ITEM", "Urn", $urn);
# }
#endregion Create or Update FLC items

#region Uploading Attachments
Write-Host "Uploading attachments..."
$fileAttachments = @()

if ($workflow.Settings.'Upload File Attachments') {
    $fileAttachments += Get-VaultFileAssociations -File $file._FullPath -Attachments
}

function GetParentDrawingFiles($file) {
    $attachments = @()
    $fileAssocArrays = $vault.DocumentService.GetLatestFileAssociationsByMasterIds(
        @($file.MasterId), [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::Dependency,
        $false, [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::None, $false,
        $false, $false, $false)

    if ($fileAssocArrays -and $fileAssocArrays[0].FileAssocs) {
        foreach ($fileAssoc in $fileAssocArrays[0].FileAssocs) {
            $extension = [System.IO.Path]::GetExtension($fileAssoc.ParFile.Name)
            if ($extension -and @(".idw", ".dwg") -contains $extension) {
                if ($fileAssoc.Typ -eq [Autodesk.Connectivity.WebServices.AssociationType]::Dependency) {
                    $parent = Get-VaultFile -FileId $fileAssoc.ParFile.Id
                    $attachments += $parent
                }
            }
        }
    }
    return $attachments
}

if ($workflow.Settings.'Upload Parent Drawing Attachments') {
    $files = GetParentDrawingFiles $file
    foreach($drawing in $files) {
        $fileAttachments += Get-VaultFileAssociations -File $drawing._FullPath -Attachments
    }
}

$downloadDirectory = Join-Path -Path "C:\Temp\" -ChildPath ([Guid]::NewGuid())
$uploadedFiles = @()
$uploadJobs = @()
foreach ($fileAttachment in $fileAttachments) {
    if (-not $uploadedFiles.Contains($fileAttachment._FullPath)) {
        Write-Host "Uploading '$($fileAttachment._Name)'..."
        $downloadedFiles = Save-VaultFile -File $fileAttachment._FullPath -DownloadDirectory $downloadDirectory
        $downloadedFile = $downloadedFiles | Select-Object -First 1

        $paramUpload = [Hashtable]::Synchronized(@{})
        $paramUpload.FlcItem = $file.FlcItem
        $paramUpload.LocalPath = $downloadedFile.LocalPath
        $paramUpload.Description = $downloadedFile._Description
        $uploadJobs += {
            param ($flcConnection, [Hashtable]$parameters)
            $fileName = Split-Path $parameters.LocalPath -leaf
            Add-FLCAttachment -InputObject $parameters.FlcItem -Path $parameters.LocalPath -Title $fileName -Description $parameters.Description
        } | InvokeAsync -Parameters $paramUpload

        $uploadedFiles += $downloadedFile._FullPath
    }
}
WaitAll -Jobs $uploadJobs
#endregion Uploading Attachments

#region Transfer BOM
Write-Host "Transfering BOM..."
$bomRows = @()

foreach ($mergedBomRow in $mergedBomRows) {
    $properties = @{
        "Bom_PositionNumber"   = (GetItemPositionNumber -Entity $mergedBomRow)
        "Workspace"            = $mergedBomRow.FlcItem.Workspace
        "Id"                   = $mergedBomRow.FlcItem.Id
        "Bom_Quantity"         = $mergedBomRow.Bom_ItemQuantity
        #"Bom_Qty Pos"          = $mergedBomRow.Bom_Quantity
        #"Bom_Row Order"        = $mergedBomRow.Bom_RowOrder
        "Bom_$($bomFieldName)" = $bomFieldValue
    }

    $bomRows += $properties
}

$existingBomRows = $file.FlcItem | Get-FLCBOM
$manualBomRows = @($existingBomRows | Where-Object { $_."Bom_$($bomFieldName)" -ne $bomFieldValue })
foreach ($manualBomRow in $manualBomRows) {
    $bomRows += $manualBomRow
}

$flcBom = $file.FlcItem | Update-FLCBOM -Rows $bomRows -ErrorAction Stop
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
            $properties = @{
                "Row Order"                = $entityBomRow.Bom_RowOrder
                "Pos Nr"                   = (GetItemPositionNumber -Entity $entityBomRow)
                "Number"                   = $entityBomRow."$($workflow.VaultUnique)"
                "Quantity (Numeric Value)" = $entityBomRow.Bom_Quantity
                "Item Qty"                 = $entityBomRow.Bom_ItemQuantity
                "Title"                    = $entityBomRow._Title
                "Revision"                 = $entityBomRow._Revision
            }

            $rows += $properties
        }

        $gridIdField = "Pos Nr"
        $file.FlcItem | Update-FLCGrid -Rows $rows -UniqueField $gridIdField
    }
    else {
        Write-Host "Part List Details data is identical to BOM data and won't be transferred!"
    }
}
#endregion Part List Details Grid

CleanupWorkingDirectory -Folder $downloadDirectory

$stopwatch.Stop()
Write-Host "Completed job '$($job.Name)' in $([int]$stopwatch.Elapsed.TotalSeconds) Seconds"