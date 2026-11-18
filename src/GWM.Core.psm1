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
    # be returned as an exit code so callers can classify expected conditions.
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

function ConvertTo-GwmRedactedRemoteUrl {
    [CmdletBinding()]
    param([AllowNull()][string]$RemoteUrl)
    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return $RemoteUrl }

    $redacted = [regex]::Replace($RemoteUrl, '(?<=://)[^/@\s]+@', '[REDACTED]@')
    $redacted = [regex]::Replace(
        $redacted,
        '(?i)([?&](?:token|access_token|auth|password|passwd|key|api_key)=)[^&#\s]*',
        '$1[REDACTED]'
    )
    return $redacted
}

function Get-GwmSyncEligibility {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$State)

    if (-not $State.IsRepository) { return [pscustomobject]@{ Eligible=$false; Reason='Not a valid Git working tree.' } }
    if ($State.Detached -or [string]::IsNullOrWhiteSpace([string]$State.Branch)) { return [pscustomobject]@{ Eligible=$false; Reason='HEAD is detached.' } }
    if ([string]::IsNullOrWhiteSpace([string]$State.Upstream)) { return [pscustomobject]@{ Eligible=$false; Reason='No unambiguous upstream is configured.' } }
    if ($State.IsDirty -or @($State.StatusLines).Count -gt 0) { return [pscustomobject]@{ Eligible=$false; Reason='Working tree or index is not clean.' } }
    if ($null -eq $State.Ahead -or $null -eq $State.Behind) { return [pscustomobject]@{ Eligible=$false; Reason='Upstream divergence is unknown.' } }
    if ($State.Ahead -gt 0) { return [pscustomobject]@{ Eligible=$false; Reason='Local branch contains commits not present upstream.' } }
    if ($State.Behind -le 0) { return [pscustomobject]@{ Eligible=$false; Reason='Local branch is not strictly behind upstream.' } }
    [pscustomobject]@{ Eligible=$true; Reason='Clean attached branch is strictly behind its upstream.' }
}

function Test-GwmRepositoryStateUnchanged {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Before,
        [Parameter(Mandatory = $true)]$After
    )

    $beforeStatus = (@($Before.StatusLines) -join "`n")
    $afterStatus = (@($After.StatusLines) -join "`n")
    return (
        [string]$Before.Branch -ceq [string]$After.Branch -and
        [string]$Before.Head -ceq [string]$After.Head -and
        [string]$Before.Upstream -ceq [string]$After.Upstream -and
        $beforeStatus -ceq $afterStatus
    )
}

function Invoke-GwmFetch {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Repository)

    $remote = [string]$Repository.Remote
    if ($remote -notmatch '^[A-Za-z0-9._-]+$') {
        return [pscustomobject]@{ Success=$false; Remote=$remote; Output='Configured remote name is invalid.'; ExitCode=2 }
    }

    $urlResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('remote', 'get-url', $remote)
    $remoteUrl = if ($urlResult.ExitCode -eq 0) { $urlResult.Output } else { $null }
    $fetchResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('fetch', '--no-prune', '--no-tags', $remote)
    $output = ConvertTo-GwmRedactedRemoteUrl -RemoteUrl $fetchResult.Output
    if ($remoteUrl) {
        $safeUrl = ConvertTo-GwmRedactedRemoteUrl -RemoteUrl $remoteUrl
        $output = $output.Replace($remoteUrl, $safeUrl)
    }
    [pscustomobject]@{
        Success=($fetchResult.ExitCode -eq 0)
        Remote=$remote
        RemoteUrl=ConvertTo-GwmRedactedRemoteUrl -RemoteUrl $remoteUrl
        Output=$output
        ExitCode=$fetchResult.ExitCode
    }
}

function Invoke-GwmFetchForRepositories {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Repositories)

    $results = @()
    foreach ($repository in $Repositories) {
        try {
            $fetch = Invoke-GwmFetch -Repository $repository
            $results += [pscustomobject]@{
                Name=$repository.Name
                Path=$repository.Path
                FetchStatus=if ($fetch.Success) { 'FETCHED' } else { 'FAILED' }
                Remote=$fetch.Remote
                RemoteUrl=$fetch.RemoteUrl
                ExitCode=$fetch.ExitCode
                Reason=$fetch.Output
            }
        }
        catch {
            $results += [pscustomobject]@{
                Name=$repository.Name
                Path=$repository.Path
                FetchStatus='FAILED'
                Remote=[string]$repository.Remote
                RemoteUrl=$null
                ExitCode=$null
                Reason=(ConvertTo-GwmRedactedRemoteUrl -RemoteUrl $_.Exception.Message)
            }
        }
    }
    return @($results)
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


