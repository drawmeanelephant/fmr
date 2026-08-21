# Issue 23: CLI DX — Completions + `fmr open` + `fmr list` (M1 — Ship)

**Milestone**: M1 v0.2 Ship (`docs/MILESTONES.md`)  
**Area**: Core CLI (Zig)  
**Size**: M (2h)  
**Depends On**: #22 (version)

---

## 1. Goal & Context

T3’s CLI feels good because `tab` works. fmr’s CLI is powerful but discoverability is `fmr --help` → memorize. Two gaps that cost you daily:

1. **No completions.** `fmr sync <TAB>` should complete repo names, `fmr --config <TAB>` files, `fmr run <repo> <TAB>` command names. Without this you `fmr status` → copy-paste.
2. **No quick open.** You `fmr status` → see `boris` → `open ~/dev/drawmeanelephant/boris` in Terminal or click through GUI. Want `fmr open boris` (Finder) and `fmr open boris --editor cursor` (or `--terminal`).
3. **No list.** `fmr status` is heavy (git). `fmr list` should be instant (config only) with `--kind zig` filtering — useful for scripts and completions source.

## 2. CLI Signatures

```
fmr completion <shell>          # shell: zsh | bash | fish
fmr open <repo> [--editor <name>|--finder|--terminal] [--worktree <session>]
fmr list [--kind <kind>] [--json]
```

- `completion` prints a shell script to stdout; install via `eval "$(fmr completion zsh)"`. Must complete: subcommands, repo names (from config), `--kind` values, `run` command names, flags.
- `open` resolves `paths.repos/<repo>` (and `paths.worktrees/<repo>/<session>` if given) and opens via `open` (macOS) or `$EDITOR`. No git I/O. Exit 2 if repo unknown. Respects catalog `path` from config.
- `list` is `status` without git — just config. `--kind` filters (`zig`, `go`, `node`, `site`, `bash`, `other`). `--json` emits same shape as config but filtered. Cheap, no locks.

## 3. Technical Specification

- `src/main.zig` — add dispatch for `completion`, `open`, `list`. `completion` has no config load dependency for speed? But completing repo names needs config — load it, fallback to empty on error.
- `src/completion.zig` *(new, ~150 lines)* — generators for zsh/bash/fish. Steal pattern from `zig build` completions: `_fmr` function with `compadd`. For bash, `complete -F`. For fish, `complete -c fmr`. Tested by sourcing in a temp shell, not by unit alone.
- `src/open.zig` *(new, ~80 lines)* — path resolution + `std.process.spawn` of `open <path>` or `$EDITOR <path>`. On Linux fallback to `xdg-open`.
- `src/config.zig` — no change; `list` reuses `Config.load` and filters.

## 4. Acceptance Criteria

- [ ] `fmr completion zsh | head` prints `_fmr()` with `sync|status|doctor|config|check|run|rag|add|remove|open|list`.
- [ ] In `zsh -f` with `eval "$(fmr completion zsh)"`, typing `fmr sync <TAB>` completes repo names from `workspace.example.json`.
- [ ] `fmr open oliver` opens `~/dev/drawmeanelephant/oliver` (mock with `echo` in tests).
- [ ] `fmr list --kind zig --json` emits only `kind: zig` repos, `exit: 0`, valid JSON.
- [ ] `zig fmt --check && zig build test && zig build test-e2e` green.
