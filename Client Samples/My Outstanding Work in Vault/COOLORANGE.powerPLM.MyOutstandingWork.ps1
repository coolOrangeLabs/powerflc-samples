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

Add-VaultMenuItem -Location ToolsMenu -Name "Fusion 360 Manage - My Outstanding Work..." -Action {

    $user = $vault.AdminService.GetUserByUserId($vaultConnection.UserID)
    if (-not $user.Email) {
        [System.Windows.MessageBox]::Show("Please set your email address in Vault.", "powerPLM Client", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    $connected = $false
    $settings = $vault.KnowledgeVaultService.GetVaultOption("POWERFLC_SETTINGS")
    if ($settings) {
        $settings = ConvertFrom-Json $settings
        $connected = Connect-FLC -Tenant $settings.Tenant.Name -ClientId $settings.Tenant.ClientId -ClientSecret $settings.Tenant.ClientSecret -UserId $user.Email
    }

    if (-not $connected) {
        [System.Windows.MessageBox]::Show("Connection to Fusion 360 Manage failed.", "powerPLM Client", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    $xamlFile = [xml](Get-Content "$PSScriptRoot\COOLORANGE.powerPLM.MyOutstandingWork.xaml")
    $window = [Windows.Markup.XamlReader]::Load( (New-Object System.Xml.XmlNodeReader $xamlFile) )

    # get item
    $response = Invoke-RestMethod -Uri "$($flcConnection.Url.AbsoluteUri)api/v3/users/@me/outstanding-work" -Method Get -Headers @{
        "Content-Type"  = "application/json"
        "Authorization" = $flcConnection.AuthenticationToken
        "X-tenant"      = $flcConnection.Tenant.ToUpper()
        "X-user-id"     = $flcConnection.UserId
    }

    $workItems = @()
    foreach ($work in $response.outstandingWork) {
        $dueDate = [string]::Empty
        if ($work.milestoneDate) {
            $dueDate = ([DateTime]$work.milestoneDate).ToString("MM/dd/yyyy")
        }

        $workItem = New-Object PSCustomObject -Property @{
            Title           = $work.item.title
            Urn             = $work.item.urn
            Workspace       = $work.workspace.title
            MilestoneStatus = $work.milestoneStatus
            DueDate         = $dueDate
            State           = $work.workflowStateName
        }

        $workItems += $workItem
    }

    $window.FindName('Button').Add_Click({
            $link = "$($flcConnection.Url.AbsoluteUri)plm/mainDashboard"
            Start-Process $link
        }.GetNewClosure())

    [System.Windows.RoutedEventHandler]$clickEvent = {
        param ($button, $e)
        $row = $button.DataContext
        $workspace = $flcConnection.Workspaces.Find($row.Workspace)
        $urn = $row.Urn.Replace(":", "%60").Replace(".", ",")
        $link = "$($flcConnection.Url.AbsoluteUri)plm/workspaces/$($workspace.Id)/items/itemDetails?view=full&tab=details&mode=view&itemId=$($urn)"
        Start-Process $link
    }
    
    $buttonColumn = New-Object System.Windows.Controls.DataGridTemplateColumn
    $buttonColumn.Header = "Open"
    $buttonFactory = New-Object System.Windows.FrameworkElementFactory([System.Windows.Controls.Button])
    $buttonFactory.SetValue([System.Windows.Controls.Button]::ContentProperty, "...")
    $buttonFactory.SetValue([System.Windows.Controls.Button]::HeightProperty, [double]18)
    $buttonFactory.SetValue([System.Windows.Controls.Button]::ToolTipProperty, "Open in Fusion 360 Manage...")
    $buttonFactory.AddHandler([System.Windows.Controls.Button]::ClickEvent, $clickEvent)
    $dataTemplate = New-Object System.Windows.DataTemplate
    $dataTemplate.VisualTree = $buttonFactory
    $buttonColumn.CellTemplate = $dataTemplate
    $window.FindName('DataGrid').Columns.Add($buttonColumn)
    $window.FindName('DataGrid').ItemsSource = $workItems

    $window.ShowDialog()
}