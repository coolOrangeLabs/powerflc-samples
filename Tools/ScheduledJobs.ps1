Add-Type -Path "C:\Program Files\Autodesk\Vault Client 2021\Explorer\Autodesk.Connectivity.WebServices.dll"
$vaultServer = "localhost"
$vaultName = "Vault"
$vaultUser = "Administrator"
$vaultPassword = ""

$identities = New-Object Autodesk.Connectivity.WebServices.ServerIdentities
$identities.DataServer = $vaultServer
$identities.FileServer = $vaultServer
$credentials = New-Object Autodesk.Connectivity.WebServicesTools.UserPasswordCredentials($identities, $vaultName, $vaultUser, $vaultPassword, $false)
$vault = New-Object Autodesk.Connectivity.WebServicesTools.WebServiceManager ($credentials)


# delete all existing coolorange jobs that are added periodically
$jobs = $vault.JobService.GetScheduledJobs()
foreach($job in $jobs) {
    if ($job.Typ -like "coolorange.flc*") {
        $vault.JobService.DeleteScheduledJob($job.Id)
        Write-Host "$($job.Typ) deleted"
    }
}

<#
JobService.AddScheduledJob to add a job periodically
Parameters
type:              The type of job to add.
desc:              A description of the job.
paramArray:        An array of parameters for the job.
priority:          The priority of the job. A lower number means a higher priority. 1 is the lowest possible number.
execDate:          The DateTime at which the job is first scheduled (can be DateTime.Now).
execFreqInMinutes: The frequency in minutes at which to schedule the job (e.g. 1440 minutes = daily).
#>
# $vault.JobService.AddScheduledJob("coolorange.flc.sync.folder", "TEST", $null, 10, [System.DateTime]::Now, 1)