function New-GwmSyncResult {
    param(
        [string]$Status,
        [string]$Reason,
        [string]$RecommendedAction,
        [AllowNull()][string]$BeforeCommit,
        [AllowNull()][string]$AfterCommit,
        [AllowNull()][string]$TargetCommit,
        [AllowNull()][object]$Ahead,
        [AllowNull()][object]$Behind,
        [AllowNull()][object]$ExitCode
    )
    [pscustomobject]@{
        SyncStatus=$Status
        Reason=$Reason
        RecommendedAction=$RecommendedAction
        BeforeCommit=$BeforeCommit
        AfterCommit=$AfterCommit
        TargetCommit=$TargetCommit
        Ahead=$Ahead
        Behind=$Behind
        ExitCode=$ExitCode
    }
}

function Invoke-GwmFastForward {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Repository)

    $beforeFetch = Get-GwmRepositoryState -Repository $Repository
    if (-not $beforeFetch.IsRepository) {
        return New-GwmSyncResult -Status 'FAILED' -Reason $beforeFetch.Reason -RecommendedAction 'Verify the repository path and Git working tree.' -BeforeCommit $null -AfterCommit $null -TargetCommit $null -Ahead $null -Behind $null -ExitCode 2
    }

    # A detached branch or branch without an upstream cannot be synchronized.
    # Classify it before contacting the configured remote so a missing origin
    # does not mask the actionable repository configuration state.
    if ($beforeFetch.Detached -or [string]::IsNullOrWhiteSpace([string]$beforeFetch.Upstream)) {
        $eligibility = Get-GwmSyncEligibility -State $beforeFetch
        return New-GwmSyncResult -Status 'NEEDS_ATTENTION' -Reason $eligibility.Reason -RecommendedAction $beforeFetch.RecommendedAction -BeforeCommit $beforeFetch.Head -AfterCommit $beforeFetch.Head -TargetCommit $null -Ahead $beforeFetch.Ahead -Behind $beforeFetch.Behind -ExitCode 0
    }

    $fetch = Invoke-GwmFetch -Repository $Repository
    if (-not $fetch.Success) {
        return New-GwmSyncResult -Status 'FAILED' -Reason ("Fetch failed for remote '{0}': {1}" -f $fetch.Remote, $fetch.Output) -RecommendedAction 'Check remote configuration and network/authentication, then run Sync again.' -BeforeCommit $beforeFetch.Head -AfterCommit $beforeFetch.Head -TargetCommit $null -Ahead $beforeFetch.Ahead -Behind $beforeFetch.Behind -ExitCode $fetch.ExitCode
    }

    $afterFetch = Get-GwmRepositoryState -Repository $Repository
    if (-not (Test-GwmRepositoryStateUnchanged -Before $beforeFetch -After $afterFetch)) {
        return New-GwmSyncResult -Status 'NEEDS_ATTENTION' -Reason 'Repository state changed while fetching; no working-branch update was attempted.' -RecommendedAction 'Inspect the repository state and run Sync again when no other Git operation is active.' -BeforeCommit $beforeFetch.Head -AfterCommit $afterFetch.Head -TargetCommit $null -Ahead $afterFetch.Ahead -Behind $afterFetch.Behind -ExitCode 0
    }

    $eligibility = Get-GwmSyncEligibility -State $afterFetch
    if (-not $eligibility.Eligible) {
        $status = if ($afterFetch.Classification -eq 'UP_TO_DATE') { 'UP_TO_DATE' } else { 'NEEDS_ATTENTION' }
        return New-GwmSyncResult -Status $status -Reason $eligibility.Reason -RecommendedAction $afterFetch.RecommendedAction -BeforeCommit $afterFetch.Head -AfterCommit $afterFetch.Head -TargetCommit $null -Ahead $afterFetch.Ahead -Behind $afterFetch.Behind -ExitCode 0
    }

    $remote = [string]$Repository.Remote
    $expectedPrefix = $remote + '/'
    if (-not $afterFetch.Upstream.StartsWith($expectedPrefix, [System.StringComparison]::Ordinal)) {
        return New-GwmSyncResult -Status 'NEEDS_ATTENTION' -Reason ("Branch upstream '{0}' does not belong to configured remote '{1}'." -f $afterFetch.Upstream, $remote) -RecommendedAction 'Align the repository remote setting and branch upstream, then run Sync again.' -BeforeCommit $afterFetch.Head -AfterCommit $afterFetch.Head -TargetCommit $null -Ahead $afterFetch.Ahead -Behind $afterFetch.Behind -ExitCode 0
    }

    $targetResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('rev-parse', '--verify', ($afterFetch.Upstream + '^{commit}'))
    if ($targetResult.ExitCode -ne 0 -or $targetResult.Output -notmatch '^[0-9a-fA-F]{40,64}$') {
        return New-GwmSyncResult -Status 'FAILED' -Reason 'Unable to resolve the fetched upstream to a commit SHA.' -RecommendedAction 'Inspect the configured upstream and fetched remote-tracking reference.' -BeforeCommit $afterFetch.Head -AfterCommit $afterFetch.Head -TargetCommit $null -Ahead $afterFetch.Ahead -Behind $afterFetch.Behind -ExitCode $targetResult.ExitCode
    }
    $targetCommit = $targetResult.Output.ToLowerInvariant()

    $ancestorResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('merge-base', '--is-ancestor', 'HEAD', $targetCommit)
    if ($ancestorResult.ExitCode -ne 0) {
        $status = if ($ancestorResult.ExitCode -eq 1) { 'NEEDS_ATTENTION' } else { 'FAILED' }
        return New-GwmSyncResult -Status $status -Reason 'The fetched target is not confirmed as a fast-forward descendant of HEAD.' -RecommendedAction 'Review local and upstream history manually; GWM will not merge or rebase.' -BeforeCommit $afterFetch.Head -AfterCommit $afterFetch.Head -TargetCommit $targetCommit -Ahead $afterFetch.Ahead -Behind $afterFetch.Behind -ExitCode $ancestorResult.ExitCode
    }

    $beforeUpdate = Get-GwmRepositoryState -Repository $Repository
    if (-not (Test-GwmRepositoryStateUnchanged -Before $afterFetch -After $beforeUpdate)) {
        return New-GwmSyncResult -Status 'NEEDS_ATTENTION' -Reason 'Repository state changed immediately before update; no working-branch update was attempted.' -RecommendedAction 'Inspect the repository state and run Sync again when no other Git operation is active.' -BeforeCommit $afterFetch.Head -AfterCommit $beforeUpdate.Head -TargetCommit $targetCommit -Ahead $beforeUpdate.Ahead -Behind $beforeUpdate.Behind -ExitCode 0
    }

    $confirmedTarget = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('rev-parse', '--verify', ($beforeUpdate.Upstream + '^{commit}'))
    if ($confirmedTarget.ExitCode -ne 0 -or $confirmedTarget.Output.ToLowerInvariant() -cne $targetCommit) {
        return New-GwmSyncResult -Status 'NEEDS_ATTENTION' -Reason 'The upstream tracking reference changed after the target commit was captured.' -RecommendedAction 'Fetch and inspect the repository again before attempting an update.' -BeforeCommit $beforeUpdate.Head -AfterCommit $beforeUpdate.Head -TargetCommit $targetCommit -Ahead $beforeUpdate.Ahead -Behind $beforeUpdate.Behind -ExitCode $confirmedTarget.ExitCode
    }

    $mergeResult = Invoke-GwmGit -RepositoryPath $Repository.Path -Arguments @('merge', '--ff-only', '--no-edit', $targetCommit)
    if ($mergeResult.ExitCode -ne 0) {
        $afterFailure = Get-GwmRepositoryState -Repository $Repository
        return New-GwmSyncResult -Status 'FAILED' -Reason ("Fast-forward-only update was rejected: {0}" -f $mergeResult.Output) -RecommendedAction 'Do not retry with merge or rebase. Inspect the repository manually and resolve any in-progress Git operation.' -BeforeCommit $beforeUpdate.Head -AfterCommit $afterFailure.Head -TargetCommit $targetCommit -Ahead $afterFailure.Ahead -Behind $afterFailure.Behind -ExitCode $mergeResult.ExitCode
    }

    $afterUpdate = Get-GwmRepositoryState -Repository $Repository
    if (-not $afterUpdate.IsRepository -or $afterUpdate.Detached -or $afterUpdate.Head -cne $targetCommit -or $afterUpdate.IsDirty -or $afterUpdate.Ahead -ne 0 -or $afterUpdate.Behind -ne 0) {
        return New-GwmSyncResult -Status 'FAILED' -Reason 'Post-update verification failed: HEAD, branch state, divergence, or working-tree cleanliness did not match the expected target.' -RecommendedAction 'Stop further synchronization and inspect the repository manually.' -BeforeCommit $beforeUpdate.Head -AfterCommit $afterUpdate.Head -TargetCommit $targetCommit -Ahead $afterUpdate.Ahead -Behind $afterUpdate.Behind -ExitCode 1
    }

    New-GwmSyncResult -Status 'UPDATED' -Reason 'Branch fast-forwarded to the fetched upstream commit and post-update verification passed.' -RecommendedAction 'No further action required.' -BeforeCommit $beforeUpdate.Head -AfterCommit $afterUpdate.Head -TargetCommit $targetCommit -Ahead $afterUpdate.Ahead -Behind $afterUpdate.Behind -ExitCode 0
}

