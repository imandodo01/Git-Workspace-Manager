Set-StrictMode -Version 2.0

function Read-GwmJsonFile {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Description was not found: $Path" }
    try {
        return ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) -ErrorAction Stop
    }
    catch { throw "Unable to read $Description '$Path': $($_.Exception.Message)" }
}

function Get-GwmConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $root = [System.IO.Path]::GetFullPath($ProjectRoot)
    $settings = Read-GwmJsonFile -Path (Join-Path $root 'config/settings.json') -Description 'Settings file'
    if (-not $settings.workspace -or [string]::IsNullOrWhiteSpace([string]$settings.workspace.root)) {
        throw 'Configuration must define workspace.root.'
    }

    $workspaceRoot = [Environment]::ExpandEnvironmentVariables([string]$settings.workspace.root)
    if (-not [System.IO.Path]::IsPathRooted($workspaceRoot)) { $workspaceRoot = Join-Path $root $workspaceRoot }
    $workspaceRoot = [System.IO.Path]::GetFullPath($workspaceRoot)
    if (-not (Test-Path -LiteralPath $workspaceRoot -PathType Container)) {
        throw "Workspace root does not exist or is not a directory: $workspaceRoot"
    }

    $excluded = @('.git', 'node_modules', 'vendor', '.venv')
    $excludedProperty = $settings.workspace.PSObject.Properties['excludedDirectories']
    if ($null -ne $excludedProperty -and $null -ne $excludedProperty.Value) {
        $excluded = @($excludedProperty.Value)
    }
    $remote = if ($settings.git.defaultRemote) { [string]$settings.git.defaultRemote } else { 'origin' }
    if ($remote -notmatch '^[A-Za-z0-9._-]+$') { throw 'git.defaultRemote contains unsupported characters.' }
    $strategy = if ($settings.git.syncStrategy) { [string]$settings.git.syncStrategy } else { 'ff-only' }
    if ($strategy -ne 'ff-only') { throw "Unsupported synchronization strategy: $strategy" }

    [pscustomobject]@{
        ProjectRoot = $root
        WorkspaceRoot = $workspaceRoot
        RecursiveDiscovery = if ($null -ne $settings.workspace.recursiveDiscovery) { [bool]$settings.workspace.recursiveDiscovery } else { $true }
        ExcludedDirectories = $excluded
        DefaultRemote = $remote
        SyncStrategy = $strategy
    }
}

function Test-GwmPathWithinRoot {
    param([string]$Path, [string]$Root)
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Find-GwmRepositories {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Configuration)
    $workspace = $Configuration.WorkspaceRoot
    $registryPath = Join-Path $Configuration.ProjectRoot 'config/repositories.json'
    $found = @()

    if (Test-Path -LiteralPath $registryPath -PathType Leaf) {
        $registry = Read-GwmJsonFile -Path $registryPath -Description 'Repository registry'
        foreach ($entry in @($registry.repositories)) {
            if ($entry.enabled -eq $false) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$entry.path)) { throw 'Every enabled repository registry entry must define path.' }
            $candidate = [string]$entry.path
            if (-not [System.IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $workspace $candidate }
            $candidate = [System.IO.Path]::GetFullPath($candidate)
            if (-not (Test-GwmPathWithinRoot -Path $candidate -Root $workspace)) { throw "Repository path is outside the configured workspace: $candidate" }
            if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Registered repository directory does not exist: $candidate" }
            $found += [pscustomobject]@{
                Name = if ($entry.name) { [string]$entry.name } else { Split-Path $candidate -Leaf }
                Path = $candidate
                Remote = if ($entry.remote) { [string]$entry.remote } else { $Configuration.DefaultRemote }
            }
        }
        return @($found | Sort-Object -Property Path -Unique)
    }

    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($workspace)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        if (Test-Path -LiteralPath (Join-Path $current '.git')) {
            $found += [pscustomobject]@{ Name=(Split-Path $current -Leaf); Path=$current; Remote=$Configuration.DefaultRemote }
            continue
        }
        if (($current -ne $workspace) -and (-not $Configuration.RecursiveDiscovery)) { continue }
        foreach ($directory in @(Get-ChildItem -LiteralPath $current -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($Configuration.ExcludedDirectories -contains $directory.Name) { continue }
            $pending.Push($directory.FullName)
        }
    }
    @($found | Sort-Object -Property Path -Unique)
}

