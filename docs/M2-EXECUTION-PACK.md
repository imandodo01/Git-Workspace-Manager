# M2 Execution Pack — Workstream Handoff

## Purpose

This document prepares the M2 work so implementation can begin directly on the office laptop. It defines ownership boundaries, implementation tasks, dependencies, deferred verification, and the integration sequence.

**This is a preparation artifact, not evidence of implementation or test success.** No PowerShell, Pester, browser, or local Git fixture tests are claimed as run by creating this plan.

## Operating constraints for the office session

1. Start from the M2 planning branch / draft PR and inspect the local Git status before changing files.
2. Preserve unrelated local changes. Do not reset, clean, stash, or overwrite user work.
3. Keep the M1 safety contract unchanged: Scan remains offline/read-only; Sync remains explicit, fetches only the configured remote, and performs verified fast-forward-only updates.
4. During the office session, implementation and static inspection may proceed, but defer execution of PowerShell/Pester tests and browser/manual report checks until the user is home in the evening.
5. Do not mark any test as passed until its command has actually been run and its result recorded.
6. Prefer one integration branch and coherent commits. Do not create artificial parallel Git branches when there is only one implementation lane. Parallelism here means isolated work packages/file ownership, not concurrent writes to shared files.
7. Never use the user's configured workspace as a test fixture. All tests must use disposable repositories and temporary output directories.

## Contract checkpoint — settle before implementation

These choices resolve the open design questions in M2-PLAN:

### Report envelope

Use a shared top-level object for both modes:
- `SchemaVersion`: string, initially `1.0`.
- `RunId`: GUID in `N` format.
- `Mode`: `Scan` or `Sync`.
- `GeneratedAt`: ISO-8601 round-trip timestamp including local offset.
- `DurationMs`: non-negative integer.
- `WorkspaceRoot`: resolved workspace path.
- `RepositoryCount`: integer count of processed results.
- `Summary`: stable object with explicit zero-valued counts.
- `Results`: array of normalized repository result objects.
- `OutputWarnings`: array of report/log/history warnings; must not overwrite repository outcomes.

Preserve existing M1 result property names and meanings wherever possible. Do not replace missing/unknown divergence values with zero. Keep mode-specific fields nullable when they do not apply.

Summary keys should remain explicit and stable: `Updated`, `UpToDate`, `NeedsAttention`, and `Failed`. For Scan, map `UP_TO_DATE` to `UpToDate`, `FAILED` to `Failed`, and every other classification (including `NEEDS_ATTENTION`, `AHEAD`, `BEHIND`, `DIVERGED`, `UNKNOWN`, and `INVALID_REPOSITORY`) to `NeedsAttention`; Scan never increments `Updated`. For Sync, map `UPDATED`, `UP_TO_DATE`, and `FAILED` to their matching buckets and all other statuses to `NeedsAttention`. Preserve the original status in each result. Unknown divergence values remain `null`, never coerced to zero.

### Artifact paths

- Default output root: `<ProjectRoot>/reports`, preserving the current behavior.
- Relative configured output paths resolve relative to `ProjectRoot`, not the process current directory.
- Keep compatibility latest JSON paths: `reports/latest-scan.json` and `reports/latest-sync.json`.
- Add latest HTML paths: `reports/latest-scan.html` and `reports/latest-sync.html`.
- Historical artifacts live under `reports/history/`.
- History filename: `gwm-{mode}-{yyyyMMddTHHmmssfff}-{runId}.{json|html}`.
- Keep report history retention per mode and format, default 30 artifacts per mode/format. A configured value of 0 disables history pruning (unbounded); reject negative or non-integer values.
- Never prune latest files, log files, unknown names, or files outside the canonical history directory.

### Logging

