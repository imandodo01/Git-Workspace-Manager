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

### Current automated coverage

- `tests/GWM.Core.Tests.ps1`: 5 classification unit tests.
- `tests/GWM.Integration.Tests.ps1`: repository state inspection, JSON report, real working-tree state-change detection, and diverged-history fast-forward rejection.
- `tests/GWM.Safety.Tests.ps1`: URL redaction, sync eligibility, state snapshot comparison, fetch failure isolation, fetch preservation, and credential redaction.
- `tests/GWM.Sync.Tests.ps1`: guarded fast-forward success, up-to-date no-op, dirty preservation, ahead/diverged rejection, detached/no-upstream rejection, fetch failure, configured-remote/upstream mismatch, and per-repository failure isolation.

The user confirmed 25/25 tests passing on Windows PowerShell 5.1/Pester 3.4.0 before the executor and its nine new tests were added. The current expected suite size is 34; executor tests have not yet been run in the user's environment. The executor is not wired into the GWM Scan entry point.

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

## 5. Manual verification

- Run launcher by double-click.
- Run entry point from PowerShell 5.1 and PowerShell 7 where available.
- Open a report in a local browser.
- Use the VS Code integration with and without the `code` command available.
- Verify behavior with paths containing spaces and non-ASCII characters.

## 6. Release gate

Do not call an MVP release-ready until:
- All automated tests pass in the supported PowerShell environment.
- The safety assertions pass.
- Configuration examples match implementation.
- README setup and usage instructions are accurate.
- No personal paths, credentials, or machine-specific repository lists are tracked.
- Final diff and Git status have been reviewed.
