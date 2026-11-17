$modulePath = Join-Path $PSScriptRoot '..\src\GWM.Core.psm1'
Import-Module -Name $modulePath -Force

function Invoke-GwmSafetyTestGit {
    param([string]$RepositoryPath, [string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $RepositoryPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        throw ("Git safety test command failed ({0}) in {1}: {2}; {3}" -f $exitCode, $RepositoryPath, ($Arguments -join ' '), ($output -join [Environment]::NewLine))
    }
    return (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
}

function New-GwmFetchSafetyFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-fetch-safety-' + [guid]::NewGuid().ToString('N'))
    $good = Join-Path $root 'good'
    $bad = Join-Path $root 'bad'
    $bare = Join-Path $root 'good-remote.git'
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    foreach ($path in @($good, $bad)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Invoke-GwmSafetyTestGit -RepositoryPath $path -Arguments @('init') | Out-Null
        Invoke-GwmSafetyTestGit -RepositoryPath $path -Arguments @('config', 'user.name', 'GWM Safety Test') | Out-Null
        Invoke-GwmSafetyTestGit -RepositoryPath $path -Arguments @('config', 'user.email', 'gwm-safety@example.invalid') | Out-Null
        Set-Content -LiteralPath (Join-Path $path 'baseline.txt') -Value 'baseline'
        Invoke-GwmSafetyTestGit -RepositoryPath $path -Arguments @('add', 'baseline.txt') | Out-Null
        Invoke-GwmSafetyTestGit -RepositoryPath $path -Arguments @('commit', '-m', 'safety fixture') | Out-Null
    }

    & git init --bare $bare 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize safety-test bare remote.' }
    Invoke-GwmSafetyTestGit -RepositoryPath $good -Arguments @('remote', 'add', 'origin', $bare) | Out-Null

    [pscustomobject]@{
        Root=$root
        Good=$good
        Bad=$bad
        Bare=$bare
        GoodRepository=[pscustomobject]@{ Name='good'; Path=$good; Remote='origin' }
        BadRepository=[pscustomobject]@{ Name='bad'; Path=$bad; Remote='origin' }
    }
}

Describe 'GWM safety boundary primitives' {
    It 'redacts URL user information' {
        $value = ConvertTo-GwmRedactedRemoteUrl -RemoteUrl 'https://alice:super-secret@github.com/org/repo.git'
        $value | Should Be 'https://[REDACTED]@github.com/org/repo.git'
        $value | Should Not Match 'super-secret'
    }

    It 'redacts sensitive query-string values' {
        $value = ConvertTo-GwmRedactedRemoteUrl -RemoteUrl 'https://example.invalid/repo.git?token=abc123&branch=main'
        $value | Should Be 'https://example.invalid/repo.git?token=[REDACTED]&branch=main'
        $value | Should Not Match 'abc123'
    }

    It 'allows only a clean attached branch strictly behind its upstream' {
        $state = [pscustomobject]@{
            IsRepository=$true; Detached=$false; Branch='main'; Upstream='origin/main'
            IsDirty=$false; StatusLines=@(); Ahead=0; Behind=2
        }
        $result = Get-GwmSyncEligibility -State $state
        $result.Eligible | Should Be $true
    }

    It 'rejects dirty, ahead, equal, unknown, detached, and no-upstream states' {
        $base = @{
            IsRepository=$true; Detached=$false; Branch='main'; Upstream='origin/main'
            IsDirty=$false; StatusLines=@(); Ahead=0; Behind=1
        }
        $cases = @(
            @{ Name='dirty'; Changes=@{ IsDirty=$true } },
            @{ Name='ahead'; Changes=@{ Ahead=1 } },
            @{ Name='equal'; Changes=@{ Behind=0 } },
            @{ Name='unknown'; Changes=@{ Behind=$null } },
            @{ Name='detached'; Changes=@{ Detached=$true; Branch='' } },
            @{ Name='no upstream'; Changes=@{ Upstream=$null } }
        )
        foreach ($case in $cases) {
            $state = [pscustomobject]($base.Clone())
            foreach ($key in $case.Changes.Keys) { $state.$key = $case.Changes[$key] }
            $result = Get-GwmSyncEligibility -State $state
            $result.Eligible | Should Be $false
        }
    }

    It 'detects changes to branch, HEAD, upstream, or working-tree status' {
        $before = [pscustomobject]@{ Branch='main'; Head='abc'; Upstream='origin/main'; StatusLines=@() }
        $same = [pscustomobject]@{ Branch='main'; Head='abc'; Upstream='origin/main'; StatusLines=@() }
        $changedHead = [pscustomobject]@{ Branch='main'; Head='def'; Upstream='origin/main'; StatusLines=@() }
        $changedBranch = [pscustomobject]@{ Branch='release'; Head='abc'; Upstream='origin/main'; StatusLines=@() }
        $changedUpstream = [pscustomobject]@{ Branch='main'; Head='abc'; Upstream='origin/release'; StatusLines=@() }
        $changedStatus = [pscustomobject]@{ Branch='main'; Head='abc'; Upstream='origin/main'; StatusLines=@(' M file.txt') }
        (Test-GwmRepositoryStateUnchanged -Before $before -After $same) | Should Be $true
        (Test-GwmRepositoryStateUnchanged -Before $before -After $changedHead) | Should Be $false
        (Test-GwmRepositoryStateUnchanged -Before $before -After $changedBranch) | Should Be $false
        (Test-GwmRepositoryStateUnchanged -Before $before -After $changedUpstream) | Should Be $false
        (Test-GwmRepositoryStateUnchanged -Before $before -After $changedStatus) | Should Be $false
    }
}

Describe 'GWM fetch isolation and preservation' {
    BeforeEach { $script:GwmFetchFixture = New-GwmFetchSafetyFixture }

    AfterEach {
        if ($script:GwmFetchFixture -and (Test-Path -LiteralPath $script:GwmFetchFixture.Root)) {
            Remove-Item -LiteralPath $script:GwmFetchFixture.Root -Recurse -Force
        }
        $script:GwmFetchFixture = $null
    }

    It 'continues fetching independent repositories after one fetch fails' {
        $results = @(Invoke-GwmFetchForRepositories -Repositories @(
            $script:GwmFetchFixture.BadRepository,
            $script:GwmFetchFixture.GoodRepository
        ))
        $results.Count | Should Be 2
        $results[0].FetchStatus | Should Be 'FAILED'
        $results[1].FetchStatus | Should Be 'FETCHED'
    }

    It 'does not modify staged, unstaged, or untracked working-tree files during fetch' {
        $modified = Join-Path $script:GwmFetchFixture.Good 'baseline.txt'
        $staged = Join-Path $script:GwmFetchFixture.Good 'staged.txt'
        $untracked = Join-Path $script:GwmFetchFixture.Good 'keep-me.txt'
        Set-Content -LiteralPath $modified -Value 'local modified content'
        Set-Content -LiteralPath $staged -Value 'local staged content'
        Set-Content -LiteralPath $untracked -Value 'local untracked content'
        Invoke-GwmSafetyTestGit -RepositoryPath $script:GwmFetchFixture.Good -Arguments @('add', 'staged.txt') | Out-Null
        $beforeHead = Invoke-GwmSafetyTestGit -RepositoryPath $script:GwmFetchFixture.Good -Arguments @('rev-parse', 'HEAD')

        $result = Invoke-GwmFetch -Repository $script:GwmFetchFixture.GoodRepository

        $result.Success | Should Be $true
        (Get-Content -LiteralPath $modified -Raw).Trim() | Should Be 'local modified content'
        (Get-Content -LiteralPath $staged -Raw).Trim() | Should Be 'local staged content'
        (Get-Content -LiteralPath $untracked -Raw).Trim() | Should Be 'local untracked content'
        (Invoke-GwmSafetyTestGit -RepositoryPath $script:GwmFetchFixture.Good -Arguments @('rev-parse', 'HEAD')) | Should Be $beforeHead
    }

    It 'does not expose credentials from a failing remote URL' {
        $secretUrl = 'https://alice:super-secret@127.0.0.1:1/repo.git'
        Invoke-GwmSafetyTestGit -RepositoryPath $script:GwmFetchFixture.Good -Arguments @('remote', 'set-url', 'origin', $secretUrl) | Out-Null

        $result = Invoke-GwmFetch -Repository $script:GwmFetchFixture.GoodRepository

        $result.Success | Should Be $false
        $result.RemoteUrl | Should Not Match 'super-secret'
        $result.Output | Should Not Match 'super-secret'
    }
}
