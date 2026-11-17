# Test Plan

## 1. Strategy

Use Pester for PowerShell unit and integration tests if available and appropriate. Do not make a third-party module a runtime dependency. Integration tests must create disposable local Git repositories and bare remotes in temporary directories, with cleanup limited to those test-owned directories.

## 2. Unit test areas

- Configuration parsing, defaults, validation, and invalid JSON.
- Workspace path normalization and boundary enforcement.
- Repository discovery, exclusions, nested repositories, and duplicates.
- Git process invocation, exit-code handling, and output capture.
- Porcelain status parsing, including staged, unstaged, renamed, deleted, and untracked files.
- Branch, upstream, ahead/behind, and detached-HEAD inspection.
- Secret-bearing remote URL redaction.
- HTML encoding and JSON serialization.
- Status classification, sync eligibility, and recommended actions.
- Repository-state snapshot comparison for race detection.

## 3. Integration scenarios

Create a bare remote and local clones in a disposable test root. Simulate:
1. Clean and already up to date.
2. Remote receives one commit; local is behind after fetch.
3. Local-only commit (ahead).
4. Remote-only commit (behind).
5. Local and remote commits diverge.
6. Staged modification.
7. Unstaged modification.
8. Untracked file.
9. Detached HEAD.
10. Missing upstream.
11. Fetch failure or unavailable remote.
12. Multiple repositories where one fetch fails and another succeeds.
13. Fetch preserves staged, unstaged, and untracked working-tree contents.
14. Remote URLs containing credentials are redacted from fetch results.
15. Fast-forward-only update rejection.
16. Repository state changes between inspection and update.
17. Paths and branch names containing HTML-sensitive characters.

### Current automated coverage — M1

The user confirmed **41 passed, 0 failed** on Windows PowerShell 5.1 with Pester 3.4.0 after the two no-upstream regression tests were added.

- `tests/GWM.Core.Tests.ps1`: classification unit tests.
- `tests/GWM.Integration.Tests.ps1`: repository state inspection, JSON report, race and diverged-history checks, offline Scan, explicit Sync success, dirty-work preservation, and Sync failure exit handling.
- `tests/GWM.Safety.Tests.ps1`: URL redaction, sync eligibility, state snapshot comparison, fetch failure isolation, fetch preservation, and credential redaction.
- `tests/GWM.Sync.Tests.ps1`: guarded fast-forward success, up-to-date no-op, dirty preservation, ahead/diverged rejection, detached/no-upstream preflight (including when the configured remote is absent), fetch failure, configured-remote/upstream mismatch, and per-repository failure isolation.

The assistant performed static source and test review; it did not execute PowerShell or Pester in the user's Windows environment. GitHub reported no CI workflow run or commit status check for the M1 merge commit.

## 4. Safety assertions

For dirty and diverged repositories:
- Working-tree file contents remain byte-for-byte unchanged.
- Local commits remain reachable.
- No merge or rebase is initiated.
- No stash is created.
- No branch is reset or force-updated.

For fetch:
- Only the configured remote is fetched.
- Pruning is disabled.
- A fetch failure for one repository does not stop independent repositories.
- Working-tree and index contents remain unchanged.
- Credential-bearing URL data is not exposed in returned diagnostics.

For the guarded fast-forward executor:
- Only a clean, attached branch with an unambiguous upstream and a strictly behind-only relationship is eligible.
- Repository state is rechecked immediately before update.
- The update uses fast-forward-only semantics.
- Resulting HEAD equals the fetched upstream commit.
- No local files are unexpectedly modified.
- The result is classified UPDATED only after verification.

## 5. Command behavior

- Start-GWM.cmd defaults to Scan and must not fetch or mutate repositories.
- Start-GWM.cmd -Mode Sync is the only initial command path that fetches and fast-forwards.
- Sync writes `reports/latest-sync.json`; Scan writes `reports/latest-scan.json`.
- Sync exit codes: 0 all repositories updated/current, 1 at least one needs attention, 2 at least one repository fails.

## 6. M2 planned verification — Reporting & Observability

These are planned checks, not current implementation coverage:

- Report contract: both modes serialize the same versioned envelope and deterministic summary counts.
- HTML: Scan and Sync produce self-contained offline reports from the shared report model.
- HTML safety: hostile repository names, paths, branch names, reasons, and Git output are encoded as text.
- History: unique filenames under rapid repeated runs; latest outputs remain correct.
- Retention: only old GWM-generated files under the validated report directory are removed; unrelated sentinel files and files outside the directory remain untouched.
- Configuration: invalid output directories, negative/invalid retention limits, and malformed settings fail safely with actionable messages.
- Logging: enabled/disabled behavior, per-run records, bounded retention, and safe error redaction.
- Failure isolation: report/log write failures are visible and do not hide repository Sync outcomes or produce false success.
- Compatibility: run the complete suite under Windows PowerShell 5.1 / Pester 3.4.0; test PowerShell 7 where available.

## 7. Manual verification

- Run launcher by double-click.
- Run entry point from PowerShell 5.1 and PowerShell 7 where available.
- Open generated HTML reports in a local browser with network disconnected.
- Confirm long repository lists and long error/recommended-action text remain readable.
- Verify behavior with paths containing spaces and non-ASCII characters.
- Verify logging disabled and enabled using temporary output directories.

## 8. Release gate

Do not call an MVP release-ready until:
- All automated tests pass in the supported PowerShell environment.
- The safety assertions pass.
- Configuration examples match implementation.
- README setup and usage instructions are accurate.
- No personal paths, credentials, or machine-specific repository lists are tracked.
- Final diff and Git status have been reviewed.
