# `fmr` Roadmap & Issue Index

This directory contains standalone, self-contained task specifications for implementing the remaining roadmap slices of **`fmr`** (*Fix My Repository*).

Each issue is formatted with clear **Context**, **CLI Signatures**, **Architectural Guardrails**, **Files to Touch**, and **Acceptance Criteria**, making them directly feedable to AI coding assistants (Claude Code, Antigravity, Cursor, etc.).

---

## Issue Index

| Issue | Target Slice | Description | Status | Spec Document |
|---|---|---|---|---|
| **Slice 0** | Core Scaffold | Git safety matrix, `fmr status`, `fmr sync`, `fmr doctor`, atomic locks, E2E fixture suite | **Completed** | — |
| **Issue #1** | **Slice 1** | **Named Commands**: `fmr check` and `fmr run`, kind defaults, sequential runner | Ready for dev | [`issue-01-slice-1-named-commands.md`](./issue-01-slice-1-named-commands.md) |
| **Issue #2** | **Slice 2** | **RAG Snapshots**: `fmr rag`, SHA snapshot tree, atomic symlink `current`, staging, `files` and `command` modes | Ready for dev | [`issue-02-slice-2-rag-snapshots.md`](./issue-02-slice-2-rag-snapshots.md) |
| **Issue #3** | **Slice 3** | **Production Catalog & Exporters**: 13 repos in `workspace.json`, parameterizing exporter scripts | Ready for dev | [`issue-03-slice-3-exporter-migration.md`](./issue-03-slice-3-exporter-migration.md) |
| **Issue #4** | **Slice 4** | **Retirement & Tooling**: `fmr rag --gc <n>`, `fmr doctor --fix`, `--json` machine output | Ready for dev | [`issue-04-slice-4-retire-and-polish.md`](./issue-04-slice-4-retire-and-polish.md) |

---

## Agent Prompting Workflow

To feed an issue to Claude Code or an agent:
```text
Read docs/issues/issue-01-slice-1-named-commands.md and implement the requested features.
Follow the exact CLI signature, exit codes, sequential execution policy, and acceptance criteria.
Run `zig fmt --check src/*.zig build.zig`, `zig build test`, and `zig build test-e2e` to verify your solution.
```
