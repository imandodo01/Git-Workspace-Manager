function Resolve-GwmOutputDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$RelativePath = 'reports'
    )

    $root = [System.IO.Path]::GetFullPath($ProjectRoot)
    if (-not [System.IO.Directory]::Exists($root)) {
        throw "Project root does not exist: $root"
    }

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw 'Output directory must be relative to ProjectRoot.'
    }

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Output directory must remain beneath ProjectRoot.'
    }

    # Reject existing reparse-point segments so a lexically safe path cannot
    # escape ProjectRoot through a directory symlink or junction.
    $current = $candidate
    while ($current.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Output directory cannot contain a symbolic link or junction.'
            }
        }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($parent) -or $parent.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) { break }
        $current = $parent
    }

    return $candidate
}

function New-GwmHistoryFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Report,
        [Parameter(Mandatory = $true)][ValidateSet('json', 'html')][string]$Format
    )

    if ($Report.Mode -notin @('Scan', 'Sync')) {
        throw "Unsupported report mode: $($Report.Mode)"
    }
    $runId = [string]$Report.RunId
    if ($runId -notmatch '^[0-9a-fA-F]{32}$') {
        throw 'Report RunId must be a 32-character hexadecimal GUID.'
    }

    $generatedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Report.GeneratedAt, [ref]$generatedAt)) {
        throw 'Report GeneratedAt must be a valid ISO-8601 timestamp.'
    }

    $stamp = $generatedAt.ToString('yyyyMMddTHHmmssfff', [System.Globalization.CultureInfo]::InvariantCulture)
    return ('gwm-{0}-{1}-{2}.{3}' -f $Report.Mode.ToLowerInvariant(), $stamp, $runId.ToLowerInvariant(), $Format)
}

function Write-GwmAtomicFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not [System.IO.Directory]::Exists($directory)) {
        [void][System.IO.Directory]::CreateDirectory($directory)
    }

    $temporaryPath = Join-Path $directory ('.gwm-tmp-' + [guid]::NewGuid().ToString('N'))
    $encoding = [System.Text.UTF8Encoding]::new($false)
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $Content, $encoding)
        if ([System.IO.File]::Exists($fullPath)) {
            try {
                [System.IO.File]::Replace($temporaryPath, $fullPath, $null)
            }
            catch {
                # Windows PowerShell 5.1/filesystems that do not support Replace
                # fall back to same-directory Move with overwrite semantics.
                Move-Item -LiteralPath $temporaryPath -Destination $fullPath -Force -ErrorAction Stop
            }
        }
        else {
            [System.IO.File]::Move($temporaryPath, $fullPath)
        }

        return [pscustomobject]@{ Success = $true; Path = $fullPath; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Path = $fullPath; Error = $_.Exception.Message }
    }
    finally {
        if ([System.IO.File]::Exists($temporaryPath)) {
            try { [System.IO.File]::Delete($temporaryPath) } catch { }
        }
    }
}

function Write-GwmHistoryArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HistoryDirectory,
        [Parameter(Mandatory = $true)]$Report,
        [Parameter(Mandatory = $true)][ValidateSet('json', 'html')][string]$Format,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    try {
        $fileName = New-GwmHistoryFileName -Report $Report -Format $Format
        $root = [System.IO.Path]::GetFullPath($HistoryDirectory)
        if (-not [System.IO.Directory]::Exists($root)) {
            [void][System.IO.Directory]::CreateDirectory($root)
        }
        $path = Join-Path $root $fileName
        if ([System.IO.File]::Exists($path) -or [System.IO.Directory]::Exists($path)) {
            return [pscustomobject]@{ Success = $false; Path = $path; Error = 'History artifact already exists; refusing to overwrite it.' }
        }
        return Write-GwmAtomicFile -Path $path -Content $Content
    }
    catch {
        return [pscustomobject]@{ Success = $false; Path = $null; Error = $_.Exception.Message }
    }
}

function Write-GwmLatestArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    return Write-GwmAtomicFile -Path $Path -Content $Content
}

function Invoke-GwmHistoryRetention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HistoryDirectory,
        [Parameter(Mandatory = $true)][ValidateSet('Scan', 'Sync')][string]$Mode,
        [Parameter(Mandatory = $true)][ValidateSet('json', 'html')][string]$Format,
        [ValidateRange(0, 2147483647)][int]$RetentionCount = 30
    )

    $result = [pscustomobject]@{ Success = $true; DeletedCount = 0; PreservedCount = 0; Warnings = @() }
    if ($RetentionCount -eq 0) { return $result }

    try {
        if (-not [System.IO.Directory]::Exists($HistoryDirectory)) { return $result }
        $root = [System.IO.Path]::GetFullPath($HistoryDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
        if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw 'History directory must be a real directory, not a reparse point.'
        }

        $pattern = '^gwm-' + $Mode.ToLowerInvariant() + '-\d{8}T\d{9}-[0-9a-f]{32}\.' + $Format + '$'
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
                    [System.IO.File]::Delete($candidate)
                    $result.DeletedCount++
                }
                catch {
                    $result.Warnings += ("Could not prune '{0}': {1}" -f $item.Name, $_.Exception.Message)
                }
            }
        }
    }
    catch {
        $result.Success = $false
        $result.Warnings += $_.Exception.Message
    }

    return $result
}

Export-ModuleMember -Function Resolve-GwmOutputDirectory, New-GwmHistoryFileName, Write-GwmHistoryArtifact, Write-GwmLatestArtifact, Invoke-GwmHistoryRetention
