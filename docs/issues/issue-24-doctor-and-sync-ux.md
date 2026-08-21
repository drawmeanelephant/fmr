# Issue 24: Doctor & Sync UX — Actionable Fixes for `url-mismatch` / `not-a-repo` (M1 — Ship)

**Milestone**: M1 v0.2 Ship (`docs/MILESTONES.md`)  
**Area**: Core CLI (Zig) — `src/doctor.zig` + `src/sync.zig`  
**Size**: S (1–2h)  
**Depends On**: #22

---

## 1. Goal & Context

`fmr doctor` today reports correctly but doesn’t help you fix the two most common local problems you actually have (seen Aug 20 run: 5× `not-a-repo`, 2× `url-mismatch`):

```
[problem] boris: directory exists but is not a git repo
[problem] oliver: url mismatch (config git@..., origin https://...)
```

Both are “problem” level, but `--fix` only prunes stale locks/staging (`src/doctor.zig:95`). The user still manually `rm -rf` or `git remote set-url`. T3 would just “fix it” — fmr must not auto-delete checkouts (invariant `docs/ARCHITECTURE.md:65` #2) but *should* make the fix one copy-paste or one `--fix` confirmation.

## 2. Specification

### `fmr doctor --fix` additions

- **Stale `not-a-repo` dirs:** when `gk == .absent` (dir exists, not a git repo, no important files), `--fix` prints `[fix] would remove <path> (empty / not a repo) — run with --force to delete` and *only* deletes if `--fix --force` (or `--force-fix`) is given. Never deletes non-empty dirs with user files without explicit flag. For now, just improve the message to include `rm -rf <path>` + `fmr sync <repo>` one-liner.

- **URL mismatch:** `--fix` prints `[fix] oliver: run git -C <path> remote set-url origin <config-url>`; with `--fix --force` it actually runs `git remote set-url origin <config-url>` and re-checks. Guard: only if `config url` is non-empty and valid.

### `fmr sync` error enrichment

- `url_mismatch` refusal (`src/sync.zig:229`) already prints `fix config or run: git -C <primary> remote set-url origin <url>` — ensure it also appears in `--json` `details`/`message` so GUI can surface a “Fix Remote” button later.

- Add `--fix-origin` flag to `sync` that auto-runs `set-url` before fetch when mismatch is the *only* refusal reason (single repo). Exit 0 on success, 3 otherwise.

## 3. Files to Touch

- `src/doctor.zig:95` — extend `fixStale` (rename to `fixStaleAndRemediate`) to handle url-mismatch with `--force` gate; improve `repoChecks` messages to include exact `rm -rf` hint.
- `src/sync.zig:177` — add `--fix-origin` handling before `remoteUrl` check when flag set.
- `src/main.zig` — parse `--fix-origin` for `sync`, pass to `sync.run`; pass `force` into `doctor.run` `fix` path already exists (`--fix` + `--force` combo).
- `src/test_e2e.zig` — fixtures for url-mismatch + `--fix-origin` success.

## 4. Acceptance Criteria

- [ ] `fmr doctor --fix` on a `not-a-repo` dir prints `rm -rf <path> && fmr sync <name>` hint, does not delete without `--force`.
- [ ] `fmr doctor --fix --force` on a url-mismatch runs `set-url` and second `doctor` is clean (in a temp fixture).
- [ ] `fmr sync oliver --fix-origin --json` fixes the remote and proceeds to fetch/ff-only when the only problem was url-mismatch.
- [ ] Invariant preserved: no `rm -rf` of checkouts without `--force`; no `reset --hard` anywhere (`grep -r "reset --hard" src/` = 0).
- [ ] `zig build test-e2e` adds 2 new scenarios, all green.
