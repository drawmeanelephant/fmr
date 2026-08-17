# fmr `--json` Contract (Ground Truth)

> Verified against the source (`src/status.zig`, `src/sync.zig`, `src/doctor.zig`,
> `src/exec.zig`, `src/rag.zig`) on Aug 16, 2026. The Swift models in GUI-1 must
> decode exactly these shapes. **This is the source of truth — do not trust the
> draft shapes in `yard-plan.md` §4**, which promised fields that were never
> implemented (`before`/`after` shas on sync, per-repo `action`).

## Common envelope

Every command emits one JSON object to **stdout**. `stderr` is reserved for
errors/diagnostics and is empty on success.

```json
{ "version": 1, "command": "<cmd>", "exit": <int>, ... }
```

- `version` is always `1`.
- `command` is the subcommand (`status | sync | doctor | check | rag`) — except
  `rag --gc`, which emits `"command": "rag-gc"` with a **different shape** (below).
- `exit` mirrors the process exit code and follows the fmr exit-code contract
  (0 ok, 1 error, 2 usage, 3 refusal, 4 subprocess failed, 5 config invalid).
  **Treat the JSON `exit` field as the source of truth**, not the process exit
  status.
- Flags are position-independent: `fmr status --json` and `fmr --json status`
  are equivalent. `--json` suppresses all human output.

## 1. `fmr status --json` — always exits 0

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

**No top-level `summary`.** `exit` is always `0` — repo problems are expressed in
the per-repo fields, never as a non-zero status.

Field types and enums:

| Field | Type | Values |
|---|---|---|
| `name` | string | repo name from config |
| `kind` | enum | `zig`, `go`, `node`, `site`, `bash`, `other` |
| `path` | string | absolute primary checkout path (GUI-3 Finder/Terminal openers) |
| `url` | string | remote URL from config; `""` when local-only |
| `branch` | string | current branch; `""` when missing/detached |
| `head` | string | short SHA (7 chars); `""` when none |
| `state` | enum | `ok`, `missing`, `not_repo`, `worktree`, `detached`, `unborn` |
| `paused` | bool | `sync.enabled == false` in config |
| `ahead` / `behind` | int | commit counts vs. upstream |
| `dirty_tracked` | int | tracked modified files |
| `untracked` | int | untracked files |
| `snap` | enum | `ok`, `stale`, `none` |
| `sessions` | int | Conductor worktree session count |

> ⚠️ **Derive, don't match.** `state` is *never* `dirty`, `behind`, `ahead`,
> `wrong_branch`, or `url_mismatch` — those are conveyed via `dirty_tracked`,
> `behind`, `ahead`. A dirty repo still reports `state: "ok"`. The UI pills
> (Clean / Behind / Dirty / Refused) must be computed from the counts, e.g.
> `dirty = dirty_tracked > 0 || untracked > 0`, `behind = behind > 0`.
>
> ✅ `kind`, `path`, and `url` are now emitted (added Aug 2026) — GUI-3's kind
> filters, URL links, and Finder/Terminal openers can use them directly.

## 2. `fmr sync --json`

```json
{
  "version": 1,
  "command": "sync",
  "exit": 3,
  "repos": [
    { "name": "boris", "result": "ok", "action": "noop", "before": "a50aa15", "after": "a50aa15", "exit": 0, "message": "up to date" },
    { "name": "oliver", "result": "refused", "action": "dirty", "before": "", "after": "", "exit": 3, "message": "dirty: ..." }
  ],
  "summary": { "ok": 1, "refused": 1, "failed": 0, "skipped": 0 }
}
```

- Per-repo fields: `name`, `result` (`ok | refused | failed | skipped`),
  `action`, `before`, `after`, `exit`, `message` (human-readable outcome/repair
  hint).
- **The only command with a top-level `summary`.**
- `action` values: `clone`, `fast-forward`, `noop`, `skip`, `lock-held`, `fail`,
  or a refusal tag (`dirty`, `ahead`, `diverged`, `detached`, `unborn`,
  `wrong_branch`, `url_mismatch`, `is_worktree`, `not_a_repo`,
  `no_origin_branch`).
- `before`/`after` are short SHAs; `""` when not applicable (refusals, failures).
  This enables "`1234abc → 5678def (fast-forward)`" rows directly from JSON
  (added Aug 2026).

## 3. `fmr doctor --json`

