# Issue 22: Docs & Version Truth (M1 — Ship)

**Milestone**: M1 v0.2 Ship (`docs/MILESTONES.md`)  
**Area**: Docs / Build  
**Size**: S (1–2h)  
**Depends On**: None

---

## 1. Goal & Context

The code is ahead of the docs. Three concrete lies:

1. `docs/issues/README.md:31` marks GUI-6 (issue-10) as `Ready` and #16–21 as “Backlog — not yet started”, but PRs #17 (`d329f73`), #18 (`5eedadc`), #19 (`a6c05c0`), #20 (`0de49de`), #21 (`93b67f4` + `dafeead`) already shipped them. `src/main.zig:47` already parses `run --json`, `app/Sources/FmrApp/FMRBridge.swift:43` already calls `config --json`, `.github/workflows/ci.yml:38` already has a `gui` job.
2. `src/main.zig:17` still reports `0.1.0` despite 8 post-0.1 features (`add/remove`, recents, palette, hardening).
3. No single place says “done by tomorrow” — `docs/MILESTONES.md` now exists and must be the source of truth, but issues don’t link to it.

This issue makes docs match reality and bumps the version so `Fmr.app` About can show it.

## 2. Technical Specification

### Files to touch

- `src/main.zig:17` — bump `pub const version = "0.1.0"` → `"0.2.0"` (leave `"0.3.0"` for M2 tag; or bump directly to `0.2.0` now and `0.3.0` in M2).
- `docs/issues/README.md` — rewrite index:
  - Table 01–04 = Closed
  - Table 05–10 (GUI-1..6: issues 05,06,07,08,09,10) = Closed (list PR numbers)
  - Table 16–21 = Closed (list PR numbers) — *not* Backlog
  - Add Milestones section linking to `docs/MILESTONES.md` and new issues 22–29
- `docs/MILESTONES.md` — already created; ensure it’s linked from `README.md:250` “Further Reading”.
- `README.md:246` Roadmap checkboxes — check Slice 4 and add “M1 Ship / M2 Personal” note.
- `docs/gui/README.md` — mark follow-ups #1–3 as Done (they were done in #16–#18).

### Docs hygiene pass (30 min)

- `grep -r "file://" docs/ || true` — must be zero (already fixed in #22 but verify).
- `grep -r "implementation_plan" docs/ || true` — must be zero.
- `grep -r "0\.1\.0" docs/ app/` — update to `0.2.0` or make it templated.

## 3. Acceptance Criteria

- [ ] `fmr --version` prints `fmr 0.2.0`.
- [ ] `grep -r "file://" docs/` finds nothing.
- [ ] `docs/issues/README.md` lists issues 01–10 and 16–21 as Closed with PR links, and lists 22–29 as Ready / In Progress with milestone refs.
- [ ] `docs/MILESTONES.md` is linked from `README.md` and `docs/issues/README.md`.
- [ ] `zig fmt --check src/*.zig build.zig && zig build test && zig build test-e2e && swift test --package-path app` green.
