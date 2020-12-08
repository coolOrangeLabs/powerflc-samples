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

function AddFolderProperties($vaultFolder, $propDefs){
    $propInsts = $vault.PropertyService.GetProperties("FLDR", @($vaultFolder.Id), $propDefs.Id)

    $existingProperties = $vaultFolder | Get-Member -MemberType @("Property", "NoteProperty") | Select-Object { $_.Name } -ExpandProperty Name
    foreach ($propInst in $propInsts) {
        $propDef = $propDefs | Where-Object { $_.Id -eq $propInst.PropDefId }
        if ($existingProperties -notcontains $propDef.DispName) {
            $vaultFolder | Add-Member NoteProperty $propDef.DispName $propInst.Val
        }
    }
}

function CopyFolderProperties($sourceFolder, $targetFolder, $propDefs)
{
    $noSysPropDefs = $propDefs | Where-Object { $_.IsSys -eq $false } | Select-Object { $_.Id } -ExpandProperty Id
    $propInsts = $vault.PropertyService.GetProperties("FLDR", @($sourceFolder.Id), $noSysPropDefs)
    if (-not $propInsts) { return }

    $propInstParamArray = New-Object Autodesk.Connectivity.WebServices.PropInstParamArray
    $propInstParams = @()
    foreach ($propInst in $propInsts) {
        $propInstParam = New-Object Autodesk.Connectivity.WebServices.PropInstParam
        $propInstParam.PropDefId = $propInst.PropDefId
        $propInstParam.Val = $propInst.Val
        $propInstParams += $propInstParam
    }
    $propInstParamArray.Items = $propInstParams

    $vault.DocumentServiceExtensions.UpdateFolderProperties(@($targetFolder.Id), @($propInstParamArray));
}

function CopyFolder($sourceFolder, $targetFolder, $propDefs)
{
    $childFolders = $vault.DocumentService.GetFoldersByParentId($sourceFolder.Id, $false)
    if (-not $childFolders) { return }
    foreach ($childFolder in $childFolders)
    {
        $newFolder = $vault.DocumentServiceExtensions.AddFolderWithCategory($childFolder.Name, $targetFolder.Id, $false, $childFolder.Cat.CatId)
        CopyFolderProperties $childFolder $newFolder $propDefs
        CopyFolder $childFolder $newFolder $propDefs
    }
}

class MappedProperty {
    [string]$FlcName
    [object]$FlcValue
    [string]$VaultName
    [object]$VaultValue
    [bool]IsIdentical () { 
        if($this.FlcValue) { $flcValueFilled = $true } else { $flcValueFilled = $false }
        if($this.VaultValue) { $vaultValueFilled = $true } else { $vaultValueFilled = $false }
        if ($flcValueFilled -eq $false -and $vaultValueFilled -eq $false ) {
            return $true
        }
        if($this.VaultValue -and $this.FlcValue) {
            if ($this.FlcValue.GetType() -eq [byte[]] -or $this.VaultValue.GetType() -eq [byte[]]) {
                return ([string]$this.FlcValue -eq [string]$this.VaultValue)
            }
        }
        return ($this.FlcValue -eq $this.VaultValue -and $flcValueFilled -eq $vaultValueFilled) 
    }
}

function GetFlcPropertiesToUpdate ($mappingName, $entity, $flcItem) {
    $properties = @{}
    $mappedProperties = GetMappedProperties -mappingName $mappingName -entity $entity -flcItem $flcItem
    foreach ($mp in $mappedProperties) {
        if (-not $mp.IsIdentical()) {            
            $properties.Add($mp.FlcName, $mp.VaultValue)
        }
    }
    return $properties;
}

function GetVaultPropertiesToUpdate ($mappingName, $entity, $flcItem) {
    $properties = @{}
    $mappedProperties = GetMappedProperties -mappingName $mappingName -entity $entity -flcItem $flcItem
    foreach ($mp in $mappedProperties) {
        if (-not $mp.IsIdentical()) {            
            $properties.Add($mp.VaultName, $mp.FlcValue)
        }
    }
    return $properties;
}

function GetMappedProperties($mappingName, $entity, $flcItem) {
    $mapping = $workflow.Mappings | Where-Object { $_.Name -eq $mappingName }
    if (-not $mapping) {
        throw "Cannot find mapping configuration for mapping '$mappingName'"
    }

    $mappedProperties = New-Object System.Collections.Generic.List[MappedProperty] 
    foreach($fieldMapping in $mapping.FieldMappings) {
        $m = [MappedProperty]::new()
        $m.FlcName = $fieldMapping.Flc
        $m.VaultName =  $fieldMapping.Function + $fieldMapping.Vault
        
        if ($entity) {
            $value = $null
            if ($fieldMapping.Function) {
                $value = &$fieldMapping.Function $entity
            } else {
                $propName = $fieldMapping.Vault
                $value = $entity.$propName
            }
            if ($value -and $value.GetType() -eq [Autodesk.DataManagement.Client.Framework.Vault.Currency.Properties.ThumbnailInfo]) {
                $value = $value.Image
            }
            $m.VaultValue = $value
        }

        if ($flcItem) {
            $fieldName = $fieldMapping.Flc
            $m.FlcValue = $flcItem.$fieldName
        }

        $mappedProperties.Add($m) | Out-Null
    }        

    return $mappedProperties    
}