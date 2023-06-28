#==============================================================================#
# (c) 2023 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

function GetVaultName($Entity) {
    return $vaultConnection.Vault
}

function GetVaultServer($Entity) {
    $serverUri = New-Object Uri -ArgumentList $vault.InformationService.Url
    $hostname = $serverUri.Host
    if ($hostname -ieq "localhost") { $hostname = [System.Net.Dns]::GetHostName() }
    return $hostname
}

function GetEntityId($Entity) {
    return $Entity.Id
}
function GetEntityMasterId($Entity) {
    return $Entity.MasterId
}

function GetVaultPersistentId($Entity) {
    $id = $vault.KnowledgeVaultService.GetPersistentIds($Entity._EntityTypeID, @($Entity.Id), [Autodesk.Connectivity.WebServices.EntPersistOpt]::Latest) | Select-Object -First 1
    return $id
}

function GetObjectId($Entity) {
    if ($Entity._EntityTypeID -eq "ITEM") {
        $objectId = [System.Web.HttpUtility]::UrlEncode($Entity._Number)
    } elseif ($Entity._EntityTypeID -eq "FILE") {
        $objectId = [System.Web.HttpUtility]::UrlEncode($Entity._FullPath)
    } else {
        return ""
    }

    return $objectId
}

function GetVaultThickClientLink($Entity) {
    if ($Entity._EntityTypeID -eq "ITEM") {
        $objectType = "ItemRevision"
    } elseif ($Entity._EntityTypeID -eq "FILE") {
        $objectType = "File"
    } else {
        return ""
    }
    $objectId = GetObjectId $Entity

    $serverUri = New-Object Uri -ArgumentList $vault.InformationService.Url
    $hostname = $serverUri.Host
    if ($hostname -ieq "localhost") { $hostname = [System.Net.Dns]::GetHostName() }
    return "$($serverUri.Scheme)://$($hostname)/AutodeskDM/Services/EntityDataCommandRequest.aspx?Vault=$($vaultConnection.Vault)&ObjectId=$($objectId)&ObjectType=$($objectType)&Command=Select"
}

function GetVaultThinClientLink($entity) {
    if ($entity._EntityTypeID -eq "ITEM") { 
        $path = "items/itemversion/$($entity.Id)"
    } elseif ($entity._EntityTypeID -eq "FILE") {
        $path = "explore/fileversion/$($entity.Id)"
    } elseif ($entity._EntityTypeID -eq "CO") {
        $path = "changeorders/changeorder/$($entity.MasterId)"
    } else {
        return ""
    }
 
    $serverUri = New-Object Uri -ArgumentList $vault.InformationService.Url
    $hostname = $serverUri.Host
    if ($hostname -ieq "localhost") { $hostname = [System.Net.Dns]::GetHostName() }
    return "$($serverUri.Scheme)://$($hostname)/AutodeskTC/$($vaultConnection.Vault)/$($path)"
}

# function GetVaultThinClientLink($Entity) {
#     $id = GetVaultPersistentId -entity $Entity
#     $serverUri = New-Object Uri -ArgumentList $vault.InformationService.Url
#     $hostname = $serverUri.Host
#     if ($hostname -ieq "localhost") { $hostname = [System.Net.Dns]::GetHostName() }
#     return "$($serverUri.Scheme)://$($hostname)/AutodeskTC/$($hostname)/$($vaultConnection.Vault)#/Entity/Details?id=m$($id)&itemtype=$($Entity._EntityType.DisplayName)"
# }

function GetItemPositionNumber($Entity) {
    $position = $Entity.Bom_PositionNumber
    if (-not $position) {
        $position = "0"
    }

    $s = ($position -replace "[^-\d]+" , '')
    return [int]$s
}