# `fmr` Roadmap & Issue Index

This directory contains standalone, self-contained task specifications for implementing the remaining roadmap slices of **`fmr`** (*Fix My Repository*).

Each issue is formatted with clear **Context**, **CLI Signatures**, **Architectural Guardrails**, **Files to Touch**, and **Acceptance Criteria**, making them directly feedable to AI coding assistants (Claude Code, Antigravity, Cursor, etc.).

---

## Issue Index

## Core CLI Engine Roadmap

| Issue | Slice | Title | Spec Document | Status |
|---|---|---|---|---|
| **#1** | Slice 1 | Named Commands (`fmr check` and `fmr run`) | [`issue-01-slice-1-named-commands.md`](./issue-01-slice-1-named-commands.md) | Closed (PR #5) |
| **#2** | Slice 2 | Immutable RAG Snapshots (`fmr rag`) | [`issue-02-slice-2-rag-snapshots.md`](./issue-02-slice-2-rag-snapshots.md) | Closed (PR #6) |
| **#3** | Slice 3 | Catalog Completion & Exporter Migration | [`issue-03-slice-3-exporter-migration.md`](./issue-03-slice-3-exporter-migration.md) | Closed (PR #7) |
| **#4** | Slice 4 | Script Retirement, Retention GC (`--gc`), & JSON Output (`--json`) | [`issue-04-slice-4-retire-and-polish.md`](./issue-04-slice-4-retire-and-polish.md) | Closed (PR #7) |

---

## Native macOS Swift App Roadmap

| Issue | Slice | Title | Spec Document | Status |
|---|---|---|---|---|
| **#5** | GUI-1 | Swift Package Architecture, Process Bridge, & JSON Decoders | [`issue-05-gui-1-swift-bridge-and-models.md`](./issue-05-gui-1-swift-bridge-and-models.md) | Closed (PR #12) |
| **#6** | GUI-2 | macOS Menu Bar Companion Popover (`MenuBarView`) | [`issue-06-gui-2-menu-bar-companion.md`](./issue-06-gui-2-menu-bar-companion.md) | Closed (PR #12) |
| **#7** | GUI-3 | Full Workspace Dashboard Window (`WorkspaceDashboardView`) | [`issue-07-gui-3-workspace-dashboard.md`](./issue-07-gui-3-workspace-dashboard.md) | Closed (PR #12) |
| **#8** | GUI-4 | Diagnostics Sheet, App Packaging (`scripts/build_app.sh`), & Polish | [`issue-08-gui-4-diagnostics-and-packaging.md`](./issue-08-gui-4-diagnostics-and-packaging.md) | Closed (PR #12) |
| **#13** | GUI-5 | Worktree Operations, Editor Launchers, & Extended Models | [`issue-09-gui-5-worktree-management-and-extended-models.md`](./issue-09-gui-5-worktree-management-and-extended-models.md) | Closed (PR #14) |
| **#15** | GUI-6 | Repository Onboarding: `fmr add`, Native GUI Import Sheet & Drag-and-Drop | [`issue-10-repo-management-and-import.md`](./issue-10-repo-management-and-import.md) | Ready |


---

## Agent Prompting Workflow

To feed an issue to Claude Code or an agent:
```text
Read docs/issues/issue-01-slice-1-named-commands.md and implement the requested features.
Follow the exact CLI signature, exit codes, sequential execution policy, and acceptance criteria.
Run `zig fmt --check src/*.zig build.zig`, `zig build test`, and `zig build test-e2e` to verify your solution.
```
