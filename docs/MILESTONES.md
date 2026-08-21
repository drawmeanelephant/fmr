# fmr Milestones — End of Tomorrow Ship Plan

> **Target: `v0.2` + `v0.3` shipped by EOD Fri Aug 22, 2026.**  
> Everything below is scoped for ~12–14h total (Tonight + Tomorrow). Each issue is **S (1–2h)** unless marked **M (2–3h)**. No issue depends on a future Zig version or network service.

## Reality Check (Aug 20, 23:30)

`zig build test` / `zig build test-e2e` / `swift test --package-path app` all **green**. Core slices 0–4 and GUI-1..5 + onboarding are **landed** (PRs #5, #6, #7, #12, #14, #17–#27). `workspace.example.json:32` lists 13 repos, `src/main.zig:17` reports `0.1.0`, `scripts/build_app.sh:1` builds a signed `LSUIElement` app.

What T3 does better today: cloud fleet, generic templates. What fmr already does better: **deterministic local safety** (`src/state.zig` pure decision table), **worktree isolation** (`README:52` Conductor contract), **immutable RAG snapshots**, **native menu-bar** (`app/Sources/FmrApp/FmrApp.swift:15`).

**What’s actually broken:** docs drift (`docs/issues/README.md:31` still marks GUI-6 as Ready and #16–21 as backlog, but they’re merged in #17–#23), local `fmr doctor` shows 9 problems (5 not-a-repo dirs, 2 url-mismatches, 2 missing roots), version never bumped.

---

## Milestone M1 — v0.2 Ship: “It Actually Works”

**Goal:** A stranger can `git clone && zig build && fmr doctor` without WTFs. Docs match code, CLI feels finished, GUI is a daily driver.

**Deadline: Thu night → Fri 12:00.** 4 issues, 6–7h.

| Issue | Title | Size | Owner |
|---|---|---|---|
| #22 | Docs & Version Truth — kill stale references, add this file, bump to `0.2.0` | S | — |
| #23 | CLI DX — completions + `fmr open` + `fmr list` | M | — |
| #24 | Doctor & Sync UX — actionable fixes for `url-mismatch` / `not-a-repo` | S | — |
| #25 | GUI Menubar Polish — notifications, About version, empty states | S | — |

**Exit criteria:**
- `docs/issues/README.md` lists every issue 01–29 with correct status.
- `fmr --version` = `0.2.0`, `dist/Fmr.app` About shows same, `codesign --verify` pass.
- `fmr doctor` on `workspace.example.json` with no stale dirs = 0 problems (or only expected “not cloned yet” oks).
- `eval "$(fmr completion zsh)"` gives `fmr sync <TAB>` → repo names.
- Manual dogfood: `fmr status && fmr sync --all && fmr doctor --fix && fmr rag --all` twice in a row = green.

## Milestone M2 — v0.3 Personal: “Better Than T3 *For Me*”

**Goal:** Make fmr the thing you open *instead* of T3 when you want personal control + AI superpowers. Each feature is a T3-gap that only a local tool can do safely.

**Deadline: Fri 12:00 → Fri 20:00.** 4 issues, 6–7h.

| Issue | Title | Size | Owner |
|---|---|---|---|
| #26 | `fmr context` — AI-ready workspace dump (one-shot prompt injection) | S | — |
| #27 | `fmr grep` — cross-repo ripgrep (beats T3’s file picker) | S | — |
| #28 | `fmr mcp` — MCP server so Claude/Cursor *must* use fmr, not raw git | M | — |
| #29 | `fmr daemon` — optional launchd auto-sync (local-only, no fleet) | S | — |

**Exit criteria:**
- `fmr context boris --json` pasted into Claude gives it branch/head/dirty/snap + recent commits without extra `git` calls.
- `fmr grep "TODO" --kind zig` searches only Zig primaries, respects `.gitignore`, prints `repo:path:line`.
- Claude Code can call `mcp__fmr__status` / `mcp__fmr__sync` via `fmr mcp` stdio.
- `fmr daemon install --interval 10m` creates `~/Library/LaunchAgents/com.drawmeanelephant.fmr.plist`, `fmr daemon status` shows next run.

## Non-goals (explicitly *not* by tomorrow)

- No embeddings/vector DB — snapshots stay as files (`source-rag/<sha>/`); querying is grep/context only.
- No remote fleet, auth, or hosting — T3 wins there, we don’t compete.
- No TUI, watch mode, daemon by default — daemon is opt-in only.
- No `reset --hard`, `rm -rf` of checkouts, or `push --force` — invariants in `docs/ARCHITECTURE.md:64` stay.

## Schedule

```
Thu 23:30–01:00  Issue #22 (docs) + #23 start (completions)
Fri 08:00–10:00  #23 finish + #24 (doctor/sync UX)
Fri 10:00–12:00  #25 (GUI polish) — M1 code freeze, tag v0.2.0
Fri 12:00–14:00  #26 (context) + #27 (grep)
Fri 14:00–17:00  #28 (MCP) — largest chunk
Fri 17:00–19:00  #29 (daemon)
Fri 19:00–20:00  Buffer: `zig fmt --check`, full test matrix, demo GIF, RELEASE notes
```

Each slice ends with `zig build test && zig build test-e2e && swift test --package-path app` green.

## How to use this doc

- Every new issue (`docs/issues/issue-22-*.md` … `issue-29-*.md`) links here as Parent Plan.
- `docs/issues/README.md` is the index — this file is the timeline.
- When an issue lands, update its row to `Closed (PR #X)` and check its acceptance criteria.
- Tag `v0.2.0` after M1, `v0.3.0` after M2.
