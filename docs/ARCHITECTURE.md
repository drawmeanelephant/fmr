# fmr — Architecture & Developer Guide

> Companion to the README. This document maps the source layout to behavior so a
> new contributor can find where each concern lives and what invariants to
> preserve when changing code.

## 1. Module map

`fmr` is a zero-dependency Zig CLI. The design rule is: **git facts are gathered
in one place, decisions are pure, and every mutation goes through an explicit
safety check.**

| File | Responsibility |
|---|---|
| `src/main.zig` | Entrypoint. Flag parsing, command dispatch, exit-code aggregation, config discovery (`--config`, `~/config/fmr/workspace.json`, fallback `~/config/yard/workspace.json`). |
| `src/config.zig` | `workspace.json` parser/validator. `_`-prefixed comment keys, `~/` path expansion, `{placeholder}` expansion, defaults-by-kind lookup. |
| `src/process.zig` | Subprocess layer. Spawn + capture + timeouts, env construction. Isolates `std.process` API churn (the main Zig-version risk). Defines `Ctx` (allocator, io, environ) passed everywhere. |
| `src/state.zig` | **Pure decision table.** `git.Facts → state.Decision` (`clone | noop | ff_only | refuse`). Zero I/O — fully unit-tested with fabricated facts. |
| `src/git.zig` | Read-only fact extraction: `rev-parse`, `status --porcelain`, `rev-list`, `.git` dir-vs-file check, remote URL, plus the only mutations allowed: `clone`, `fetch`, `merge --ff-only`. |
| `src/sync.zig` | Sync engine: atomic worker pool with bounded parallelism, per-repo mkdir locks (`~/.fmr/locks/<repo>.sync.lock`), decision execution + refusal reporting with repair hints. |
| `src/status.zig` | Parallel read-only inspector: branch, HEAD, ahead/behind, dirty counts, snapshot state, Conductor session count. |
| `src/doctor.zig` | Offline diagnostics: git presence, roots exist/overlap, `.git`-file worktree detection, per-repo problems, disk free, stale locks/staging (`--fix`). |
| `src/exec.zig` | `fmr check` / `fmr run`. Sequential named-command execution, env injection, subprocess output forwarding. |
| `src/rag.zig` | RAG snapshot pipeline: staging dir, `<sha40>/` snapshot dirs, `manifest.json`, atomic `current` symlink swap, `--force` re-export, `--gc <n>` retention. |
| `src/ui.zig` | Line formatting, TTY color detection, `NO_COLOR` support, aligned tables, summary aggregation, `--json` emission. |
| `src/test_e2e.zig` | End-to-end suite: builds real temp git fixtures (no network), runs the installed binary, asserts exit codes and disk state. |

### Command → module dispatch

| Command | Module | Notes |
|---|---|---|
| `fmr status` | `status.zig` | Parallel, read-only |
| `fmr sync` | `sync.zig` | Parallel, locked, mutating |
| `fmr doctor` | `doctor.zig` | Sequential, offline, `--fix` mutates locks/staging only |
| `fmr config` | `config.zig` | Catalog dump: emits the parsed `workspace.json` as JSON |
| `fmr check` | `exec.zig` | Sequential by policy |
| `fmr run` | `exec.zig` | Single repo + named command |
| `fmr rag` | `rag.zig` | Sequential (shared `source-rag` root) |

## 2. Data flow

```
            workspace.json ──► config.zig ──► Config
                                                 │
   argv ──► main.zig (dispatch)                 │
                 │                              ▼
                 ├── status ──► status.zig ──► git.zig (facts) ──► ui
                 ├── sync   ──► sync.zig ──► state.zig (decide) ──► git.zig (mutate) ──► ui
                 ├── doctor ──► doctor.zig (offline checks) ──► ui
                 ├── check  ──► exec.zig ──► process.zig (spawn argv) ──► ui
                 └── rag    ──► rag.zig ──► process.zig (exporter) ──► source-rag/<name>/<sha>/
```

- **Sync is the only flow that mutates git state**, and only via `git.zig`'s three
  sanctioned operations (clone, fetch, merge `--ff-only`). Every other mutation is
  lock/state-dir housekeeping.
