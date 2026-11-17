# M2 — Reporting & Observability Plan

## Goal

Make each Scan and Sync run easy to understand, inspect later, and troubleshoot without changing the safety behavior delivered in M1.

M2 is a reporting and operational visibility milestone. It is not a GUI milestone and does not change Git synchronization policy.

## Baseline facts

- M1 is merged to `main` at `d47379c7a8b51e8cdb6a76042eb3549864ecb620`.
- The user confirmed all 41 Pester tests pass on Windows PowerShell 5.1 with Pester 3.4.0.
- Scan and Sync currently write separate latest JSON snapshots under `reports/`.
- The current entry point constructs Scan and Sync report objects separately and writes JSON directly.
- The example settings already contain reporting and logging options, but the current configuration loader and entry point do not yet implement those options.
- HTML reporting, historical report retention, and operational log retention are not implemented.
- GitHub reports no CI workflow run or status check for the M1 merge commit. Local Pester confirmation is the available test evidence.

## In scope

### 1. Shared report contract

Define one stable, versioned run envelope consumed by JSON and HTML renderers.

Minimum envelope fields:
- `schemaVersion`: report schema version.
- `runId`: unique identifier for this execution.
- `mode`: `Scan` or `Sync`.
- `generatedAt`: ISO-8601 timestamp with local offset.
- `durationMs`: elapsed run duration.
- `repositoryCount`: number of repositories processed.
- `summary`: aggregate status counts, including zero-valued statuses.
- `results`: per-repository results using the existing M1 result data, normalized without losing fields.

Per-repository content should retain the useful M1 fields: repository name/path, branch/upstream where available, classification or sync status, ahead/behind, changed-file summary, before/after/target commits where relevant, reason, recommended action, and fetch/update outcome where relevant.

The contract must distinguish unavailable values from zero and must not silently change the meaning of existing status fields. The report schema and compatibility behavior must be documented before renderer implementation.

### 2. JSON and HTML output

- Keep the existing latest JSON filenames compatible: `latest-scan.json` and `latest-sync.json`.
- Add matching latest HTML outputs: `latest-scan.html` and `latest-sync.html`.
- Render HTML from the same normalized report object as JSON; do not build separate status logic for HTML.
- HTML must be self-contained and usable offline.
- No remote scripts, stylesheets, analytics, images, or active content.
- Encode all filesystem-, Git-, and configuration-derived text for HTML context.
- Use readable status summaries, repository-level detail, and recommended next actions.
- Keep report generation failure visible and return a non-success process result; never report a fully successful run if required output could not be written.

### 3. Report history and retention

- Preserve latest report paths for compatibility.
- Add timestamped historical JSON and HTML artifacts for each completed run.
- Avoid filename collisions for repeated runs in the same second (use runId or an equivalent stable suffix).
- Retention is bounded and configurable; keep the latest artifacts regardless of history pruning.
- Retention must only delete files inside the resolved GWM report-history directory that match GWM's own generated filename pattern.
- Do not delete unrelated files or traverse outside the configured output directory.
- Define whether the retention limit applies per mode and format; default should be predictable and documented.
- A history/retention failure must be reported without hiding the primary Scan/Sync result.

### 4. Operational logs

- Honor `logging.enabled` and the configured log output/retention settings.
- Write one log per run (or another documented bounded strategy) with timestamp and mode.
- Record useful operational events and errors without recording file contents, credentials, environment variables, private keys, or full secret-bearing remote URLs.
- Reuse and extend existing remote URL redaction where applicable; sanitize Git-derived error text before writing it.
- Logs are local artifacts, ignored by Git, and have documented retention.
- Logging failure must not change a safe Git decision or cause the tool to claim a repository update that did not occur. Surface the logging failure in the terminal/report.

### 5. Configuration

- Validate reporting/logging settings and provide safe defaults.
- Resolve relative output directories deterministically and document the base directory.
- Keep local paths and machine-specific values out of tracked files.
- Ensure the example settings match what the implementation actually supports.
- Do not add a mandatory runtime dependency.

## Out of scope

- Selective repository Sync or per-repository Sync controls (M3).
- VS Code open actions (M3).
- GUI, tray application, background service, scheduler, or automatic synchronization.
- Remote report hosting, telemetry, analytics, or cloud storage.
- Credential management or authentication changes.
- DevEnv Manager integration.
- Changes to the M1 rule that Sync is explicit and fast-forward-only.

## Workstreams and dependencies

