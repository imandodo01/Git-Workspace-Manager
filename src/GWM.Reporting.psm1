function ConvertTo-GwmHtmlEncodedText {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return '&mdash;'
    }

    if ($Value -is [System.Array]) {
        $text = (@($Value | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    }
    else {
        $text = [string]$Value
    }

    $encoded = [System.Net.WebUtility]::HtmlEncode($text)
    return [regex]::Replace($encoded, '\r\n|\n|\r', '<br>')
}

function Get-GwmHtmlPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-GwmHtmlStatusClass {
    [CmdletBinding()]
    param([AllowNull()][string]$Status)

    switch ($Status) {
        { $_ -in @('UP_TO_DATE', 'UPDATED') } { return 'status-ok' }
        'FAILED' { return 'status-failed' }
        default { return 'status-attention' }
    }
}

function Add-GwmHtmlDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory = $true)][string]$Label,
        [AllowNull()][object]$Value
    )

    [void]$Builder.Append('<div class="detail"><dt>')
    [void]$Builder.Append((ConvertTo-GwmHtmlEncodedText -Value $Label))
    [void]$Builder.Append('</dt><dd>')
    [void]$Builder.Append((ConvertTo-GwmHtmlEncodedText -Value $Value))
    [void]$Builder.AppendLine('</dd></div>')
}

