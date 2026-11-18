$loggingModulePath = Join-Path $PSScriptRoot '..\src\GWM.Logging.psm1'
Import-Module -Name $loggingModulePath -Force

function New-GwmLoggingFixtureReport {
    param(
        [string]$Mode = 'Scan',
        [string]$RunId = ([guid]::NewGuid().ToString('N')),
        [string]$GeneratedAt = '2026-11-18T10:00:00.000+07:00'
    )
    [pscustomobject]@{ Mode = $Mode; RunId = $RunId; GeneratedAt = $GeneratedAt }
}

Describe 'GWM operational logging' {
    It 'defaults logging to enabled with the documented path and retention' {
        $options = Get-GwmLoggingOptions -Settings ([pscustomobject]@{})
        $options.Enabled | Should Be $true
        $options.RelativePath | Should Be 'logs'
        $options.RetentionCount | Should Be 30
    }

    It 'validates explicit logging settings and rejects invalid retention or rooted paths' {
        $settings = [pscustomobject]@{
            logging = [pscustomobject]@{ enabled=$false; path='runtime-logs'; retentionCount=0 }
        }
        $options = Get-GwmLoggingOptions -Settings $settings
        $options.Enabled | Should Be $false
        $options.RelativePath | Should Be 'runtime-logs'
        $options.RetentionCount | Should Be 0

        $badRetention = [pscustomobject]@{ logging=[pscustomobject]@{ retentionCount=1.5 } }
        { Get-GwmLoggingOptions -Settings $badRetention } | Should Throw
        $rooted = [pscustomobject]@{ logging=[pscustomobject]@{ path=([System.IO.Path]::GetTempPath()) } }
        { Get-GwmLoggingOptions -Settings $rooted } | Should Throw
    }

    It 'does not create a log directory or file when logging is disabled' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-logging-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            $report = New-GwmLoggingFixtureReport
            $result = Write-GwmRunLog -ProjectRoot $root -Report $report -Events @() -Enabled $false
            $result.Success | Should Be $true
            $result.Enabled | Should Be $false
            (Test-Path -LiteralPath (Join-Path $root 'logs')) | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'writes UTF-8 NDJSON with safe event fields and redacts secrets' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-logging-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            $report = New-GwmLoggingFixtureReport -RunId '0123456789abcdef0123456789abcdef'
            $events = @(
                [pscustomobject]@{
                    Event='FetchFailed'
                    Timestamp='2026-11-18T10:00:00.000+07:00'
                    Repository=('repo-' + [char]0x8CC7 + [char]0x6599 + '-' + [char]::ConvertFromUtf32(0x1F600))
                    Error='fatal: https://alice:super-secret@example.invalid/repo.git?token=abc123 password=hunter2 Bearer eyJhbGciOiJIUzI1NiJ9'
                    Counts=[pscustomobject]@{ Failed=1; Updated=0 }
                    Arguments=@('--config','credential.helper=secret')
                    Environment=[pscustomobject]@{ API_TOKEN='must-not-appear' }
                }
            )
            $result = Write-GwmRunLog -ProjectRoot $root -Report $report -Events $events
            $result.Success | Should Be $true
            Test-Path -LiteralPath $result.Path | Should Be $true
            $raw = [System.IO.File]::ReadAllText($result.Path, [System.Text.Encoding]::UTF8)
            $raw | Should Match 'FetchFailed'
            $raw | Should Match ([regex]::Escape(('repo-' + [char]0x8CC7 + [char]0x6599 + '-' + [char]::ConvertFromUtf32(0x1F600))))
            $raw | Should Match '\[REDACTED\]'
            $raw | Should Not Match 'super-secret|abc123|hunter2|eyJhbGci|must-not-appear|credential.helper'
            $lines = @($raw.Trim() -split [regex]::Escape([Environment]::NewLine))
            $lines.Count | Should Be 1
            $entry = ConvertFrom-Json -InputObject $lines[0]
            $entry.RunId | Should Be $report.RunId
            $entry.Mode | Should Be 'Scan'
            $entry.Counts.Failed | Should Be 1
            $entry.PSObject.Properties['Arguments'] | Should Be $null
            $entry.PSObject.Properties['Environment'] | Should Be $null
            $bytes = [System.IO.File]::ReadAllBytes($result.Path)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'rejects output traversal and returns a warning without changing the report' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-logging-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            $report = New-GwmLoggingFixtureReport
            $before = $report | ConvertTo-Json -Compress
            $result = Write-GwmRunLog -ProjectRoot $root -Report $report -Events @() -RelativePath '..\outside'
            $result.Success | Should Be $false
            $result.Warnings.Count | Should BeGreaterThan 0
            ($report | ConvertTo-Json -Compress) | Should Be $before
            (Test-Path -LiteralPath (Join-Path (Split-Path $root -Parent) 'outside')) | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'retains only the newest generated logs across Scan and Sync runs' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-logging-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            for ($i = 1; $i -le 3; $i++) {
                $report = New-GwmLoggingFixtureReport -RunId ('4444444444444444444444444444444' + $i) -GeneratedAt ("2026-11-1{0}T10:00:00.000+07:00" -f $i)
                $name = New-GwmLogFileName -Report $report
                [System.IO.File]::WriteAllText((Join-Path $root $name), [string]$i)
            }
            $sync = New-GwmLoggingFixtureReport -Mode Sync -RunId '55555555555555555555555555555555'
            [System.IO.File]::WriteAllText((Join-Path $root (New-GwmLogFileName -Report $sync)), 'sync')
            [System.IO.File]::WriteAllText((Join-Path $root 'notes.txt'), 'keep')

            $result = Invoke-GwmLogRetention -LogDirectory $root -RetentionCount 2
            $result.Success | Should Be $true
            $result.DeletedCount | Should Be 1
            @(Get-ChildItem -LiteralPath $root -Filter 'gwm-scan-*.log').Count | Should Be 1
            @(Get-ChildItem -LiteralPath $root -Filter 'gwm-sync-*.log').Count | Should Be 1
            @(Get-ChildItem -LiteralPath $root -Filter 'gwm-*.log').Count | Should Be 2
            (Test-Path -LiteralPath (Join-Path $root 'notes.txt')) | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'treats zero retention as disabled and preserves unrelated files' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-logging-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][System.IO.Directory]::CreateDirectory($root)
            $report = New-GwmLoggingFixtureReport
            $name = New-GwmLogFileName -Report $report
            [System.IO.File]::WriteAllText((Join-Path $root $name), 'keep')
            $result = Invoke-GwmLogRetention -LogDirectory $root -RetentionCount 0
            $result.Success | Should Be $true
            $result.DeletedCount | Should Be 0
            (Test-Path -LiteralPath (Join-Path $root $name)) | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
