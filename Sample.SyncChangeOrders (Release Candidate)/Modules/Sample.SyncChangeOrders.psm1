Import-Module powerVault

#override Clean-Up Cmdlet because of issues deleting empty folders
function Clean-Up {
    param(
        [string]$folder = $null,
        $files = @()
    )
    function Remove-EmptyFolders($folder) {
        $folders = @($folder, (Get-ChildItem $folder -Recurse))
        $folders = @($folders | Where-Object { $_.PSIsContainer -and @(Get-ChildItem -LiteralPath $_.Fullname -Recurse | Where-Object { -not $_.PSIsContainer }).Count -eq 0 })
        Remove-Items $folders      
    }    
    function Remove-Items($items) {
        $items | ForEach-Object { Remove-Item -Path $_.FullName -Force -Recurse -confirm:$false -ErrorAction SilentlyContinue }
    }
    
    $files = @($files | ForEach-Object { 
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
        
    if (-not $folder -and $files.Count -gt 0) {
        $folder = $files[0]
        while ( $true ) {          
            if (-not ($folder = Split-Path $folder)) {
                throw('No folder found')
            }
            
            if (($files | Where-Object { (Split-Path $_).StartsWith($folder) }).Count -eq $files.Count) {
                break;
            }
        }
    }
    if (Test-Path $folder) {
        Remove-EmptyFolders (Get-Item $folder)
    }
}

function GetItemFromUrn($urn) {
    if (-not $urn) { return "" }
    $contents = $urn.Split(':');
    $values = $contents[$contents.Length - 1].Split('.')
    $names = $contents[$contents.Length - 2].Split('.')
    return $values[[array]::IndexOf($names, "item")];
}

function GetWorkspaceFromUrn($urn) {
    if (-not $urn) { return "" }
    $contents = $urn.Split(':');
    $values = $contents[$contents.Length - 1].Split('.')
    $names = $contents[$contents.Length - 2].Split('.')
    return $values[[array]::IndexOf($names, "workspace")];
}

function Add-VaultChangeOrderComment($ChangeOrderName, $Title, $Message) {
    if ($Title -or $Message) {
        try {
            $changeOrder = $vault.ChangeOrderService.GetChangeOrderByNumber($ChangeOrderName)

            $msgGroup = New-Object Autodesk.Connectivity.WebServices.MsgGroup
            $msg = New-Object Autodesk.Connectivity.WebServices.Msg
            $msg.MsgTxt = $Message
            $msg.CreateDate = (Get-Date)
            $msg.CreateUserName = $vaultConnection.UserName
            $msg.Subject = $Title
            $msgGroup.Msg = $msg
            $comments = @($msgGroup)

            $vault.ChangeOrderService.AddComment($changeOrder.Id, $comments, $null)
        }
        catch {
            if ($Error[0].Exception.InnerException -eq "1608") {
                throw "ERROR: Could not find the specified change order - $($ChangeOrderName)"
            } else {
                throw "ERROR: $($Error[0])"
            }
        }
    }
    else {
        Write-Warning "Title and Message are both empty. No comments will be added."
    }
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