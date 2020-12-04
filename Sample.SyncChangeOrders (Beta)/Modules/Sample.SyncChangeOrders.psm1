Import-Module powerVault

#override Clean-Up Cmdlet because of issues deleting empty folder
function Clean-Up {
    param(
        [string]$folder = $null,
        $files = @()
    )
    function Remove-EmptyFolders($folder) {
        $folders = @($folder, (Get-ChildItem $folder -Recurse))
        $folders = @($folders | Where { $_.PSIsContainer -and @(Get-ChildItem -LiteralPath $_.Fullname -Recurse | Where { -not $_.PSIsContainer }).Count -eq 0 })
        Remove-Items $folders      
    }    
    function Remove-Items($items) {
        $items | foreach { Remove-Item -Path $_.FullName -Force -Recurse -confirm:$false -ErrorAction SilentlyContinue }
    }
    
    $files = @($files | foreach { 
            if ($_.GetType() -eq [string]) { Get-Item $_ -ErrorAction SilentlyContinue }
            elseif ($_.GetType() -eq [System.IO.FileInfo]) { $_ }
            else { Get-Item $_.LocalPath -ErrorAction SilentlyContinue }    
        })
    
    if (-not $files -and $folder) {
        $files = Get-ChildItem $folder -Recurse
    }
    
    if ($files) {
        Remove-Items $files
    }
        
    if ( -not $folder -and $files.Count -gt 0 ) {
        $folder = $files[0]
        while ( $true ) {          
            if (-not ($folder = Split-Path $folder)) {
                throw('No folder found')
            }
            
            if (($files | where { (Split-Path $_).StartsWith($folder) }).Count -eq $files.Count) {
                break;
            }
        }
    }
    if (Test-Path $folder) {
        Remove-EmptyFolders (Get-Item $folder)
    }
}

function GetViewFromUrn($urn) {
    if (-not $urn) { return "" }
    $contents = $urn.Split(':');
    $values = $contents[$contents.Length - 1].Split('.')
    $names = $contents[$contents.Length - 2].Split('.')
    return $values[[array]::IndexOf($names, "view")];
}

function GetItemFromUrn($urn) {
    if (-not $urn) { return "" }
    $contents = $urn.Split(':');
    $values = $contents[$contents.Length - 1].Split('.')
    $names = $contents[$contents.Length - 2].Split('.')
    return $values[[array]::IndexOf($names, "item")];
}

function GetViewFromUrn($urn) {
    if (-not $urn) { return "" }
    $contents = $urn.Split(':');
    $values = $contents[$contents.Length - 1].Split('.')
    $names = $contents[$contents.Length - 2].Split('.')
    return $values[[array]::IndexOf($names, "view")];
}

function GetWorkspaceFromUrn($urn) {
    if (-not $urn) { return "" }
    $contents = $urn.Split(':');
    $values = $contents[$contents.Length - 1].Split('.')
    $names = $contents[$contents.Length - 2].Split('.')
    return $values[[array]::IndexOf($names, "workspace")];
}

function GetVaultProperties($mappingName, $flcItem) {
    $mapping = $workflow.Mappings | Where-Object { $_.Name -eq $mappingName }
    if (-not $mapping) {
        throw "Cannot find mapping configuration for mapping '$mappingName'"
    }

    $properties = @{}
    foreach ($fieldMapping in $mapping.FieldMappings) {
        if ($fieldMapping.Function) {
            continue
        }
        else {
            $propName = $fieldMapping.Flc
            $value = $flcItem.$propName
        }
        if ($value -and $value.GetType() -eq [Autodesk.DataManagement.Client.Framework.Vault.Currency.Properties.ThumbnailInfo]) {
            continue
        }
        $properties.Add($fieldMapping.Vault, $value) | Out-Null
    }
    return $properties
}

