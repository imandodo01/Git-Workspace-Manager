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
- Status classification and recommended actions.

## 3. Integration scenarios

Create a bare remote and local clones in a disposable test root. Simulate:
1. Clean and already up to date.
2. Remote receives one commit; local is fast-forwarded.
3. Local-only commit (ahead).
4. Remote-only commit (behind).
5. Local and remote commits diverge.
6. Staged modification.
7. Unstaged modification.
8. Untracked file.
9. Detached HEAD.
10. Missing upstream.
11. Fetch failure or unavailable remote.
12. Fast-forward-only update rejection.
13. Multiple repositories where one fails but others continue.
14. Repository state changes during a run.
15. Paths and branch names containing HTML-sensitive characters.
16. Remote URLs containing credentials are redacted from all outputs.

### Current automated integration coverage

`tests/GWM.Integration.Tests.ps1` currently covers clean/up-to-date, staged changes, untracked files, local-ahead, remote-behind after fetch, diverged histories, detached HEAD, and missing upstream. Every test creates its own temporary seed repository, bare remote, and clone, then removes only that test-owned directory. These tests inspect state; they do not execute GWM synchronization.

The remaining scenarios above—especially fetch failures, fast-forward execution/rejection, concurrent state changes, report encoding, and credential redaction—remain future test work and are not claimed as covered by the current integration suite.

## 4. Safety assertions

For dirty and diverged repositories:
- Working-tree file contents remain byte-for-byte unchanged.
- Local commits remain reachable.
- No merge or rebase is initiated.
- No stash is created.
- No branch is reset or force-updated.

For successful fast-forward:
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
- All automated tests pass.
- The safety assertions pass.
- Configuration examples match implementation.
- README setup and usage instructions are accurate.
- No personal paths, credentials, or machine-specific repository lists are tracked.
- Final diff and Git status have been reviewed.
