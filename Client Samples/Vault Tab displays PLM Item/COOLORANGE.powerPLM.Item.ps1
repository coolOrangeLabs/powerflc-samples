#==============================================================================#
# (c) 2023 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

if ($processName -notin @('Connectivity.VaultPro')) {
    return
}

Add-VaultTab -Name 'Fusion 360 Manage Item' -EntityType Item -Action {
    param($selectedItem)

    $partNumber = $selectedItem._Number
    $xamlFile = [xml](Get-Content "$PSScriptRoot\COOLORANGE.powerPLM.Item.xaml")
    $tab = [Windows.Markup.XamlReader]::Load( (New-Object System.Xml.XmlNodeReader $xamlFile) )

    $tab.FindName('Button').Visibility = "Collapsed"
    $tab.FindName('ItemData').Visibility = "Collapsed"

    # Connect to Fusion 360 Manage
    $connected = $false
    $settings = $vault.KnowledgeVaultService.GetVaultOption("POWERFLC_SETTINGS")
    if ($settings) {
        $settings = ConvertFrom-Json $settings
        $connected = Connect-FLC -Tenant $settings.Tenant.Name -ClientId $settings.Tenant.ClientId -ClientSecret $settings.Tenant.ClientSecret -UserId $settings.Tenant.SystemUserEmail
    }

    if (-not $connected) {
        $tab.FindName('Title').Content = "Connection to Fusion 360 Manage failed."
        return $tab
    }
    
    # Get Fusion 360 Manage Item
    $workspace = $flcConnection.Workspaces.Find("Items")
    $flcItem = (Get-FLCItems -Workspace $workspace.Name -Filter ('ITEM_DETAILS:{0}="{1}"' -f "NUMBER", $partNumber))[0]
    if ($? -eq $false) { return }

    if (-not $flcItem) {
        $tab.FindName('Title').Content = "No Fusion 360 Manage Item associated with item $($partNumber)"
        return $tab
    }

    # Display Fusion 360 Manage Item
    $tab.FindName('ItemData').Visibility = "Visible"
    $tab.FindName('ItemData').DataContext = $flcItem
    $tab.FindName('Title').Content = "Fusion 360 Manage Item '$partNumber' - '$($flcItem.Title)'"
    $tab.FindName('Button').Visibility = "Visible"
    $tab.FindName('Button').Content = "Go To PLM Item..."

    # Get Fusion 360 Manage Change Order
    $flcItemRaw = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/workspaces/$($workspace.Id)/items/$($flcItem.RootId)" -Method Get -Headers @{
        "Content-Type"  = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-tenant"      = $flcConnection.Tenant.ToUpper()
        "X-user-id"     = $flcConnection.UserId
    }
    $flcChangeOrder = (Get-FLCItems -Workspace "Change Orders" -Filter ('{0}="{1}"' -f "itemDescriptor", $flcItemRaw.undergoingChange.title))[0]
    if ($flcChangeOrder) {
        $tab.FindName('ChangeOrderData').DataContext = $flcChangeOrder
    }

    # Add button click event
    $urn = $flcItemRaw.urn.Replace(":", "%60").Replace(".", ",")
    $tab.FindName('Button').Tag = "$($flcConnection.Url.AbsoluteUri)plm/workspaces/$($workspace.Id)/items/itemDetails?view=full&tab=details&mode=view&itemId=$($urn)"
    $tab.FindName('Button').Add_Click({
            param ($button, $e)
            Start-Process $button.Tag
        }.GetNewClosure())

    return $tab
}