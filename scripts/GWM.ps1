[CmdletBinding()]
param(
    [ValidateSet('Scan')][string]$Mode = 'Scan',
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\src\GWM.Core.psm1'

try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    $configuration = Get-GwmConfiguration -ProjectRoot $ProjectRoot
    $repositories = @(Find-GwmRepositories -Configuration $configuration)

    Write-Host ''
    Write-Host 'Git Workspace Manager' -ForegroundColor Cyan
    Write-Host ("Workspace: {0}" -f $configuration.WorkspaceRoot)
    Write-Host ("Repositories discovered: {0}" -f $repositories.Count)
    Write-Host ''

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
    $reportDirectory = Join-Path $ProjectRoot 'reports'
    if (-not (Test-Path -LiteralPath $reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    $reportPath = Join-Path $reportDirectory 'latest-scan.json'
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host ''
    Write-Host ("JSON report: {0}" -f $reportPath)
}
catch {
    Write-Error $_
    exit 1
}
