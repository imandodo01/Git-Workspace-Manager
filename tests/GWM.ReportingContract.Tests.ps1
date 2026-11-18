$modulePath = Join-Path $PSScriptRoot '..\src\GWM.Core.psm1'
Import-Module -Name $modulePath -Force

Describe 'GWM shared run report contract' {
    $startedAt = [DateTimeOffset]::Parse('2026-11-18T10:00:00+07:00')
    $finishedAt = [DateTimeOffset]::Parse('2026-11-18T10:00:02.500+07:00')

    It 'creates the same versioned envelope for Scan and Sync' {
        $scanResult = [pscustomobject]@{ Name='scan-repo'; Classification='UP_TO_DATE'; Ahead=0; Behind=0 }
        $syncResult = [pscustomobject]@{ Name='sync-repo'; SyncStatus='UPDATED'; BeforeCommit='abc'; AfterCommit='def' }

        $scan = New-GwmRunReport -Mode 'Scan' -WorkspaceRoot 'C:\fixtures' -Results @($scanResult) -StartedAt $startedAt -FinishedAt $finishedAt
        $sync = New-GwmRunReport -Mode 'Sync' -WorkspaceRoot 'C:\fixtures' -Results @($syncResult) -StartedAt $startedAt -FinishedAt $finishedAt

        @($scan.PSObject.Properties.Name | Sort-Object) -join ',' | Should Be (@($sync.PSObject.Properties.Name | Sort-Object) -join ',')
        $scan.SchemaVersion | Should Be '1.0'
        $sync.SchemaVersion | Should Be '1.0'
        $scan.Mode | Should Be 'Scan'
        $sync.Mode | Should Be 'Sync'
        $scan.RunId | Should Match '^[0-9a-f]{32}$'
        $sync.RunId | Should Match '^[0-9a-f]{32}$'
        $scan.DurationMs | Should Be 2500
        $sync.DurationMs | Should Be 2500
        $scan.WorkspaceRoot | Should Be 'C:\fixtures'
        $scan.GeneratedAt | Should Be '2026-11-18T10:00:02.5000000+07:00'
        @($scan.OutputWarnings).Count | Should Be 0
    }

    It 'normalizes Scan classifications without changing result fields' {
        $results = @(
            [pscustomobject]@{ Name='current'; Classification='UP_TO_DATE'; Ahead=0; Behind=0 },
            [pscustomobject]@{ Name='dirty'; Classification='NEEDS_ATTENTION'; Ahead=$null; Behind=$null },
            [pscustomobject]@{ Name='ahead'; Classification='AHEAD'; Ahead=2; Behind=0 },
            [pscustomobject]@{ Name='behind'; Classification='BEHIND'; Ahead=0; Behind=3 },
            [pscustomobject]@{ Name='diverged'; Classification='DIVERGED'; Ahead=1; Behind=1 },
            [pscustomobject]@{ Name='unknown'; Classification='UNKNOWN'; Ahead=$null; Behind=$null },
            [pscustomobject]@{ Name='invalid'; Classification='INVALID_REPOSITORY' },
            [pscustomobject]@{ Name='failed'; Classification='FAILED' }
        )

        $report = New-GwmRunReport -Mode 'Scan' -WorkspaceRoot 'C:\fixtures' -Results $results -StartedAt $startedAt -FinishedAt $finishedAt

        $report.RepositoryCount | Should Be 8
        $report.Summary.Updated | Should Be 0
        $report.Summary.UpToDate | Should Be 1
        $report.Summary.NeedsAttention | Should Be 6
        $report.Summary.Failed | Should Be 1
        $report.Results[1].Ahead | Should Be $null
        $report.Results[1].Classification | Should Be 'NEEDS_ATTENTION'
    }

    It 'normalizes Sync statuses and includes explicit zero counts' {
        $results = @(
            [pscustomobject]@{ Name='updated'; SyncStatus='UPDATED'; Ahead=0; Behind=0 },
            [pscustomobject]@{ Name='current'; SyncStatus='UP_TO_DATE'; Ahead=0; Behind=0 },
            [pscustomobject]@{ Name='attention'; SyncStatus='NEEDS_ATTENTION'; Ahead=$null; Behind=$null },
            [pscustomobject]@{ Name='failed'; SyncStatus='FAILED'; ExitCode=2 }
        )

        $report = New-GwmRunReport -Mode 'Sync' -WorkspaceRoot 'C:\fixtures' -Results $results -StartedAt $startedAt -FinishedAt $finishedAt

        $report.Summary.Updated | Should Be 1
        $report.Summary.UpToDate | Should Be 1
        $report.Summary.NeedsAttention | Should Be 1
        $report.Summary.Failed | Should Be 1
        $report.Results[2].Ahead | Should Be $null
        $report.Results[3].ExitCode | Should Be 2
    }

    It 'returns stable zero-valued counts for an empty workspace' {
        $report = New-GwmRunReport -Mode 'Scan' -WorkspaceRoot 'C:\fixtures' -Results @() -StartedAt $startedAt -FinishedAt $finishedAt

        $report.RepositoryCount | Should Be 0
        $report.Summary.Updated | Should Be 0
        $report.Summary.UpToDate | Should Be 0
        $report.Summary.NeedsAttention | Should Be 0
        $report.Summary.Failed | Should Be 0
        @($report.Results).Count | Should Be 0
    }
}