- Default logging enabled unless current settings explicitly specify otherwise; honor `logging.enabled=false`.
- Default log root: `<ProjectRoot>/logs`; relative paths resolve against ProjectRoot.
- One UTF-8 text log per run: `gwm-{mode}-{timestamp}-{runId}.log`.
- Default retention: 30 GWM-generated log files; 0 disables pruning.
- Log operational event names, timestamps, repository display name, sanitized error summary, and run counts. Never log file contents, environment variables, command-line secrets, private keys, or raw credential-bearing URLs.
- A logging failure becomes an output warning; it must not alter a Git safety decision or mask a repository Sync failure.

### Partial output failures

- The repository operation result remains authoritative and is preserved.
- Any required latest JSON write failure makes the overall command non-successful (exit code 2 unless an existing higher-priority failure code is already defined).
- HTML/history/log failures are surfaced as output warnings and a non-zero process result; they must never result in a false success.
- Keep repository-level `FAILED` separate from artifact-output failure in the report model. Document the exit-code precedence explicitly before changing CLI behavior.

## Workstream packets

### M2-A — Shared report contract (blocking)

**Primary ownership:** `src/GWM.Core.psm1` report-model functions; contract section in docs; report-focused unit tests.

Tasks:
1. Inspect current Scan and Sync result shapes and enumerate all fields before refactoring.
2. Add one constructor/normalizer for the shared run envelope.
3. Add deterministic summary normalization with explicit zero counts.
4. Preserve nullable/unknown values and existing per-repository M1 fields.
5. Add schema version and run metadata without changing Git decision logic.
6. Keep existing JSON output property compatibility where feasible; document any unavoidable shape migration.
7. Define a single report-output result/warning model for downstream writers.

Deliverables:
- Shared report model used by both Scan and Sync.
- Documented schema and compatibility notes.
- Contract tests for Scan and Sync, empty workspace, all status buckets, and unknown values.

Exit check:
- Both modes serialize the same envelope shape and stable summary keys.
- Existing M1 safety tests' intent and result semantics remain unchanged.

### M2-B — HTML renderer

**Primary ownership:** new `src/GWM.Reporting.psm1` (or similarly named reporting module) and HTML-specific tests. Avoid changing CLI integration until M2 integration owner wires it.

Tasks:
1. Implement context-appropriate HTML encoding for all dynamic text.
2. Render self-contained HTML with embedded CSS only; no external resources, JavaScript, analytics, or network calls.
3. Render run metadata, summary cards/table, repository detail, statuses, reason, and recommended action.
4. Handle empty results, long paths, Unicode, line breaks, and missing values.
5. Write to a caller-supplied path; renderer itself must not decide Git status or mutate repository state.
6. Return structured success/failure rather than swallowing write errors.

Deliverables:
- HTML renderer module.
- Unit tests for escaping and output structure.
- Example output screenshot/manual review deferred to evening.

Exit check:
- Malicious strings such as `<script>`, quotes, ampersands, and tag-like branch names appear as inert text.
- Output is self-contained and can be opened offline.

### M2-C — History and retention

**Primary ownership:** new `src/GWM.History.psm1` (or equivalent focused helper) and history tests.

Tasks:
1. Implement deterministic output-root resolution shared with reporting/logging.
2. Generate collision-resistant history names using timestamp plus RunId.
3. Write historical JSON/HTML artifacts from the exact same report payload used for latest outputs.
4. Update latest artifacts atomically where practical (temporary sibling file then replace/move); document fallback behavior on Windows PowerShell 5.1.
5. Implement retention over GWM-owned filename patterns only.
6. Canonicalize the history directory and validate every candidate is a direct child before deletion.
7. Preserve latest outputs and unrelated sentinel files; never recurse into child directories.
8. Return pruning counts and warnings.

Deliverables:
- History/retention helper.
- Tests for collisions, order, retention boundaries, malformed names, unrelated files, path traversal, missing directories, and write/delete failures.

Exit check:
- Only eligible old generated artifacts are pruned; unrelated files survive.

