#==============================================================================#
# PowerShell script sample for coolOrange powerFLC                             #
# (c) 2020 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

Import-Module powerFLC

Write-Host "Starting job '$($job.Name)'..."
$begin = [DateTime]::UtcNow

if (-not $IAmRunningInJobProcessor) {
    Import-Module powerJobs
    $job = New-Object PSObject -Property @{ Name = "Sample.TransferFiles" }
    Open-VaultConnection -Server "localhost" -Vault "Vault" -User "Administrator" -Password ""
    $file = Get-VaultFile -File "$/Designs/Inventor Sample Data/Models/Assemblies/Stapler/Stapler.idw"
    $user = $vault.AdminService.GetUserByUserId($vaultConnection.UserID)
} else {
    $jobs = $vault.JobService.GetJobsByDate([int]::MaxValue, [DateTime]::MinValue)
    $user = $vault.AdminService.GetUserByUserId(($jobs | Where-Object { $_.Id -eq $job.Id }).CreateUserId)    
}

$supportedExtensions = $workflow.Settings.'Supported File Extensions'.Split(@(';', ' '), [System.StringSplitOptions]::RemoveEmptyEntries)
if ($supportedExtensions -notcontains $file._Extension) {
    Write-Host "Files with extension: '$($file._Extension)' are not supported"
    return
}

Write-Host "User: '$($user.Name)', Email: '$($user.Email)'"
if (-not $user.Email) {
    throw "There is no email address configured for user '$($user.Name)'! The Vault user email address is used to authenticate with Fusion Lifecycle!"
}

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

function CreateOrUpdateFLCItem($entity, $properties) {  
    $uniqueFlcField = $workspace.ItemFields.Find($workflow.FlcUnique)
    $flcItem = (Get-FLCItems -Workspace $workspace.Name -Filter ('ITEM_DETAILS:{0}="{1}"' -f $uniqueFlcField.Id, $entity."$($workflow.VaultUnique)"))[0]
    if (-not $flcItem) {
        Write-Host "Create item $($entity."$($workflow.VaultUnique)")..."
        $flcItem = Add-FLCItem -Workspace $workspace.Name -Properties $properties
    } else {
        Write-Host "Update item $($entity."$($workflow.VaultUnique)")..."
        $flcItem = Update-FLCItem -Workspace $flcItem.Workspace -ItemId $flcItem.Id -Properties $properties
    }

    if (-not $flcItem -or -not $flcItem.Id) {
        throw "Item cannot be created/updated in Fusion Lifecycle"
    } else {
        $urn = "urn:adsk.plm:tenant.workspace.item:$($tenant.Name.ToUpper()).$($workspace.Id).$($flcItem.Id)"
        $vault.PropertyService.SetEntityAttribute($entity.MasterId, "FLC.ITEM", "Urn", $urn);
    }

    return $flcItem
}

Write-Host "Create or Update FLC item..."
$properties = GetFlcProperties "Item Field Mapping" $file
$flcItem = CreateOrUpdateFLCItem $file $properties

Write-Host "Uploading attachments..."
$fileAttachments = @()

if ($workflow.Settings.'Upload File Attachments') {
    $fileAttachments += Get-VaultFileAssociations -File $file._FullPath -Attachments
}

#TODO: supported file extensions!
if ($workflow.Settings.'Upload Native Files') {
    $fileAttachments += $file
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
        $paramUpload.FlcItem = $flcItem
        $paramUpload.LocalPath = $file.LocalPath
        $paramUpload.Description = $file._Description
        $uploadJobs += {
            param ($flcConnection, [Hashtable]$parameters)
            $fileName = Split-Path $parameters.LocalPath -leaf  
            $parameters.FlcItem | Add-FLCAttachment -Path $parameters.LocalPath -Title $fileName -Description $parameters.Description
        } | InvokeAsync -Parameters $paramUpload

        $uploadedFiles += $file._FullPath
    }
}
WaitAll -Jobs $uploadJobs

# Cleanup
if (Test-Path $downloadDirectory) {
    Clean-Up -folder $downloadDirectory
}

$end = [DateTime]::UtcNow
Write-Host "Completed job '$($job.Name)' in $([int]([TimeSpan]($end - $begin)).TotalSeconds) Seconds"