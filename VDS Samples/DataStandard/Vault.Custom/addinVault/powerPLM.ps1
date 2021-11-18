# needs to be called from withing Default.ps1 - OnTabContextChanged
function OnTabContextChanged_Fusion360Manage
{
	if ($VaultContext.SelectedObject.TypeId.SelectionContext -eq "ItemMaster" -and $xamlFile -eq "powerPLM.xaml")
	{
		$items = $vault.ItemService.GetItemsByIds(@($vaultContext.SelectedObject.Id))
		$entity = Get-VaultItem -Number $items[0].ItemNum
		$flcItem = GetFlcItem "Vault Items and BOMs" "NUMBER" $entity._Number
		$dsWindow.FindName("F360MData").DataContext = $flcItem
		$dsWindow.FindName("VaultData").DataContext = $entity

		if (-not $flcItem) {
			$dsWindow.FindName("View").Visibility = "Hidden"
		} else {
			$dsWindow.FindName("View").Visibility = "Visible"
		}
	}
	if ($VaultContext.SelectedObject.TypeId.SelectionContext -eq "FileMaster" -and $xamlFile -eq "powerPLM.xaml")
	{
		$fileMasterId = $vaultContext.SelectedObject.Id
		$entity = Get-VaultFile -FileId $fileMasterId
		$flcItem = GetFlcItem "Vault Items and BOMs" "NUMBER" $entity._PartNumber
		$dsWindow.FindName("F360MData").DataContext = $flcItem
		$dsWindow.FindName("VaultData").DataContext = $entity

		if (-not $flcItem) {
			$dsWindow.FindName("View").Visibility = "Hidden"
		} else {
			$dsWindow.FindName("View").Visibility = "Visible"
		}
	}
	if ($VaultContext.SelectedObject.TypeId.SelectionContext -eq "ChangeOrder" -and $xamlFile -eq "powerPLM.xaml")
	{
		$entity = Get-VaultChangeOrder -ChangeOrderId $vaultContext.SelectedObject.Id
		$flcItem = GetFlcItem "Change Orders" "NUMBER" $entity._Number
		$dsWindow.FindName("F360MData").DataContext = $flcItem
		$dsWindow.FindName("F360MAffectedItems").ItemsSource = ($flcItem  | Get-FLCItemAssociations -AffectedItems)
		
		if (-not $flcItem) {
			$dsWindow.FindName("View").Visibility = "Hidden"
		} else {
			$dsWindow.FindName("View").Visibility = "Visible"
		}
	}
}

function GetFlcItem($workspace, $fieldName, $number)
{
	if (-not $flcConnection) {
		$option = $vault.KnowledgeVaultService.GetVaultOption("POWERFLC_SETTINGS")
		$settings = ConvertFrom-Json $option
		Connect-FLC -Tenant $settings.Tenant.Name -ClientId $settings.Tenant.ClientId -ClientSecret $settings.Tenant.ClientSecret -UserId $settings.Tenant.SystemUserEmail | Out-Null
	}

	$flcItem = (Get-FLCItems -Workspace $workspace -Filter ('ITEM_DETAILS:{0}="{1}"' -f $fieldName, $number))[0]
	return $flcItem
}


function UpdateVaultEntity
{
	$flcItem = $dsWindow.FindName("F360MData").DataContext
	$entity = $dsWindow.FindName("VaultData").DataContext
	
	if ($entity._EntityTypeID -eq "ITEM") {
		# https://doc.coolorange.com/projects/coolorange-powervaultdocs/en/stable/code_reference/commandlets/update-vaultitem.html
		Update-VaultItem -Number $flcItem.Number -Description $flcItem.Description -Title $flcItem.Title
	} elseif ($entity._EntityTypeID -eq "FILE") {
		# https://doc.coolorange.com/projects/coolorange-powervaultdocs/en/stable/code_reference/commandlets/update-vaultfile.html
		Update-VaultFile -File $entity._FullPath -Properties @{
			"Description" = $flcItem.Description
			"Title" = $flcItem.Title
		}
	}

	RefreshView $entity
}

