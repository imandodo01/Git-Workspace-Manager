$coreModulePath = Join-Path $PSScriptRoot '..\src\GWM.Core.psm1'
$reportingModulePath = Join-Path $PSScriptRoot '..\src\GWM.Reporting.psm1'
Import-Module -Name $coreModulePath -Force
Import-Module -Name $reportingModulePath -Force

function New-GwmHtmlTestReport {
    param([object[]]$Results = @(), [object[]]$Warnings = @(), [string]$Mode = 'Scan')

    $startedAt = [DateTimeOffset]::Parse('2026-11-18T10:00:00+07:00')
    $finishedAt = [DateTimeOffset]::Parse('2026-11-18T10:00:01+07:00')
    $report = New-GwmRunReport -Mode $Mode -WorkspaceRoot 'C:\fixtures' -Results $Results -StartedAt $startedAt -FinishedAt $finishedAt
    $report.OutputWarnings = @($Warnings)
    return $report
}

Describe 'GWM self-contained HTML report renderer' {
    It 'writes a self-contained report with run metadata and summary' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-html-' + [guid]::NewGuid().ToString('N'))
        try {
            $result = [pscustomobject]@{
                Name='sample-repo'; Path='C:\fixtures\sample-repo'; Classification='UP_TO_DATE'
                Branch='main'; Upstream='origin/main'; Head='abc123'; Ahead=0; Behind=0
                StatusLines=@(); Reason='Clean'; RecommendedAction='No action required.'
            }
            $report = New-GwmHtmlTestReport -Results @($result)
            $outputPath = Join-Path $root 'reports\latest-scan.html'

            $write = New-GwmHtmlReport -Report $report -OutputPath $outputPath

            $write.Success | Should Be $true
            (Test-Path -LiteralPath $outputPath) | Should Be $true
            $html = Get-Content -LiteralPath $outputPath -Raw
            $html | Should Match '<!doctype html>'
            $html | Should Match 'Schema version'
            $html | Should Match 'Run ID'
            $html | Should Match 'Up to date'
            $html | Should Match 'sample-repo'
            $html | Should Match 'origin/main'
            $html | Should Match 'No action required.'
            $html | Should Match '<style>'
            $html | Should Not Match '<script\b'
            $html | Should Not Match '<link\b'
            $html | Should Not Match '(?i)(src|href)\s*=\s*["'']https?://'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'encodes hostile text and preserves line breaks as inert markup' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-html-' + [guid]::NewGuid().ToString('N'))
        try {
            $hostileName = '<script>alert("x")</script> & "repo"'
            $hostileBranch = 'feature/<img src=x onerror=alert(1)>'
            $result = [pscustomobject]@{
                Name=$hostileName; Path='C:\fixtures\A&B'; Classification='NEEDS_ATTENTION'
                Branch=$hostileBranch; Upstream=$null; Head=$null; Ahead=$null; Behind=$null
                StatusLines=@(" M file-one.txt", "?? file-two.txt")
                Reason=('first line' + [Environment]::NewLine + 'second line & more')
                RecommendedAction='Review <local> changes.'
            }
            $report = New-GwmHtmlTestReport -Results @($result) -Warnings @('<warning> & "detail"')
            $outputPath = Join-Path $root 'hostile.html'

            $write = New-GwmHtmlReport -Report $report -OutputPath $outputPath
            $html = Get-Content -LiteralPath $outputPath -Raw

            $write.Success | Should Be $true
            $html | Should Match '&lt;script&gt;alert\(&quot;x&quot;\)&lt;/script&gt;'
            $html | Should Match '&lt;img src=x onerror=alert\(1\)&gt;'
            $html | Should Match 'A&amp;B'
            $html | Should Match 'first line<br>second line &amp; more'
            $html | Should Match '&lt;warning&gt; &amp; &quot;detail&quot;'
            $html | Should Not Match '<script\b'
            $html | Should Not Match '<img\b'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'renders an explicit empty-workspace state' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-html-' + [guid]::NewGuid().ToString('N'))
        try {
            $report = New-GwmHtmlTestReport
            $outputPath = Join-Path $root 'empty.html'

            $write = New-GwmHtmlReport -Report $report -OutputPath $outputPath
            $html = Get-Content -LiteralPath $outputPath -Raw

            $write.Success | Should Be $true
            $html | Should Match 'No repositories were found in this workspace.'
            $html | Should Match '0'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'renders Sync fields, Unicode, and long paths' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-html-' + [guid]::NewGuid().ToString('N'))
        try {
            $longPath = 'C:\fixtures\' + (('long-segment-' * 24) + 'repository')
            $result = [pscustomobject]@{
                Name='資料庫-東京-😀'; Path=$longPath; SyncStatus='UPDATED'
                BeforeCommit='before-sha'; AfterCommit='after-sha'; TargetCommit='target-sha'
                Ahead=0; Behind=0; ExitCode=0; Reason='Fast-forward completed.'
                RecommendedAction='No action required.'
            }
            $report = New-GwmHtmlTestReport -Results @($result) -Mode 'Sync'
            $outputPath = Join-Path $root 'sync.html'

            $write = New-GwmHtmlReport -Report $report -OutputPath $outputPath
            $html = Get-Content -LiteralPath $outputPath -Raw

            $write.Success | Should Be $true
            $html | Should Match '資料庫-東京-😀'
            $html | Should Match 'before-sha'
            $html | Should Match 'after-sha'
            $html | Should Match 'target-sha'
            $html | Should Match 'Fast-forward completed.'
            $html | Should Match ([regex]::Escape($longPath))
            $html | Should Match 'UPDATED'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'returns a structured failure when the output path cannot be written' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-html-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $report = New-GwmHtmlTestReport
            $write = New-GwmHtmlReport -Report $report -OutputPath $root

            $write.Success | Should Be $false
            [string]::IsNullOrWhiteSpace($write.Error) | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    It 'rejects a report that does not satisfy the shared envelope contract' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-html-' + [guid]::NewGuid().ToString('N'))
        try {
            $invalidReport = [pscustomobject]@{ Mode='Scan'; Results=@() }
            $write = New-GwmHtmlReport -Report $invalidReport -OutputPath (Join-Path $root 'invalid.html')

            $write.Success | Should Be $false
            $write.Error | Should Match 'missing required property'
            (Test-Path -LiteralPath (Join-Path $root 'invalid.html')) | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }
}
