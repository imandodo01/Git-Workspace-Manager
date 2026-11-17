# M1 — Foundation Implementation

## Delivered foundation

- PowerShell module for configuration loading, repository discovery, Git invocation, repository inspection, and state classification.
- Local-only Scan command, explicit Sync command, and Windows CMD launcher.
- Pester unit and disposable-local-Git integration tests using syntax compatible with Pester 3.x.
- Separate local JSON snapshots: reports/latest-scan.json and reports/latest-sync.json.
- Fetch safety primitives: configured-remote fetch with pruning disabled, per-repository failure isolation, credential redaction, strict fast-forward eligibility evaluation, and repository-state snapshot comparison.
- Guarded fast-forward executor: pins the fetched upstream SHA, validates the configured-remote/upstream relationship, rechecks state before update, uses FF-only semantics, and verifies the final HEAD and working-tree state.
- Multi-repository sync wrapper that isolates repository-level failures.
- Sync exit codes: 0 when all repositories are updated or current, 1 when attention is required, and 2 when one or more repositories fail.

## Verification checkpoint

- The user confirmed 35 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive on Windows PowerShell 5.1 with Pester 3.4.0 before command-mode integration.
- Three additional command integration tests cover offline Scan, explicit Sync fast-forward and JSON reporting, and attention exit code with dirty-work preservation.
- The current expected suite size is 38 tests. The three latest command integration tests have not yet been run in the user's Windows environment.
- All integration tests use disposable local repositories and bare remotes; they do not operate on the user's configured workspace.
- The assistant performed static source and test review only; it did not execute Pester or PowerShell in the user's Windows environment.

## Current limitations

- HTML reporting, log retention, selective repository selection, and VS Code actions are not implemented.
- Scan reports divergence against cached upstream tracking refs and may be stale until a Sync fetch occurs.
- State comparison reduces race risk but cannot lock out concurrent editor or Git activity between the final check and update.
- Final report/log credential-redaction coverage remains future work.

## Local setup

1. Copy config/settings.example.json to config/settings.json.
2. Set workspace.root to the intended workspace directory.
3. Optionally copy config/repositories.example.json to config/repositories.json and define explicit repositories. If the registry exists, it is used instead of recursive discovery.
4. Run Start-GWM.cmd for a local-only Scan.
5. Run Start-GWM.cmd -Mode Sync only when ready to fetch and fast-forward eligible repositories.
6. Run tests with Invoke-Pester .\tests.

Sync is explicit and is never invoked by the default launcher command.
