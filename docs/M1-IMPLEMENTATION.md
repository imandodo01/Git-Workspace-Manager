# M1 — Foundation Implementation

## Delivered foundation

- PowerShell module for local configuration loading, repository discovery, Git invocation, repository inspection, and state classification.
- PowerShell scan entry point and Windows CMD launcher.
- Initial Pester tests using syntax compatible with Pester 3.x.
- Scan writes a local JSON snapshot to reports/latest-scan.json.

## Current limitations

- M1 scan is read-only. It does not fetch or synchronize repositories.
- HTML reporting, log retention, selective repository selection, and VS Code actions are not implemented yet.
- Pester tests have been authored but must be executed on Windows PowerShell 5.1.

## Local setup

1. Copy config/settings.example.json to config/settings.json.
2. Set workspace.root to the intended workspace directory.
3. Optionally copy config/repositories.example.json to config/repositories.json and define explicit repositories. If the registry exists, it is used instead of recursive discovery.
4. Run Start-GWM.cmd or powershell.exe -NoProfile -File .\scripts\GWM.ps1.
5. Run tests with Invoke-Pester .\tests.

Do not run synchronization from this milestone. Review scan output and test results first.
