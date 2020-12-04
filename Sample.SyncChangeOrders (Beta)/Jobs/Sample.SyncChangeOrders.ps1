if (-not $IAmRunningInJobProcessor) {
    # for manual script execution
    Import-Module powerJobs
    $job = New-Object PSObject -Property @{ Name = "Sample.SyncChangeOrders" }
    Open-VaultConnection -Server "localhost" -Vault "Vault" -User "Administrator" -Password ""
}

Import-Module powerFLC
Write-Host "Starting job '$($job.Name)'..."
$begin = [DateTime]::UtcNow

Write-Host "Connecting to Fusion Lifecycle..."
$connected = Connect-FLC -Tenant $tenant.Name -ClientId $tenant.ClientId -ClientSecret $tenant.ClientSecret -UserId $tenant.SystemUserEmail
if (-not $connected) {
    throw "Connection to Fusion Lifecycle failed! Error: `n $($connected.Error.Message)!`n See '$($env:LOCALAPPDATA)\coolOrange\powerFLC\Logs\powerFLC.log' for details"
}

if (-not $workflow) {
    throw "Cannot find workflow configuration with name '$($job.Name)'"
}

$workspace = $flcConnection.Workspaces.Find("Change Orders")
if (-not $workspace) {
    throw "Workspace $($_workflow.FlcWorkspace) cannot be found!"
}
$entitiyUrns = $vault.PropertyService.FindEntityAttributes("FLC.ITEM", "Urn")
Write-Host "Connected to $($flcConnection.Url) - Workspace: $($workspace.Name)"