function New-ChangeOrder {
    param (
        $Workflowname,
        $RoutingName,
        $ChangeOrderName,
        $Title,
        $Description,
        $SchemeName,
        [PSDefaultValue(Help = "Today")]
        [DateTime]$ApprovedDeadLine = $(Get-Date),
        $ItemMasterIds,
        $ItemNumbers,
        $FileMasterIds,
        $FullFileNames,
        $AttachmentFileMasterIds, #Vault API incorrectly documents to expect Ids instead of MasterIds for file attachments
        $AttachmentFullFileNames, #Array of Absolute vault File path to a files to be attached to the current ChangeOrder
        $LinkedProperties,
        $Properties,
        $Emails
    )
    try {
        #workflow and routing
        [Autodesk.Connectivity.WebServices.Workflow]$workflow = GetWorkflow($workflowname)
        if ($workflow) {
            $routing = GetRouting $workflow.Id $routingName
        }
        if (-not $routing) {
            throw "ERROR: Not found any routing with the name - $($routingName)"
        }


        #items
        if (-not $ItemMasterIds) {
            if ($ItemNumbers) {
                foreach ($itemNumber in $ItemNumbers) {
                    $item = $vault.ItemService.GetLatestItemByItemNumber($itemNumber)
                    $ItemMasterIds += $item.MasterId
                }
            }
        }
        
        #files
        if (-not $FileMasterIds) {
            if ($FullFileNames) {
                $files = $vault.DocumentService.FindLatestFilesByPaths($FullFileNames)
                $FileMasterIds = $files.MasterId
            }
        }
        

        #Attachments
        if (-not $AttachmentFileMasterIds) {
            if ($AttachmentFullFileNames) {
                $Attachfiles = $vault.DocumentService.FindLatestFilesByPaths($AttachmentFullFileNames)
                $AttachmentFileMasterIds = $Attachfiles.MasterId
            }
        }

        #properties
        if ($properties) {
            $propinsts = GetProperties($properties)
        }
        
        if (-not $changeOrderName) {
            $changeOrderNumberingScheme = GetChangeOrderNumberingScheme($schemeName)
            if (-not $changeOrderNumberingScheme) {
                throw "ERROR: Couldn't find numbering scheme - $($schemeName)"
            }
            $changeOrderName = $vault.ChangeOrderService.GetChangeOrderNumberBySchemeId($changeOrderNumberingScheme.SchmID)
        }
        #AssociatedProperties
        if ($LinkedProperties) {
            $AssociatedProperties = GetAssociatedProperties($LinkedProperties)
        }

        return $vault.ChangeOrderService.AddChangeOrder(
            $routing.Id,
            $ChangeOrderName, 
            $Title, 
            $Description,
            $ApprovedDeadLine,
            $ItemMasterIds,
            $AttachmentFileMasterIds,
            $FileMasterIds,
            $propinsts,
            $AssociatedProperties,
            $null,
            $Emails)
    }
    catch {
        if ($Error[0].Exception.InnerException -eq "303") {
            throw "ERROR: Permission denied for user $($vaultConnection.UserName)"
        }
        if ($Error[0].Exception.InnerException -eq "1612") {
            throw "ERROR: The item is being managed by another change order"
        }
        else {
            throw "ERROR: $($Error[0])"
        }
    }
}

