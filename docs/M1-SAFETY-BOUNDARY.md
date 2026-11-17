# M1 Safety Boundary

## Scope

This stage adds reusable safety primitives and a guarded fast-forward executor before connecting synchronization to the user-facing command. The existing Scan entry point remains read-only and does not fetch or update checked-out branches.

## Implemented primitives

- ConvertTo-GwmRedactedRemoteUrl: redacts URL user-info and sensitive query values.
- Invoke-GwmFetch: fetches only the configured remote with --no-prune --no-tags; returns a structured result and redacts credential-bearing URL data.
- Invoke-GwmFetchForRepositories: isolates fetch results per repository so one failure does not stop the remaining repositories.
- Get-GwmSyncEligibility: allows only valid, attached, clean repositories with a configured upstream, known divergence, zero local-ahead commits, and at least one upstream-only commit.
- Test-GwmRepositoryStateUnchanged: compares branch, HEAD, upstream, and status lines across two inspections.
- Invoke-GwmFastForward: fetches the configured remote, rejects changed or ineligible state, verifies that the upstream belongs to the configured remote, pins the fetched target SHA, rechecks repository state and target identity, uses git merge --ff-only against that exact SHA, then verifies HEAD, divergence, and working-tree cleanliness.
- Invoke-GwmSyncForRepositories: processes repositories independently and records a per-repository failure without stopping subsequent repositories.
- Integration checks verify that a real working-tree change is detected between inspections and that Git rejects a diverged update under --ff-only without changing HEAD or losing either side's files.

## Execution sequence

1. Capture the repository state.
2. Fetch only the configured remote without pruning or tags.
3. Confirm branch, HEAD, upstream, and working-tree status did not change during fetch.
4. Evaluate strict eligibility; dirty, ahead, diverged, detached, and no-upstream states are not updated.
5. Confirm the branch upstream belongs to the configured remote.
6. Resolve and pin the upstream commit SHA; confirm it is a descendant of current HEAD.
7. Re-inspect state immediately before update and confirm the upstream still resolves to the pinned SHA.
8. Run git merge --ff-only --no-edit <target-sha>.
9. Verify HEAD equals the pinned SHA, the branch remains attached, divergence is zero, and the working tree is clean.

A failed or ambiguous step stops that repository. There is no fallback to merge commits, rebase, reset, stash, or force update.

## Explicit non-goals

- The Scan entry point is not wired to this executor.
- No git pull, rebase, reset, stash, checkout, push, or branch rewrite.
- State comparison reduces race risk but cannot prevent another process or editor from changing files between the final check and Git's update. The FF-only guard and post-update verification remain mandatory.
- No production-workspace test fixtures.

## Verification

Run on Windows PowerShell 5.1 with Pester 3.4.0:

~~~powershell
Invoke-Pester .\tests
~~~

The user confirmed 25/25 tests passing before the executor and its nine integration tests were added. The expected suite size is now 34 tests. The executor tests have not yet been run in the user's Windows environment.
