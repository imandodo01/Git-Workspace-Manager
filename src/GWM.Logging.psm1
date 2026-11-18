# GWM operational logging helpers.
# Source remains ASCII-only for Windows PowerShell 5.1 compatibility.

$script:GwmLoggingCorePath = Join-Path $PSScriptRoot 'GWM.Core.psm1'
Import-Module -Name $script:GwmLoggingCorePath -Force
Import-Module -Name (Join-Path $PSScriptRoot 'GWM.History.psm1') -Force

function Get-GwmLoggingOptions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Settings)

    $logging = $Settings.logging
    $enabled = $true
    $relativePath = 'logs'
    $retentionCount = 30

    if ($null -ne $logging) {
        if ($null -ne $logging.PSObject.Properties['enabled']) {
            if ($logging.enabled -isnot [bool]) { throw 'logging.enabled must be a boolean.' }
            $enabled = [bool]$logging.enabled
        }
        if ($null -ne $logging.PSObject.Properties['path']) {
            if ($logging.path -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$logging.path)) {
                throw 'logging.path must be a non-empty relative path.'
            }
            $relativePath = [string]$logging.path
        }
        if ($null -ne $logging.PSObject.Properties['retentionCount']) {
            $value = $logging.retentionCount
            if ($value -isnot [int] -and $value -isnot [long]) {
                throw 'logging.retentionCount must be a non-negative integer.'
            }
            if ([long]$value -lt 0 -or [long]$value -gt 2147483647) {
                throw 'logging.retentionCount must be between 0 and 2147483647.'
            }
            $retentionCount = [int]$value
        }
    }

    if ([System.IO.Path]::IsPathRooted($relativePath)) {
        throw 'logging.path must be relative to ProjectRoot.'
    }

    [pscustomobject]@{
        Enabled = $enabled
        RelativePath = $relativePath
        RetentionCount = $retentionCount
    }
}

function ConvertTo-GwmSafeLogText {
    [CmdletBinding()]
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return $null }
    $safe = ConvertTo-GwmRedactedRemoteUrl -RemoteUrl $Value
    $safe = [regex]::Replace(
        $safe,
        '(?i)\b(password|passwd|token|access_token|api[_-]?key|secret|authorization)\b(\s*[:=]\s*)(["'']?)[^\s,;''"]+\3',
        '$1$2[REDACTED]'
    )
    $safe = [regex]::Replace($safe, '(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*', 'Bearer [REDACTED]')
    return $safe
}

function New-GwmLogFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Report)

    if ($Report.Mode -notin @('Scan', 'Sync')) { throw 'Report Mode must be Scan or Sync.' }
    $runId = [string]$Report.RunId
    if ($runId -notmatch '^[0-9a-fA-F]{32}$') { throw 'Report RunId must be a 32-character hexadecimal GUID.' }
    $generatedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Report.GeneratedAt, [ref]$generatedAt)) {
        throw 'Report GeneratedAt must be a valid ISO-8601 timestamp.'
    }
    $stamp = $generatedAt.ToString('yyyyMMddTHHmmssfff', [System.Globalization.CultureInfo]::InvariantCulture)
    return ('gwm-{0}-{1}-{2}.log' -f $Report.Mode.ToLowerInvariant(), $stamp, $runId.ToLowerInvariant())
}

function Invoke-GwmLogRetention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LogDirectory,
        [ValidateRange(0, 2147483647)][int]$RetentionCount = 30
    )

    $result = [pscustomobject]@{ Success = $true; DeletedCount = 0; PreservedCount = 0; Warnings = @() }
    if ($RetentionCount -eq 0) { return $result }

    try {
        if (-not [System.IO.Directory]::Exists($LogDirectory)) { return $result }
        $root = [System.IO.Path]::GetFullPath($LogDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
        if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw 'Log directory must be a real directory, not a reparse point.'
        }

        $pattern = '^gwm-(scan|sync)-\d{8}T\d{9}-[0-9a-f]{32}\.log
        $eligible = @()
        foreach ($item in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)) {
            if ($item.PSIsContainer -or (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
                $result.PreservedCount++
                continue
            }
            $parent = [System.IO.Path]::GetFullPath($item.DirectoryName).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            if (-not $parent.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or $item.Name -cnotmatch $pattern) {
                $result.PreservedCount++
                continue
            }
            $eligible += $item
        }

        $ordered = @($eligible | Sort-Object Name -Descending)
        if ($ordered.Count -gt $RetentionCount) {
            foreach ($item in @($ordered | Select-Object -Skip $RetentionCount)) {
                try {
                    $candidate = [System.IO.Path]::GetFullPath($item.FullName)
                    $parent = [System.IO.Path]::GetDirectoryName($candidate).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
                    if (-not $parent.Equals($root, [System.StringComparison]::OrdinalIgnoreCase) -or [System.IO.Path]::GetFileName($candidate) -cnotmatch $pattern) {
                        throw 'Retention candidate failed final ownership/path validation.'
                    }
                    $current = Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
                    if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $current.PSIsContainer) {
                        throw 'Retention candidate is no longer a regular file.'
                    }
                    [System.IO.File]::Delete($candidate)
                    $result.DeletedCount++
                }
                catch {
                    $result.Warnings += ("Could not prune '{0}': {1}" -f $item.Name, (ConvertTo-GwmSafeLogText -Value $_.Exception.Message))
                }
            }
        }
    }
    catch {
        $result.Success = $false
        $result.Warnings += (ConvertTo-GwmSafeLogText -Value $_.Exception.Message)
    }
    return $result
}

