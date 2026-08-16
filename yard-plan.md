# Yard — Workspace Manager in Zig. Scope Document v0.1

Status: draft for review. No code written. All facts about the bash script are from
`proud-brahmagupta.sh` (read in full). Repo internals for boris/oliver/DipshitOS were
NOT inspected (working trees are live); where the plan depends on their internals, the
assumption is marked **[A]**.

---

## 1. Problem statement and non-goals

The current workspace manager is a 259-line bash script that mixes three jobs — sync,
test, and RAG export — with interactive menus, `reset --hard`, `|| true`, and
repo-name `if/elif` dispatch. It cannot coexist with Conductor: a hard reset destroys
agent worktrees' intent and can corrupt branches checked out through worktrees. It
cannot grow without getting worse.

Yard is a small, config-driven Zig CLI that owns exactly three things:

1. **Repo catalog** — one config file names every repo, its URL, default branch, and
   what "check" and "rag" mean for it.
2. **Safe sync** — fetch + fast-forward on one designated primary checkout per repo.
   Everything else (worktrees, branches, agent sessions) is left alone.
3. **Named commands** — check, rag, run, driven by argv in the config, never by
   repo-name switches in Zig.

RAG output is a versioned, immutable snapshot tree (`source-rag/<name>/<sha>/` +
`current` symlink). Existing exporter scripts are preserved and called as subprocesses.

**Non-goals (v1):** no Cargo/rustodian (rustodian is removed from the catalog,
deliberately), no `reset --hard`, no `rm -rf` of checkouts, no swallowing failures,
no TUI/menu, no watch mode, no daemon, no embeddings or vector store, no agent
orchestration, no replacing Conductor or Claude Code, no Rust, no Nix flakes, no
monorepo, no remote/orchestrated fleet, no git hooks, no LFS or submodule
management, no auth/key storage.

---

## 2. Architecture

### 2.1 Process diagram

```
 you / coding agent
        │   argv: yard sync/check/rag/run/status/doctor [repo...]
        ▼
     ┌─────────────────┐   reads     ~/config/yard/workspace.json
     │      yard       │◀──────────── (JSON, stdlib parse, zero deps)
     │  (Zig binary)   │
     └────────┬────────┘
              │ std.process spawn, bounded parallelism, per-repo lock
   ┌──────────┼──────────────┬───────────────────┬────────────────┐
   ▼          ▼              ▼                   ▼                ▼
 git         exporters    checks              files-mode        ~/.yard/
 clone/      (python3/    (zig build test,    (glob copy,        locks/ logs/
 fetch/      bash/sh,      go test, npm        no subprocess)
 ff-only     invoked via  test/build — never
             config argv)  run in parallel)
   │          │              │                   │
   ▼          ▼              ▼                   ▼
~/dev/drawmeanelephant/<name>   ~/Code/source-rag/<name>/<sha>/   (immutable snapshot)
  (primary checkout —            ~/Code/source-rag/<name>/current  (symlink → <sha>)
   the ONLY checkout
   yard syncs)
   │
   │  git worktree add, executed ONLY by Conductor (reads the primary's .git)
   ▼
 ~/Code/worktrees/<name>/<session>/   ← Conductor + agents. Yard never writes
                                        git state here. Not in the repo catalog.
```

All state flows one way: primary → worktrees (via git, Conductor); primary → snapshots
(via yard + exporters). Nothing ever flows back into the primary from a worktree.

### 2.2 Conductor contract (how the two tools share a repo)

- Conductor must create worktrees from the **primary checkout**, never a copy:
  `git -C ~/dev/drawmeanelephant/<name> worktree add ~/Code/worktrees/<name>/<session> -b <branch>`
  (absolute worktree path — git refuses a worktree inside the main working tree, which
  is why `~/Code/worktrees` is a separate root).
- Yard's sync runs `fetch` + `merge --ff-only` on the primary only. A fast-forward on
  the primary never touches worktree checkouts or branch refs that worktrees hold, so
  agent sessions are structurally safe.
- Yard's safety rules make a worktree/primary collision impossible to hit silently:
  a primary whose `.git` is a *file* (i.e. it is itself a worktree) → sync refused
  (exit 3). `yard doctor` verifies path overlap between the three roots.
