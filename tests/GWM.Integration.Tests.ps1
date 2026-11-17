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

        $exitCode | Should Be 0
        $reportPath = Join-Path $script:GwmFixture.Root 'reports/latest-scan.json'
        (Test-Path -LiteralPath $reportPath -PathType Leaf) | Should Be $true
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $report.RepositoryCount | Should Be 1
        $report.WorkspaceRoot | Should Be $script:GwmFixture.Local
        @($report.Results).Count | Should Be 1
        $report.Results[0].Name | Should Be 'local'
        $report.Results[0].Classification | Should Be 'UP_TO_DATE'
        $report.Results[0].Head | Should Match '^[0-9a-f]{40}
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
}

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
}
