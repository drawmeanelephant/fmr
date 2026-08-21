# Issue 26: `fmr context` — AI-Ready Workspace Dump (M2 — Personal)

**Milestone**: M2 v0.3 Personal (`docs/MILESTONES.md`)  
**Area**: Core CLI (Zig)  
**Size**: S (1–2h)  
**Depends On**: #22

---

## 1. Goal & Context

T3’s magic is “paste your workspace into the LLM”. fmr can do it *better* because it’s local and precise: no guessing, no extra `git status` calls from the agent. One command should dump everything an agent needs to be useful without running git itself:

```
fmr context [repo...] [--json]  # default: human, --json: for MCP/grep
```

This is the single easiest win to make the tool “good for me” — you `fmr context boris --json | pbcopy` → paste into Claude and it knows branch, head, dirty, behind, snap, worktrees, recent commits, catalog kind/commands, without you typing.

## 2. CLI Signature

```
fmr context [repo...] [--json] [--commits <n>]  # n default 3, max 10
```

- Human mode (no `--json`): prints a markdown block per repo, suitable for pasting into a prompt. Includes: repo name/kind/path/url, branch/head, ahead/behind/dirty/untracked, snap, sessions, `check`/`commands`/`rag` mode, last `n` commits (`git log --oneline -n`), and worktree list (`git worktree list`).
- `--json` mode: emits the standard envelope with `command: "context"` and per-repo `context` object (all of the above as structured fields). Stdout is pure JSON.

## 3. Technical Specification

- `src/context.zig` *(new, ~200 lines)* — reuses `git.zig` helpers (`headBranch`, `shortSha`, `aheadBehind`, `porcelain`, worktree list via `worktreeList`, `git log`). No mutations, no locks. Sequential (like `check`/`rag`) but fast — just git reads.
- `src/main.zig` — dispatch `context`, parse `--commits`, `--json`, repo filter (default all).
- `docs/gui/json-contract.md` — add section 9: `fmr context --json` shape.

## 4. Acceptance Criteria

- [ ] `fmr context boris` prints markdown with `boris | afterparty | a50aa15 | kind: zig | snap: none | 0 sessions | last 3 commits`.
- [ ] `fmr context boris --json` emits `{"version":1,"command":"context","exit":0,"repos":[{"name":"boris","branch":"...","head":"...","kind":"zig","dirty_tracked":0,...,"commits":[...]}]}` valid JSON.
- [ ] `fmr context --json` with 13 repos completes in <1s on fixtures.
- [ ] `zig build test && zig build test-e2e && swift test --package-path app` green (e2e adds 2 contexts).