- Branch refs shared through `.git`: agents in worktrees can `git push` branches;
  yard never deletes or rebases refs. Divergence on the primary (e.g. an agent forced
  the primary's branch) is refused with repair instructions, never auto-fixed.
- Worktree lifecycle (add/remove/session naming) is entirely Conductor's. `yard status`
  shows worktree session counts read-only, for orientation only.

### 2.3 Directory model (challenged, kept, two additions)

Accepted as proposed, with the primaries staying where they are:
`~/dev/drawmeanelephant/<name>` primary (the existing root — no move),
`~/Code/worktrees/<name>/<session>` Conductor-managed,
`~/Code/source-rag/<name>/<sha>/` + `current` symlink. All three roots overridable in
config. Two small additions, neither complicating:

1. `~/.yard/` state dir: `locks/<name>.lock` (mkdir-atomic; prevents two concurrent
   `yard sync` runs from two terminals/agents) and append-only `yard.log` (one line per
   operation, for agent debugging).
2. `doctor` enforces that `worktrees` and `source-rag` roots are **not** inside the
   `repos` root and vice versa — otherwise snapshots would dirty a primary or a
   worktree checkout would live inside one.

Existing repos today live at `~/dev/drawmeanelephant/<name>` (with boris worktrees in
 `~/dev/drawmeanelephant/boris/worktrees/`). **Default: no move.** `paths.repos` points
 at the existing tree (`~/dev/drawmeanelephant`) from day one. The optional migration
 to `~/Code/repos/` (slice 4) is one `mv` per repo, done manually, with Conductor
 repointed at the new path; until then everything runs in place and the old
 `worktrees/` subdirs are left untouched for Conductor to migrate/retire.

---

## 3. Config schema

**Format: JSON, not TOML.** Justification: Zig's `std.json` is stdlib — zero
dependencies, matching the "zero or very few Zig deps" constraint. TOML requires a
third-party crate (`zig-toml`), which adds a dependency for the sake of comments.
Compensation for JSON's lack of comments: the parser **ignores keys starting with
`_`**, so users can write `"_note": "why this repo's branch is afterparty"`. Example
config is fully documented in README.

File: `~/config/yard/workspace.json` (override with `yard --config <path>`; directory
of the config file is `{workspace}`).

```jsonc
{
  "_version": 1,
  "paths": {
    "repos":      "~/dev/drawmeanelephant",
    "worktrees":  "~/Code/worktrees",
    "sourceRag":  "~/Code/source-rag"
  },
  "parallelism": { "sync": 4, "status": 4, "check": 1, "rag": 1 },
  "defaults": {
    "zig":  { "check": { "argv": ["zig", "build", "test"] } },
    "go":   { "check": { "argv": ["go", "test", "./..."] } },
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
        "command": { "argv": ["python3", "{workspace}/scripts/export_boris_rag.py", "{rag_out}"],
                     "output": "{rag_out}" }
      },
      "commands": {
        "serve": { "argv": ["zig", "build", "run", "--", "serve"] },
        "site": { "argv": ["zig", "build"] }
      }
    },
    {
      "name": "DipshitOS",
      "url": "git@github.com:drawmeanelephant/DipshitOS.git",
      "kind": "zig",
      "worktree_safe": false
    },
    {
      "name": "oliver",
      "url": "git@github.com:drawmeanelephant/oliver.git",
      "kind": "zig",
      "worktree_safe": false,
      "rag": {
        "files": { "globs": ["*.md", "*.toml", "*.json"], "max_depth": 2 }
      }
    },
    {
      "name": "know",
      "url": "git@github.com:MrEmanuel/know.git",
      "kind": "go",
      "rag": {
        "command": { "argv": ["go", "run", "./cmd/{name}", "rag"], "output": "rag-archive" }
      }
    },
    {
      "name": "codex-limits",
      "url": "https://github.com/thrr87/codex-limits.git",
      "kind": "go"
    },
    {
      "name": "fullonrogues.org",
      "url": "git@github.com:drawmeanelephant/fullonrogues.org.git",
      "kind": "site",
      "rag": {
        "command": { "argv": ["python3", "{workspace}/scripts/export_boris_site_rag.py", "{name}"],
                     "output": "out/rag" }
      }
    },
    {
      "name": "rotkeeper",
      "url": "git@github.com:drawmeanelephant/rotkeeper.git",
      "kind": "bash",
      "rag": {
        "command": { "argv": ["{repo}/rotkeeper.sh", "book", "--all"], "output": "bones/book-reports" }
      },
      "commands": { "init": { "argv": ["{repo}/rotkeeper.sh", "init"] } }
    },
    {
      "name": "minutes-without-motion",
      "url": "git@github.com:drawmeanelephant/minutes-without-motion.git",
      "kind": "bash",
      "rag": { "command": { "argv": ["bash", "scripts/rag.sh"], "output": "rags" } }
    },
    {
      "name": "la-famille",
      "url": "git@github.com:drawmeanelephant/la-famille.git",
      "kind": "other",
      "rag": { "command": { "argv": ["python3", "{workspace}/scripts/export_la_famille_rag.py", "{rag_out}"] } }
    },
    {
      "name": "filed.fyi",
      "url": "git@github.com:drawmeanelephant/filed.fyi.git",
      "kind": "other",
      "rag": { "command": { "argv": ["python3", "{workspace}/scripts/export_filed_fyi_rag.py", "{rag_out}"] } }
    },
    {
      "name": "apex",
      "url": "git@github.com:ApexMarkdown/apex.git",
      "kind": "other",
      "rag": { "command": { "argv": ["python3", "{workspace}/scripts/export_apex_rag.py", "{rag_out}"] } }
    },
    {
      "name": "thermalextractiondevices.com",
      "url": "git@github.com:drawmeanelephant/thermalextractiondevices.com.git",
      "kind": "site",
      "rag": { "command": { "argv": ["python3", "{workspace}/scripts/export_boris_site_rag.py", "{name}"],
                            "output": "out/rag" } }
    },
    {
      "name": "corgifever.com",
      "url": "git@github.com:drawmeanelephant/corgifever.com.git",
      "kind": "site",
      "rag": { "command": { "argv": ["python3", "{workspace}/scripts/export_boris_site_rag.py", "{name}"],
                            "output": "out/rag" } }
    }
  ]
}
```

**Field rules (validation failures → exit 5, naming the field):**

| Field | Required | Rule |
|---|---|---|
| `name` | yes | `[a-zA-Z0-9._-]+`, unique; drives paths, placeholders, and output |
| `url` | no | absent → repo is local-only: sync skipped with a notice, check/rag/run still work |
| `kind` | no | `zig\|go\|node\|site\|bash\|other`; informational + `defaults` lookup |
| `default_branch` | no | omitted → resolved from `refs/remotes/origin/HEAD` at sync time |
| `worktree_safe` | no | default `false`; `true` means Conductor uses worktrees; doctor reports session count |
| `sync.enabled` | no | default `true`; `false` → status shows `paused`, sync skips |
| `check` | no | object `{"argv":[...]}`; default from `defaults[kind]`; absent → check prints `skip: no check configured` |
| `rag` | no | exactly one of: `command`+`output`, or `files` (globs, optional `max_depth`) — no third mode |
| `rag.command` | no | object `{"argv":[...]}` (+ optional `output`); run with cwd = primary |
| `rag.output` | no | path to copy into the snapshot; relative to cwd unless it starts with `/` or `{` |
| `commands.<name>` | no | named commands for `yard run`; same `{"argv":[...]}` shape as `check` |
| `env` | no | extra env for rag/commands (e.g. `{"YARD_SKIP_X": "1"}`) |

**Placeholders** (expanded in any `argv`): `{workspace}` (config file dir), `{repo}`
(primary path), `{name}` (repo name), `{branch}` (default branch), `{rag_out}`
(absolute staging dir for the current rag run). Env set for every subprocess:
`YARD_REPO`, `YARD_NAME`, `YARD_BRANCH`, `YARD_RAG_OUT` (rag only), inherited env
passed through.

**Migration of legacy special cases** (all now config, zero Zig switches):
boris `afterparty` → `default_branch`; `export_boris_rag.py` → boris rag command;
`export_boris_site_rag.py <name>` → site repos; minutes `scripts/rag.sh` + `rags/` →
command+output; rotkeeper `rotkeeper.sh init` + `book --all` + `bones/book-reports` →
command+output (+ `init` as a named command, since `init` also dirties/needs manual
running — it is NOT part of rag); Go `go run ./cmd/<name> rag` + `rag-archive/` →
`{name}` placeholder; fallback `*.md/*.toml/Package.swift` maxdepth-2 copy → `files`
mode. rustodian: **absent**, deliberately.

**[A]** Assumed exporter changes (slice 2): `export_boris_rag.py`,
`export_la_famille_rag.py`, `export_filed_fyi_rag.py`, `export_apex_rag.py` currently
write to the old script's flat `source-rag/<name>/`. Plan patches each to accept an
optional output arg (`{rag_out}`), defaulting to the old path — patch in the migration
issue, verified by old behavior. If any exporter can't be patched, fall back to a
repo-relative `output` dir instead. `out/rag` for site repos and DipshitOS/oliver check
argv are **[A]**; config can be edited later without touching Zig.

---

## 4. CLI UX

```
yard <command> [repo...] [flags]

Commands (v1):
  yard status                    read-only snapshot of every repo
  yard sync [repo...]            fetch + fast-forward primary(s); clone if missing
  yard check [repo...]           run configured check argv (sequential)
  yard rag [repo...]             run exporter, snapshot into source-rag
  yard run <repo> <command>      run a named command from config
  yard doctor                    offline self-diagnostics

Flags: --config <path>   --all / -a (all repos, default for bare status/sync)
       --force (rag only: re-run exporter even if snapshot exists)
       --jobs <n> (overrides sync parallelism)
       (--json is v2-only, designed in §4 below — not in v1)
```

**Exit codes** (multi-repo: highest severity wins; every repo still gets one line):

| Code | Meaning | Examples |
|---|---|---|
| 0 | ok (including no-op "already up to date") | |
| 1 | unexpected error | I/O failure, fsync of symlink |
| 2 | usage | unknown command/repo, `yard run` without a command |
| 3 | safety refusal | dirty/ahead/diverged/detached/wrong branch/wrong URL/path violation |
| 4 | subprocess failed | git fetch failed, exporter exited 2, npm test failed |
| 5 | config invalid | bad JSON, unknown field, bad repo name |

**Human output** (colors only when stdout is a TTY):

```
$ yard sync
[ok]     boris        afterparty  1234abc → 5678def (fast-forward)
[ok]     oliver       main        up to date
[ok]     know         main        cloned (fresh)
[refuse] DipshitOS    main        dirty: 3 files modified, 1 untracked — commit or
                                  stash; worktrees untouched. Repair: git -C ~/dev/drawmeanelephant/DipshitOS status
[fail]   rotkeeper    main        python3 …/export_boris_rag.py exited 2 (cwd=~/dev/drawmeanelephant/rotkeeper)
Summary: 3 ok, 1 refused, 1 failed   (exit 4)
```

Failure lines always include: repo name, exact command, exit code, cwd. No `|| true`,
no silent skips — a skipped repo is a `[skip]` line with a reason.

**Future `--json` shape (designed now, implemented v2):** `{"version":1,"exit":4,
"command":"sync","repos":[{"name":"boris","result":"ok","before":"1234abc",
"after":"5678def","action":"fast-forward"},…],"summary":{"ok":3,"refused":1,
"failed":1}}`. Same structure for all commands, so agents can parse it without
special-casing.

---

## 5. Git safety matrix

State is detected once per repo with: `rev-parse --is-inside-work-tree`,
`.git` dir-vs-file check, `symbolic-ref --short HEAD`, `status --porcelain`
(exit-ok, no color), `rev-list --left-right --count HEAD...origin/<branch>`.
All read-only.

| # | Repo state | sync | check | rag | run | status | doctor |
|---|---|---|---|---|---|---|---|
| 1 | Missing (no dir) | clone `--branch <default_branch>` (or origin/HEAD), exit 0 on success | refuse: "run yard sync first" (exit 3) | same | same | `missing` | `missing` (informational) |
| 2 | Dir exists, not a git repo | refuse (exit 3): "not a git repo; fix or delete manually" | refuse | refuse | refuse | `not-a-repo` | problem |
| 3 | `.git` is a file (primary is itself a worktree) | refuse (exit 3): "this is a worktree; sync primaries only" | refuse | refuse | refuse | `worktree?` | problem (path model broken) |
| 4 | Clean, up to date | no-op, exit 0 | run | run (snapshot exists → skip, exit 0) | run | `ok` | ok |
| 5 | Clean, behind | fetch + `merge --ff-only`, exit 0 | run | run | run | `behind N` | ok |
| 6 | Clean, ahead (only) | refuse (exit 3): print `git -C <primary> push origin <branch>` and worktree hint | run | run | run | `ahead N` | warn |
| 7 | Clean, diverged | refuse (exit 3): print `git rebase origin/<branch>` + warning to do it in a worktree, or `git push --force-with-lease` if intentional | run | run | run | `diverged ±N` | warn |
| 8 | Dirty (tracked changes, staged or not) | refuse (exit 3), list `--short` lines | run | refuse without `--force` (snapshot would be unreproducible) | run | `dirty N` | warn |
| 9 | Untracked files only | allow — ff-only can still refuse naturally if a file collides (then exit 3 with the path) | run | run, manifest records `untracked_count` | run | `dirty 0/N` | ok |
| 10 | Detached HEAD | refuse (exit 3): "checkout <branch> in the primary, or work in a worktree" | run | run (snapshot keyed by sha, still valid) | run | `detached <sha>` | warn |
| 11 | Unborn branch / empty repo | refuse (exit 3) with repair text | run | refuse | run | `empty` | warn |
| 12 | Clean, but on the wrong branch (`default_branch` set and HEAD ≠ it) | refuse (exit 3): "primary must hold the default branch" + `git -C <primary> checkout <branch>` hint | run | run | run | `wrong-branch` | warn |
| 13 | URL mismatch (`remote get-url origin` ≠ config `url`) | refuse (exit 3), print both | run | run | run | `url-mismatch` | problem |
| 14 | Fetch/network failure | fail (exit 4): repo, exact `git fetch` command, code | — | — | — | `unreachable` | doctor is offline-only, never tests |
| 15 | Submodules present | allowed (ff-only), `--recurse-submodules` NOT used; doctor warns | run | run | run | `submodules N` | warn |
| 16 | Concurrent sync (lock exists) | exit 3 with lock owner PID from `~/.yard/locks/` | — | — | — | — | stale-lock cleanup |

Rules baked in: never `reset --hard`, never `rm -rf` of checkouts, never delete
refs, never touch a path whose `.git` is a file, never `--force` a push/checkout,
never run npm/go/zig checks in parallel. The primary checkout always holds the
configured `default_branch` (row 12); doctor warns if a worktree checkout sits on
the default branch (agents should use session branches).

---

## 6. RAG snapshot layout and idempotency

```
~/Code/source-rag/<name>/
  <full-sha>/            # git rev-parse HEAD (40 chars — cheap, unambiguous, no collision handling)
    manifest.json        # {"name","sha","branch","created_at","dirty":false,"untracked_count":N,
                         #  "command":["python3",…],"note":null}
    <exported files…>
  current                # symlink → <full-sha>   (updated only on full success)
  .staging/              # transient; never left behind (doctor cleans stale staging)
```

**Run sequence** (per repo, sequential — the shared `source-rag` root and `current`
symlink make parallelism pointless):
1. Refuse if repo dirty (matrix row 8) unless `--force`.
2. `sha = rev-parse HEAD`. If `<sha>/` exists and no `--force`: print `[ok] boris: rag
   up to date (5678def)` and exit 0 — exporters are NOT re-run. Idempotency is keyed
   on source sha, so `yard rag` after `yard sync` with no change costs nothing.
3. Create `.staging/<name>-<sha>-<pid>/`, set `YARD_RAG_OUT` to it, run
   `rag.command` (cwd = primary). Any nonzero exit → exit 4 with repo + command + code;
   staging is removed; `current` untouched.
4. Copy `rag.output` into staging (or run `files` glob walk into staging). Copying
   into a sibling staging dir, not into the final snapshot dir, keeps "snapshot
   exists" = "snapshot complete".
5. Write `manifest.json`, then `mv .staging/… <full-sha>/` (same filesystem, atomic
   rename) and `mv current.new current` (symlink swap, atomic on APFS).
6. `--force`: replace the old `<sha>` dir (staging is renamed over after the old dir
   is moved to `.trash-<sha>`; tiny non-atomic window, acceptable for a personal
   tool, documented).

**Idempotency rules:** snapshot exists → skip (rule 2). `current` dangling → doctor
warn + fix by pointing at newest `<sha>` dir (doctor --fix, v2). Manifest is the
source of truth for `--json` and future GC (v2: `yard rag --gc <n>` keeps newest n
per repo). Legacy flat `source-rag/<name>/` dirs from the bash script are NOT
snapshots: left in place during migration, listed by doctor as `legacy-dir`,
removable via doctor --fix (v2).

---

## 7. Zig module breakdown and test strategy

**Dependencies: none.** `std.json` (config), `std.process` (spawn), `std.fs`
(paths, copies), `std.posix` (symlinks, atomic rename). Pin Zig version (assumed
0.15.x, matching oliver **[A]**) in `build.zig.zon`; `std.process` API changes are
the main churn risk, so the subprocess layer is one file.

Slice 0 ships **exactly 9 files**: `build.zig`, `build.zig.zon`, and:

```
src/main.zig                   argv dispatch, exit code aggregation, per-repo runner loop
src/config.zig                 JSON parse, validation, path expansion, placeholders
src/state.zig                  pure: git-state detection → decision table (unit-testable)
src/git.zig                    subprocess wrappers: clone/fetch/ff-only/status/symbolic-ref
src/process.zig                spawn + capture + timeout, cwd/env argv, error formatting
src/sync.zig                   sync state machine (clone | no-op | ff-only | refuse)
src/status.zig                 parallel read-only snapshot (uses process + state)
src/doctor.zig                 offline checks: roots, overlaps, .git file checks,
                               stale locks/staging, legacy dirs, disk free
src/ui.zig                     line format, TTY color, summary aggregation
```

`check.zig`, `rag.zig`, `run.zig` land in slices 1–2.

`state.zig` is a pure function `(git facts) → decision`; `git.zig` only gathers facts.
This is the whole testing story: the decision table is tested with fabricated facts,
no git needed.

**Test strategy (keeps the disk small):** `zig build test`
- Unit: config parse (good/bad JSON, unknown fields, placeholders, path expansion);
  `state.zig` decision table (every matrix row of section 5).
- Integration (few, cheap): build the binary, run it against a temp `$HOME` with
  fixtures created by **real git** — each fixture is a repo initialized with 2
  commits and a bare "origin" clone, so it's a couple of MB total, never a real clone.
  Fake exporters are 5-line shell scripts writing a file into `$YARD_RAG_OUT`.
  Assert: exit codes, snapshot dirs, symlink target, ff-only outcome, refusal
  messages, `[fail]` lines.
- No network, no big fixtures, no real repos. `~/.yard` and `~/Code/*` are redirected
  via config `paths` to temp dirs in every test.
- Manual sanity: `yard doctor` against the real config (offline).

---

## 8. Migration plan (ordered slices)

**Slice 0 — "works tonight" (one evening):** exactly 9 files (scaffold, `config.zig` +
validator, `git.zig` + `state.zig`, `yard status`, `yard sync` with the full safety
matrix, `yard doctor` (offline subset), locks, tests). Config contains all 13 repos
with correct URLs/branches; check/rag argv only for boris + oliver + DipshitOS. Can
run alongside the bash script (different directories — script's flat `source-rag/` is
untouched).

**Slice 1 — named execution:** `yard check`, `yard run`, subprocess error
formatting (exit 4 contract), `defaults` lookup, sequential policy.

**Slice 2 — RAG pipeline:** snapshot layout, staging, idempotency, `files` mode
(oliver, know fallback); `command`+`output` mode; patch the four self-writing
exporters (boris, la-famille, filed.fyi, apex) to accept `{rag_out}` with old-path
default; migrate site repos, minutes, rotkeeper.

**Slice 3 — remainder + cutover:** wire Go repos (`know`, `codex-limits`) and any
remaining files-mode repos; finalize config for all 13; run yard sync+rag end to end
for a week alongside the script; keep `proud-brahmagupta.sh` untouched until then.

**Slice 4 — retirement + polish:** delete `proud-brahmagupta.sh` (after ≥2 weeks of
zero divergence), optional `mv` of primaries `~/dev/drawmeanelephant/<name>` →
`~/Code/repos/` (default: no move — the old root stays the root), repoint Conductor
(only if primaries move), doctor --fix for legacy flat `source-rag` dirs + stale
locks, retention GC. `--json` stays v2 (shape from §4).

Slices are additive: each ends with a working CLI that is a strict superset of the
previous slice's capabilities. Slice 0 does not touch a single existing directory.

---

## 9. GitHub Project issues

| # | Title | Area | Effort | Depends |
|---|---|---|---|---|
| 1 | Scaffold yard: Zig project, argv dispatch, exit-code contract | Core CLI | S | — |
| 2 | Config schema v1: parse, validate, placeholders, `_`-keys | Core CLI | M | 1 |
| 3 | Git facts layer + pure decision table (all 16 matrix rows) | Core CLI | M | 1 |
| 4 | `yard status` (parallel, read-only) | Core CLI | M | 2, 3 |
| 5 | `yard sync`: clone / ff-only / refusals + repair text + locks | Core CLI | L | 2, 3 |
| 6 | `yard check`: argv, kind defaults, sequential policy | Core CLI | S | 5 |
| 7 | `yard run` + named commands + env/placeholders | Core CLI | M | 6 |
| 8 | Bounded parallelism + per-repo locks + `--jobs` | Core CLI | S | 5 |
| 9 | RAG snapshots: staging, sha dirs, manifest, `current` swap, idempotency | RAG | M | 5 |
| 10 | RAG `command`+`output` mode + `{rag_out}` + `--force` | RAG | M | 9 |
| 11 | Patch 4 self-writing exporters to accept output arg | RAG | M | 10 |
| 12 | Migrate remaining exporters: sites, minutes, rotkeeper, Go, files-mode | RAG | M | 9 |
| 13 | Conductor contract: doc + doctor guards + worktree path checks | Conductor | S | 2 |
| 14 | `yard doctor` full offline checklist | Core CLI | S | 5 |
| 15 | Production config: 13 repos, rustodian removed, special cases migrated | Migration | S | 2 |
| 16 | README: config guide, Conductor setup, safety policy | Docs | S | 13 |
| 17 | `--json` on all commands, shape from §4 (v2) | Core CLI | S | 4 |
| 18 | Cutover: retire bash script, repoint Conductor if primaries move, legacy cleanup | Migration | M | 12, 15, 16 |

**Acceptance criteria:**

1. `zig build test` green; `yard bogus` → exit 2; `yard sync` on empty config → 0 with
   `0 repos`; every exit code in §4 reachable by a fixture.
2. Valid config parses; each invalid fixture (bad JSON, dup name, bad URL, bad kind,
   unknown key) → exit 5 naming the field; `{workspace}/{repo}/{name}/{branch}`
   expand correctly; `_note` ignored.
3. Decision table covers rows 1–16; `state.zig` unit tests reference the matrix; all
   refusal paths reachable from CLI integration tests with fixture repos.
4. `yard status` prints all 13 repos from the production config; missing/ok/dirty
   rows correct (no `--json` in v1).
5. Fixture tests: missing → clone; clean+behind → ff-only (sha moves); ahead/diverged
   → exit 3 with both shas and repair text; dirty → exit 3 listing `--short` lines;
   detached/`.git`-file/empty/wrong-branch → exit 3; URL mismatch → exit 3; failed fetch → exit 4;
   concurrent lock → exit 3 with PID. No `reset`/`rm -rf` anywhere in the codebase.
6. `yard check boris` runs `zig build test` (config), `yard check` on a repo with no
   check config prints `[skip]`; check never parallelizes; failed check → exit 4 with
   command + code.
7. `yard run rotkeeper init` runs with cwd = primary and `YARD_REPO` set; unknown
   command → exit 2 listing available names.
8. Two concurrent `yard sync --all` → exactly one proceeds, other exits 3; `--jobs 1`
   runs serial.
9. `yard rag boris` creates `<sha>/manifest.json` + `current` symlink; second run is
   a no-op `up to date`; `--force` replaces the dir; a failing exporter leaves no
   staging dir and leaves `current` untouched.
10. Same as 9 via `{rag_out}`; exporter scripts (patched) write into `YARD_RAG_OUT`
    and still write to their old path when given no arg.
11. All four exporters accept the output arg; old-path behavior verified by running
    the unpatched invocation once before/after.
12. `yard rag --all` snapshots every repo with a configured rag; files-mode repos
    (oliver, know, codex-limits if files-mode) produce the same file set the old
    script's `find` produced (diffed once against the legacy dir, then legacy dir is
    untouched).
