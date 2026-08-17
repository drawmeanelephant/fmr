# `fmr` (Fix My Repository)

> **`fmr`** — *Fix My Repository* / *Fuckin' Manage Repos* / *Fuck Me Running*
> A fast, safe, deterministic workspace manager for multi-repo development and agentic workflows in Zig.

`fmr` manages git workspaces with strict safety guarantees: safe fast-forward synchronization, read-only status overviews, diagnostics, and seamless integration with Conductor and AI coding agents without risking uncommitted work or corrupted branch states.

---

## 1. Overview & Core Principles

`fmr` replaces unstructured workspace management scripts with a zero-dependency Zig CLI built around three core jobs:

1. **Repo Catalog**: A single configuration file (`workspace.json`) declaring every repo, its remote URL, default branch, kind, and build/check/rag behaviors.
2. **Safe Primary Sync**: Fetch and fast-forward ONLY on designated primary checkouts. Agent worktrees, active branches, and unstaged changes are never clobbered.
3. **Deterministic Diagnostics**: Offline self-checks (`fmr doctor`) to ensure root directories, branch states, permissions, and disk capacities are intact.

### Non-Negotiable Safety Rules
- **No destructive git commands**: Never runs `git reset --hard`, `git checkout --force`, or `git push --force`.
- **No deleting checkouts or refs**: Never calls `rm -rf` on working trees and never deletes branches or remote tracking references.
- **Fail-safe refusal**: If a primary checkout is dirty, ahead of origin, diverged, detached, on the wrong branch, or is itself a worktree, `fmr` **refuses to sync** with exit code `3` and prints exact manual remediation commands.
- **mkdir-atomic concurrency locks**: Prevents concurrent `fmr sync` runs from clashing on the same repository across multiple terminal sessions or background agents (`~/.fmr/locks/`).

---

## 2. Directory Layout & Architecture

`fmr` enforces strict separation across three root directories:

```
~ (HOME)
├── dev/drawmeanelephant/           # paths.repos (Primary checkouts ONLY)
│   ├── boris/                     # git checkout (on default_branch)
│   ├── oliver/
│   └── ...
├── Code/worktrees/                # paths.worktrees (Conductor / agent sessions)
│   ├── boris/
│   │   ├── session-1/             # git worktree add ... (feature branches)
│   │   └── session-2/
│   └── ...
├── Code/source-rag/               # paths.sourceRag (Immutable RAG snapshots)
│   ├── boris/
│   │   ├── <sha40>/               # Snapshot tree for specific commit SHA
│   │   │   └── manifest.json
│   │   └── current -> <sha40>     # Atomic symlink to latest snapshot
│   └── ...
└── .fmr/
    └── locks/                     # Atomic lock directories (~/.fmr/locks/<repo>.sync.lock)
```

### The Conductor Contract

`fmr` and Conductor (or AI coding agents) share repositories through git's native worktree capabilities:

- **Primary checkout**: Lives in `paths.repos` (e.g. `~/dev/drawmeanelephant/<name>`). `fmr`'s `sync` interacts **exclusively** with this directory.
- **Session worktrees**: Conductor creates session worktrees rooted in `paths.worktrees`:
  ```bash
  git -C ~/dev/drawmeanelephant/<name> worktree add ~/Code/worktrees/<name>/<session> -b <branch>
  ```
- **Unidirectional state flow**: Primaries hold the default branch. Worktrees hold session/feature branches. Agent changes in worktrees are pushed upstream via git branches, never merged into the primary locally by automated tools.
- **Worktree safety guards**: If a primary's `.git` is a file (meaning it is a worktree, not a primary repo), `fmr` immediately refuses to sync it (exit 3).

---

## 3. Git Safety Decision Matrix

Before any mutation occurs, `fmr` assesses the state of the checkout against this decision matrix:

