# Issue 27: `fmr grep` — Cross-Repo Ripgrep (M2 — Personal)

**Milestone**: M2 v0.3 Personal (`docs/MILESTONES.md`)  
**Area**: Core CLI (Zig)  
**Size**: S (1–2h)  
**Depends On**: #22

---

## 1. Goal & Context

T3’s file picker searches one repo at a time. You have 13. Finding “where did I handle `worktree_safe`?” means 13 `grep`s. `fmr grep` should be the fastest way to search your *workspace*:

```
fmr grep <pattern> [repo...] [--kind <kind>] [--json] [-- -r <ripgrep args>]
```

Uses `rg` if present, falls back to `grep -R`. Respects `.gitignore` inside each primary. Parallel per-repo like `status`/`sync` (reuse `src/status.zig` pool pattern).

## 2. CLI Signature

```
fmr grep <pattern> [repo...] [--kind <kind>] [--json] [--max-count <n>] [-- -r <extra rg args>]
```

- `<pattern>` is a regex (passed verbatim to `rg`). Repo filter optional; default all. `--kind zig` limits to `kind == zig`.
- Human mode: prints `repo:path:line:col:match` with repo prefix, color when TTY. Exit 0 if any match, 1 if none, 2 usage, 4 rg failed — mirrors `rg` contract but aggregated (highest wins).
- `--json` mode: emits `{"version":1,"command":"grep","exit":0,"hits":[{"repo":"boris","file":"src/main.zig","line":17,"col":4,"text":"..."}]}`.

## 3. Technical Specification

- `src/grep.zig` *(new, ~180 lines)* — detects `rg` (`which rg` or `Process` probe), builds argv per repo (`rg --line-number --column --no-heading --color never <pattern> <primary>` plus `--glob !.git`), spawns in bounded pool (`cfg.parallelism.status` or `--jobs`). Captures stdout, parses `file:line:col:text` lines, prefixes with repo name.
- `src/main.zig` — dispatch `grep`, parse `--kind`, `--json`, `--max-count`, `--jobs`, and `--` passthrough.
- No new config schema. No index — ripgrep is fast enough for 13 repos (<200ms on warm FS).

## 4. Acceptance Criteria

- [ ] `fmr grep "pub const version" --kind zig` prints `boris:src/main.zig:17:pub const version = "0.1.0"` (or 0.2.0).
- [ ] `fmr grep "doesnotexist123" --json` emits `{"hits":[]}` with exit 1 and valid JSON.
- [ ] `fmr grep "TODO" boris oliver` limits to 2 repos.
- [ ] Falls back to `grep -R -n` when `rg` not on PATH (tested by `PATH=/usr/bin` in e2e).
- [ ] `zig build test && zig build test-e2e` green (2 new grep fixtures).