13. Doctor reports a fake worktree primary (`.git` file) and a path overlap; doc
    section "Conductor contract" exists with the exact `git worktree add` command.
14. Doctor exits 1 with a per-check summary when roots missing/overlapping, legacy
    flat dirs present, disk < 1 GiB; 0 otherwise; warns when a worktree holds the
    default branch; never touches the network.
15. Config has all 13 repos; rustodian absent; boris `afterparty`; URLs match
    `proud-brahmagupta.sh` lines 13–25; every special case from §3 resolves to a
    config entry, no Zig switch.
16. README: schema table, placeholders, safety policy (§5), Conductor setup, slice
    history.
17. `yard --json <cmd>` emits §4 shape (v2); `jq`-parseable; no color codes when piped.
18. Script deleted from disk; primaries stay at `~/dev/drawmeanelephant/` (default) or
    move to `~/Code/repos/` with Conductor repointed (verified with one real session);
    legacy flat
    `source-rag` dirs removed by doctor --fix; `yard doctor` clean; `yard sync --all
    && yard rag --all` green twice in a row.

---

## 10. Risks and "do not build"

**Risks:**
- *Exporter internals unknown* — self-writing exporters may not accept an output arg;
  mitigations: patch-with-default in issue 11, `files` mode as universal fallback,
  manifest records exact command per snapshot.
