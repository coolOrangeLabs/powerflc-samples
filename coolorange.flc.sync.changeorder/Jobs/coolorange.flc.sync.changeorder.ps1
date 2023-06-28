Import-Module vaultFLC
Write-Host "Starting job '$($job.Name)'..."

Write-Host "Connecting to Fusion 360 Manage..."
$connection = ConvertFrom-Json $vault.KnowledgeVaultService.GetVaultOption("VAULTFLC_CONNECTION_SETTINGS")
Connect-FLC -Tenant $connection.Tenant -ClientId $connection.ClientId -ClientSecret $connection.ClientSecret -UserId $connection.DefaultUserEmail
Write-Host "Connected to $($flcConnection.Url)"

function Get-FLCWorkspace($workspacId) {
    if($workspaceId.Contains('/')){ $workspaceId = $workspaceId.Split('/')[-1] }
    $workspace = $flcConnection.Workspaces.Item($workspaceId)
    return $workspace
}

$mapping = ConvertFrom-Json $vault.KnowledgeVaultService.GetVaultOption("VAULTFLC_MAPPING_SETTINGS")
$workspace = Get-FLCWorkspace -workspaceId $mapping.ECO_W
Write-Host "Workspace: $($workspace.Name)"

Write-Host "Get change orders"
$stateMappings = $mapping.ECO_StateMapping
foreach ($stateMapping in $stateMappings) {
    $flcStates = Get-FLCStates -Workspace $workspace.Name
    $flcState = $flcStates | Where-Object { $_.urn -like "*$($stateMapping.FLC)" }
    $changeOrders = Get-FLCItems -Workspace $workspace.Name -Filter "workflowState=`"$($flcState.name)`""
    Write-Host "$($changeOrders.Count) $($workspace.Name) found with state '$($flcState.name)'"
    foreach ($changeOrder in $changeOrders) {
        $affectedItems = Get-FLCAffectedItems -Workspace $workspace -item $changeOrder
        foreach ($affectedItem in $affectedItems) {
            $partNumber = $affectedItem.'Part Number'
            if ($null -ne $partNumber -and $partNumber -ne "") {
                Write-Host "Searching for Vault file with part number '$partNumber'"
                $vaultEntities = Get-VaultFiles -Properties @{ 'Part Number' = $partNumber }
                #$vaultEntities = Get-VaultItem -Number $partNumber
                foreach ($vaultEntity in $vaultEntities) {
                    Write-Host "Changing to state '$($stateMapping.VLT)' for '$($vaultEntity._Name)'"
                    Update-VaultFile -File $vaultEntity._FullPath -Status $stateMapping.VLT
                    #Write-Host "Changing to state '$($stateMapping.VLT)' for '$partNumber'"
                    #Update-VaultItem -Number $partNumber -Status "In Review" #TODO: implement status change as not supported yet by powerVault
                }
            }
        }
    }
}

Write-Host "Completed job '$($job.Name)'"