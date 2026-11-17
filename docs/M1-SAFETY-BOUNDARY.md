# M1 Safety Boundary

## Scope

This stage adds reusable safety primitives and tests before implementing working-branch synchronization. It does not change the current scan entry point and does not update checked-out branches.

## Implemented primitives

- `ConvertTo-GwmRedactedRemoteUrl`: redacts URL user-info and sensitive query values.
- `Invoke-GwmFetch`: fetches only the configured remote with `--no-prune --no-tags`; returns a structured result and redacts credential-bearing URL data.
- `Invoke-GwmFetchForRepositories`: isolates fetch results per repository so one failure does not stop the remaining repositories.
- `Get-GwmSyncEligibility`: allows only valid, attached, clean repositories with a configured upstream, known divergence, zero local-ahead commits, and at least one upstream-only commit.
- `Test-GwmRepositoryStateUnchanged`: compares branch, HEAD, upstream, and status lines across two inspections.

## Explicit non-goals

- No automatic fetch from the current Scan command.
- No pull, merge, rebase, reset, stash, checkout, or branch update.
- No claim that state comparison eliminates every possible race; it is a pre-update guard. Fast-forward-only Git behavior remains a required final guard.
- No production-workspace test fixtures.

## Verification

Run on Windows PowerShell 5.1 with Pester 3.4.0:

```powershell
Invoke-Pester .\tests
```

The new safety suite must pass before the next stage. The existing user's 15/15 result predates these tests and must not be reused as evidence for this stage.