- *`std.process` churn across Zig versions* — one-file isolation (process.zig), pinned
  Zig version in `build.zig.zon`.
- *ff-only natural collisions* (untracked file shadows an incoming path) — git itself
  refuses; mapped to exit 3 with the conflicting path. Correct, not silent.
- *Agents running yard concurrently* — mkdir-atomic locks per repo, lock owner PID in
  error text.
- *Snapshot growth* — no GC in v1; `yard rag --gc <n>` scheduled v2; snapshots are
  content-addressed-ish (sha-keyed), so re-runs don't duplicate.
- *Private-repo auth* — ssh agent / https creds are the user's; clone failures surface
  as exit 4 with the exact command; doctor is offline-only and never probes.
- *Conductor moving `origin/HEAD`* — `default_branch` in config wins when set; boris
  covered; others fall back to origin/HEAD at sync time.
- *Moving primaries in slice 4* — optional; one `mv` per repo, done manually, Conductor
  repointed before the script is deleted; default is no move.

**Do not build (v1 and beyond):** rustodian port or any Rust in the repo path; any
Cargo invocation; `reset --hard` in any code path; `rm -rf` on checkouts; `|| true`
semantics anywhere; a TUI/menu (argv is the interface; the bash script's menu is a
cautionary tale); watch mode; daemon/agent orchestration; embeddings or a vector DB
(a RAG product is out of scope — snapshots are the deliverable); git hooks; LFS;
submodule init/update; partial clones; branch/ref deletion; remote orchestration or
shared-state services; storing credentials; Nix flakes; a monorepo of all projects;
replacing Conductor, Claude Code, or git worktree UX.

