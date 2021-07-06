if (-not $IAmRunningInJobProcessor) { # for manual script execution
    $ErrorActionPreference = "Stop"
    Import-Module powerJobs
    $job = New-Object PSObject -Property @{ Name = "Sample.SyncChangeOrders" }
    Open-VaultConnection -Server "localhost" -Vault "Vault" -User "Administrator" -Password ""
    #$changeOrder = Get-VaultChangeOrder -Number "CO-000001"
}

Import-Module powerFLC
Write-Host "Starting job '$($job.Name)'..."
$begin = [DateTime]::UtcNow

Write-Host "Connecting to Fusion 360 Manage..."
$connected = Connect-FLC -Tenant $tenant.Name -ClientId $tenant.ClientId -ClientSecret $tenant.ClientSecret -UserId $tenant.SystemUserEmail
if (-not $connected) {
    throw "Connection to Fusion 360 Manage failed! Error: `n $($connected.Error.Message)!`n See '$($env:LOCALAPPDATA)\coolOrange\powerFLC\Logs\powerFLC.log' for details"
}
if (-not $workflow) {
    throw "Cannot find workflow configuration with name '$($job.Name)'"
}
$workspace = $flcConnection.Workspaces.Find($workflow.FlcWorkspace)
if (-not $workspace) {
    throw "Workspace $($workflow.FlcWorkspace) cannot be found!"
}
Write-Host "Connected to $($flcConnection.Url) - Workspace: $($workspace.Name)"

$entityUrns = $vault.PropertyService.FindEntityAttributes("FLC.ITEM", "Urn")
$states = @($workspace.WorkflowActions.FromState; $workspace.WorkflowActions.ToState) | Sort-Object -Property * -Unique

$triggerState = $workflow.Settings.'Trigger State'
$lifecycleTransition = $workflow.Settings.'Affected Items Lifecycle Transition'
$workflowAction = $workflow.Settings.'Workflow Action'
$attachmentsFolder = $workflow.Settings.'Vault Attachments Folder'

if (-not ($states | Where-Object { $_.Name -eq $triggerState })) {
    throw "The configured 'Trigger State'='$triggerState' is not available in the workspace '$($workspace.Name)'"
}
if (-not ($workspace.LifecycleTransitions | Where-Object { $_.Name -eq $lifecycleTransition })) {
    throw "The configured 'Affected Items Lifecycle Transition'='$lifecycleTransition' is not available in the workspace '$($workspace.Name)'"
}
if (-not ($workspace.WorkflowActions | Where-Object { $_.Name -eq $workflowAction })) {
    throw "The configured 'Workflow Action'='$workflowAction' is not available in the workspace '$($workspace.Name)'"
}
try {
    $vault.DocumentService.GetFolderByPath($attachmentsFolder) | Out-Null
} catch {
    throw "The configured 'Vault Attachments Folder'='$attachmentsFolder' does not exist in Vault"
}

