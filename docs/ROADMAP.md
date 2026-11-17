# Product Roadmap

## Product direction

Git Workspace Manager (GWM) is a Windows-first, local utility for inspecting and safely synchronizing multiple Git repositories. It remains independent from DevEnv Manager. Integration or consolidation is only a future option to reassess after both tools mature; it is not part of this roadmap.

The delivery plan uses four product milestones. M1 is complete. M2 is the active planning target.

## Milestones

| Milestone | Outcome | Scope | Exit condition |
|---|---|---|---|
| M1 — Foundation | Safe multi-repository inspection and synchronization | Configuration loading, discovery, Scan, explicit guarded Sync, JSON snapshots, safety tests | M1 acceptance and local PowerShell/Pester verification complete |
| M2 — Reporting & Observability | Reports and run history are useful, inspectable, and safe | Stable report contract, HTML reports, JSON/HTML history, retention, structured local logs, redaction and output security | Report and logging acceptance criteria pass on supported PowerShell |
| M3 — Workflow & Usability | Common repository workflows require less manual effort | Selective repository operations, clearer configuration/setup validation, optional VS Code actions, CLI usability | Workflow acceptance criteria pass without weakening M1 safety boundaries |
| M4 — Release & Hardening | GWM is ready for a tagged v1.0 release | PowerShell compatibility, scale/performance checks, CI, security review, documentation, release packaging | Release gate in the specification and test plan passes |

## Delivery approach

- Keep one authoritative integration base: `main`.
- Use short-lived, focused feature branches and pull requests for coherent work.
- Define shared contracts before splitting work that consumes them.
- Parallelize only independent workstreams with isolated ownership and verification.
- Keep tests on disposable local Git repositories. Never use the configured real workspace as a destructive fixture.
- Run focused checks as soon as a workstream is testable, then run combined regression checks after integration.
- Preserve the explicit Sync opt-in and all M1 safety guarantees throughout later milestones.

## M2 workstreams

1. **Report contract and renderer (blocking):** define a versioned run/report envelope and render self-contained HTML from the same structured data used by JSON.
2. **History and retention (dependent):** preserve latest report paths while adding timestamped history and bounded retention.
3. **Operational logging (mostly independent after configuration contract):** add local structured run logs, retention, and safe diagnostics.
4. **Security and verification (cross-cutting):** validate HTML encoding, JSON serialization, path handling, redaction, retention, and failure behavior.
5. **Documentation and UX (dependent on contracts):** update examples, usage, and report interpretation guidance.

See [M2 Plan](M2-PLAN.md) for detailed scope, dependencies, acceptance criteria, and verification.

## Scope discipline

- M2 does not add selective Sync, a GUI, background scheduling, automatic conflict resolution, remote credential management, or DevEnv Manager integration.
- M3 does not weaken the no-reset/no-clean/no-stash/no-rebase/no-force-push policy.
- M4 release readiness requires actual test and CI evidence; documentation or static review alone is insufficient.
- Milestone scope may be adjusted when implementation evidence reveals a correctness or safety issue. Record material scope changes in the decision log.