function New-GwmHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Report,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    $resolvedPath = $null
    try {
        if ($Report.Mode -notin @('Scan', 'Sync')) {
            throw 'Report Mode must be Scan or Sync.'
        }

        foreach ($requiredProperty in @('SchemaVersion', 'RunId', 'GeneratedAt', 'DurationMs', 'WorkspaceRoot', 'RepositoryCount', 'Summary', 'Results', 'OutputWarnings')) {
            if ($null -eq $Report.PSObject.Properties[$requiredProperty]) {
                throw ("Report is missing required property '{0}'." -f $requiredProperty)
            }
        }

        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            throw 'OutputPath must not be empty.'
        }

        $resolvedPath = [System.IO.Path]::GetFullPath($OutputPath)
        $directory = [System.IO.Path]::GetDirectoryName($resolvedPath)
        if ([string]::IsNullOrWhiteSpace($directory)) {
            throw 'Unable to resolve the output directory.'
        }
        [void][System.IO.Directory]::CreateDirectory($directory)

        $builder = New-Object System.Text.StringBuilder
        [void]$builder.AppendLine('<!doctype html>')
        [void]$builder.AppendLine('<html lang="en">')
        [void]$builder.AppendLine('<head>')
        [void]$builder.AppendLine('<meta charset="utf-8">')
        [void]$builder.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
        [void]$builder.Append('<title>GWM ')
        [void]$builder.Append((ConvertTo-GwmHtmlEncodedText -Value $Report.Mode))
        [void]$builder.AppendLine(' report</title>')
        [void]$builder.AppendLine('<style>')
        [void]$builder.AppendLine(':root{color-scheme:light;--ink:#172033;--muted:#657084;--line:#dce2ea;--surface:#fff;--page:#f4f6f9;--accent:#2457a7;--ok:#176b45;--warn:#8a5b00;--bad:#a12626}')
        [void]$builder.AppendLine('*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:14px/1.5 "Segoe UI",Arial,sans-serif}')
        [void]$builder.AppendLine('.container{max-width:1200px;margin:0 auto;padding:32px 24px}h1{margin:0 0 6px;font-size:28px}.subtitle{color:var(--muted);margin:0 0 24px}')
        [void]$builder.AppendLine('.panel,.repo-card{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:18px;margin:16px 0;box-shadow:0 1px 2px rgba(20,32,50,.04)}')
        [void]$builder.AppendLine('.metadata,.details{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px}.detail dt{font-size:12px;color:var(--muted)}.detail dd{margin:2px 0 0;overflow-wrap:anywhere}')
        [void]$builder.AppendLine('.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}.metric{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:16px}.metric strong{display:block;font-size:26px}.metric span{color:var(--muted)}')
        [void]$builder.AppendLine('.repo-heading{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}.repo-heading h2{font-size:17px;margin:0;overflow-wrap:anywhere}.status{display:inline-block;padding:3px 9px;border-radius:999px;font-size:12px;font-weight:600;overflow-wrap:anywhere}.status-ok{background:#e5f4ec;color:var(--ok)}.status-attention{background:#fff3d9;color:var(--warn)}.status-failed{background:#fde8e8;color:var(--bad)}')
        [void]$builder.AppendLine('.details{margin-top:16px}.detail{min-width:0}.detail dd{overflow-wrap:anywhere}.section-title{font-size:18px;margin:26px 0 10px}.empty{color:var(--muted);text-align:center;padding:24px}.warnings{border-left:4px solid var(--warn)}')
        [void]$builder.AppendLine('@media(max-width:600px){.container{padding:20px 14px}h1{font-size:23px}.panel,.repo-card{padding:14px}}')
        [void]$builder.AppendLine('</style>')
        [void]$builder.AppendLine('</head>')
        [void]$builder.AppendLine('<body><main class="container">')
        [void]$builder.Append('<h1>Git Workspace Manager — ')
        [void]$builder.Append((ConvertTo-GwmHtmlEncodedText -Value $Report.Mode))
        [void]$builder.AppendLine('</h1>')
        [void]$builder.AppendLine('<p class="subtitle">Repository workspace report</p>')

        [void]$builder.AppendLine('<section class="panel metadata" aria-label="Run metadata">')
        Add-GwmHtmlDetail -Builder $builder -Label 'Schema version' -Value $Report.SchemaVersion
        Add-GwmHtmlDetail -Builder $builder -Label 'Run ID' -Value $Report.RunId
        Add-GwmHtmlDetail -Builder $builder -Label 'Generated at' -Value $Report.GeneratedAt
        Add-GwmHtmlDetail -Builder $builder -Label 'Duration (ms)' -Value $Report.DurationMs
        Add-GwmHtmlDetail -Builder $builder -Label 'Workspace root' -Value $Report.WorkspaceRoot
        Add-GwmHtmlDetail -Builder $builder -Label 'Repositories' -Value $Report.RepositoryCount
        [void]$builder.AppendLine('</section>')

        [void]$builder.AppendLine('<section class="summary" aria-label="Run summary">')
        foreach ($metric in @(
            [pscustomobject]@{ Name='Updated'; Value=$Report.Summary.Updated },
            [pscustomobject]@{ Name='Up to date'; Value=$Report.Summary.UpToDate },
            [pscustomobject]@{ Name='Needs attention'; Value=$Report.Summary.NeedsAttention },
            [pscustomobject]@{ Name='Failed'; Value=$Report.Summary.Failed }
        )) {
            [void]$builder.Append('<div class="metric"><strong>')
            [void]$builder.Append((ConvertTo-GwmHtmlEncodedText -Value $metric.Value))
            [void]$builder.Append('</strong><span>')
            [void]$builder.Append((ConvertTo-GwmHtmlEncodedText -Value $metric.Name))
            [void]$builder.AppendLine('</span></div>')
        }
        [void]$builder.AppendLine('</section>')

        [void]$builder.AppendLine('<h2 class="section-title">Repository details</h2>')
        $results = @($Report.Results)
        if ($results.Count -eq 0) {
            [void]$builder.AppendLine('<section class="panel empty">No repositories were found in this workspace.</section>')
        }
        else {
            foreach ($result in $results) {
                $status = if ($Report.Mode -eq 'Scan') { [string]$result.Classification } else { [string]$result.SyncStatus }
                $statusClass = Get-GwmHtmlStatusClass -Status $status
                $name = Get-GwmHtmlPropertyValue -InputObject $result -Name 'Name'
                [void]$builder.AppendLine('<article class="repo-card">')
                [void]$builder.Append('<div class="repo-heading"><h2>')
                [void]$builder.Append((ConvertTo-GwmHtmlEncodedText -Value $name))
                [void]$builder.Append('</h2><span class="status ')
                [void]$builder.Append($statusClass)
                [void]$builder.Append('">')
                [void]$builder.Append((ConvertTo-GwmHtmlEncodedText -Value $status))
                [void]$builder.AppendLine('</span></div>')
                [void]$builder.AppendLine('<dl class="details">')

                foreach ($field in @(
                    [pscustomobject]@{ Label='Path'; Name='Path' },
                    [pscustomobject]@{ Label='Branch'; Name='Branch' },
                    [pscustomobject]@{ Label='Upstream'; Name='Upstream' },
                    [pscustomobject]@{ Label='HEAD'; Name='Head' },
                    [pscustomobject]@{ Label='Ahead'; Name='Ahead' },
                    [pscustomobject]@{ Label='Behind'; Name='Behind' },
                    [pscustomobject]@{ Label='Changed files'; Name='StatusLines' },
                    [pscustomobject]@{ Label='Before commit'; Name='BeforeCommit' },
                    [pscustomobject]@{ Label='After commit'; Name='AfterCommit' },
                    [pscustomobject]@{ Label='Target commit'; Name='TargetCommit' },
                    [pscustomobject]@{ Label='Exit code'; Name='ExitCode' },
                    [pscustomobject]@{ Label='Reason'; Name='Reason' },
                    [pscustomobject]@{ Label='Recommended action'; Name='RecommendedAction' }
                )) {
                    $value = Get-GwmHtmlPropertyValue -InputObject $result -Name $field.Name
                    if ($null -ne $value) {
                        Add-GwmHtmlDetail -Builder $builder -Label $field.Label -Value $value
                    }
                }
                [void]$builder.AppendLine('</dl></article>')
            }
        }

        $warnings = @($Report.OutputWarnings)
        if ($warnings.Count -gt 0) {
            [void]$builder.AppendLine('<section class="panel warnings"><h2>Output warnings</h2><ul>')
            foreach ($warning in $warnings) {
                [void]$builder.Append('<li>')
                [void]$builder.Append((ConvertTo-GwmHtmlEncodedText -Value $warning))
                [void]$builder.AppendLine('</li>')
            }
            [void]$builder.AppendLine('</ul></section>')
        }

        [void]$builder.AppendLine('</main></body></html>')
        $html = $builder.ToString()
        [System.IO.File]::WriteAllText($resolvedPath, $html, ([System.Text.UTF8Encoding]::new($false)))

        return [pscustomobject]@{
            Success = $true
            Path = $resolvedPath
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Path = $resolvedPath
            Error = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function New-GwmHtmlReport