```json
{
  "version": 1,
  "command": "doctor",
  "exit": 1,
  "problems": 9,
  "warnings": 0,
  "checks": [
    { "level": "ok", "message": "git version 2.54.0" },
    { "level": "problem", "message": "boris: directory exists but is not a git repo" }
  ]
}
```

- `level`: `ok | warn | problem` — **there is no `error` level**. Map
  `problem` → red in the UI.
- `exit` is `1` when `problems > 0`, else `0`. `warnings` alone do not affect exit.
- `--fix` re-runs the checks; the sheet should re-run doctor after fixing and
  show the *fresh* results, since `exit` reflects post-fix state.

## 4. `fmr check --json`

```json
{
  "version": 1,
  "command": "check",
  "exit": 4,
  "repos": [
    { "name": "boris", "status": "ok", "exit": 0, "message": "check passed" },
    { "name": "rotkeeper", "status": "failed", "exit": 4, "message": "zig exited with code 1" },
    { "name": "apex", "status": "skipped", "exit": 0, "message": "no check defined" }
  ]
}
```

- Per-repo `status`: `ok | failed | skipped`. No top-level summary.

## 5. `fmr rag --json`

```json
{
  "version": 1,
  "command": "rag",
  "exit": 0,
  "repos": [
    { "name": "boris", "status": "ok", "action": "snap", "sha": "a50aa15", "exit": 0, "message": "snapshot created" },
    { "name": "oliver", "status": "ok", "action": "up to date", "sha": "a50aa15", "exit": 0, "message": "..." }
  ]
}
```

- Per-repo `status`: `ok | skipped | refused | error`.
- Per-repo `action` (note **spaces**, e.g. `"up to date"`):
  `snap`, `"up to date"`, `skip`, `missing`, `not_repo`, `worktree`, `unborn`,
  `dirty`, `none`.

## 6. `fmr config --json` (catalog dump)

`fmr config` (aliased `fmr config --json`) emits the full parsed catalog so the
app never parses `workspace.json`: paths, parallelism, and every repo with its
`kind`, absolute `path`, `url`, `default_branch`, `worktree_safe`, `sync_enabled`,
`check` argv, `rag` mode (`command`+`output` or `files`+`globs`+`max_depth`),
`env`, and `commands` (name → argv).

```json
{
  "version": 1,
  "command": "config",
  "exit": 0,
  "paths": { "repos": "...", "worktrees": "...", "sourceRag": "..." },
  "parallelism": { "sync": 4, "status": 4, "check": 1, "rag": 1 },
  "repos": [
    {
      "name": "boris", "kind": "zig",
      "path": "/Users/tbuddy/dev/drawmeanelephant/boris",
      "url": "git@github.com:drawmeanelephant/boris.git",
      "default_branch": "afterparty",
      "worktree_safe": true, "sync_enabled": true,
      "check": ["zig", "build", "test"],
      "rag": { "mode": "command", "argv": ["python3", "..."], "output": "{rag_out}" },
      "env": [],
      "commands": { "serve": ["zig", "build", "run", "--", "serve"] }
    }
  ]
}
```

## 7. `fmr rag --gc <n> --json` — different shape!

```json
{ "version": 1, "command": "rag-gc", "exit": 0, "pruned": 3, "retaining": 2 }
```

No `repos` array. Model this as a separate type if the app surfaces GC.

## Integration notes for the bridge

1. **Invocation**: `fmr <subcommand> [repo...] --json`. For repo-targeted ops
   pass names: `fmr sync boris oliver --json`.
2. **Drain both pipes**: while `Process` runs, read stdout *and* stderr
   concurrently (`FileHandle.readabilityHandler` on both) or a chatty exporter
   (`fmr rag`) will fill the 64 KB pipe buffer and deadlock the child.
3. **`fmr run` has no `--json`** and streams output directly to the terminal —
   GUI-3's live console should use `fmr run <repo> <cmd>` with raw output
   forwarding, not the JSON path.
4. **One process per action**: `sync`/`status` parallelize internally. "Sync All"
   is a single `fmr sync --all --json` process — spawning N processes would trip
   fmr's own per-repo locks.
5. **Sandboxing**: the app must run **unsandboxed** (no App Sandbox entitlement)
   to spawn `fmr` and read `~/dev`, `~/Code`, and `~/config` — or use a privileged
   helper. This is a GUI-1 decision that affects everything downstream.
