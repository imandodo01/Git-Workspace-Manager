# M1 — Foundation Implementation

## Delivered foundation

- PowerShell module for local configuration loading, repository discovery, Git invocation, repository inspection, and state classification.
- PowerShell scan entry point and Windows CMD launcher.
- Pester unit and disposable-local-Git integration tests using syntax compatible with Pester 3.x.
- Scan writes a local JSON snapshot to reports/latest-scan.json.
- Fetch safety primitives: configured-remote fetch with pruning disabled, per-repository failure isolation, credential redaction, strict fast-forward eligibility evaluation, and repository-state snapshot comparison.

## Verification checkpoint

- Local verification previously reported by the user: 15 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive on Windows PowerShell 5.1 with Pester 3.4.0. This result predates the new safety test file.
- The new `tests/GWM.Safety.Tests.ps1` suite covers URL redaction, eligibility boundaries, state comparison, fetch failure isolation, fetch preservation, and credential redaction.
- The new safety suite has not yet been executed in the user's local environment. Do not treat its assertions as verified until the user runs `Invoke-Pester .\tests`.
- All integration tests use disposable local repositories and bare remotes; they do not operate on the user's configured workspace.

## Current limitations

- The regular GWM scan remains read-only. Fetch helpers exist but are not yet called by the scan entry point.
- No working-branch fast-forward executor or post-update verification exists yet.
- State comparison is implemented as a reusable guard but is not yet part of an update transaction.
- HTML reporting, log retention, selective repository selection, and VS Code actions are not implemented yet.
- HTML output encoding and final report/log credential-redaction coverage remain future work.

## Local setup

1. Copy config/settings.example.json to config/settings.json.
2. Set workspace.root to the intended workspace directory.
3. Optionally copy config/repositories.example.json to config/repositories.json and define explicit repositories. If the registry exists, it is used instead of recursive discovery.
4. Run Start-GWM.cmd or powershell.exe -NoProfile -File .\scripts\GWM.ps1.
5. Run tests with Invoke-Pester .\tests.

Do not run synchronization from this milestone. Review scan output and test results first.