M2-C implementation contract:
- `Resolve-GwmOutputDirectory -ProjectRoot <path> [-RelativePath reports]` returns a canonical path beneath ProjectRoot and rejects rooted, traversing, and existing reparse-point segments.
- `New-GwmHistoryFileName -Report <envelope> -Format json|html` validates Mode, a 32-hex RunId, and GeneratedAt, then returns the agreed GWM history filename.
- `Write-GwmHistoryArtifact -HistoryDirectory <path> -Report <envelope> -Format json|html -Content <serialized output>` writes one immutable artifact and refuses filename collisions. The caller supplies serialized JSON/HTML so M2-E can derive both outputs from the same report envelope.
- `Write-GwmLatestArtifact -Path <path> -Content <serialized output>` writes UTF-8 without BOM through a temporary sibling file, using File.Replace where supported and a same-directory Move-Item overwrite fallback where it is not.
- `Invoke-GwmHistoryRetention -HistoryDirectory <path> -Mode Scan|Sync -Format json|html -RetentionCount <integer>` prunes only matching direct-child regular files; 0 disables pruning. It returns Success, DeletedCount, PreservedCount, and Warnings.
- History retention is isolated by mode and format. Latest files, malformed names, unrelated files, directories, and reparse-point entries are preserved. Retention revalidates the canonical parent and filename immediately before deletion.
- Module functions are not wired into the CLI in M2-C; M2-E owns integration.

### M2-D — Operational logging

**Primary ownership:** new `src/GWM.Logging.psm1` and logging tests.

Tasks:
1. Parse and validate logging enabled/path/retention settings.
2. Implement per-run log writer with stable event format and UTF-8 encoding.
3. Sanitize Git errors and remote URLs before log serialization; reuse existing redaction primitives.
4. Do not serialize environment variables, raw process argument arrays, file contents, credentials, or private keys.
5. Implement bounded retention with the same canonical-path and owned-filename safeguards as history.
6. Ensure disabled logging creates no log file and does not create the log directory.
7. Ensure log failures return warnings and never alter repository update eligibility/outcome.

Deliverables:
- Logging helper.
- Tests for disabled/enabled modes, redaction, retention, path boundaries, and failure isolation.

Exit check:
- Logs contain enough diagnostic context to troubleshoot but no secret-bearing values.

### M2-D implementation contract

- `Get-GwmLoggingOptions -Settings <settings>` defaults logging to enabled, `logs`, and retention 30; validates boolean `enabled`, non-empty relative `path`, and integer `retentionCount` from 0 through 2147483647.
- `New-GwmLogFileName -Report <envelope>` validates Scan/Sync mode, 32-hex RunId, and GeneratedAt; returns `gwm-{mode}-{yyyyMMddTHHmmssfff}-{runId}.log`.
- `Write-GwmRunLog -ProjectRoot -Report -Events [-Enabled] [-RelativePath] [-RetentionCount]` writes one UTF-8 NDJSON file per run. Only Timestamp, RunId, Mode, Event, Repository display name, Error, and the four known summary counts are serialized. Arbitrary event properties, process arguments, environment variables, and file contents are ignored.
- URL user information and sensitive query values use the Core redaction primitive; common secret assignments and Bearer values are additionally redacted before serialization.
- Disabled logging returns success without resolving or creating the log directory.
- Log paths are resolved beneath ProjectRoot through the M2-C output-path helper; existing reparse-point segments are rejected. New files use CreateNew semantics and are never overwritten.
- `Invoke-GwmLogRetention -LogDirectory [-RetentionCount 30]` applies one retention pool across Scan and Sync log files, ordered by the timestamp embedded in each filename (not by the mode prefix); 0 disables pruning. Only matching direct-child GWM log files are eligible; unrelated names, directories, and reparse points are preserved.
- Logging and retention failures are returned as warnings/results; callers must preserve the repository operation result. M2-D does not modify CLI exit codes or Git decisions.

### M2-E — Security, integration, tests, documentation

**Primary ownership:** integration owner; shared entry point and config only after A–D modules have stable interfaces.

