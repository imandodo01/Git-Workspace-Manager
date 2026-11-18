$modulePath = Join-Path $PSScriptRoot '..\src\GWM.Core.psm1'
Import-Module -Name $modulePath -Force

function New-GwmConfigurationFixture {
    param([hashtable]$Overrides = @{})

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('gwm-config-' + [guid]::NewGuid().ToString('N'))
    $configDirectory = Join-Path $root 'config'
    $workspaceRoot = Join-Path $root 'workspace'
    [void][System.IO.Directory]::CreateDirectory($configDirectory)
    [void][System.IO.Directory]::CreateDirectory($workspaceRoot)

    $settings = @{
        workspace = @{ root = $workspaceRoot; recursiveDiscovery = $true }
        git = @{ defaultRemote = 'origin'; syncStrategy = 'ff-only' }
    }
    foreach ($key in $Overrides.Keys) {
        $settings[$key] = $Overrides[$key]
    }

    $json = ConvertTo-Json -InputObject $settings -Depth 8
    [System.IO.File]::WriteAllText((Join-Path $configDirectory 'settings.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    [pscustomobject]@{ ProjectRoot = $root; WorkspaceRoot = $workspaceRoot }
}

Describe 'GWM reporting and logging configuration' {
    It 'provides safe defaults when reporting and logging sections are omitted' {
        $fixture = New-GwmConfigurationFixture
        try {
            $configuration = Get-GwmConfiguration -ProjectRoot $fixture.ProjectRoot
            $configuration.Reporting.OutputDirectory | Should Be 'reports'
            (@($configuration.Reporting.Formats) -join ',') | Should Be 'json,html'
            $configuration.Reporting.KeepHistory | Should Be $true
            $configuration.Reporting.RetentionCount | Should Be 30
            $configuration.Logging.Enabled | Should Be $true
            $configuration.Logging.Path | Should Be 'logs'
            $configuration.Logging.RetentionCount | Should Be 30
        }
        finally {
            if (Test-Path -LiteralPath $fixture.ProjectRoot) { Remove-Item -LiteralPath $fixture.ProjectRoot -Recurse -Force }
        }
    }

    It 'normalizes supported formats and returns validated relative output settings' {
        $fixture = New-GwmConfigurationFixture -Overrides @{
            reporting = @{ formats = @('HTML', 'json'); outputDirectory = 'runtime-reports'; keepHistory = $false; retentionCount = 0 }
            logging = @{ enabled = $false; path = 'runtime-logs'; retentionCount = 12 }
        }
        try {
            $configuration = Get-GwmConfiguration -ProjectRoot $fixture.ProjectRoot
            (@($configuration.Reporting.Formats) -join ',') | Should Be 'html,json'
            $configuration.Reporting.OutputDirectory | Should Be 'runtime-reports'
            $configuration.Reporting.KeepHistory | Should Be $false
            $configuration.Reporting.RetentionCount | Should Be 0
            $configuration.Logging.Enabled | Should Be $false
            $configuration.Logging.Path | Should Be 'runtime-logs'
            $configuration.Logging.RetentionCount | Should Be 12
        }
        finally {
            if (Test-Path -LiteralPath $fixture.ProjectRoot) { Remove-Item -LiteralPath $fixture.ProjectRoot -Recurse -Force }
        }
    }

    It 'rejects rooted and traversal output directories' {
        $rooted = [System.IO.Path]::GetTempPath()
        $fixture = New-GwmConfigurationFixture -Overrides @{ reporting = @{ outputDirectory = $rooted } }
        try {
            { Get-GwmConfiguration -ProjectRoot $fixture.ProjectRoot } | Should Throw
        }
        finally {
            if (Test-Path -LiteralPath $fixture.ProjectRoot) { Remove-Item -LiteralPath $fixture.ProjectRoot -Recurse -Force }
        }

        $fixture = New-GwmConfigurationFixture -Overrides @{ logging = @{ path = '..\outside' } }
        try {
            { Get-GwmConfiguration -ProjectRoot $fixture.ProjectRoot } | Should Throw
        }
        finally {
            if (Test-Path -LiteralPath $fixture.ProjectRoot) { Remove-Item -LiteralPath $fixture.ProjectRoot -Recurse -Force }
        }
    }

    It 'requires JSON and rejects unsupported or duplicate report formats' {
        $fixture = New-GwmConfigurationFixture -Overrides @{ reporting = @{ formats = @('html') } }
        try {
            { Get-GwmConfiguration -ProjectRoot $fixture.ProjectRoot } | Should Throw
        }
        finally {
            if (Test-Path -LiteralPath $fixture.ProjectRoot) { Remove-Item -LiteralPath $fixture.ProjectRoot -Recurse -Force }
        }

        $fixture = New-GwmConfigurationFixture -Overrides @{ reporting = @{ formats = @('json', 'pdf') } }
        try {
            { Get-GwmConfiguration -ProjectRoot $fixture.ProjectRoot } | Should Throw
        }
        finally {
            if (Test-Path -LiteralPath $fixture.ProjectRoot) { Remove-Item -LiteralPath $fixture.ProjectRoot -Recurse -Force }
        }

        $fixture = New-GwmConfigurationFixture -Overrides @{ reporting = @{ formats = @('json', 'JSON') } }
        try {
            { Get-GwmConfiguration -ProjectRoot $fixture.ProjectRoot } | Should Throw
        }
        finally {
            if (Test-Path -LiteralPath $fixture.ProjectRoot) { Remove-Item -LiteralPath $fixture.ProjectRoot -Recurse -Force }
        }
    }

    It 'rejects invalid booleans and retention counts' {
        $invalidCases = @(
            @{ reporting = @{ keepHistory = 'yes' } },
            @{ reporting = @{ retentionCount = -1 } },
            @{ reporting = @{ retentionCount = 2147483648 } },
            @{ logging = @{ enabled = 1 } },
            @{ logging = @{ retentionCount = 1.5 } }
        )
        foreach ($overrides in $invalidCases) {
            $fixture = New-GwmConfigurationFixture -Overrides $overrides
            try {
                { Get-GwmConfiguration -ProjectRoot $fixture.ProjectRoot } | Should Throw
            }
            finally {
                if (Test-Path -LiteralPath $fixture.ProjectRoot) { Remove-Item -LiteralPath $fixture.ProjectRoot -Recurse -Force }
            }
        }
    }
}
