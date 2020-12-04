#region Item Versions
function Get-FLCLatestItemVersion($Workspace, $ItemId) {
    $latestId = $null
    $ws = $flcConnection.Workspaces.Find($Workspace)

    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/items/$($ItemId)/versions" -Method Get -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
    
    foreach ($version in $response.versions) {
        #Status: UNRELEASED; WORKING; LATEST or SUPERSEDED
        if ($version.status -eq "LATEST" -or $version.status -eq "UNRELEASED") { 
            $latestId = GetItemFromUrn -urn $version.item.urn
            break
        }
    }

    if (-not $latestId) {
        $latestId = $itemId
    }

    return $latestId
}

function Get-FLCItemVersions($WorkspaceId, $ItemId) {
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($WorkspaceId)/items/$($ItemId)/versions" -Method Get -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
    return $response.versions
}
#endregion

#region Affected Items
function Get-FLCAffectedItems($workspace, $item) {
    $result = @()
    $wsId = $workspace.Id
    $itemId = $item.id

    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$wsId/items/$itemId/affected-items" -Method Get -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }    
    return $response.affectedItems
}

function Add-FLCAffectedItem($workspace, $fromWorkspace, $item, $fromItem) {
    $result = @()
    $wsId = $workspace.Id
    $itemId = $item.Id
    $body = "[ `"/api/v3/workspaces/$($fromWorkspace)/items/$($fromItem)`" ]"
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$wsId/items/$itemId/affected-items" -Method Post -ContentType "application/json;charset=UTF-8" -Body $body -Headers @{
        "Accept"        = "application/vnd.autodesk.plm.affected.items.bulk+json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
}

#endregion

#region Download AWS File
function Start-AWSDownload ($url, $localFile) {    
    Invoke-WebRequest -Uri $url  -Method Get -Headers @{        
        "Upgrade-Insecure-Requests" = 1        
        "Sec-Fetch-Site"            = "cross-site"        
        "Sec-Fetch-Mode"            = "navigate"        
        "Sec-Fetch-User"            = "?1"        
        "Sec-Fetch-Dest"            = "document"        
        "Accept-Encoding"           = "gzip, deflate, br"    
    } -OutFile $localFile
}
#endregion

#region FLC Item Attachments
function Get-FLCAttachments {
    [CmdletBinding()]
    param(
        [Parameter()]$Workspace,
        [Parameter()]$Item
    )

    $result = @()
    $ws = $flcConnection.Workspaces.Find($Workspace)

    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/items/$($item.Id)/attachments?asc=name" -Method Get -Headers @{
        "Accept"        = "application/vnd.autodesk.plm.attachments.bulk+json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
    
    foreach ($data in $response.attachments) {
        $result += $data
    }

    return $result
}
#endregion

#region States
function Get-FLCStates($Workspace) {
    $result = @()
    $ws = $flcConnection.Workspaces.Find($Workspace)

    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/workflows/1/states" -Method Get -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
    
    foreach ($state in $response.states) {
        $result += $state
    }

    return $result
}

function Get-Transitions($Workspace, $ItemId) {
    $ws = $flcConnection.Workspaces.Find($Workspace)
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/workflows/1/transitions" -Method Get -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
    return $response
}

function Update-FLCState($Workspace, $ItemId, $TransitionId, $Comment) {    
    $ws = $flcConnection.Workspaces.Find($Workspace)    
    $body = "{ `"comment`" : `"  + $Comment + `" }"
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/items/$($ItemId)/workflows/1/transitions" -Method Post -ContentType "application/json;charset=utf-8" -Body $body -Headers @{
        "Accept"           = "application/json"
        "Authorization"    = $flcConnection.AuthenticationToken
        "X-user-id"        = $flcConnection.UserId
        "X-Tenant"         = $flcConnection.Tenant
        "Content-Location" = "/api/v3/workspaces/$($ws.Id)/workflows/1/transitions/$($TransitionId)"
    }
}
#endregion
#region Views
function Get-FLCViews($Workspace, $ItemId) {    
    $ws = $flcConnection.Workspaces.Find($Workspace)
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/items/$($ItemId)/views" -Method Get -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
    return $response
}

function Get-FLCAffectedItemTransitions($Workspace, $ItemId, $viewId, $affectedItemId) {
    $ws = $flcConnection.Workspaces.Find($Workspace)
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/items/$($ItemId)/views/$($viewId)/affected-items/$($affectedItemId)/transitions" -Method Get -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
    return $response
}

function Get-FLCViewAffectedItem($Workspace, $ItemId, $viewId, $affectedItemId) {
    $ws = $flcConnection.Workspaces.Find($Workspace)
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/items/$($ItemId)/views/$($viewId)/affected-items/$($affectedItemId)" -Method Get -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }
    return $response
}

function Update-FLCViewAffectedItemTransition($Workspace, $ItemId, $viewId, $affectedItemId, $AffectedItem) {
    $ws = $flcConnection.Workspaces.Find($Workspace)
    $body = $AffectedItem | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($ws.Id)/items/$($ItemId)/views/$($viewId)/affected-items/$($affectedItemId)" -Method Put -ContentType "application/json" -Body $body -Headers @{
        "Accept"        = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-user-id"     = $flcConnection.UserId
        "X-Tenant"      = $flcConnection.Tenant
    }    
}
#endregion