Tasks:
1. Extend config defaults/validation for report output, history retention, log output, and log retention.
2. Ensure example settings are exactly aligned with supported keys and defaults.
3. Wire A–D into `scripts/GWM.ps1` without duplicating report normalization or status logic.
4. Define exit-code precedence for repository failures and artifact failures.
5. Add integration tests that run Scan and Sync against disposable Git fixtures and temporary ProjectRoot paths.
6. Add tests proving output errors do not hide repository results or report false success.
7. Update README, architecture, configuration, security, test plan, and changelog.
8. Inspect final diff and verify tracked files contain no local config, logs, reports, secrets, or personal workspace paths.

#### M2-E1 — Configuration and validation checkpoint

Implemented on the integration branch:
- `Get-GwmConfiguration` now returns normalized `Reporting` and `Logging` settings alongside the existing workspace/Git settings.
- Defaults: JSON + HTML, `reports`, history enabled, retention 30; logging enabled, `logs`, retention 30.
- JSON is mandatory; only `json` and `html` are accepted, case-normalized, and duplicates are rejected.
- Report/log output paths must be relative, non-empty, and contain no `.` or `..` segments; they resolve against `ProjectRoot`.
- Boolean values must be JSON booleans. Retention must be a non-negative 32-bit integer.
- Example configuration and `docs/CONFIGURATION.md` now use the validated keys: `reporting.outputDirectory`, `reporting.keepHistory`, `reporting.retentionCount`, `logging.path`, and `logging.retentionCount`.
- Added `tests/GWM.Configuration.Tests.ps1` for defaults, normalized settings, path boundaries, formats, boolean types, and retention validation.
- Local verification completed after repairing a duplicated malformed tail in `src/GWM.Core.psm1` (commit `5e392bb`). The user pulled the branch with `git pull --ff-only`; the working tree was clean and HEAD matched `origin/feature/m2-reporting-observability`.
- PowerShell parser validation passed (`Parser OK`).
- Full suite command: `Invoke-Pester .\\tests`; result: **72 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive** in 64.3 seconds.
- The supplied verification output did not include the exact PowerShell and Pester versions, so those versions are not recorded for this run.

**M2-E1 status: Implemented / Verified.** Acceptance remains subject to the combined M2 integration and end-to-end checks.

The CLI does not consume these normalized settings yet. E2 owns that integration.

Deliverables:
- Integrated Scan/Sync output pipeline.
- Config validation and updated examples.
- Combined regression suite and documentation.

Exit check:
- M1 safety contract preserved; M2 acceptance criteria pass; all deferred verification is executed and recorded.

## File ownership map

| Area | Workstream | Ownership rule |
|---|---|---|
| `src/GWM.Core.psm1` | M2-A | Report model changes only; do not alter M1 sync decision logic |
| `src/GWM.Reporting.psm1` | M2-B | HTML rendering only; consumes report model |
| `src/GWM.History.psm1` | M2-C | History paths, writes, retention only |
| `src/GWM.Logging.psm1` | M2-D | Operational logging only |
| `scripts/GWM.ps1` | M2-E | One integration owner; no parallel edits |
| `config/settings.example.json` | M2-E | One integration owner; align with validated config |
| `tests/*Reporting*` | M2-B | Renderer unit tests |
| `tests/*History*` | M2-C | History and retention tests |
| `tests/*Logging*` | M2-D | Logging tests |
| `tests/*Integration*` | M2-E | End-to-end tests; one owner |
| `docs/*`, `README.md`, `CHANGELOG.md` | M2-E | Update after interfaces stabilize |

If only one developer/agent is available, follow A → B/C/D in sequence → E. Keep modules isolated to reduce integration conflicts.

## Office-session execution checklist (tests deferred)

### Before coding
- [ ] Confirm branch and clean/understood Git status.
- [ ] Read current AGENTS.md and applicable AES policies in the office environment.
- [ ] Inspect local repo instructions and compare local branch with origin.
- [ ] Confirm no local changes will be overwritten.
- [ ] Review current M2 plan and this execution pack.

