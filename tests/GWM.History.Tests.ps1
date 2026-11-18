$historyModulePath = Join-Path $PSScriptRoot '..\src\GWM.History.psm1'
Import-Module -Name $historyModulePath -Force

function New-GwmHistoryFixtureReport {
    param(
        [string]$Mode = 'Scan',
        [string]$RunId = ([guid]::NewGuid().ToString('N')),
        [string]$GeneratedAt = '2026-11-18T10:00:00.000+07:00'
    )
    [pscustomobject]@{ Mode = $Mode; RunId = $RunId; GeneratedAt = $GeneratedAt }
}

Describe 'GWM history artifact helpers' {
    It 'resolves a relative output directory beneath the project root' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-history-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            $resolved = Resolve-GwmOutputDirectory -ProjectRoot $root
            $resolved | Should Be ([System.IO.Path]::GetFullPath((Join-Path $root 'reports')))
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'rejects rooted and traversing output paths' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-history-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            { Resolve-GwmOutputDirectory -ProjectRoot $root -RelativePath '..\outside' } | Should Throw
            { Resolve-GwmOutputDirectory -ProjectRoot $root -RelativePath ([System.IO.Path]::GetTempPath()) } | Should Throw
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'creates deterministic names containing mode timestamp RunId and format' {
        $report = New-GwmHistoryFixtureReport -RunId '0123456789abcdef0123456789abcdef'
        $name = New-GwmHistoryFileName -Report $report -Format json
        $name | Should Be 'gwm-scan-20261118T100000000-0123456789abcdef0123456789abcdef.json'
    }

    It 'rejects malformed report identity and timestamp' {
        $badId = New-GwmHistoryFixtureReport -RunId 'not-a-guid'
        { New-GwmHistoryFileName -Report $badId -Format json } | Should Throw
        $badDate = New-GwmHistoryFixtureReport -GeneratedAt 'not-a-date'
        { New-GwmHistoryFileName -Report $badDate -Format html } | Should Throw
    }

    It 'writes a history artifact without overwriting a collision' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-history-' + [guid]::NewGuid().ToString('N'))
        try {
            $report = New-GwmHistoryFixtureReport -RunId '0123456789abcdef0123456789abcdef'
            $first = Write-GwmHistoryArtifact -HistoryDirectory $root -Report $report -Format json -Content '{"value":1}'
            $second = Write-GwmHistoryArtifact -HistoryDirectory $root -Report $report -Format json -Content '{"value":2}'
            $first.Success | Should Be $true
            $second.Success | Should Be $false
            [System.IO.File]::ReadAllText($first.Path, [System.Text.Encoding]::UTF8) | Should Be '{"value":1}'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'atomically updates a latest artifact and writes UTF-8 without BOM' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-history-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            $path = Join-Path $root 'latest-scan.json'
            $first = Write-GwmLatestArtifact -Path $path -Content 'old'
            $second = Write-GwmLatestArtifact -Path $path -Content 'new'
            $first.Success | Should Be $true
            $second.Success | Should Be $true
            [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | Should Be 'new'
            $bytes = [System.IO.File]::ReadAllBytes($path)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) | Should Be $false
            @(Get-ChildItem -LiteralPath $root -Filter '.gwm-tmp-*').Count | Should Be 0
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'retains only the newest eligible files within the selected mode and format' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-history-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            $ids = @(
                '00000000000000000000000000000001',
                '00000000000000000000000000000002',
                '00000000000000000000000000000003'
            )
            for ($i = 0; $i -lt 3; $i++) {
                $report = New-GwmHistoryFixtureReport -RunId $ids[$i] -GeneratedAt ("2026-11-1{0}T10:00:00.000+07:00" -f ($i + 1))
                $write = Write-GwmHistoryArtifact -HistoryDirectory $root -Report $report -Format json -Content ([string]$i)
                $write.Success | Should Be $true
            }
            $sync = New-GwmHistoryFixtureReport -Mode Sync -RunId '11111111111111111111111111111111'
            (Write-GwmHistoryArtifact -HistoryDirectory $root -Report $sync -Format json -Content 'sync').Success | Should Be $true
            $html = New-GwmHistoryFixtureReport -RunId '22222222222222222222222222222222'
            (Write-GwmHistoryArtifact -HistoryDirectory $root -Report $html -Format html -Content '<html/>').Success | Should Be $true

            $result = Invoke-GwmHistoryRetention -HistoryDirectory $root -Mode Scan -Format json -RetentionCount 2
            $result.Success | Should Be $true
            $result.DeletedCount | Should Be 1
            @(Get-ChildItem -LiteralPath $root -Filter 'gwm-scan-*.json').Count | Should Be 2
            @(Get-ChildItem -LiteralPath $root -Filter 'gwm-sync-*.json').Count | Should Be 1
            @(Get-ChildItem -LiteralPath $root -Filter 'gwm-scan-*.html').Count | Should Be 1
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'preserves unrelated files malformed names latest files and child directories' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-history-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            $sentinel = Join-Path $root 'important.txt'
            $malformed = Join-Path $root 'gwm-scan-invalid-0123456789abcdef0123456789abcdef.json'
            $latest = Join-Path $root 'latest-scan.json'
            [System.IO.File]::WriteAllText($sentinel, 'keep')
            [System.IO.File]::WriteAllText($malformed, 'keep')
            [System.IO.File]::WriteAllText($latest, 'keep')
            $child = Join-Path $root 'nested'
            [void][System.IO.Directory]::CreateDirectory($child)
            [System.IO.File]::WriteAllText((Join-Path $child 'nested.txt'), 'keep')
            for ($i = 1; $i -le 3; $i++) {
                $report = New-GwmHistoryFixtureReport -RunId ('3333333333333333333333333333333' + $i) -GeneratedAt ("2026-11-1{0}T10:00:00.000+07:00" -f $i)
                [void](Write-GwmHistoryArtifact -HistoryDirectory $root -Report $report -Format json -Content 'history')
            }

            $result = Invoke-GwmHistoryRetention -HistoryDirectory $root -Mode Scan -Format json -RetentionCount 1
            $result.DeletedCount | Should Be 2
            (Test-Path -LiteralPath $sentinel) | Should Be $true
            (Test-Path -LiteralPath $malformed) | Should Be $true
            (Test-Path -LiteralPath $latest) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $child 'nested.txt')) | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'treats zero retention as disabled and a missing history directory as a no-op' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-history-' + [guid]::NewGuid().ToString('N'))
        $zero = Invoke-GwmHistoryRetention -HistoryDirectory $root -Mode Scan -Format json -RetentionCount 0
        $missing = Invoke-GwmHistoryRetention -HistoryDirectory $root -Mode Scan -Format json -RetentionCount 30
        $zero.Success | Should Be $true
        $zero.DeletedCount | Should Be 0
        $missing.Success | Should Be $true
        (Test-Path -LiteralPath $root) | Should Be $false
    }
}