function UpdateF360MItem
{
	$flcItem = $dsWindow.FindName("F360MData").DataContext
	$entity = $dsWindow.FindName("VaultData").DataContext

	if ($entity._EntityTypeID -eq "ITEM") {
		# https://doc.coolorange.com/projects/coolorange-powerflcdocs/en/stable/code_reference/commandlets/Update-FLCItem.html
		$flcItem | Update-FLCItem -Properties @{ 
			"Description" = $entity.'Description (Item,CO)'
			"Title" = $entity.'Title (Item,CO)'
			"Units" = $entity.Units
		}
	} elseif ($entity._EntityTypeID -eq "FILE") {
			# https://doc.coolorange.com/projects/coolorange-powerflcdocs/en/stable/code_reference/commandlets/Update-FLCItem.html
			$flcItem | Update-FLCItem -Properties @{ 
				"Description" = $entity.'Description'
				"Title" = $entity.'Title'
			}	
	}

	RefreshView $entity
}

function RefreshView($entity) {
	[System.Windows.Forms.SendKeys]::SendWait("{F5}")

	if ($entity._EntityTypeID -eq "FILE") {
		$file = $vault.DocumentService.GetLatestFileByMasterId($entity.MasterId)
		$folder = $vault.DocumentService.GetFolderById($file.FolderId)
		$cFolder = New-Object Connectivity.Services.Document.Folder($folder)
		$cDocFolder = New-Object Connectivity.Explorer.Document.DocFolder($cFolder)
		$cFile = New-Object Connectivity.Services.Document.File($file)
		$cFileExplorerObject = New-Object Connectivity.Explorer.Document.FileExplorerObject($cFile)

		$vwCtx = New-Object Connectivity.Explorer.Framework.LocationContext($cFileExplorerObject, $cDocFolder)
		$navCtx = New-Object Connectivity.Explorer.Framework.LocationContext($cDocFolder)
	} elseif ($entity._EntityTypeID -eq "ITEM") {
		$item = $vault.ItemService.GetLatestItemByItemMasterId($entity.MasterId)
		$cItemRev = New-Object Connectivity.Services.Item.ItemRevision($vaultConnection, $item)
		$cItemRevExpObj = New-Object Connectivity.Explorer.Item.ItemRevisionExplorerObject($cItemRev)
		$cItemMaster = New-Object Connectivity.Explorer.Item.ItemMaster

		$vwCtx = New-Object Connectivity.Explorer.Framework.LocationContext($cItemRevExpObj)
		$navCtx = New-Object Connectivity.Explorer.Framework.LocationContext($cItemMaster)
	} elseif ($entity._EntityTypeID -eq "CO") {
		$eco = $vault.ChangeOrderService.GetChangeOrderByNumber($entity.Number)
		$cCoRev = New-Object Connectivity.Services.ChangeOrder.ChangeOrder($eco)
		$cCoRevExpObj = New-Object Connectivity.Explorer.ChangeOrderObjects.ChangeOrderExplorerObject($cCoRev)
		$cCoMaster = New-Object Connectivity.Explorer.ChangeOrderObjects.COMaster

		$vwCtx = New-Object Connectivity.Explorer.Framework.LocationContext($cCoRevExpObj)
		$navCtx = New-Object Connectivity.Explorer.Framework.LocationContext($cCoMaster)
	}
	else {
		return
	}

	$sc = New-Object Connectivity.Explorer.Framework.ShortcutMgr+Shortcut
	$sc.NavigationContext = $navCtx
	$sc.ViewContext = $vwCtx
	$sc.Select($null)    
}

function GoToFlc
{
	$flcItem = $dsWindow.FindName("F360MData").DataContext
	$url = GetUrl $flcItem
	[System.Diagnostics.Process]::Start($url)
}

function GetUrl($flcItem)
{
	if (-not $flcItem.Id) {
		return $flcConnection.Url.AbsoluteUri + "plm/mainDashboard"
	} else {
		$ws = $flcConnection.Workspaces.Find($flcItem.Workspace)
		$urn = ("urn%60adsk,plm%60tenant,workspace,item%60{0},{1},{2}" -f $flcConnection.Tenant.ToUpper(), $ws.Id, $flcItem.Id)
		$url = ("https://{0}.autodeskplm360.net/plm/workspaces/{1}/items/itemDetails?view=full&tab=details&mode=view&itemId={2}" -f $flcConnection.Tenant.ToLower(), $ws.Id, $urn)
		return $url
	}
}