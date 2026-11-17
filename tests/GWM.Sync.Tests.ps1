$modulePath = Join-Path $PSScriptRoot '..\src\GWM.Core.psm1'
Import-Module -Name $modulePath -Force

function Invoke-GwmSyncTestGit {
    param([string]$RepositoryPath, [string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $RepositoryPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        throw ("Git test command failed ({0}) in {1}: {2}; {3}" -f $exitCode, $RepositoryPath, ($Arguments -join ' '), ($output -join [Environment]::NewLine))
    }
    return (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
}

function New-GwmSyncFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-sync-' + [guid]::NewGuid().ToString('N'))
    $seed = Join-Path $root 'seed'
    $remote = Join-Path $root 'remote.git'
    $local = Join-Path $root 'local'
    New-Item -ItemType Directory -Path $seed -Force | Out-Null
    Invoke-GwmSyncTestGit -RepositoryPath $seed -Arguments @('init') | Out-Null
    Invoke-GwmSyncTestGit -RepositoryPath $seed -Arguments @('config', 'user.name', 'GWM Sync Test') | Out-Null
    Invoke-GwmSyncTestGit -RepositoryPath $seed -Arguments @('config', 'user.email', 'gwm-sync@example.invalid') | Out-Null
    Set-Content -LiteralPath (Join-Path $seed 'baseline.txt') -Value 'baseline'
    Invoke-GwmSyncTestGit -RepositoryPath $seed -Arguments @('add', 'baseline.txt') | Out-Null
    Invoke-GwmSyncTestGit -RepositoryPath $seed -Arguments @('commit', '-m', 'initial sync test commit') | Out-Null
    $branch = Invoke-GwmSyncTestGit -RepositoryPath $seed -Arguments @('branch', '--show-current')
    & git init --bare $remote 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize disposable bare remote.' }
    Invoke-GwmSyncTestGit -RepositoryPath $seed -Arguments @('remote', 'add', 'origin', $remote) | Out-Null
    Invoke-GwmSyncTestGit -RepositoryPath $seed -Arguments @('push', '-u', 'origin', $branch) | Out-Null
    & git "--git-dir=$remote" symbolic-ref HEAD ("refs/heads/" + $branch) 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to set disposable remote HEAD.' }
    & git clone $remote $local 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clone disposable bare remote.' }
    Invoke-GwmSyncTestGit -RepositoryPath $local -Arguments @('config', 'user.name', 'GWM Sync Test') | Out-Null
    Invoke-GwmSyncTestGit -RepositoryPath $local -Arguments @('config', 'user.email', 'gwm-sync@example.invalid') | Out-Null
    [pscustomobject]@{
        Root=$root
        Seed=$seed
        Remote=$remote
        Local=$local
        Branch=$branch
        Repository=[pscustomobject]@{ Name='sync-fixture'; Path=$local; Remote='origin' }
    }
}

function Add-GwmSyncTestCommit {
    param([string]$RepositoryPath, [string]$FileName, [string]$Value, [string]$Message)
    Set-Content -LiteralPath (Join-Path $RepositoryPath $FileName) -Value $Value
    Invoke-GwmSyncTestGit -RepositoryPath $RepositoryPath -Arguments @('add', $FileName) | Out-Null
    Invoke-GwmSyncTestGit -RepositoryPath $RepositoryPath -Arguments @('commit', '-m', $Message) | Out-Null
}

Describe 'GWM guarded fast-forward executor' {
    BeforeEach { $script:GwmSyncFixture = New-GwmSyncFixture }

    AfterEach {
        if ($script:GwmSyncFixture -and (Test-Path -LiteralPath $script:GwmSyncFixture.Root)) {
            Remove-Item -LiteralPath $script:GwmSyncFixture.Root -Recurse -Force
        }
        $script:GwmSyncFixture = $null
    }

    It 'fast-forwards a clean behind branch to the exact fetched target and verifies the result' {
        Add-GwmSyncTestCommit -RepositoryPath $script:GwmSyncFixture.Seed -FileName 'remote-update.txt' -Value 'remote update' -Message 'remote update'
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Seed -Arguments @('push', 'origin', $script:GwmSyncFixture.Branch) | Out-Null
        $expected = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Seed -Arguments @('rev-parse', 'HEAD')

        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository

        $result.SyncStatus | Should Be 'UPDATED'
        $result.TargetCommit | Should Be $expected
        $result.AfterCommit | Should Be $expected
        (Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $expected
        (Get-Content -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'remote-update.txt') -Raw).Trim() | Should Be 'remote update'
        $state = Get-GwmRepositoryState -Repository $script:GwmSyncFixture.Repository
        $state.IsDirty | Should Be $false
        $state.Ahead | Should Be 0
        $state.Behind | Should Be 0
    }

    It 'leaves an up-to-date branch unchanged' {
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')
        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository
        $result.SyncStatus | Should Be 'UP_TO_DATE'
        $result.BeforeCommit | Should Be $before
        $result.AfterCommit | Should Be $before
        (Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $before
    }

    It 'does not update a dirty repository and preserves staged, unstaged, and untracked content' {
        Add-GwmSyncTestCommit -RepositoryPath $script:GwmSyncFixture.Seed -FileName 'remote-update.txt' -Value 'remote update' -Message 'remote update'
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Seed -Arguments @('push', 'origin', $script:GwmSyncFixture.Branch) | Out-Null
        Set-Content -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'baseline.txt') -Value 'unstaged local content'
        Set-Content -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'staged.txt') -Value 'staged local content'
        Set-Content -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'untracked.txt') -Value 'untracked local content'
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('add', 'staged.txt') | Out-Null
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')

        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository

        $result.SyncStatus | Should Be 'NEEDS_ATTENTION'
        $result.AfterCommit | Should Be $before
        (Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $before
        (Get-Content -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'baseline.txt') -Raw).Trim() | Should Be 'unstaged local content'
        (Get-Content -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'staged.txt') -Raw).Trim() | Should Be 'staged local content'
        (Get-Content -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'untracked.txt') -Raw).Trim() | Should Be 'untracked local content'
        (Test-Path -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'remote-update.txt')) | Should Be $false
    }

    It 'rejects an ahead branch without changing its local commit' {
        Add-GwmSyncTestCommit -RepositoryPath $script:GwmSyncFixture.Local -FileName 'local-only.txt' -Value 'local commit' -Message 'local-only commit'
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')
        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository
        $result.SyncStatus | Should Be 'NEEDS_ATTENTION'
        $result.AfterCommit | Should Be $before
        (Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $before
        (Test-Path -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'local-only.txt')) | Should Be $true
    }

    It 'rejects diverged history without merging or losing either side' {
        Add-GwmSyncTestCommit -RepositoryPath $script:GwmSyncFixture.Local -FileName 'local-only.txt' -Value 'local commit' -Message 'local-only commit'
        Add-GwmSyncTestCommit -RepositoryPath $script:GwmSyncFixture.Seed -FileName 'remote-only.txt' -Value 'remote commit' -Message 'remote-only commit'
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Seed -Arguments @('push', 'origin', $script:GwmSyncFixture.Branch) | Out-Null
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')

        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository

        $result.SyncStatus | Should Be 'NEEDS_ATTENTION'
        $result.AfterCommit | Should Be $before
        (Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $before
        (Test-Path -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'local-only.txt')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'remote-only.txt')) | Should Be $false
    }

    It 'rejects a detached HEAD without updating it' {
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('checkout', '--detach', 'HEAD') | Out-Null
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')
        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository
        $result.SyncStatus | Should Be 'NEEDS_ATTENTION'
        $result.AfterCommit | Should Be $before
    }

    It 'rejects a branch without an upstream' {
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('branch', '--unset-upstream') | Out-Null
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')
        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository
        $result.SyncStatus | Should Be 'NEEDS_ATTENTION'
        $result.AfterCommit | Should Be $before
    }

    It 'classifies a branch without upstream before fetching a missing remote' {
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('branch', '--unset-upstream') | Out-Null
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('remote', 'remove', 'origin') | Out-Null
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')

        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository

        $result.SyncStatus | Should Be 'NEEDS_ATTENTION'
        $result.Reason | Should Match 'No unambiguous upstream'
        $result.ExitCode | Should Be 0
        $result.AfterCommit | Should Be $before
        (Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $before
    }

    It 'reports fetch failure without updating the local branch' {
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Seed -Arguments @('remote', 'set-url', 'origin', (Join-Path $script:GwmSyncFixture.Root 'missing-remote.git')) | Out-Null
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('remote', 'set-url', 'origin', (Join-Path $script:GwmSyncFixture.Root 'missing-remote.git')) | Out-Null
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')
        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository
        $result.SyncStatus | Should Be 'FAILED'
        $result.AfterCommit | Should Be $before
        (Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $before
    }

    It 'rejects an upstream that does not belong to the configured remote' {
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('remote', 'add', 'backup', $script:GwmSyncFixture.Remote) | Out-Null
        Add-GwmSyncTestCommit -RepositoryPath $script:GwmSyncFixture.Seed -FileName 'remote-update.txt' -Value 'remote update' -Message 'remote update'
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Seed -Arguments @('push', 'origin', $script:GwmSyncFixture.Branch) | Out-Null
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('fetch', 'backup') | Out-Null
        Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('branch', '--set-upstream-to', ('backup/' + $script:GwmSyncFixture.Branch)) | Out-Null
        $before = Invoke-GwmSyncTestGit -RepositoryPath $script:GwmSyncFixture.Local -Arguments @('rev-parse', 'HEAD')

        $result = Invoke-GwmFastForward -Repository $script:GwmSyncFixture.Repository

        $result.SyncStatus | Should Be 'NEEDS_ATTENTION'
        $result.Reason | Should Match 'does not belong to configured remote'
        $result.AfterCommit | Should Be $before
        (Test-Path -LiteralPath (Join-Path $script:GwmSyncFixture.Local 'remote-update.txt')) | Should Be $false
    }

    It 'continues syncing independent repositories after one repository fails' {
        $secondFixture = New-GwmSyncFixture
        try {
            $badRepository = [pscustomobject]@{
                Name='missing-repository'
                Path=(Join-Path $script:GwmSyncFixture.Root 'missing-repository')
                Remote='origin'
            }
            Add-GwmSyncTestCommit -RepositoryPath $secondFixture.Seed -FileName 'remote-update.txt' -Value 'remote update' -Message 'remote update'
            Invoke-GwmSyncTestGit -RepositoryPath $secondFixture.Seed -Arguments @('push', 'origin', $secondFixture.Branch) | Out-Null
            $expected = Invoke-GwmSyncTestGit -RepositoryPath $secondFixture.Seed -Arguments @('rev-parse', 'HEAD')

            $results = @(Invoke-GwmSyncForRepositories -Repositories @($badRepository, $secondFixture.Repository))

            $results.Count | Should Be 2
            $results[0].SyncStatus | Should Be 'FAILED'
            $results[1].SyncStatus | Should Be 'UPDATED'
            $results[1].AfterCommit | Should Be $expected
            (Invoke-GwmSyncTestGit -RepositoryPath $secondFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $expected
        }
        finally {
            if (Test-Path -LiteralPath $secondFixture.Root) {
                Remove-Item -LiteralPath $secondFixture.Root -Recurse -Force
            }
        }
    }

}
