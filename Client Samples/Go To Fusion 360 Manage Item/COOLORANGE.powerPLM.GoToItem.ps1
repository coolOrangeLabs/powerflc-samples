#==============================================================================#
# (c) 2023 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

Add-VaultMenuItem -Location ItemContextMenu -Name "Go To Fusion 360 Manage Item..." -Action {
    param($entities)
    
    if (-not $flcConnection) {
        # Connect to Fusion 360 Manage
        $connected = $false
        $settings = $vault.KnowledgeVaultService.GetVaultOption("POWERFLC_SETTINGS")
        if ($settings) {
            $settings = ConvertFrom-Json $settings
            $connected = Connect-FLC -Tenant $settings.Tenant.Name -ClientId $settings.Tenant.ClientId -ClientSecret $settings.Tenant.ClientSecret -UserId $settings.Tenant.SystemUserEmail
        }

        if (-not $connected) {
            Write-Host "Connection to Fusion 360 Manage failed."
            return
        }        
    }

    $workspace = $flcConnection.Workspaces.Find("Items") #TODO: adjust your workspace name if it's not "Items"

    foreach($item in $entities){

        $entAttrs = @($vault.PropertyService.GetEntityAttributes($item.MasterId, "FLC.ITEM"))
        $entAttr = $entAttrs | Where-Object { $_.Attr -eq "Urn" }
        if (-not $entAttr) { continue }

        $flcItem = (Get-FLCItems -Workspace $workspace.Name -Filter ('ITEM_DETAILS:{0}="{1}"' -f "NUMBER", $item._Number))[0] #TODO: adjust your item number field if it's not "NUMBER"
        if ($? -eq $false) { continue }
        if (-not $flcItem) { continue }

        $urn = $entAttr.Val.Replace(":", "%60").Replace(".", ",")
        Start-Process "$($flcConnection.Url.AbsoluteUri)plm/workspaces/$($workspace.Id)/items/itemDetails?view=full&tab=details&mode=view&itemId=$($urn)"
    }
}