function Edit-ChangeOrder {
    param (
        [Parameter(Mandatory = $true)]
        $ChangeOrderName,
        $Title,
        $Description,
        [PSDefaultValue(Help = "Today")]
        [DateTime]$ApprovedDeadLine = $(Get-Date),
        $ItemMasterIds, #Array of Item MasterId to add or remove      
        $ItemsNumbers, #Array of Item numbers to add or remove
        $FileMasterIds, #Array of File's MasterId to add or remove
        $FullFileNames, #Array of File's FullFileName in Vault to add or remove
        $AttachmentFileMasterIds, #Array of Files MasterId to attach or remove
        $AttachmentFullFileNames, #Array of File's FullFileName in Vault to attach or remove
        $LinkedProperties,
        $Properties
    )
    try {
        #items
        if (-not $ItemMasterIds) {
            foreach ($itemNumber in $ItemsNumbers) {
                $item = $vault.ItemService.GetLatestItemByItemNumber($itemNumber)
                $ItemMasterIds += $item.MasterId
            }
        }
        #Attachments
        if (-not $AttachmentFileMasterIds) {
            if ($AttachmentFullFileNames) {
                $files = $vault.DocumentService.FindLatestFilesByPaths($AttachmentFullFileNames)           
                $files | foreach { $AttachmentFileMasterIds += $_.MasterId }
            }
        }
        #files
        if (-not $FileMasterIds) {
            if ($FullFileNames) {
                $files = $vault.DocumentService.FindLatestFilesByPaths($FullFileNames)           
                $files | foreach { $FileMasterIds += $_.MasterId }
            }
        }
        #properties
        if ($properties) {
            $propinsts = GetProperties($properties)
        }

        #AssociatedProperties
        if ($LinkedProperties) {
            $AssociatedProperties = GetAssociatedProperties($LinkedProperties)
        }

        $changeOrder = $vault.ChangeOrderService.GetChangeOrderByNumber($ChangeOrderName)
        $changeOrderGroup = $vault.ChangeOrderService.GetChangeOrderGroupByChangeOrderId($changeOrder.Id)
        if ($changeOrderGroup.ItemIdArray) {
            $items = $vault.ItemService.GetItemsByIds($changeOrderGroup.ItemIdArray)
        }
        if ($changeOrderGroup.AttmtIdArray) {
            $attachedfiles = $vault.DocumentService.GetFilesByIds($changeOrderGroup.AttmtIdArray)
        }
        if ($changeOrderGroup.FileIdArray) {
            $files = $vault.DocumentService.GetFilesByIds($changeOrderGroup.AttmtIdArray)
        }

        if ($ItemMasterIds)  {
            $ItemMasterIdsToAdd = $ItemMasterIds |  Where-Object { $items.MasterId -notcontains $_}  
            $ItemMasterIdsToRemove = $items.MasterId | Where-Object { $ItemMasterIds -notcontains $_} 
        }
        if ($AttachmentFileMasterIds)  {
            $FileMasterIdsToAttach = $AttachmentFileMasterIds |  Where-Object { $attachedfiles.MasterId -notcontains $_}  
            $FileMasterIdsToDettach = $attachedfiles.MasterId | Where-Object { $AttachmentFileMasterIds -notcontains $_} 
        }
        if ($FileMasterIds)  {
            $FileMasterIdsToAdd = $FileMasterIds |  Where-Object { $files.MasterId -notcontains $_}  
            $FileMasterIdsToRemove = $files.MasterId | Where-Object { $FileMasterIds -notcontains $_} 
        }
        $editChangeOrder = $vault.ChangeOrderService.EditChangeOrder($ChangeOrder.Id)
        return $vault.ChangeOrderService.UpdateChangeOrder($editChangeOrder.Id, $ChangeOrderName, $Title, $Description, $ApprovedDeadLine, $ItemMasterIdsToAdd, $ItemMasterIdsToRemove, $FileMasterIdsToAttach, $FileMasterIdsToDettach, $FileMasterIdsToAdd, $FileMasterIdsToRemove, $propinsts, $null, $null, $null, $AssociatedProperties, $null, -1, $null, $null)
    }
    catch {
        if ($Error[0].Exception.InnerException -eq "1608") {
            throw "ERROR: Could not find the specified change order - $($ChangeOrderName)"
        }
        if ($Error[0].Exception.InnerException -eq "303") {
            throw "ERROR: Permission denied for user $($vaultConnection.UserName)"
        }
        if ($Error[0].Exception.InnerException -eq "1612") {
            throw "ERROR: The item is being managed by another change order"
        }
        else {
            if ($editChangeOrder) {
                $vault.ChangeOrderService.UndoEditChangeOrder($editChangeOrder.Id)
            }
            throw "ERROR: $($Error[0])"
        }
    }
}

function Change-State {
    param (
        [Parameter(Mandatory = $true)]
        $ChangeOrderName,
        $DesiredAction,
        $Email
    )
    #workflow and routing
    #[Autodesk.Connectivity.WebServices.Workflow]$workflow = GetWorkflow($workflowname)
    #if ($workflow)
    #{
    #    $workflowInfo = $vault.ChangeOrderService.GetWorkflowInfo($workflow.Id)
    #}
    try {
        $changeOrder = $vault.ChangeOrderService.GetChangeOrderByNumber($ChangeOrderName)
        if ($changeOrder.ActivityArray) {
            $activity = $ChangeOrder.ActivityArray | where { $_.DispName -eq $DesiredAction }
            if ($activity) {
                $editChangeOrder = $vault.ChangeOrderService.StartChangeOrderActivity($changeOrder.Id, $activity.Id, $changeOrder.StateId, $changeOrder.StateEntered)    
                return $vault.ChangeOrderService.CommitChangeOrderActivity($editChangeOrder.Id, $activity.Id, $editChangeOrder.StateId, $editChangeOrder.StateEntered, $null, $Email)
            }
            else {
                throw "ERROR: The $($DesiredAction) is not a valid action."
            }
        }
        else {
            throw "ERROR: Change Order cannot be moved to another state."
        }
    }
    catch {
        if ($Error[0].Exception.InnerException -eq "1608") {
            throw "ERROR: Could not find the specified change order - $($ChangeOrderName)"
        }
        else {
            if ($editChangeOrder) {
                $vault.ChangeOrderService.CancelChangeOrderActivity($editChangeorder.Id, $activity.Id)            
            }
            throw "ERROR: $($Error[0])"
        }
    }
}

function Get-VaultECO {
    param (
        [Parameter(Mandatory = $true)]
        $ChangeOrderName
    )
    try {
        $vault.ChangeOrderService.GetChangeOrderByNumber($ChangeOrderName)
    }
    catch {
        if ($Error[0].Exception.InnerException -eq "1608") {
            throw "ERROR: Could not find the specified change order - $($ChangeOrderName)"
        }        
        else {
            throw "ERROR: $($Error[0])"
        }
    }
}