function Invoke-GwmSyncForRepositories {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$Repositories)

    $results = @()
    foreach ($repository in $Repositories) {
        try {
            $sync = Invoke-GwmFastForward -Repository $repository
            $results += [pscustomobject]@{
                Name=$repository.Name
                Path=$repository.Path
                SyncStatus=$sync.SyncStatus
                Reason=$sync.Reason
                RecommendedAction=$sync.RecommendedAction
                BeforeCommit=$sync.BeforeCommit
                AfterCommit=$sync.AfterCommit
                TargetCommit=$sync.TargetCommit
                Ahead=$sync.Ahead
                Behind=$sync.Behind
                ExitCode=$sync.ExitCode
            }
        }
        catch {
            $results += [pscustomobject]@{
                Name=$repository.Name
                Path=$repository.Path
                SyncStatus='FAILED'
                Reason=(ConvertTo-GwmRedactedRemoteUrl -RemoteUrl $_.Exception.Message)
                RecommendedAction='Inspect this repository manually; other repositories will continue independently.'
                BeforeCommit=$null
                AfterCommit=$null
                TargetCommit=$null
                Ahead=$null
                Behind=$null
                ExitCode=$null
            }
        }
    }
    return @($results)
}


function New-GwmRunReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Scan', 'Sync')][string]$Mode,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [AllowEmptyCollection()][object[]]$Results = @(),
        [Parameter(Mandatory = $true)][DateTimeOffset]$StartedAt,
        [Parameter(Mandatory = $true)][DateTimeOffset]$FinishedAt
    )

    $counts = @{
        Updated = 0
        UpToDate = 0
        NeedsAttention = 0
        Failed = 0
    }

    foreach ($result in @($Results)) {
        $status = if ($Mode -eq 'Scan') {
            [string]$result.Classification
        }
        else {
            [string]$result.SyncStatus
        }

        switch ($status) {
            'UPDATED' { $counts.Updated++ }
            'UP_TO_DATE' { $counts.UpToDate++ }
            'FAILED' { $counts.Failed++ }
            default { $counts.NeedsAttention++ }
        }
    }

    $durationMs = [int][math]::Max(0, [math]::Round(($FinishedAt - $StartedAt).TotalMilliseconds))

    [pscustomobject]@{
        SchemaVersion = '1.0'
        RunId = [guid]::NewGuid().ToString('N')
        Mode = $Mode
        GeneratedAt = $FinishedAt.ToString('o')
        DurationMs = $durationMs
        WorkspaceRoot = $WorkspaceRoot
        RepositoryCount = @($Results).Count
        Summary = [pscustomobject]@{
            Updated = $counts.Updated
            UpToDate = $counts.UpToDate
            NeedsAttention = $counts.NeedsAttention
            Failed = $counts.Failed
        }
        Results = @($Results)
        OutputWarnings = @()
    }
}

Export-ModuleMember -Function Get-GwmConfiguration, Find-GwmRepositories, Invoke-GwmGit, Get-GwmRepositoryState, Get-GwmStateClassification, ConvertTo-GwmRedactedRemoteUrl, Get-GwmSyncEligibility, Test-GwmRepositoryStateUnchanged, Invoke-GwmFetch, Invoke-GwmFetchForRepositories, Invoke-GwmFastForward, Invoke-GwmSyncForRepositories, New-GwmRunReport