---

## 11. Open questions (recommended defaults — "yes" adopts them)

1. **Config format JSON, not TOML?** Default: **yes, JSON** — stdlib `std.json`, zero
   deps; `_note` keys compensate for no comments.
2. **Primaries move from `~/dev/drawmeanelephant/` to `~/Code/repos/`?** Default:
   **no — keep `~/dev/drawmeanelephant` as the root forever**; `paths.repos` points
   at it from day one, nothing ever moves. (If a move is ever wanted, it's one `mv`
   per repo in slice 4 + repointing Conductor — the config only changes `paths.repos`.)
3. **DipshitOS is public/private and its check command?** Assumed: private,
   `zig build test` **[A]**. If it has a bespoke build (bash + qemu), its config gains
   a `commands` entry — schema already supports it.
4. **Patch the four self-writing exporters (boris/la-famille/filed.fyi/apex) to take
   an output arg?** Default: **yes** (old path stays the default, so the bash script
   keeps working during overlap).
5. **Check runs only when asked (`yard check`), never auto-run after sync?** Default:
   **yes** — compose `yard sync && yard check` in a shell alias if wanted.
6. **Untracked files block rag (reproducibility) or merely get counted in the
   manifest?** Default: **merely counted**; snapshots keyed on HEAD sha, `dirty`
   flag in manifest.
7. **Keep every snapshot forever in v1?** Default: **yes**; GC (`--gc <n>`) lands
   with `--json` in v2.
8. **Sequential rag/check is the v1 default?** Default: **yes**; only sync and
   status parallelize (4). npm install across 13 repos must never stampede.
9. **Config lives at `~/config/yard/workspace.json` with `--config` override?**
   Default: **yes**.
10. **`--json` is v2-only, shape fixed for all commands?** Default: **yes** — one
    shape everywhere (§4), no per-command improvisation; nothing in v1 emits JSON.
