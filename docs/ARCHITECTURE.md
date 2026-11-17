# Architecture

## 1. Architectural direction

GWM is a small, modular PowerShell command-line utility. Its modules are separated by responsibility, but the initial implementation should avoid frameworks, plugin systems, databases, or unnecessary abstractions.

## 2. High-level components

```text
Launcher (CMD) / PowerShell entry point
                  |
            Configuration
                  |
       Repository Discovery/Registry
                  |
              Mode Router
              /       \
           Scan         Sync
            |            |
      Git Inspection  Fetch + Inspection
            |            |
       Scan Report   Safety + FF Executor
                          |
                  Verification + Report
```

### Entry point
- `Start-GWM.cmd`: double-click launcher.
- `scripts/GWM.ps1`: command-line entry point and explicit Scan / Sync mode routing. Scan is the default.

### Configuration
- Loads local settings and repository registry.
- Applies documented defaults.
- Validates schema and paths before repository operations.
- Does not store credentials.

### Repository discovery and registry
- Resolves one configured workspace root.
- Finds Git working trees according to discovery settings.
- Allows explicit include/exclude behavior.
- Normalizes paths and avoids duplicate processing.
- Does not recursively enumerate inside a discovered repository.

### Git inspection
- Invokes Git CLI with argument-safe process invocation.
- Captures exit codes and standard output/error separately.
- Queries branch, upstream, status, and divergence.
- Does not parse human-formatted output when Git offers stable porcelain or machine-readable output.

### Synchronization policy and executor
- Makes a decision from an explicit repository state model.
- Fetches the selected remote.
- Re-inspects state after fetch.
- Executes only a fast-forward-only update when all preconditions pass.
- Never runs destructive or history-rewriting commands.

### Result model
Each repository produces a structured result with stable fields such as:
- `name`, `path`, `branch`, `upstream`
- `workingTree`, `ahead`, `behind`
- `fetchStatus`, `syncStatus`, `reason`, `recommendedAction`
- `beforeCommit`, `afterCommit`, `durationMs`

Field names may be adjusted during implementation, but JSON schema changes must be documented.

### Reporting
- Terminal output: concise per-repository status and Sync aggregate summary.
- JSON: separate latest-scan.json and latest-sync.json structured run records.
- HTML remains planned and is not implemented.

### Logging
- One run log per execution or a documented rotation strategy.
- Logs contain operational diagnostics, not credentials or full secret-bearing URLs.
- Logging failures must not silently hide synchronization failures.

### VS Code integration
- Optional integration through the `code` CLI.
- Opening a repository is an explicit user action or a deliberate configured behavior.
- No automatic mass-opening.

## 3. Data flow and safety boundaries

Scan performs local inspection only and never fetches. Sync parses and validates configuration before any network operation, validates repository paths, and captures local state. Invalid repositories are failed; detached HEAD and branches without an upstream are classified as needing attention before fetch. Remaining repositories fetch the configured remote, recalculate divergence, and only update a clean attached branch with a valid upstream and behind-only relationship. The update uses fast-forward-only semantics and final state is verified and recorded.

## 4. Failure isolation

Errors are isolated per repository wherever safe. Invalid global configuration stops the run before repository operations. A repository-specific failure is recorded and processing continues for other repositories. A failure to write reports is surfaced clearly and must not be reported as a successful complete run.

## 5. Configuration and portability

- Tracked example configuration contains placeholders and portable examples only.
- User-specific configuration is local and ignored.
- Workspace root is configured, not hardcoded.
- Runtime outputs remain inside the GWM directory by default unless configured otherwise.
- No machine identity or account identifier is required.

## 6. Future extension points

Potential future additions include additional report formats, configurable remote policies, and DevEnv Manager integration. These are not implementation requirements for the initial release. Keep current module boundaries sufficient but do not build speculative extension infrastructure.
