$modulePath = Join-Path $PSScriptRoot '..\src\GWM.Core.psm1'
Import-Module -Name $modulePath -Force

function Invoke-GwmTestGit {
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


function Invoke-GwmTestGitResult {
    param([string]$RepositoryPath, [string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $RepositoryPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    [pscustomobject]@{
        ExitCode = $exitCode
        Output = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    }
}

function New-GwmIntegrationFixture {
    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-integration-' + [guid]::NewGuid().ToString('N'))
    $seedPath = Join-Path $fixtureRoot 'seed'
    $remotePath = Join-Path $fixtureRoot 'remote.git'
    $localPath = Join-Path $fixtureRoot 'local'
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $seedPath -Force | Out-Null

    Invoke-GwmTestGit -RepositoryPath $seedPath -Arguments @('init') | Out-Null
    Invoke-GwmTestGit -RepositoryPath $seedPath -Arguments @('config', 'user.name', 'GWM Integration Test') | Out-Null
    Invoke-GwmTestGit -RepositoryPath $seedPath -Arguments @('config', 'user.email', 'gwm-test@example.invalid') | Out-Null
    Set-Content -LiteralPath (Join-Path $seedPath 'baseline.txt') -Value 'baseline'
    Invoke-GwmTestGit -RepositoryPath $seedPath -Arguments @('add', 'baseline.txt') | Out-Null
    Invoke-GwmTestGit -RepositoryPath $seedPath -Arguments @('commit', '-m', 'initial test commit') | Out-Null

    $branch = Invoke-GwmTestGit -RepositoryPath $seedPath -Arguments @('branch', '--show-current')
    & git init --bare $remotePath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize disposable bare remote.' }
    Invoke-GwmTestGit -RepositoryPath $seedPath -Arguments @('remote', 'add', 'origin', $remotePath) | Out-Null
    Invoke-GwmTestGit -RepositoryPath $seedPath -Arguments @('push', '-u', 'origin', $branch) | Out-Null
    & git "--git-dir=$remotePath" symbolic-ref HEAD ("refs/heads/" + $branch) 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to set disposable remote HEAD.' }
    & git clone $remotePath $localPath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to clone disposable bare remote.' }
    Invoke-GwmTestGit -RepositoryPath $localPath -Arguments @('config', 'user.name', 'GWM Integration Test') | Out-Null
    Invoke-GwmTestGit -RepositoryPath $localPath -Arguments @('config', 'user.email', 'gwm-test@example.invalid') | Out-Null

    [pscustomobject]@{
        Root = $fixtureRoot
        Seed = $seedPath
        Remote = $remotePath
        Local = $localPath
        Branch = $branch
        Repository = [pscustomobject]@{ Name='integration-fixture'; Path=$localPath; Remote='origin' }
    }
}

function Add-GwmTestCommit {
    param([string]$RepositoryPath, [string]$FileName, [string]$Value, [string]$Message)
    Set-Content -LiteralPath (Join-Path $RepositoryPath $FileName) -Value $Value
    Invoke-GwmTestGit -RepositoryPath $RepositoryPath -Arguments @('add', $FileName) | Out-Null
    Invoke-GwmTestGit -RepositoryPath $RepositoryPath -Arguments @('commit', '-m', $Message) | Out-Null
}


function Set-GwmEntryPointSettings {
    param([string]$ProjectRoot, [string]$WorkspaceRoot)
    $configDirectory = Join-Path $ProjectRoot 'config'
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    $settings = @{
        workspace = @{ root = $WorkspaceRoot; recursiveDiscovery = $false }
        git = @{ defaultRemote = 'origin'; syncStrategy = 'ff-only' }
    } | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Join-Path $configDirectory 'settings.json') -Value $settings -Encoding UTF8
}

function Invoke-GwmEntryPoint {
    param([string]$ProjectRoot, [string]$Mode)
    $entryPoint = Join-Path $PSScriptRoot '..\scripts\GWM.ps1'
    $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entryPoint -ProjectRoot $ProjectRoot -Mode $Mode 2>&1)
    [pscustomobject]@{
        ExitCode=$LASTEXITCODE
        Output=(($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    }
}

Describe 'GWM repository state integration' {
    BeforeEach { $script:GwmFixture = New-GwmIntegrationFixture }

    AfterEach {
        if ($script:GwmFixture -and (Test-Path -LiteralPath $script:GwmFixture.Root)) {
            Remove-Item -LiteralPath $script:GwmFixture.Root -Recurse -Force
        }
        $script:GwmFixture = $null
    }

    It 'inspects a clean repository whose local branch matches its upstream' {
        $state = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $state.IsRepository | Should Be $true
        $state.Classification | Should Be 'UP_TO_DATE'
        $state.Ahead | Should Be 0
        $state.Behind | Should Be 0
        $state.IsDirty | Should Be $false
    }

    It 'detects staged changes without changing their contents' {
        $file = Join-Path $script:GwmFixture.Local 'baseline.txt'
        Set-Content -LiteralPath $file -Value 'staged user content'
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('add', 'baseline.txt') | Out-Null
        $state = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $state.Classification | Should Be 'NEEDS_ATTENTION'
        $state.IsDirty | Should Be $true
        (Get-Content -LiteralPath $file -Raw).Trim() | Should Be 'staged user content'
    }

    It 'detects unstaged changes without changing their contents' {
        $file = Join-Path $script:GwmFixture.Local 'baseline.txt'
        Set-Content -LiteralPath $file -Value 'unstaged user content'
        $state = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $state.Classification | Should Be 'NEEDS_ATTENTION'
        $state.IsDirty | Should Be $true
        (Get-Content -LiteralPath $file -Raw).Trim() | Should Be 'unstaged user content'
    }

    It 'detects an untracked file and preserves it' {
        $file = Join-Path $script:GwmFixture.Local 'untracked-user-file.txt'
        Set-Content -LiteralPath $file -Value 'keep me'
        $state = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $state.Classification | Should Be 'NEEDS_ATTENTION'
        $state.IsDirty | Should Be $true
        (Get-Content -LiteralPath $file -Raw).Trim() | Should Be 'keep me'
    }

    It 'detects a local-only commit as ahead' {
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Local -FileName 'local.txt' -Value 'local' -Message 'local-only commit'
        $state = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $state.Classification | Should Be 'AHEAD'
        $state.Ahead | Should Be 1
        $state.Behind | Should Be 0
    }

    It 'detects a remote-only commit as behind after fetch' {
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Seed -FileName 'remote.txt' -Value 'remote' -Message 'remote-only commit'
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Seed -Arguments @('push', 'origin', $script:GwmFixture.Branch) | Out-Null
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('fetch', 'origin') | Out-Null
        $state = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $state.Classification | Should Be 'BEHIND'
        $state.Ahead | Should Be 0
        $state.Behind | Should Be 1
        (Test-Path -LiteralPath (Join-Path $script:GwmFixture.Local 'remote.txt')) | Should Be $false
    }

    It 'detects diverged local and remote histories' {
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Local -FileName 'local.txt' -Value 'local' -Message 'local-only commit'
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Seed -FileName 'remote.txt' -Value 'remote' -Message 'remote-only commit'
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Seed -Arguments @('push', 'origin', $script:GwmFixture.Branch) | Out-Null
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('fetch', 'origin') | Out-Null
        $state = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $state.Classification | Should Be 'DIVERGED'
        $state.Ahead | Should Be 1
        $state.Behind | Should Be 1
        (Test-Path -LiteralPath (Join-Path $script:GwmFixture.Local 'local.txt')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $script:GwmFixture.Local 'remote.txt')) | Should Be $false
    }

    It 'detects detached HEAD' {
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('checkout', '--detach', 'HEAD') | Out-Null
        $state = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $state.Detached | Should Be $true
        $state.Classification | Should Be 'NEEDS_ATTENTION'
    }

    It 'writes a valid JSON scan report with a stable summary structure' {
        $configDirectory = Join-Path $script:GwmFixture.Root 'config'
        New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
        $settings = @{
            workspace = @{ root = $script:GwmFixture.Local; recursiveDiscovery = $false }
            git = @{ defaultRemote = 'origin'; syncStrategy = 'ff-only' }
        } | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath (Join-Path $configDirectory 'settings.json') -Value $settings -Encoding UTF8

        $entryPoint = Join-Path $PSScriptRoot '..\scripts\GWM.ps1'
        $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $entryPoint -ProjectRoot $script:GwmFixture.Root 2>&1)
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            throw ("GWM entry point failed with exit code {0}. Child-process output:`n{1}" -f $exitCode, ($output -join [Environment]::NewLine))
        }
        $reportPath = Join-Path $script:GwmFixture.Root 'reports/latest-scan.json'
        (Test-Path -LiteralPath $reportPath -PathType Leaf) | Should Be $true
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $report.RepositoryCount | Should Be 1
        $report.WorkspaceRoot | Should Be $script:GwmFixture.Local
        @($report.Results).Count | Should Be 1
        $report.Results[0].Name | Should Be 'local'
        $report.Results[0].Classification | Should Be 'UP_TO_DATE'
        $report.Results[0].Head | Should Match '^[0-9a-f]{40}$'
    }


    It 'detects a working-tree change between two repository inspections' {
        $before = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository
        $file = Join-Path $script:GwmFixture.Local 'changed-during-run.txt'
        Set-Content -LiteralPath $file -Value 'concurrent user content'
        $after = Get-GwmRepositoryState -Repository $script:GwmFixture.Repository

        (Test-GwmRepositoryStateUnchanged -Before $before -After $after) | Should Be $false
        (Get-Content -LiteralPath $file -Raw).Trim() | Should Be 'concurrent user content'
        $after.Head | Should Be $before.Head
    }

    It 'rejects a diverged update with ff-only and preserves both sides' {
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Local -FileName 'local-only.txt' -Value 'local user commit' -Message 'local-only commit'
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Seed -FileName 'remote-only.txt' -Value 'remote commit' -Message 'remote-only commit'
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Seed -Arguments @('push', 'origin', $script:GwmFixture.Branch) | Out-Null
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('fetch', 'origin') | Out-Null

        $beforeHead = Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('rev-parse', 'HEAD')
        $localFile = Join-Path $script:GwmFixture.Local 'local-only.txt'
        $remoteFile = Join-Path $script:GwmFixture.Local 'remote-only.txt'

        $merge = Invoke-GwmTestGitResult -RepositoryPath $script:GwmFixture.Local -Arguments @('merge', '--ff-only', ('origin/' + $script:GwmFixture.Branch))

        $merge.ExitCode | Should Not Be 0
        (Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $beforeHead
        (Test-Path -LiteralPath $localFile) | Should Be $true
        (Get-Content -LiteralPath $localFile -Raw).Trim() | Should Be 'local user commit'
        (Test-Path -LiteralPath $remoteFile) | Should Be $false
    }

    It 'detects a repository without an upstream' {
        $orphanPath = Join-Path $script:GwmFixture.Root 'orphan'
        New-Item -ItemType Directory -Path $orphanPath -Force | Out-Null
        Invoke-GwmTestGit -RepositoryPath $orphanPath -Arguments @('init') | Out-Null
        Invoke-GwmTestGit -RepositoryPath $orphanPath -Arguments @('config', 'user.name', 'GWM Integration Test') | Out-Null
        Invoke-GwmTestGit -RepositoryPath $orphanPath -Arguments @('config', 'user.email', 'gwm-test@example.invalid') | Out-Null
        Set-Content -LiteralPath (Join-Path $orphanPath 'initial.txt') -Value 'initial'
        Invoke-GwmTestGit -RepositoryPath $orphanPath -Arguments @('add', 'initial.txt') | Out-Null
        Invoke-GwmTestGit -RepositoryPath $orphanPath -Arguments @('commit', '-m', 'orphan initial commit') | Out-Null
        $repository = [pscustomobject]@{ Name='no-upstream'; Path=$orphanPath; Remote='origin' }
        $state = Get-GwmRepositoryState -Repository $repository
        $state.Upstream | Should Be $null
        $state.Classification | Should Be 'NEEDS_ATTENTION'
    }

    It 'keeps Scan offline and does not fetch or update the working branch' {
        Set-GwmEntryPointSettings -ProjectRoot $script:GwmFixture.Root -WorkspaceRoot $script:GwmFixture.Local
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Seed -FileName 'remote-only.txt' -Value 'remote update' -Message 'remote-only update'
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Seed -Arguments @('push', 'origin', $script:GwmFixture.Branch) | Out-Null
        $beforeHead = Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('rev-parse', 'HEAD')

        $run = Invoke-GwmEntryPoint -ProjectRoot $script:GwmFixture.Root -Mode 'Scan'

        $run.ExitCode | Should Be 0
        (Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $beforeHead
        (Test-Path -LiteralPath (Join-Path $script:GwmFixture.Local 'remote-only.txt')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $script:GwmFixture.Root 'reports/latest-scan.json')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $script:GwmFixture.Root 'reports/latest-sync.json')) | Should Be $false
    }

    It 'exposes Sync mode and reports a verified fast-forward update' {
        Set-GwmEntryPointSettings -ProjectRoot $script:GwmFixture.Root -WorkspaceRoot $script:GwmFixture.Local
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Seed -FileName 'remote-update.txt' -Value 'remote update' -Message 'remote update'
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Seed -Arguments @('push', 'origin', $script:GwmFixture.Branch) | Out-Null
        $expectedHead = Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Seed -Arguments @('rev-parse', 'HEAD')

        $run = Invoke-GwmEntryPoint -ProjectRoot $script:GwmFixture.Root -Mode 'Sync'

        $run.ExitCode | Should Be 0
        (Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $expectedHead
        (Get-Content -LiteralPath (Join-Path $script:GwmFixture.Local 'remote-update.txt') -Raw).Trim() | Should Be 'remote update'
        $reportPath = Join-Path $script:GwmFixture.Root 'reports/latest-sync.json'
        (Test-Path -LiteralPath $reportPath -PathType Leaf) | Should Be $true
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $report.Mode | Should Be 'Sync'
        $report.RepositoryCount | Should Be 1
        $report.Summary.Updated | Should Be 1
        $report.Summary.Failed | Should Be 0
        $report.Results[0].SyncStatus | Should Be 'UPDATED'
        $report.Results[0].AfterCommit | Should Be $expectedHead
    }

    It 'returns an attention exit code and preserves dirty work in Sync mode' {
        Set-GwmEntryPointSettings -ProjectRoot $script:GwmFixture.Root -WorkspaceRoot $script:GwmFixture.Local
        Add-GwmTestCommit -RepositoryPath $script:GwmFixture.Seed -FileName 'remote-update.txt' -Value 'remote update' -Message 'remote update'
        Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Seed -Arguments @('push', 'origin', $script:GwmFixture.Branch) | Out-Null
        $beforeHead = Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('rev-parse', 'HEAD')
        $userFile = Join-Path $script:GwmFixture.Local 'keep-me.txt'
        Set-Content -LiteralPath $userFile -Value 'uncommitted user content'

        $run = Invoke-GwmEntryPoint -ProjectRoot $script:GwmFixture.Root -Mode 'Sync'

        $run.ExitCode | Should Be 1
        (Invoke-GwmTestGit -RepositoryPath $script:GwmFixture.Local -Arguments @('rev-parse', 'HEAD')) | Should Be $beforeHead
        (Get-Content -LiteralPath $userFile -Raw).Trim() | Should Be 'uncommitted user content'
        (Test-Path -LiteralPath (Join-Path $script:GwmFixture.Local 'remote-update.txt')) | Should Be $false
        $report = Get-Content -LiteralPath (Join-Path $script:GwmFixture.Root 'reports/latest-sync.json') -Raw | ConvertFrom-Json
        $report.Summary.NeedsAttention | Should Be 1
        $report.Results[0].SyncStatus | Should Be 'NEEDS_ATTENTION'
    }

}