function Write-GwmRunLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)]$Report,
        [AllowEmptyCollection()][object[]]$Events = @(),
        [bool]$Enabled = $true,
        [string]$RelativePath = 'logs',
        [ValidateRange(0, 2147483647)][int]$RetentionCount = 30
    )

    $result = [pscustomobject]@{ Success = $true; Enabled = $Enabled; Path = $null; Error = $null; Warnings = @() }
    if (-not $Enabled) { return $result }

    $path = $null
    $createdLog = $false
    try {
        $directory = Resolve-GwmOutputDirectory -ProjectRoot $ProjectRoot -RelativePath $RelativePath
        if (-not [System.IO.Directory]::Exists($directory)) {
            [void][System.IO.Directory]::CreateDirectory($directory)
        }
        $directoryItem = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
        if (($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Log directory cannot be a symbolic link or junction.'
        }

        $fileName = New-GwmLogFileName -Report $Report
        $path = Join-Path $directory $fileName
        if ([System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path)) {
            throw 'Log file already exists; refusing to overwrite it.'
        }

        $lines = @()
        foreach ($event in @($Events)) {
            $eventName = [string]$event.Event
            if ([string]::IsNullOrWhiteSpace($eventName)) { $eventName = 'Event' }
            $timestamp = [string]$event.Timestamp
            if ([string]::IsNullOrWhiteSpace($timestamp)) { $timestamp = [DateTimeOffset]::Now.ToString('o') }
            $entry = [ordered]@{
                Timestamp = $timestamp
                RunId = [string]$Report.RunId
                Mode = [string]$Report.Mode
                Event = ConvertTo-GwmSafeLogText -Value $eventName
            }
            if ($null -ne $event.PSObject.Properties['Repository']) {
                $entry.Repository = ConvertTo-GwmSafeLogText -Value ([string]$event.Repository)
            }
            if ($null -ne $event.PSObject.Properties['Error']) {
                $entry.Error = ConvertTo-GwmSafeLogText -Value ([string]$event.Error)
            }
            if ($null -ne $event.PSObject.Properties['Counts']) {
                $counts = [ordered]@{}
                foreach ($key in @('Updated', 'UpToDate', 'NeedsAttention', 'Failed')) {
                    $property = $event.Counts.PSObject.Properties[$key]
                    if ($null -ne $property -and $property.Value -is [ValueType]) {
                        $counts[$key] = $property.Value
                    }
                }
                $entry.Counts = [pscustomobject]$counts
            }
            $lines += (ConvertTo-Json -InputObject ([pscustomobject]$entry) -Depth 5 -Compress)
        }

        $content = if ($lines.Count -gt 0) { [string]::Join([Environment]::NewLine, [string[]]$lines) + [Environment]::NewLine } else { '' }
        $encoding = [System.Text.UTF8Encoding]::new($false)
        $bytes = $encoding.GetBytes($content)
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        $createdLog = $true
        try {
            if ($bytes.Length -gt 0) { $stream.Write($bytes, 0, $bytes.Length) }
        }
        finally { $stream.Dispose() }
        $result.Path = $path

        $retention = Invoke-GwmLogRetention -LogDirectory $directory -RetentionCount $RetentionCount
        if (-not $retention.Success -or $retention.Warnings.Count -gt 0) {
            $result.Warnings += @($retention.Warnings)
        }
    }
    catch {
        if ($createdLog -and $path -and [System.IO.File]::Exists($path)) {
            try { [System.IO.File]::Delete($path) } catch { }
        }
        $result.Success = $false
        $result.Error = ConvertTo-GwmSafeLogText -Value $_.Exception.Message
        $result.Warnings += $result.Error
    }
    return $result
}

Export-ModuleMember -Function Get-GwmLoggingOptions, ConvertTo-GwmSafeLogText, New-GwmLogFileName, Invoke-GwmLogRetention, Write-GwmRunLog