#region Time Triggered Job
if (-not $changeOrder) {
    $flcChangeOrders = Get-FLCItems -Workspace $workspace.Name -Filter "workflowState=$triggerState"
    Write-Host "$($flcChangeOrders.Count) Change Order item(s) retrieved"
    
    #$flcChangeOrder = $flcChangeOrders[1]
    foreach ($flcChangeOrder in $flcChangeOrders) {
        Write-Host "Processing item '$($flcChangeOrder.$($workflow.FlcUnique))'"

        $tempDirectory = "C:\TEMP"
        $workingDirectory = [System.IO.Path]::Combine($tempDirectory, "$($flcChangeOrder.$($workflow.FlcUnique))")
        
        $affectedItemsInVault = @()
        $affectedItemsNotInVault = @()

        $affectedItems = $flcChangeOrder | Get-FLCItemAssociations -AffectedItems
        Write-Host "$($affectedItems.Count) affected item(s) received from Fusion 360 Manage"
        
        foreach ($flcItem in $affectedItems) {
            $workspaceId = $flcConnection.Workspaces.Find($flcItem.Workspace).Id
            $itemVersions = Get-FLCItemVersions -workspace $workspaceId -ItemId $flcItem.Id
            $existingItem = $null
            foreach ($itemVersion in $itemVersions) {
                $existingItem = $entityUrns | Where-Object { $_.Val -eq $itemVersion.item.urn }
                if ($existingItem) { break }
            }
            if ($existingItem) {
                $item = $vault.ItemService.GetLatestItemByItemMasterId($existingItem.EntityId)
                $affectedItemsInVault += $item.ItemNum
            } else {
                $affectedItemsNotInVault += $flcItem.Number #TODO: change the field 'Number' if not present in your items workspace!
            }
        }

        $attachments = $flcChangeOrder | Get-FLCItemAssociations -Attachments 
        Write-Host "$($attachments.Count) attachment(s) received from Fusion 360 Manage"
        $attachmentFileNames = @()
        foreach ($attachment in $attachments) {
            $downloadedFile = $attachment | Save-FLCAttachment -DownloadPath $workingDirectory
            $destinationFullFileName = "$attachmentsFolder/$($flcChangeOrder.$($workflow.FlcUnique))/$($attachment.FileName)"
            $uploadedFile = Add-VaultFile -From $downloadedFile.FullName -To $destinationFullFileName -Force $true
            Write-Host "$($uploadedFile._Name) added to Vault"
            $attachmentFileNames += $uploadedFile._FullPath
        }

        try { 
            $co = Get-VaultChangeOrder -Number $flcChangeOrder.$($workflow.FlcUnique) -ErrorAction Stop
            if (-not $co) { throw }
        } catch {
            $co = Add-VaultChangeOrder -Number $flcChangeOrder.$($workflow.FlcUnique)
            $createComment = $true
        }

        $urn = "urn:adsk.plm:tenant.workspace.item:$($tenant.Name.ToUpper()).$($workspace.Id).$($flcChangeOrder.Id)"
        $vault.PropertyService.SetEntityAttribute($co.Id, "FLC.ITEM", "Urn", $urn)

        $mapping = $workflow.Mappings | Where-Object { $_.Name -eq "Item Field Mapping" }
        if (-not $mapping) {
            throw "Cannot find mapping configuration for mapping '$mappingName'"
        }
        
        $properties = @{}
        foreach ($fieldMapping in $mapping.FieldMappings) {
            if ($fieldMapping.Function) {
                Write-Warning "Functions are not supported for mappings from Fusion 360 to Vault!"
                continue
            }
            else {
                $propName = $fieldMapping.Flc
                $value = $flcChangeOrder.$propName

                if ($fieldMapping.Vault -eq "Title (Item,CO)") {
                    $title = $value
                    continue
                }
                if ($fieldMapping.Vault -eq "Description (Item,CO)") {
                    $description = [System.Web.HttpUtility]::HtmlDecode($value) -replace '<[^>]+>',''
                    continue
                }
                if ($fieldMapping.Vault -eq "Due Date") {
                    $dueDate = $value
                    continue
                }
            }
            if ($value -and $value.GetType() -eq [Autodesk.DataManagement.Client.Framework.Vault.Currency.Properties.ThumbnailInfo]) {
                Write-Warning "Images are not supported for mappings from Fusion 360 to Vault!"
                continue
            }
            $properties.Add($fieldMapping.Vault, $value) | Out-Null
        }

        if ($dueDate) {
            $co = Update-VaultChangeOrder -Number $co._Number -Title $title -Description $description -Properties $properties -ItemRecords $affectedItemsInVault -Attachments $attachmentFileNames -DueDate $dueDate 
        } else {
            $co = Update-VaultChangeOrder -Number $co._Number -Title $title -Description $description -Properties $properties -ItemRecords $affectedItemsInVault -Attachments $attachmentFileNames
        }

        if ($affectedItemsNotInVault -and $createComment) {
            $message = ([System.String]::Join([Environment]::NewLine, $affectedItemsNotInVault))
            Add-VaultChangeOrderComment -ChangeOrderName $co._Number -Title "Affected Items not in Vault" -Message $message
            Write-Host "Affected Items not in Vault: $message"
        }

        #Cleanup temporary downloaded attachment files and delete the folder
        Sample.SyncChangeOrders\Clean-Up -folder $workingDirectory
    }
}
#endregion