#region Time Triggered Job
if (-not $changeOrder) {
    $fromState = $workflow.Settings.'From State'
    $filter = "workflowState=$fromState"
    $tempDirectory = "C:\TEMP"
    $tempFile = $job.Name + ".date"
    $tempFullFileName = [System.IO.Path]::Combine($tempDirectory, $tempFile)
    if (Test-Path $tempFullFileName) {
        $lastCheck = Get-Content -Path $tempFullFileName
        $filter = "(" + $filter + ")" + " AND (lastModifiedOn>=$lastCheck)"
    }
    $flcChangeOrders = Get-FLCItems -Workspace $workspace.Name -Filter $filter
    Write-Host "$($flcChangeOrders.Count) Change Order item(s) retrieved"
    
    foreach ($flcChangeOrder in $flcChangeOrders) {
        $workingDirectory = [System.IO.Path]::Combine($tempDirectory, "$($flcChangeOrder.$($workflow.FlcUnique))")
        New-Item -ItemType Directory -Force -Path $workingDirectory
        #Affected Items of FLC CO
        $affectedItemsMasterId = @()
        $AffectItemsNotInVaultList = @()
        $affectedItems = Get-FLCAffectedItems -workspace $workspace -item $flcChangeOrder
        Write-Host "$($affectedItems.Count) FLC affected item(s) retrieved"
        foreach ($flcItem in $affectedItems) {
            $ItemId = GetItemFromUrn -urn $flcItem.item.urn
            $workspaceId = GetWorkspaceFromUrn -urn $flcItem.item.urn
            $itemVersions = Get-FLCItemVersions -workspace $workspaceId -ItemId $ItemId
            $existingItem = $null
            foreach ($item in $itemVersions) {
                $existingItem = $entitiyUrns | Where-Object { $_.Val -eq $item.item.urn }
                if ($existingItem) {
                    break
                }
            }  
            if ($existingItem) {
                $affectedItemsMasterId += $existingItem.EntityId
            }
            else {
                $AffectItemsNotInVaultList += $flcItem.item.title
            }
        }
        #Dowload Attachments
        $attachments = Get-FLCAttachments -Workspace $workspace.Name -Item $flcChangeOrder
        foreach ($attachment in $attachments) {
            Start-AWSDownload -url $attachment.url -localFile "$($workingDirectory)\$($attachment.name)"
        }
        #Add to Vault preconfigured folder
        $attachmentsMasterIds = @()
        $downloadedFiles = Get-ChildItem -Path $workingDirectory
        Write-Host "$($downloadedFiles.Count) attachment(s) downloaded"

        $attachmentFolder = $workflow.Settings.'Attachment Folder'
        $createSubfolder = $workflow.Settings.'Attachment Subfolders'

        foreach ($downloadedFile in $downloadedFiles) {
            if ($createSubfolder) {
                $subFolder = $($workflow.FlcUnique)
                $destinationFullFileName = "$attachmentFolder/$($flcChangeOrder.$subFolder)/$($downLoadedFile.Name)"
            }
            else {
                $destinationFullFileName = "$attachmentFolder/$($downLoadedFile.Name)"
            }
            $uploadedFile = Add-VaultFile -From $downloadedFile.FullName -To $destinationFullFileName -Force $true
            $attachmentsMasterIds += $uploadedFile.MasterId
        }
        
        #properties
        $properties = GetVaultProperties -mappingName "Item Field Mapping" -flcItem $flcChangeOrder
        #linkedProperties
        #$LinkedProperties = @{"100011" = @{"test" = "again value"; "Title" = "again title"}}
        
        #New-ChangeOrder or Update ChangeOrder        
        #check if change order exists then update otherwise create new change order
        $eco = $null
        $urn = "urn:adsk.plm:tenant.workspace.item:$($tenant.Name.ToUpper()).$($workspace.Id).$($flcChangeOrder.Id)"
        $existingECO = $entitiyUrns | where { $_.Val -eq $urn }
        if ($existingECO) {
            $eco = $vault.ChangeOrderService.GetChangeOrdersByIds(@($existingECO.EntityId))
        }
        $parameters = @{
            Title = $properties.'Title (Item,CO)'
            Description = $properties.'Description (Item,CO)'
            ItemMasterIds = $affectedItemsMasterId
            AttachmentFileMasterIds = $attachmentsMasterIds
            Properties = $properties
        }
        if ($eco) {
            try {
                $vaultChangeOrder = Edit-ChangeOrder -ChangeOrderName $eco.Num @parameters
                Write-Host "ECO '$($eco.Num)' Updated."
            }
            catch {
                Write-Host "ECO '$($eco.Num)' cannot be updated."
            }
        }
        else {            
            $vaultChangeOrder = New-ChangeOrder -ChangeOrderName $properties.'Change Order Number' @parameters
            Write-Host "New ECO '$($vaultChangeOrder.Num)' created."
            if (-not $vaultChangeOrder) {
                throw "Failed to Create new Vault ECO"
            }
            else {
                $ecourn = "urn:adsk.plm:tenant.workspace.item:$($tenant.Name.ToUpper()).$($workspace.Id).$($flcChangeOrder.Id)"
                $vault.PropertyService.SetEntityAttribute($vaultChangeOrder.Id, "FLC.ITEM", "Urn", $ecourn);
            }
            if ($AffectItemsNotInVaultList) {
                Add-Comments -ChangeOrderName $vaultChangeOrder.Num -Title "Affected FLC Items not in Vault" -Message ([System.string]::join([Environment]::NewLine, $AffectItemsNotInVaultList))
                Write-Host "New comment added."
            }
        }        
        

        #Cleanup temporary downloaded attachment files and delete the folder
        Sample.SyncChangeOrders\Clean-Up -folder $workingDirectory
    }
    
    $lastCheck = Get-Date -Format "yyyy-MM-dd"
    Set-Content -Path $tempFullFileName -Value $lastCheck
}
#endregion

