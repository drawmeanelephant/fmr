# Issue 21: Docs — Consolidate GUI Docs & Fix Stale References

**Area**: Documentation  \
**Parent Plan**: [`docs/gui/README.md`](../gui/README.md)  \
**Depends On**: None

---

## 1. Goal & Context

Documentation for the GUI phase lives in two overlapping places:

- `docs/gui/` — `json-contract.md` (the verified `--json` contract, source of
  truth), `README.md` (issue review), `gui-1-spec.md` (revised GUI-1 spec).
- `docs/issues/issue-05..09` — the official per-slice GUI issue specs, which
  reference a **nonexistent** `implementation_plan.md` and contain **stale
  absolute paths** (`file:///Users/tbuddy/Documents/antigravity/fuckmerunning/...`)
  from a previous checkout location.

This issue makes the docs coherent: one contract reference, no dead links, no
stale paths, and a clear index of where each GUI concern is specified.

## 2. Technical Specification

### Changes

1. **Single JSON contract source of truth**: `docs/gui/json-contract.md` is the
   canonical reference. Update `docs/issues/issue-05..09` to link to it
   (`../../docs/gui/json-contract.md` or relative path) instead of
   `implementation_plan.md`.
2. **Fix stale paths**: replace every
   `file:///Users/tbuddy/Documents/antigravity/fuckmerunning/...` link in
   `docs/issues/*.md` and `docs/gui/*.md` with relative repo paths (e.g.
   `app/Sources/FmrApp/Models.swift`).
3. **Reconcile `gui-1-spec.md` vs `issue-05`**: keep the issue spec as the
   task-facing doc and the gui-1-spec as the design reference; add cross-links
   and state which wins on conflict (the issue spec, once updated).
4. **Index**: ensure `docs/issues/README.md` lists every GUI issue (05–09, 13,
   15) and the backlog (16–21) with status.

### Files to touch

- `docs/issues/issue-05..09-*.md`
- `docs/gui/README.md`, `docs/gui/gui-1-spec.md`
- `docs/issues/README.md`

## 3. Acceptance Criteria

- [ ] No `file:///Users/...` path remains anywhere in `docs/`.
- [ ] No doc references `implementation_plan.md` (which doesn't exist).
- [ ] Every GUI issue spec links to `docs/gui/json-contract.md` for the JSON shape.
- [ ] `docs/issues/README.md` lists issues 05–15 with statuses.
- [ ] `grep -rn "fuckmerunning" docs/` returns nothing.
