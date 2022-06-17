#==============================================================================#
# PowerShell script sample for coolOrange powerFLC                             #
# (c) 2020 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

if (-not $IAmRunningInJobProcessor) {
    Import-Module powerJobs
    $job = New-Object PSObject -Property @{ Name = "coolorange.flc.sync.folder" }
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

$workspace = $flcConnection.Workspaces.Find($workflow.FlcWorkspace)
if (-not $workspace) {
    throw "Workspace $($workflow.FlcWorkspace) cannot be found!"
}
Write-Host "Connected to $($flcConnection.Url) - Workspace: $($workspace.Name)"

$states = @($workspace.WorkflowActions.FromState; $workspace.WorkflowActions.ToState) | Sort-Object -Property * -Unique
$stateNames = $workflow.Settings.'Valid States' -split @("; ")
$stateFilters = @()
foreach ($stateName in $stateNames) {
    $state = $states | Where-Object { $_.Name -eq $stateName }
    if ($state) {
        $stateFilters += "(workflowState=`"$($state.Name)`")"
    }
}
$filter = $stateFilters -join " OR "

$tempDirectory = "C:\TEMP"
$tempFile = $job.Name + ".date"
$tempFullFileName = [System.IO.Path]::Combine($tempDirectory, $tempFile)
if (Test-Path $tempFullFileName)
{
    $lastCheck = Get-Content -Path $tempFullFileName
    $filter = "(" + $filter + ")" + " AND (lastModifiedOn>=$lastCheck)"
}

Write-Host "Retrieving items from Fusion Lifecycle ($($filter))..."

$flcItems = Get-FLCItems -Workspace $workspace.Name -Filter $filter
Write-Host "$($flcItems.Count) item(s) retrieved"

if ($flcItems.Count -gt 0) {
    Write-Host "Retrieving folders from Vault..."
    $targetFolderPath = $workflow.Settings.'Target Folder'
    $targetFolder = $vault.DocumentService.GetFoldersByPaths(@($targetFolderPath))[0]
    $folders = $vault.DocumentService.GetFoldersByParentId($targetFolder.Id, $false)
    Write-Host "$($folders.Count) folders found in '$($targetFolder.FullName)'"

    Write-Host "Starting synchronization..."
    $propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("FLDR")
    $cats = $vault.CategoryService.GetCategoriesByEntityClassId("FLDR", $true)
    $categoryName = $workflow.Settings.'Folder Category'
    $cat = $cats | Where-Object { $_.Name -eq $categoryName }

    $copyFolderStructure = $workflow.Settings.'Copy Folder Structure'
    $templateFolderPath =  $workflow.Settings.'Folder Structure Template Path'

    foreach ($flcItem in $flcItems) {
        $fieldName = $workflow.FlcUnique
        $folderName = $flcItem.$fieldName
        $folder = $folders | Where-Object { $_.Name -eq $folderName }
        if (-not $folder) {
            Write-Host "Creating folder '$($folderName)'..."  
            $folder = $vault.DocumentServiceExtensions.AddFolderWithCategory($folderName, $targetFolder.Id, $false, $cat.Id)

            if ($copyFolderStructure -eq $true) {
                Write-Host "Creating sub folders from template '$($templateFolderPath)' for folder '$($folder.FullName)'..."
                $templateFolder = $vault.DocumentService.GetFoldersByPaths(@($templateFolderPath))[0]
                CopyFolder $templateFolder $folder $propDefs
            }
        } else {
            Write-Host "Updating folder '$($folderName)'..."
        }

        $propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("FLDR")
        $propInsts = $vault.PropertyService.GetProperties("FLDR", @($vaultFolder.Id), $propDefs.Id)
        $existingProperties = $folder | Get-Member -MemberType @("Property", "NoteProperty") | Select-Object { $_.Name } -ExpandProperty Name
        foreach ($propInst in $propInsts) {
            $propDef = $propDefs | Where-Object { $_.Id -eq $propInst.PropDefId }
            if ($existingProperties -notcontains $propDef.DispName) {
                $folder | Add-Member NoteProperty $propDef.DispName $propInst.Val
            }
        }

        $properties = GetVaultPropertiesToUpdate -mappingName "Item Field Mapping" -entity $folder -flcItem $flcItem
        if ($properties.Count -le 0) {
            Write-Host "Folder properties for folder '$($folder.FullName)' are up-to-date..."
            continue
        }

        $propInstParamArray = New-Object Autodesk.Connectivity.WebServices.PropInstParamArray
        $propInstParams = @()
        foreach ($prop in $properties.GetEnumerator()) {
            $propDef= $propDefs | Where-Object { $_.DispName -eq $prop.Name }
            $propInstParam = New-Object Autodesk.Connectivity.WebServices.PropInstParam
            $propInstParam.PropDefId = $propDef.Id
            $propInstParam.Val = $prop.Value
            $propInstParams += $propInstParam
        }
        $propInstParamArray.Items = $propInstParams

        Write-Host "Updating folder properties for folder '$($folder.FullName)'..."
        $vault.DocumentServiceExtensions.UpdateFolderProperties(@($folder.Id), @($propInstParamArray))
    }
}

$lastCheck = Get-Date -Format "yyyy-MM-dd"
Set-Content -Path $tempFullFileName -Value $lastCheck

$end = [DateTime]::UtcNow
Write-Host "Completed job '$($job.Name)' in $([int]([TimeSpan]($end - $begin)).TotalSeconds) Seconds"