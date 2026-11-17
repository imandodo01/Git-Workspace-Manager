# M1 — Foundation Implementation

## Delivered foundation

- PowerShell module for local configuration loading, repository discovery, Git invocation, repository inspection, and state classification.
- PowerShell scan entry point and Windows CMD launcher.
- Pester unit tests and disposable-local-Git integration tests using syntax compatible with Pester 3.x; the latest local verification passed 15/15 tests on Windows PowerShell 5.1 with Pester 3.4.0.
- Scan writes a local JSON snapshot to reports/latest-scan.json.

## Verification checkpoint

- Local verification reported by the user: 15 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive.
- Coverage includes state classification, preservation of staged/unstaged/untracked changes, ahead/behind/diverged histories, detached HEAD, missing upstream, and JSON scan-report structure.
- Tests use disposable local Git repositories and bare remotes; they do not operate on the user's configured workspace.

## Current limitations

- M1 scan is read-only. It does not fetch or synchronize repositories.
- HTML reporting, log retention, selective repository selection, and VS Code actions are not implemented yet.
- Fetch failure handling, fast-forward execution/rejection, concurrent state changes, HTML output encoding, and credential redaction remain unimplemented or unverified.

## Local setup

1. Copy config/settings.example.json to config/settings.json.
2. Set workspace.root to the intended workspace directory.
3. Optionally copy config/repositories.example.json to config/repositories.json and define explicit repositories. If the registry exists, it is used instead of recursive discovery.
4. Run Start-GWM.cmd or powershell.exe -NoProfile -File .\scripts\GWM.ps1.
5. Run tests with Invoke-Pester .\tests.

Do not run synchronization from this milestone. Review scan output and test results first.
