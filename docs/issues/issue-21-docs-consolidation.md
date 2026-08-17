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
  referenced a **nonexistent** `implementation_plan.md` and contained **stale
  absolute `file://` links** from a previous checkout location.

This issue makes the docs coherent: one contract reference, no dead links, no
stale paths, and a clear index of where each GUI concern is specified.

## 2. Technical Specification

### Changes

1. **Single JSON contract source of truth**: `docs/gui/json-contract.md` is the
   canonical reference. Update `docs/issues/issue-05..09` to point to it
   (`../../docs/gui/json-contract.md`) instead of `implementation_plan.md`.
2. **Fix stale paths**: replace every stale `file:///...` link in
   `docs/issues/*.md` with relative repo paths (e.g. `../../src/main.zig`).
3. **Reconcile `gui-1-spec.md` vs `issue-05`**: keep the issue spec as the
   task-facing doc and the gui-1-spec as the design reference; add cross-links
   and state which wins on conflict (the issue spec wins, once updated).
4. **Index**: ensure `docs/issues/README.md` lists every GUI issue (05–09, 13,
   15) and the backlog (16–21) with status.

### Files to touch

- `docs/issues/issue-01..10-*.md`, `docs/issues/issue-16..20-*.md`
- `docs/gui/README.md`, `docs/gui/gui-1-spec.md`
- `docs/issues/README.md`

## 3. Acceptance Criteria

- [x] No stale absolute `file://` links remain anywhere in `docs/`.
- [x] No doc links to the nonexistent implementation-plan file.
- [x] Every GUI issue spec links to `docs/gui/` for the JSON shape / plan.
- [x] `docs/issues/README.md` lists GUI issues 05–09, 13, 15 and the backlog 16–21.
- [x] No references to the previous checkout's absolute paths remain in `docs/`.
