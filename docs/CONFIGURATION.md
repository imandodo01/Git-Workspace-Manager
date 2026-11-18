# Configuration

## 1. Files

The repository contains templates only:
- `config/settings.example.json`
- `config/repositories.example.json`

The user creates local copies:
- `config/settings.json`
- `config/repositories.json`

Local files are ignored by Git and must never be committed. GWM should explain how to create them when missing.

## 2. Settings

The settings loader validates workspace, Git, reporting, and logging settings. Unknown sections such as the reserved `integration` section are not currently acted on by the CLI.

### Workspace

- `workspace.root` is required and may be absolute or relative to `ProjectRoot`.
- The resolved workspace directory must already exist.
- `recursiveDiscovery` defaults to `true`.
- `excludedDirectories` defaults to `.git`, `node_modules`, `vendor`, and `.venv`.

### Git

- `git.defaultRemote` defaults to `origin`.
- `git.syncStrategy` defaults to `ff-only`; other strategies are rejected.
- Sync remains explicit and fast-forward-only.

### Reporting

- `reporting.formats` defaults to `["json", "html"]`. JSON is mandatory and is the canonical report format; HTML is optional.
- `reporting.outputDirectory` defaults to `reports`.
- `reporting.keepHistory` defaults to `true`.
- `reporting.retentionCount` defaults to `30`; zero disables pruning when history is enabled.
- `keepHistory=false` disables timestamped history. Latest report files remain separate from history retention.

### Logging

- `logging.enabled` defaults to `true`.
- `logging.path` defaults to `logs`.
- `logging.retentionCount` defaults to `30`; zero disables pruning.

## 3. Output path rules

Report and log paths must be non-empty relative directory paths. They resolve against `ProjectRoot`, never against the process current working directory. Rooted paths and paths containing `.` or `..` segments are rejected.

The output helpers additionally validate canonical paths and reject reparse-point/symlink boundaries where applicable. Defaults are:
- `<ProjectRoot>/reports`
- `<ProjectRoot>/logs`

Do not use parent-relative paths such as `../reports` or `../logs`.

## 4. Repository registry

The registry may explicitly include repositories by path and optionally override the default remote or enable/disable synchronization per repository. A repository registry entry must not contain credentials.

The first implementation may support either explicit registry mode or discovery mode. If both are supported, define deterministic precedence and duplicate handling.

## 5. Defaults and validation

- Invalid JSON is a configuration error; do not silently replace it.
- Missing local configuration may be initialized from examples only with clear user feedback, or the tool may provide a documented setup command.
- The configured workspace root must exist and be a directory before scanning.
- Reject paths outside the workspace root unless a later, explicit requirement changes the single-workspace boundary.
- Reject unsupported sync strategies rather than silently falling back.
- Retention values must be non-negative integers within the supported 32-bit range.
- Boolean settings must be JSON booleans, not strings or numeric values.
- Report formats are limited to `json` and `html`, without duplicates; JSON is required.
- Never store Git credentials, access tokens, private keys, or passwords in configuration.

## 6. Example configuration

See `config/settings.example.json`. Its values are illustrative and must not contain personal machine paths.