### Implementation order
- [ ] M2-A: implement report envelope and contract comments/docs.
- [ ] M2-B: implement HTML renderer and add tests (do not execute tests during office session).
- [ ] M2-C: implement history naming, atomic latest writes, safe retention, and tests.
- [ ] M2-D: implement log writer, redaction, retention, and tests.
- [ ] M2-E: integrate configuration and CLI once module interfaces are stable.
- [ ] Update documentation and changelog to reflect implementation, not planned status.
- [ ] Inspect source and test diffs statically; search for risky file deletion, raw URL logging, dynamic HTML insertion, and accidental Sync behavior changes.
- [ ] Commit coherent work with Conventional Commit messages.

### Explicitly deferred until home/evening
- [ ] Run full Pester suite on Windows PowerShell 5.1 / Pester 3.4.0.
- [ ] Run PowerShell 7 checks if installed.
- [ ] Run disposable Git integration tests.
- [ ] Open Scan and Sync HTML reports in a browser, including offline check.
- [ ] Verify history/log retention with sentinel files and boundary cases.
- [ ] Verify no tests touched the real configured workspace.
- [ ] Record exact command, environment, passed/failed count, and any skipped checks.

## Evening verification command plan

From the repository root, after reviewing the diff and confirming the test fixtures are isolated:

```powershell
$PSVersionTable.PSVersion
Get-Module Pester -ListAvailable | Select-Object Name, Version
git status --short --branch
Invoke-Pester .\tests
$LASTEXITCODE
```

If Pester 3.4.0 does not set a useful process exit code in the installed invocation path, capture the Pester result object using syntax supported by that version and record the actual failed count. Do not infer success from console color alone.

Then perform the documented manual checks in `docs/TEST-PLAN.md`, including HTML offline behavior and retention sentinel preservation.

## Completion record template

Record:
- Branch and final commit SHA.
- Files changed.
- PowerShell version and Pester version.
- Exact test command.
- Passed / failed / skipped counts.
- Manual HTML, history, and logging checks.
- Confirmation that no real workspace repository was used as a fixture.
- Remaining defects and next action.

## Current implementation checkpoint

- M2-A report contract: implemented on `feature/m2-reporting-observability`; the user ran `Invoke-Pester .\tests` on Windows PowerShell 5.1 / Pester 3.4.0 and confirmed **45 passed, 0 failed, 0 skipped** (64.4 seconds).
- M2-B HTML renderer: implemented and locally verified by the user on Windows PowerShell 5.1 / Pester 3.4.0 (**51 passed, 0 failed, 0 skipped**); visual browser preview confirmed correct title, Unicode, and layout. Offline browser verification remains unrecorded. M2-B follow-up fix committed as `de4e9f7`.
- M2-C history/retention: implemented and verified by the user on Windows PowerShell 5.1 / Pester 3.4.0 as part of the full suite (**60 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive**, 62.72 seconds). The module is not wired into the CLI.
- M2-D operational logging: implemented and verified by the user on the local Windows PowerShell environment. The user ran `Invoke-Pester .\\tests`: **67 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive** (62.47 seconds). The cross-mode retention test confirms chronological ordering by filename timestamp. The module is not wired into the CLI.
- M2-E1 configuration/validation: implemented and locally verified. The user confirmed a clean fast-forward pull at commit `5e392bb`, PowerShell parser success, and full-suite result **72 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive** (64.3 seconds). Exact PowerShell/Pester versions were not present in the supplied output. M2-E2 CLI pipeline integration remains not started. The renderer is intentionally not wired into `scripts/GWM.ps1` yet.
- No M2 implementation has been merged to `main`.

## Status

M2 implementation is in progress. M2-B automated and visual checks are recorded; offline browser verification remains pending. M2-C is implemented and verified by the user on Windows PowerShell 5.1 / Pester 3.4.0. M2-D is implemented and its full Pester suite passed (67 passed, 0 failed). M2-E1 configuration/validation is implemented and verified by the user: parser passed and the full Pester suite reported 72 passed, 0 failed (64.3 seconds); exact runtime/module versions were not captured in the supplied output. M2-E2 CLI integration and end-to-end output verification remain.