| State | Repo Condition | Sync Action | Status Indicator | Doctor Check |
|---|---|---|---|---|
| **1** | Directory missing | `git clone -b <branch>` (exit 0) | `missing` | Informational |
| **2** | Directory exists, not a git repo | Refuse (exit 3): manual fix required | `not-a-repo` | Problem (exit 1) |
| **3** | `.git` is a file (is a worktree) | Refuse (exit 3): sync primaries only | `worktree` | Problem (exit 1) |
| **4** | Clean, up to date | No-op (exit 0) | `clean` / `snap ok` | OK |
| **5** | Clean, behind origin | `git merge --ff-only` (exit 0) | `behind N` | OK |
| **6** | Clean, ahead of origin | Refuse (exit 3): print push/worktree hint | `ahead N` | Warn |
| **7** | Clean, diverged | Refuse (exit 3): print rebase hint | `diverged ±N` | Warn |
| **8** | Dirty (tracked modifications) | Refuse (exit 3): list modified files | `dirty N` | Warn |
| **9** | Untracked files only | Allow `ff-only` (exit 0) | `N untracked` | OK |
| **10** | Detached HEAD | Refuse (exit 3): switch to branch hint | `detached` | Warn |
| **11** | Unborn / empty repository | Refuse (exit 3): commit required | `unborn` | Warn |
| **12** | Wrong branch (`HEAD` ≠ `default_branch`) | Refuse (exit 3): switch branch hint | `wrong-branch` | Warn |
| **13** | Remote URL mismatch | Refuse (exit 3): print config vs origin | `url-mismatch` | Problem (exit 1) |
| **14** | Network / Fetch failure | Fail (exit 4): command + exit code | `unreachable` | (offline only) |
| **15** | Active Lock Held | Refuse (exit 3): lock owner PID printed | — | Stale lock check |

---

## 4. Configuration Schema (`workspace.json`)

Default location: `~/config/fmr/workspace.json` (fallback: `~/config/yard/workspace.json`, override with `--config <path>`).

Comments are supported using keys starting with an underscore (`_note`, `_version`, etc.).

### Example Configuration

```json
{
  "_version": 1,
  "_note": "Production workspace catalog",
  "paths": {
    "repos": "~/dev/drawmeanelephant",
    "worktrees": "~/Code/worktrees",
    "sourceRag": "~/Code/source-rag"
  },
  "parallelism": {
    "sync": 4,
    "status": 4,
    "check": 1,
    "rag": 1
  },
  "defaults": {
    "zig": { "check": { "argv": ["zig", "build", "test"] } },
    "go": { "check": { "argv": ["go", "test", "./..."] } },
    "node": { "check": { "argv": ["npm", "test"] } }
  },
  "repos": [
    {
      "name": "boris",
      "url": "git@github.com:drawmeanelephant/boris.git",
      "kind": "zig",
      "default_branch": "afterparty",
      "worktree_safe": true,
      "rag": {
        "command": {
          "argv": ["python3", "{workspace}/scripts/export_boris_rag.py", "{rag_out}"],
          "output": "{rag_out}"
        }
      },
      "commands": {
        "serve": { "argv": ["zig", "build", "run", "--", "serve"] }
      }
    },
    {
      "name": "oliver",
      "url": "git@github.com:drawmeanelephant/oliver.git",
      "kind": "zig",
      "worktree_safe": false,
      "rag": {
        "files": {
          "globs": ["*.md", "*.toml", "*.json"],
          "max_depth": 2
        }
      }
    },
    {
      "name": "local-notes",
      "kind": "other",
      "sync": { "enabled": false }
    }
  ]
}
```

### Placeholders in `argv`

Tokens enclosed in `{...}` are expanded at runtime:
- `{workspace}`: Directory containing `workspace.json`.
- `{repo}`: Absolute path to the repository primary checkout.
- `{name}`: Name of the repository.
- `{branch}`: Configured or detected default branch.
- `{rag_out}`: Staging output directory for RAG exports.

---

## 5. CLI Usage & Commands

```bash
fmr <command> [repo...] [flags]
```

### Commands