function Get-VaultECOAffectedItems($ecoId) {
    return $vault.ChangeOrderService.GetAssociationsByChangeOrderIDs(@($ecoId), "ITEM")    
}

function Add-Comments {
    param (
        [Parameter(Mandatory = $true)]
        $ChangeOrderName,
        $Title,
        $Message
    )
    if ($Title -or $Message) {
        try {
            $changeOrder = $vault.ChangeOrderService.GetChangeOrderByNumber($ChangeOrderName)
            $comments = GetComments $Title $Message
            $vault.ChangeOrderService.AddComment($changeOrder.Id, @($comments), $null)
        }
        catch {
            if ($Error[0].Exception.InnerException -eq "1608") {
                throw "ERROR: Could not find the specified change order - $($ChangeOrderName)"
            }
            else {
                throw "ERROR: $($Error[0])"
            }
        }
    }
    else {
        Write-Warning "Title and Message are both empty. No comments will be added."
    }
}

function GetDefaultRouting() {
    $defaultWorkflow = GetWorkflow($null)
    return GetRouting $defaultWorkflow.Id $null
}

function GetWorkflow($name) {
    if ($name) { #if the workflowname is not provided then the return the default workflow    
        $workflows = $vault.ChangeOrderService.GetAllActiveWorkflows()
        return $workflows | where { $_.Name -eq $name }
    }
    #return the default workflow
    return $vault.ChangeOrderService.GetDefaultWorkflow()
}

function GetRouting($id, $name) {
    $routings = $vault.ChangeOrderService.GetRoutingsByWorkflowId($id)
    if ($name) {
        return $routings | where { $_.Name -eq $name }
    }
    #return the default routing
    return $routings | where { $_.IsDflt -eq $true }
}

function GetChangeOrderNumberingScheme($name) {
    $ecoNumSchms = $vault.NumberingService.GetNumberingSchemes("CO", [Autodesk.Connectivity.WebServices.NumSchmType]::Activated)
    if ($name) {
        return $ecoNumSchms | where { $_.Name -eq $name }
    }
    #return the default numbering scheme
    return $ecoNumSchms | where { $_.IsDflt -eq $true }
}

function GetProperties($properties) {
    $propinsts = @()
    $propdefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("CO")
    $userpropdefs = $propdefs | where { $_.IsSys -eq $false -and $_.IsAct -eq $true }
    if ($properties) {
        $properties.GetEnumerator() | foreach {
            $key = $_.key
            $property = $userpropdefs | where { $_.DispName -eq $key }
            if ($property) {
                $propInst = New-Object Autodesk.Connectivity.WebServices.PropInst
                $propInst.EntityId = -1
                $propInst.PropDefId = $property.Id
                $propInst.Valtyp = $property.Typ
                $propInst.Val = $_.value
                $propinsts += $propInst
            }
        }
    }
    
    return $propinsts
}

function GetAssociatedProperties($associatedproperties) {
    $assocPropItems = @()
    $assocPropDefs = $vault.PropertyService.GetAssociationPropertyDefinitionsByType("ChangeOrderItem")
    $activeAssocPropDefs = $assocPropDefs | where { $_.IsAct -eq $true }

    $associatedproperties.GetEnumerator() | foreach {
        $key = $_.key
        $item = $vault.ItemService.GetLatestItemByItemNumber($key)
        $props = $_.value
        $props.GetEnumerator() |  foreach {
            $key = $_.key
            $property = $activeAssocPropDefs | where { $_.DispName -eq $key }
            if ($property) {
                $assocPropItem = New-Object Autodesk.Connectivity.WebServices.AssocPropItem
                $assocPropItem.FromId = 0
                $assocPropItem.Id = 0
                $assocPropItem.PropDefId = $property.Id
                $assocPropItem.ToId = $item.MasterId
                $assocPropItem.Val = $_.value
                $assocPropItem.ValTyp = $property.Typ
                $assocPropItems += $assocPropItem
            }
        }
        
    }
    return $assocPropItems
}

function GetComments($Title, $Message) {
    $msgGroup = New-Object Autodesk.Connectivity.WebServices.MsgGroup
    $msg = New-Object Autodesk.Connectivity.WebServices.Msg
    $msg.MsgTxt = $Message
    $msg.CreateDate = (Get-Date)
    $msg.CreateUserName = $vaultConnection.UserName
    $msg.Subject = $Title
    $msgGroup.Msg = $msg
    $comments = @($msgGroup)
    return $comments
}
