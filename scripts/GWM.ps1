[CmdletBinding()]
param(
    [ValidateSet('Scan', 'Sync')][string]$Mode = 'Scan',
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

# Resolve paths after parameter binding; automatic script variables may be empty
# while PowerShell evaluates default parameter expressions.
$scriptPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    throw 'Unable to determine the script path. Run this file with -File or from its script location.'
}
$scriptDirectory = Split-Path -Parent $scriptPath
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $scriptDirectory
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$modulePath = Join-Path $scriptDirectory '..\src\GWM.Core.psm1'
$exitCode = 0

try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    $configuration = Get-GwmConfiguration -ProjectRoot $ProjectRoot
    $repositories = @(Find-GwmRepositories -Configuration $configuration)

    Write-Host ''
    Write-Host 'Git Workspace Manager' -ForegroundColor Cyan
    Write-Host ("Mode: {0}" -f $Mode)
    Write-Host ("Workspace: {0}" -f $configuration.WorkspaceRoot)
    Write-Host ("Repositories discovered: {0}" -f $repositories.Count)
    Write-Host ''

    $reportName = 'latest-scan.json'
    if ($Mode -eq 'Scan') {
        $results = @()
        foreach ($repository in $repositories) {
            try {
                $result = Get-GwmRepositoryState -Repository $repository
                $results += $result
                Write-Host ("[{0}] {1} ({2})" -f $result.Classification, $result.Name, $result.Branch)
                if ($result.Reason) { Write-Host ("  {0}" -f $result.Reason) }
            }
            catch {
                $results += [pscustomobject]@{
                    Name=$repository.Name; Path=$repository.Path; Classification='FAILED'
                    Reason=$_.Exception.Message; RecommendedAction='Inspect this repository manually and run Scan again.'
                }
                Write-Warning ("Failed to inspect {0}: {1}" -f $repository.Name, $_.Exception.Message)
            }
        }

        $summary = [pscustomobject]@{
            GeneratedAt=(Get-Date).ToString('o')
            WorkspaceRoot=$configuration.WorkspaceRoot
            RepositoryCount=$results.Count
            Results=$results
        }
    }
    else {
        $results = @(Invoke-GwmSyncForRepositories -Repositories $repositories)
        foreach ($result in $results) {
            Write-Host ("[{0}] {1}" -f $result.SyncStatus, $result.Name)
            if ($result.Reason) { Write-Host ("  {0}" -f $result.Reason) }
            if ($result.RecommendedAction -and $result.SyncStatus -ne 'UPDATED' -and $result.SyncStatus -ne 'UP_TO_DATE') {
                Write-Host ("  Next: {0}" -f $result.RecommendedAction)
            }
        }

        $updatedCount = @($results | Where-Object { $_.SyncStatus -eq 'UPDATED' }).Count
        $upToDateCount = @($results | Where-Object { $_.SyncStatus -eq 'UP_TO_DATE' }).Count
        $attentionCount = @($results | Where-Object { $_.SyncStatus -eq 'NEEDS_ATTENTION' }).Count
        $failedCount = @($results | Where-Object { $_.SyncStatus -eq 'FAILED' }).Count

        $summary = [pscustomobject]@{
            Mode='Sync'
            GeneratedAt=(Get-Date).ToString('o')
            WorkspaceRoot=$configuration.WorkspaceRoot
            RepositoryCount=$results.Count
            Summary=[pscustomobject]@{
                Updated=$updatedCount
                UpToDate=$upToDateCount
                NeedsAttention=$attentionCount
                Failed=$failedCount
            }
            Results=$results
        }
        $reportName = 'latest-sync.json'

        if ($failedCount -gt 0) {
            $exitCode = 2
        }
        elseif ($attentionCount -gt 0) {
            $exitCode = 1
        }
    }

    $reportDirectory = Join-Path $ProjectRoot 'reports'
    if (-not (Test-Path -LiteralPath $reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    $reportPath = Join-Path $reportDirectory $reportName
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host ''
    Write-Host ("JSON report: {0}" -f $reportPath)
    if ($Mode -eq 'Sync') {
        Write-Host ("Summary: {0} updated, {1} up-to-date, {2} needs attention, {3} failed" -f $updatedCount, $upToDateCount, $attentionCount, $failedCount)
    }
}
catch {
    Write-Error $_
    exit 1
}

if ($exitCode -ne 0) {
    exit $exitCode
}