#region job triggered by State change 
else {
    #find urn for the corresponding flc item    
    Write-Host "Close FLC changeorder $($changeOrder.Number) - job triggered by Vault ECO state change"
    $existingEntAttr = $entitiyUrns | where { $_.EntityId -eq $changeOrder.EntityIterationId }
    if ($existingEntAttr) {
        $id = GetItemFromUrn -urn $existingEntAttr.Val
        $flcChangeOrder = Get-FLCItems -Workspace $workspace.Name -Filter "itemId=$($id)"
        if (-not $flcChangeOrder) {
            throw "Couldn't find FLC Change Order with urn='$($existingEntAttr.Val)' for the Vault ECO '$($changeorder.Number)'"
        }
        #region affected items
        $ecoAffectedItems = Get-VaultECOAffectedItems -ecoId $changeOrder.EntityIterationId
        Write-Host "$($ecoAffectedItems.Count) Vault affected item(s) retrieved"
        $flcAffectedItems = Get-FLCAffectedItems -workspace $workspace -item $flcChangeOrder
		
        if ($ecoAffectedItems) {
            $entIdArray = $ecoAffectedItems[0].EntIdArray
            foreach ($entityId in $entIdArray) {
                $vaultItem = Get-VaultItem -ItemId $entityId
                $ecoEntityAttr = $entitiyUrns | where { $_.EntityId -eq $vaultItem.MasterId }[0]
                if ($ecoEntityAttr) {
                    $itemId = GetItemFromUrn -urn $ecoEntityAttr.Val                    
					$itemWorkspaceId = GetWorkspaceFromUrn $ecoEntityAttr.Val
                    $itemVersions = Get-FLCItemVersions -workspace $itemWorkspaceId -ItemId $itemId
                    foreach ($item in $itemVersions) {
                        $flcItem = $flcAffectedItems | where {$_.item.urn -eq $item.item.urn}[0]
                        if ($flcItem){
                            break
                        }
                    }
					if (-not $flcItem) {
                        Write-Host "Found additional affected Item $($vaultItem.Name) in Vault"
                        $workspaceId = GetWorkspaceFromUrn($ecoEntityAttr.Val)
                        $response = Add-FLCAffectedItem -workspace $workspace -fromWorkspace $workspaceId -item $flcChangeOrder -fromItem $itemId
                        if ($response.result -eq "FAILED") {
                            throw $response.errorMessage
                        }
                        Write-Host "Added item $($ecoEntityAttr.Val) to the FLC change order as affected item"
                        $views = Get-FLCViews -Workspace $workspace.Name -ItemId $flcChangeOrder.Id
                        $view = $views | where { $_.title -eq "Managed Items" }[0]
                        $viewId = GetViewFromUrn -urn $view.urn
                        $transitions = Get-FLCAffectedItemTransitions -Workspace $workspace.Name -ItemId $flcChangeOrder.Id -viewId $viewId -affectedItemId $itemId
                        $transition = $transitions | Where-Object { $_.name -eq "Initial Design Revision" }[0] | Select-Object @{N = 'link'; E = { $_.__self__ } }, @{N = 'title'; E = { $_.name } }
                        $viewAffectedItem = Get-FLCViewAffectedItem -Workspace $workspace.Name -ItemId $flcChangeOrder.Id -viewId $viewId -affectedItemId $itemId
                        $viewAffectedItem | Add-Member "targetTransition" $transition
                        Update-FLCViewAffectedItemTransition -Workspace $workspace.Name -ItemId $flcChangeOrder.Id -viewId $viewId -affectedItemId $itemId -AffectedItem $viewAffectedItem
                    }
                }
                else {
                    Write-Host "This ECO's affected item $($vaultItem.Name) is not mapped to an FLC item."
                }
            }
        }
        else {
            Write-Host "Not found any affected items on this ECO $($changeOrder.Number)"
        }
        #endregion

        #region Update FLC Change Order properties
        #$flcChangeOrder | Update-FLCItem -Properties @{'Title' = "title updated"; 'Description of Change' = "Description of change updated"}
        #Title and Description of Change
        $fromState = $workflow.Settings.'From State'
        $toState = $workflow.Settings.'To State'
        $currentState = $flcChangeOrder.WorkflowState
        if ($currentState -ne $fromState) {
            throw "The item is not in the expected state!"
        }

        $transitions = Get-Transitions -Workspace $workspace.Name -ItemId $flcChangeOrder.Id
        $transition = $transitions | where { $_.fromState.title -eq $currentState -and $_.toState.title -eq $toState }
        if ($transition) {
            $id = GetItemFromUrn -urn $transition.urn 
            Update-FLCState -Workspace $workspace.Name -ItemId $flcChangeOrder.Id -TransitionId $id
            Write-Host "$($flcChangeOrder.$($workflow.FlcUnique)) has been $($transition.Name))"
        }
        else {
            throw "Cannot find transition from state '$($currentState)' to state '$($toState)'"
        }
    }
    else {
        Write-Host "Vault ECO '$($changeOrder.Number)' is not tracked by FLC."
    }
}
#endregion

$end = [DateTime]::UtcNow
Write-Host "Completed job '$($job.Name)' in $([int]([TimeSpan]($end - $begin)).TotalSeconds) Seconds"