| Command | Description |
|---|---|
| `fmr status [repo...] [--json]` | Read-only parallel inspection of git and snapshot state across all or specified repos. |
| `fmr sync [repo...] [--jobs <n>] [--json]` | Safely fetches and fast-forwards primary checkouts (or clones if missing). |
| `fmr doctor [--fix] [--json]` | Runs offline health checks. Pass `--fix` to prune stale locks, dead-pid locks, and abandoned staging dirs. |
| `fmr config [--json]` | Dumps the parsed catalog as JSON (paths, parallelism, per-repo kind/path/url/check/rag/commands) for GUI clients. |
| `fmr check [repo...] [--json]` | Executes repo test/check command or inherited `kind` default check. |
| `fmr run <repo> <command> [args...]` | Runs a configured custom command for a repository with environment variable injection. |
| `fmr rag [repo...] [--force] [--gc <n>] [--json]` | Generates immutable RAG snapshots and updates `current` symlinks. Supports retention GC (`--gc <n>`). |
| `fmr --help`, `-h` | Prints usage and command options. |

### Flags

| Flag | Description |
|---|---|
| `--config <path>` | Path to custom `workspace.json`. Defaults to `~/config/fmr/workspace.json`. |
| `--jobs <n>` | Number of concurrent worker threads for sync operations. |
| `--force`, `-f` | Forces RAG snapshot generation even on dirty repositories or re-exports existing HEAD. |
| `--fix` | Remediates stale lock files and orphaned staging directories during `fmr doctor`. |
| `--gc <n>` | Retention garbage collection for `fmr rag`: retains newest `n` snapshots plus the active `current` target. |
| `--json` | Emits clean, machine-readable structured JSON to stdout. |
| `--all`, `-a` | Process all configured repositories (default when no repos specified). |

### Exit Code Contract

Multi-repo operations aggregate exit codes (highest severity wins):

| Code | Status | Meaning |
|---|---|---|
| `0` | **OK** | Operation completed successfully or already up to date. |
| `1` | **Unexpected Error** | File I/O failure, internal error, or lock acquisition error. |
| `2` | **Usage / CLI Error** | Unknown command, unknown repo name, or invalid arguments. |
| `3` | **Safety Refusal** | Refused due to dirty tree, ahead/diverged branch, detached HEAD, worktree conflict, or lock contention. |
| `4` | **Subprocess Failed** | A spawned command (e.g. `git clone`, `git fetch`, test suite, exporter) returned a non-zero exit code. |
| `5` | **Config Invalid** | JSON syntax error, missing required field, unknown key, or bad repo name. |

---

## 6. Building & Testing

### Requirements
- Zig compiler (`0.16.0` or compatible)
- Git (`2.20+`)

### Build
```bash
zig build
```
Compiled binary will be installed to `zig-out/bin/fmr`.

### Unit Tests
```bash
zig build test
```
Runs all 29 unit test cases covering config parsing, validation, 13-repo catalog verification, placeholder expansion, path expansion, and state machine decision logic.

### End-to-End Fixture Tests
```bash
zig build test-e2e
```
Runs 35 automated scenario suites (120+ assertions) against real temporary git fixtures to verify cloning, fast-forwarding, refusals, locks, named commands, RAG export pipelines, doctor remediation, GC pruning, and JSON outputs.

---

## 7. Implementation Roadmap

- [x] **Slice 0**: Core CLI scaffold, config engine with `_` comments, git state matrix, `fmr status`, `fmr sync` with thread isolation & atomic queue, `fmr doctor`, per-repo mkdir locks, and comprehensive test suite.
- [x] **Slice 1**: Named commands execution (`fmr check`, `fmr run`), default checks by repo kind (`zig`, `go`, `node`).
- [x] **Slice 2**: RAG snapshot pipeline (`fmr rag`), SHA snapshot directories, atomic symlink swap (`current`), command and files glob exporters.
- [x] **Slice 3**: Complete 13-repository catalog definition (`config/workspace.example.json`), multi-kind defaults, and backward compatibility.
- [x] **Slice 4**: Remediation suite (`fmr doctor --fix`), snapshot retention GC (`fmr rag --gc <n>`), and universal structured machine output (`--json`).

---

## 8. Further Reading

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — module map, data flow, safety invariants, JSON output shape, and test strategy for contributors.
- [`docs/issues/`](docs/issues/) — the slice-by-slice issue specifications that drove each implementation.
- [`yard-plan.md`](yard-plan.md) — the original scope document (v0.1 draft) this project was built from.

