# `fmr` Roadmap & Issue Index

This directory contains standalone, self-contained task specifications for implementing the remaining roadmap slices of **`fmr`** (*Fix My Repository*).

Each issue is formatted with clear **Context**, **CLI Signatures**, **Architectural Guardrails**, **Files to Touch**, and **Acceptance Criteria**, making them directly feedable to AI coding assistants (Claude Code, Antigravity, Cursor, etc.).

> Timeline: [`docs/MILESTONES.md`](../MILESTONES.md) — M1 v0.2 Ship (Thu night → Fri noon) + M2 v0.3 Personal (Fri noon → Fri 20:00). **Done by EOD Fri Aug 22, 2026.**

---

## Issue Index

## Core CLI Engine Roadmap — Shipped

| Issue | Slice | Title | Spec Document | Status |
|---|---|---|---|---|
| **#1** | Slice 1 | Named Commands (`fmr check` and `fmr run`) | [`issue-01-slice-1-named-commands.md`](./issue-01-slice-1-named-commands.md) | Closed (PR #5) |
| **#2** | Slice 2 | Immutable RAG Snapshots (`fmr rag`) | [`issue-02-slice-2-rag-snapshots.md`](./issue-02-slice-2-rag-snapshots.md) | Closed (PR #6) |
| **#3** | Slice 3 | Catalog Completion & Exporter Migration | [`issue-03-slice-3-exporter-migration.md`](./issue-03-slice-3-exporter-migration.md) | Closed (PR #7) |
| **#4** | Slice 4 | Script Retirement, Retention GC (`--gc`), & JSON Output (`--json`) | [`issue-04-slice-4-retire-and-polish.md`](./issue-04-slice-4-retire-and-polish.md) | Closed (PR #7) |

---

## Native macOS Swift App Roadmap — Shipped

| Issue | Slice | Title | Spec Document | Status |
|---|---|---|---|---|
| **#5** | GUI-1 | Swift Package Architecture, Process Bridge, & JSON Decoders | [`issue-05-gui-1-swift-bridge-and-models.md`](./issue-05-gui-1-swift-bridge-and-models.md) | Closed (PR #12) |
| **#6** | GUI-2 | macOS Menu Bar Companion Popover (`MenuBarView`) | [`issue-06-gui-2-menu-bar-companion.md`](./issue-06-gui-2-menu-bar-companion.md) | Closed (PR #12) |
| **#7** | GUI-3 | Full Workspace Dashboard Window (`WorkspaceDashboardView`) | [`issue-07-gui-3-workspace-dashboard.md`](./issue-07-gui-3-workspace-dashboard.md) | Closed (PR #12) |
| **#8** | GUI-4 | Diagnostics Sheet, App Packaging (`scripts/build_app.sh`), & Polish | [`issue-08-gui-4-diagnostics-and-packaging.md`](./issue-08-gui-4-diagnostics-and-packaging.md) | Closed (PR #12) |
| **#13** | GUI-5 | Worktree Operations, Editor Launchers, & Extended Models | [`issue-09-gui-5-worktree-management-and-extended-models.md`](./issue-09-gui-5-worktree-management-and-extended-models.md) | Closed (PR #14) |
| **#15** | GUI-6 | Repository Onboarding: `fmr add`, Native GUI Import Sheet & Drag-and-Drop | [`issue-10-repo-management-and-import.md`](./issue-10-repo-management-and-import.md) | Closed (PR #23) |

---

## Polish & Backlog — Shipped (were “backlog” in stale README)