| ID | Workstream | Deliverable | Dependency / boundary | Verification |
|---|---|---|---|---|
| M2-A | Report contract | Versioned report model and status/summary normalization | Blocking; agree before renderer/history consumers | Contract tests for Scan and Sync, stable JSON fields |
| M2-B | HTML renderer | Self-contained Scan and Sync HTML generated from report model | Depends on M2-A; owns renderer/template files | HTML output tests, hostile text encoding, offline/self-contained check |
| M2-C | History and retention | Timestamped JSON/HTML history plus bounded pruning | Depends on M2-A and output-directory semantics; avoid overlapping renderer files | Collision, retention, latest-file preservation, path-boundary tests |
| M2-D | Logging | Per-run local logs and bounded retention | Can proceed after config/path/redaction contract; separate logging module/files | Enabled/disabled behavior, retention, redaction, failure isolation |
| M2-E | Security, tests, docs | Cross-cutting tests and updated operational documentation | Test cases can be drafted after M2-A contract; final integration depends on A–D | Full Pester suite, static review, manual browser/PowerShell checks |

### Suggested execution order

1. **Contract checkpoint:** settle report envelope, filename patterns, output-directory base, retention semantics, and logging failure behavior. This is the only initial blocking design task.
2. **Parallel implementation:** after the checkpoint, M2-B (HTML renderer) and M2-D (logging) can proceed independently with separate file ownership. M2-C can proceed once the artifact naming and directory contract is fixed.
3. **Continuous verification:** add focused tests with each workstream; do not wait until all implementation is complete.
4. **Integration:** integrate workstreams into the CLI entry point, resolve any shared-file changes under one owner, and run combined regression tests.
5. **Acceptance review:** inspect generated reports/logs, validate retention boundaries, verify PowerShell 5.1, then update milestone status.

Parallelism is conditional on available contributors/agents and isolated ownership. If only one implementation lane is available, complete the same workstreams sequentially without creating artificial branches.

## Acceptance criteria

### Report contract and output
- [ ] Scan and Sync produce the same documented envelope shape with `schemaVersion`, `runId`, `mode`, `generatedAt`, `durationMs`, `repositoryCount`, `summary`, and `results`.
- [ ] Summary counts are deterministic and include zero counts for supported statuses.
- [ ] Existing latest JSON filenames remain available.
- [ ] Matching latest HTML reports are produced for both modes.
- [ ] HTML is self-contained and works without network access.
- [ ] HTML values containing `<`, `>`, `&`, quotes, Unicode, and line breaks render as text, not executable markup.
- [ ] Report write failures are surfaced and do not produce a false-success exit result.

### History and retention
- [ ] Each successful report generation creates uniquely named historical JSON and HTML files.
- [ ] Latest report files always point to the newest completed run.
- [ ] Retention removes only old GWM-generated artifacts inside the configured report directory.
- [ ] Retention limits are deterministic, documented, and tested for Scan and Sync.
- [ ] Invalid paths or retention settings fail safely without deleting unrelated files.

### Logging and privacy
- [ ] `logging.enabled=false` creates no log file.
- [ ] Enabled logging records run start/end, mode, counts, and actionable operational errors.
- [ ] Log rotation/retention is bounded and tested.
- [ ] Logs and reports do not contain credential-bearing URLs, tokens, passwords, environment variables, or repository file contents.
- [ ] A logging failure is visible but does not alter repository safety decisions or mask a Sync failure.

### Regression and compatibility
- [ ] All existing M1 safety tests continue to pass unchanged in meaning.
- [ ] Integration tests use disposable local Git repositories and temporary output directories only.
- [ ] No test reads, writes, or deletes files from the user's configured workspace.
- [ ] PowerShell 5.1 with Pester 3.4.0 remains supported.
- [ ] PowerShell 7 is tested where available; any compatibility gap is documented.
- [ ] Example configuration and documentation match implemented behavior.

## Risks and decisions to settle at the contract checkpoint

1. **Output directory semantics:** the current example contains relative paths such as `../reports`, while the current entry point writes to the repository's `reports/` directory. Decide and document the base for relative paths before implementing retention.
2. **Report compatibility:** current Scan and Sync objects differ. Normalize them without dropping M1 fields or changing existing consumers' expectations.
3. **Retention safety:** pruning is destructive to generated report artifacts. Restrict it to validated, GWM-owned filenames under a canonical output directory and test with unrelated sentinel files.
4. **Logging privacy:** Git error output is untrusted and may include URLs. Redact before serialization and test representative credential patterns.
5. **Partial output failure:** define whether JSON is the canonical artifact if HTML or history fails. A failed secondary output must be visible and must not falsely imply the full report set was generated.

## M2 exit gate

M2 is complete only when all acceptance criteria are met, the combined Pester suite passes on the supported PowerShell environment, manual HTML inspection is completed, the final diff is reviewed, and the milestone documentation accurately records what was verified.