function Invoke-GwmGit {
    [CmdletBinding()]
    param([string]$RepositoryPath, [string[]]$Arguments)
    # Windows PowerShell 5.1 can promote native stderr to a terminating error
    # when the caller uses ErrorActionPreference=Stop. Git failures must instead
    # be returned as an exit code so callers can classify expected conditions
    # such as a branch without an upstream.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $RepositoryPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    [pscustomobject]@{ ExitCode=$exitCode; Output=(@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim() }
}

function Get-GwmStateClassification {
    [CmdletBinding()]
    param([string]$Branch, [bool]$UpstreamAvailable, [string[]]$StatusLines=@(), [Nullable[int]]$Ahead, [Nullable[int]]$Behind)
    if ([string]::IsNullOrWhiteSpace($Branch)) { return [pscustomobject]@{ Status='NEEDS_ATTENTION'; Reason='Detached HEAD.'; RecommendedAction='Check out the intended local branch in VS Code or Git.' } }
    if (-not $UpstreamAvailable) { return [pscustomobject]@{ Status='NEEDS_ATTENTION'; Reason='No upstream is configured.'; RecommendedAction='Configure the branch upstream, then scan again.' } }
    if (@($StatusLines).Count -gt 0) { return [pscustomobject]@{ Status='NEEDS_ATTENTION'; Reason='Working tree contains staged, modified, or untracked files.'; RecommendedAction='Review and safely handle local changes.' } }
    if ($null -eq $Ahead -or $null -eq $Behind) { return [pscustomobject]@{ Status='UNKNOWN'; Reason='Unable to calculate upstream divergence.'; RecommendedAction='Check Git remote and upstream availability.' } }
    if ($Ahead -gt 0 -and $Behind -gt 0) { return [pscustomobject]@{ Status='DIVERGED'; Reason='Local and upstream branches have diverged.'; RecommendedAction='Review both histories and resolve manually.' } }
    if ($Ahead -gt 0) { return [pscustomobject]@{ Status='AHEAD'; Reason='Local branch contains commits not present upstream.'; RecommendedAction='Review local commits before deciding whether to push.' } }
    if ($Behind -gt 0) { return [pscustomobject]@{ Status='BEHIND'; Reason='Local branch is behind upstream.'; RecommendedAction='A fast-forward may be possible after a fresh fetch and safety re-check.' } }
    [pscustomobject]@{ Status='UP_TO_DATE'; Reason='Local branch matches upstream.'; RecommendedAction='No action required.' }
}

function Get-GwmRepositoryState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Repository)
    $inside = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('rev-parse', '--is-inside-work-tree')
    if ($inside.ExitCode -ne 0 -or $inside.Output -ne 'true') {
        return [pscustomobject]@{ Name=$Repository.Name; Path=$Repository.Path; IsRepository=$false; Classification='INVALID_REPOSITORY'; Reason='Directory is not a Git working tree.' }
    }

    $branchResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('branch', '--show-current')
    $headResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('rev-parse', 'HEAD')
    $upstreamResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    $statusResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('status', '--porcelain', '--untracked-files=all')
    $branch = $branchResult.Output
    $files = @()
    if (-not [string]::IsNullOrWhiteSpace($statusResult.Output)) {
        $files = @($statusResult.Output -split '\r?\n' | Where-Object { $_ })
    }
    $ahead = $null
    $behind = $null
    if ($upstreamResult.ExitCode -eq 0) {
        $counts = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('rev-list', '--left-right', '--count', 'HEAD...@{u}')
        if ($counts.ExitCode -eq 0 -and $counts.Output -match '^\s*(\d+)\s+(\d+)\s*$') {
            $ahead = [int]$matches[1]; $behind = [int]$matches[2]
        }
    }
    $classification = Get-GwmStateClassification -Branch $branch -UpstreamAvailable ($upstreamResult.ExitCode -eq 0) -StatusLines $files -Ahead $ahead -Behind $behind
    [pscustomobject]@{
        Name=$Repository.Name; Path=$Repository.Path; IsRepository=$true
        Branch=if ($branch) { $branch } else { $null }
        Detached=[string]::IsNullOrWhiteSpace($branch)
        Upstream=if ($upstreamResult.ExitCode -eq 0) { $upstreamResult.Output } else { $null }
        Remote=[string]$Repository.Remote
        Head=if ($headResult.ExitCode -eq 0) { $headResult.Output } else { $null }
        StatusLines=@($files); IsDirty=(@($files).Count -gt 0); Ahead=$ahead; Behind=$behind
        Classification=$classification.Status; Reason=$classification.Reason; RecommendedAction=$classification.RecommendedAction
    }
}

Export-ModuleMember -Function Get-GwmConfiguration, Find-GwmRepositories, Invoke-GwmGit, Get-GwmRepositoryState, Get-GwmStateClassification