- **RAG flow**: refuse-if-dirty (unless `--force`) → stage into
  `.staging/<name>-<sha>-<pid>/` → run exporter with `{rag_out}`/`YARD_RAG_OUT` →
  copy `output` or glob-matched files → write `manifest.json` → atomic rename to
  `<sha40>/` → atomic `current` symlink swap. "Snapshot exists" == "snapshot
  complete"; idempotency is keyed on HEAD SHA.

## 3. The git safety invariants

These are the project's non-negotiables. Any change must preserve them:

1. **Never** `git reset --hard`, `git checkout --force`, or `git push --force`.
2. **Never** delete checkouts, branches, or remote-tracking refs.
3. **Sync primaries only**: a `.git`-as-file checkout (a worktree) is refused (exit 3).
4. **Refuse, don't fix**: dirty / ahead / diverged / detached / unborn /
   wrong-branch / URL-mismatch all exit 3 with exact manual repair commands.
5. **Concurrency safety**: mkdir-atomic per-repo locks prevent two `sync` runs
   from racing; the lock file records the owning PID.

The decision logic lives entirely in `state.zig:decide()` as a pure function over
`Facts` — this is what makes the safety matrix unit-testable without git.

## 4. Exit code contract

Aggregated per multi-repo run (highest severity wins):

| Code | Meaning |
|---|---|
| `0` | OK / up to date |
| `1` | Unexpected error (I/O, internal) |
| `2` | Usage / CLI error |
| `3` | Safety refusal |
| `4` | Subprocess failed |
| `5` | Config invalid |

## 5. JSON output

`--json` on any command emits one shape to stdout:

```json
{
  "version": 1,
  "command": "status",
  "exit": 0,
  "repos": [
    {
      "name": "oliver",
      "kind": "zig",
      "path": "/Users/tbuddy/dev/drawmeanelephant/oliver",
      "url": "git@github.com:drawmeanelephant/oliver.git",
      "branch": "feat/task-lists-raw-html",
      "head": "a50aa15",
      "state": "ok",
      "paused": false,
      "ahead": 0,
      "behind": 0,
      "dirty_tracked": 0,
      "untracked": 0,
      "snap": "none",
      "sessions": 0
    }
  ]
}
```

Human output is suppressed when `--json` is given; colors only when stdout is a
TTY and `NO_COLOR` is unset.

## 6. Concurrency model

- `sync` / `status`: bounded worker pool (`parallelism.sync` / `.status` in config,
  `--jobs` overrides). Per-repo work is dispatched to a shared atomic queue.
- `check` / `rag`: **sequential by design** — never run 13 repos' `npm test` or
  exporter writes in parallel (stampede avoidance; the shared `source-rag` root
  and its `current` symlink make parallel rag pointless anyway).
- Locks: `~/.fmr/locks/<repo>.sync.lock` via `mkdir` (atomic). `doctor --fix`
  prunes stale locks (dead PID) and abandoned staging dirs.

## 7. Test strategy

| Suite | Command | Scope |
|---|---|---|
| Unit | `zig build test` | 29 tests: config parsing/validation, placeholder + `~` expansion, the full `state.zig` decision matrix with fabricated facts. No git, no network. |
| E2E | `zig build test-e2e` | 35 scenarios / 120+ assertions against real temp git fixtures: clone, ff-only, every refusal, locks, named commands, RAG export + idempotency + `--force` + GC, `doctor --fix`, `--json` across all commands. |

Fixtures are tiny (2-commit repos + bare origin), never real clones, and every
path is redirected via config to temp dirs.

## 8. Build / run cheatsheet

```bash
zig build              # → zig-out/bin/fmr
zig build test         # unit tests
zig build test-e2e     # end-to-end fixture suite
./zig-out/bin/fmr --help
./zig-out/bin/fmr --config config/workspace.example.json doctor   # read-only
./zig-out/bin/fmr --config config/workspace.example.json status   # read-only
```

`sync` and `rag` mutate real checkouts/snapshots — run them with a scratch config
pointing `paths` at temp dirs when experimenting.