| Issue | Area | Title | Spec Document | Status |
|---|---|---|---|---|
| **#16** | Core CLI | `fmr run --json` structured completion | [`issue-16-fmr-run-json.md`](./issue-16-fmr-run-json.md) | Closed (PR #17 `d329f73`) |
| **#17** | GUI | Wire `fmr config --json` into the app (kind filters, custom commands, paths) | [`issue-17-gui-config-catalog.md`](./issue-17-gui-config-catalog.md) | Closed (PR #18 `5eedadc`) |
| **#18** | CI | Build & test the Swift app in GitHub Actions | [`issue-18-ci-swift-app.md`](./issue-18-ci-swift-app.md) | Closed (PR #19 `a6c05c0`) |
| **#19** | Packaging | `build_app.sh` LSUIElement, codesigning, & versioning | [`issue-19-gui-packaging-polish.md`](./issue-19-gui-packaging-polish.md) | Closed (PR #20 `0de49de`) |
| **#20** | GUI | Harden worktree create/remove edge cases | [`issue-20-gui-worktree-hardening.md`](./issue-20-gui-worktree-hardening.md) | Closed (PR #21 `93b67f4`) |
| **#21** | Docs | Consolidate GUI docs & fix stale references | [`issue-21-docs-consolidation.md`](./issue-21-docs-consolidation.md) | Closed (PR #22 `dafeead`) |
| — | — | Recent repos, palette recents, clone-and-open | — | Closed (PR #24 `e0a88df`, #25 `f1a2780`, #26 `c03066c`) |

> The authoritative `--json` contract lives in [`docs/gui/json-contract.md`](../gui/json-contract.md) — issue specs point there rather than re-specifying field shapes.

---

## Milestones — Active (M1 + M2, EOD Fri Aug 22)

### M1 v0.2 Ship — “It Actually Works” (Thu night → Fri 12:00)

| Issue | Title | Spec Document | Size | Status |
|---|---|---|---|---|
| **#22** | Docs & Version Truth | [`issue-22-docs-and-version-truth.md`](./issue-22-docs-and-version-truth.md) | S | Closed (whirrrr) |
| **#23** | CLI DX — Completions + `fmr open` + `fmr list` | [`issue-23-cli-dx-completions-open-list.md`](./issue-23-cli-dx-completions-open-list.md) | M | Closed (whirrrr) |
| **#24** | Doctor & Sync UX — url-mismatch / not-a-repo | [`issue-24-doctor-and-sync-ux.md`](./issue-24-doctor-and-sync-ux.md) | S | Closed (whirrrr) |
| **#25** | GUI Menubar Polish — notifications, About, empty states | [`issue-25-gui-menubar-polish.md`](./issue-25-gui-menubar-polish.md) | S | Closed (whirrrr) |

### M2 v0.3 Personal — “Better Than T3 *For Me*” (Fri 12:00 → Fri 20:00)

| Issue | Title | Spec Document | Size | Status |
|---|---|---|---|---|
| **#26** | `fmr context` — AI-ready workspace dump | [`issue-26-fmr-context.md`](./issue-26-fmr-context.md) | S | Closed (whirrrr) |
| **#27** | `fmr grep` — cross-repo ripgrep | [`issue-27-fmr-grep.md`](./issue-27-fmr-grep.md) | S | Closed (whirrrr) |
| **#28** | `fmr mcp` — MCP server for Claude/Cursor | [`issue-28-fmr-mcp.md`](./issue-28-fmr-mcp.md) | M | Closed (whirrrr) |
| **#29** | `fmr daemon` — optional launchd auto-sync | [`issue-29-fmr-daemon.md`](./issue-29-fmr-daemon.md) | S | Closed (whirrrr) |

### M3 v0.4 GUI Polish & Help — “Make the next person smile” (Next sprint)

| Issue | Title | Spec Document | Size | Status |
|---|---|---|---|---|
| **#30** | Welcome & Help — First-run guidance and in-app help | [`issue-30-welcome-and-help.md`](./issue-30-welcome-and-help.md) | S | Open (#30) |
| **#31** | Empty States & Delight — Every empty list has a CTA | [`issue-31-empty-states-and-delight.md`](./issue-31-empty-states-and-delight.md) | S | Open (#31) |
| **#32** | Visual Motion & Feedback — Alive, not static | [`issue-32-visual-motion-and-feedback.md`](./issue-32-visual-motion-and-feedback.md) | S | Open (#32) |
| **#33** | Remediation & Contextual Help — Errors that fix themselves | [`issue-33-remediation-and-contextual-help.md`](./issue-33-remediation-and-contextual-help.md) | S | Open (#33) |
| **#34** | Discoverability & About — Make the app findable | [`issue-34-discoverability-and-about.md`](./issue-34-discoverability-and-about.md) | S | Open (#34) |

Milestone: [`M3 v0.4 GUI Polish & Help`](https://github.com/drawmeanelephant/fmr/milestone/1) — 5 open, 0 closed.

Detailed timeline, exit criteria, and non-goals: [`docs/MILESTONES.md`](../MILESTONES.md).

---

## Agent Prompting Workflow

To feed an issue to Claude Code or an agent:
```text
Read docs/issues/issue-22-docs-and-version-truth.md and docs/MILESTONES.md and implement the requested features.
Follow the exact CLI signature, exit codes, sequential execution policy, and acceptance criteria.
Run `zig fmt --check src/*.zig build.zig`, `zig build test`, and `zig build test-e2e` to verify your solution.
```
For M2 issues, also read `docs/gui/json-contract.md` for the JSON shape to extend.
