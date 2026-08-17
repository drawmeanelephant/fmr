# Issue 20: GUI — Harden Worktree Create/Remove

**Area**: GUI (Swift)  \
**Parent Plan**: [`docs/issues/issue-09-gui-5-worktree-management-and-extended-models.md`](./issue-09-gui-5-worktree-management-and-extended-models.md)  \
**Depends On**: Issue 17 (worktrees root comes from `fmr config --json`)

---

## 1. Goal & Context

GUI-5 added worktree creation/removal by shelling out to `git -C <repo>
worktree add/remove` directly. The happy path works, but several edge cases are
unhandled and can surface as raw errors or leave the UI stale:

1. **Dirty worktree removal fails.** `git worktree remove` refuses on a dirty
   tree. The GUI currently reports the raw git error with no recovery options.
2. **Branch / session name validation.** Arbitrary user input is passed to
   `git worktree add -b <branch>`; invalid ref names, spaces, or path separators
   produce confusing failures (or, worst case, a session path outside the
   worktrees root).
3. **Stale session rows.** A worktree removed externally (by Conductor or
   terminal) leaves a ghost row until refresh.
4. **No post-op refresh.** After create/remove, `sessions` counts and the
   worktree list aren't updated reactively.

This issue hardens these paths without weakening the Conductor contract: fmr's
core never deletes checkouts, and the GUI must not do anything destructive
without explicit user confirmation.

## 2. Technical Specification

### Rules

- **Never** run `git worktree remove --force` without a confirm dialog that
  states the worktree is dirty and that `--force` discards uncommitted work.
- Validate branch names against git ref rules (`git check-ref-format --branch`)
  before spawning; show inline validation errors.
- Sanitize session names: reject `/`, `..`, leading `.`, and names that would
  escape `paths.worktrees/<repo>/`.
- After any create/remove, call `refreshStatus()` (and reload the worktree list).

### Files to touch

- `app/Sources/FmrApp/WorkspaceViewModel.swift`:
  - `createWorktree(repoName:branch:session:)`: validate ref + session, spawn
    `git worktree add`, surface typed errors, refresh.
  - `removeWorktree(repoName:session:)`: check dirty state first (run
    `git -C <session> status --porcelain`), require confirmation when dirty,
    then `git worktree remove` (with `--force` only after confirmation), refresh.
  - Worktree list: derive the root from the catalog (`paths.worktrees`) and
    prune rows whose directory no longer exists.
- `app/Sources/FmrApp/Views/CreateWorktreeSheet.swift`: inline validation and
  error display.
- `app/Sources/FmrApp/Views/WorkspaceDashboardView.swift`: confirm dialog for
  dirty removal.
- `app/Tests/FmrAppTests/FmrAppTests.swift`: unit tests for branch/session
  validation.

## 3. Acceptance Criteria

- [ ] Invalid branch/session names are rejected with a clear message before any
      git command runs.
- [ ] Removing a clean worktree succeeds and the row disappears immediately.
- [ ] Removing a dirty worktree shows a confirm dialog; without confirmation the
      worktree is untouched.
- [ ] Removing a worktree that no longer exists on disk is a no-op (row pruned),
      not an error.
- [ ] `sessions` counts and the worktree list refresh after create/remove.
- [ ] `swift build --package-path app` and `swift test --package-path app` pass.
