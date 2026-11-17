# Synchronization and Safety Policy

## 1. Governing principle

Preserve developer work first. GWM may leave repositories unsynchronized; it must never force synchronization by discarding or rewriting local work.

## 2. Command restrictions

Allowed in normal sync mode:
- Read-only Git inspection commands.
- `git fetch` against the configured remote.
- A fast-forward-only update after all safety checks pass.

Prohibited in normal operation:
- `git reset --hard`
- `git clean`
- `git checkout --` or `git restore` that discards work
- `git stash` / automatic stash application
- Automatic merge or rebase
- Commit, push, force-push, branch deletion, or history rewrite
- Any command that silently overwrites user files

## 3. Eligibility for automatic fast-forward

A repository is eligible only when all conditions are true:
1. The directory is a valid Git working tree.
2. The working tree and index are clean, including no untracked files under the initial conservative policy.
3. HEAD is attached to a local branch.
4. The branch has an unambiguous configured upstream.
5. The configured remote is available and fetch succeeds.
6. The local branch is behind its upstream and not ahead.
7. The relationship is strictly fast-forwardable.
8. The repository state has not changed unexpectedly between inspection and update.

If any condition is false or uncertain, do not update the working branch.

## 4. State decision table

| State after fetch | Action | Report |
|---|---|---|
| Clean; equal to upstream | No update | UP_TO_DATE |
| Clean; behind only | Fast-forward-only update | UPDATED |
| Clean; ahead only | No update | NEEDS_ATTENTION — local commits not pushed |
| Clean; ahead and behind | No update | NEEDS_ATTENTION — diverged |
| Staged or unstaged changes | No update | NEEDS_ATTENTION — local modifications |
| Untracked files | No update (initial conservative policy) | NEEDS_ATTENTION — untracked files |
| Detached HEAD | No update | NEEDS_ATTENTION |
| No upstream configured | No update | NEEDS_ATTENTION |
| Fetch/auth/network failure | No update | FAILED |
| Not a valid working tree | No Git operation | FAILED or SKIPPED |
| Fast-forward-only update rejected | No retry with merge/rebase | FAILED |

## 5. Fetch semantics

- Fetch is allowed even when the working tree is dirty because it updates remote-tracking references, not checked-out files.
- Capture local working-tree state before and after fetch.
- Fetch only the configured remote; do not implicitly fetch every remote.
- Pruning remote-tracking references is disabled initially to avoid surprising local reference deletion.
- Do not expose credentials embedded in remote URLs in reports or logs.

## 6. Race and consistency handling

A developer or background process may change repository state during a run. Re-check status and HEAD immediately before updating. If the branch, index, or working tree differs from the inspected state, abort that repository's update and report that it changed during synchronization. Use fast-forward-only behavior as a final guard.

## 7. Manual resolution guidance

For dirty or diverged repositories, report:
- Repository path and branch.
- Upstream name.
- Ahead and behind counts when known.
- Staged, modified, and untracked file summaries.
- Conflicting paths when Git can identify them without initiating a merge.
- A concise recommended next step.

The developer resolves the situation in VS Code or the terminal, commits or otherwise safely handles local work, and runs GWM again. GWM does not attempt to continue an in-progress merge or rebase automatically.

## 8. Status precedence

A failed fetch takes precedence for synchronization outcome, while local working-tree findings remain visible as diagnostics. Dirty, detached, no-upstream, and diverged states are attention states rather than generic failures. A successful fast-forward must be followed by verification before reporting UPDATED.