#region job triggered by State change 
else {
    Write-Host "Synchronizing $($workspace.Name) - triggered by state change of Vault ECO '$($changeOrder._Number)'"
    $entityUrn = $entityUrns | Where-Object { $_.EntityId -eq $changeOrder.MasterId }
    if ($entityUrn) {
        $id = GetItemFromUrn -urn $entityUrn.Val
        $flcChangeOrder = (Get-FLCItems -Workspace $workspace.Name -Filter "itemId=$($id)")[0]
        if (-not $flcChangeOrder) {
            throw "Couldn't find Fusion 360 Manage item with urn='$($entityUrn.Val)' for Vault ECO '$($changeOrder._Number)'"
        }

        $items = Get-VaultChangeOrderAssociations -Number $changeOrder._Number -Type ItemRecords
        Write-Host "$($items.Count) Vault affected item(s) retrieved"

        $affectedItems = $flcChangeOrder | Get-FLCItemAssociations -AffectedItems
        Write-Host "$($affectedItems.Count) affected item(s) retrieved from Fusion 360 Manage"
        
        if ($items) {
            foreach($item in $items) {
                $entityUrn = $entityUrns | Where-Object { $_.EntityId -eq $item.MasterId }[0]
                if ($entityUrn) {
                    $id = GetItemFromUrn -urn $entityUrn.Val
                    $workspaceId = GetWorkspaceFromUrn $entityUrn.Val
                    $itemVersions = Get-FLCItemVersions -workspace $workspaceId -ItemId $id

                    foreach ($itemVersion in $itemVersions) {
                        $flcItem = $affectedItems | Where-Object { $_.Id -eq (GetItemFromUrn -urn $itemVersion.item.urn) }[0]
                        if ($flcItem) { break }
                    }
                    if (-not $flcItem) {
                        Write-Host "Additional record found in Vault: $($item._Number). Adding it to Fusion 360 Manage as affected item..."

                        $flcItem = (Get-FLCItems -Workspace $flcConnection.Workspaces[$workspaceId].Name -Filter "itemId=$($id)")[0]
                        $flcItem | Add-Member -Name "LinkedItem_LifecycleTransition" -Value $lifecycleTransition -Type NoteProperty
                        #$flcItem | Add-Member -Name "LinkedItem_EffectivityDate" -Value (Get-Date ...) -Type NoteProperty
                        $affectedItems += $flcItem
                    }
                } else {
                    Write-Host "This Vault ECO's record $($item._Number) is not present as Fusion 360 Manage item!"
                }
            }
            try {
                $flcChangeOrder | Update-FLCItem -AffectedItems $affectedItems -ErrorAction Stop
            }
            catch {
                throw "Cannot add additional affected items to Fusion 360 Manage. Reason: $($_)"
            }
        }
        else {
            Write-Host "No item records found for Vault ECO $($changeOrder._Number)"
        }

        try {
            $flcChangeOrder | Update-FLCItem -WorkflowAction $workflowAction -Comment "Updated by powerPLM" -ErrorAction Stop
        }
        catch {
            throw "Cannot perform workflow action in Fusion 360 Manage. Reason: $($_)"
        }
    }
    else {
        Write-Host "Vault ECO '$($changeOrder.Number)' is not tracked by Fusion 360 Manage!"
    }
}
#endregion

$end = [DateTime]::UtcNow
Write-Host "Completed job '$($job.Name)' in $([int]([TimeSpan]($end - $begin)).TotalSeconds) Seconds"