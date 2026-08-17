# Issue 13: GUI-5: Worktree Management, Extended Metadata Models, & Editor Launchers

**Slice**: GUI-5 (Worktree Operations & Deep Editor Integration)  
**Parent Plan**: [`implementation_plan.md`](../../implementation_plan.md)  
**Depends On**: GUI-1 through GUI-4 (Issues #8-#11)

---

## 1. Goal & Context

Elevate the SwiftUI application with active worktree management, extended metadata from core CLI updates (`kind`, `path`, `url`, `before`/`after` commit diffs), and multi-editor integration (Cursor, VS Code, Zed, Terminal, Finder):

1. **Extended Metadata Support**:
   - Decode new fields from `fmr status --json` (`kind`, `path`, `url`).
   - Decode new fields from `fmr sync --json` (`before`, `after`, `action`).
   - Support `fmr config --json` catalog viewer.
2. **Interactive Worktree Management**:
   - Dedicated Worktrees tab/section in the repo detail view.
   - Modal sheet to **Create Session Worktree** (`git worktree add ~/Code/worktrees/<repo>/<session> -b <branch>`).
   - Action to **Delete / Remove Worktree Session** safely.
3. **Editor Launchers**:
   - One-click launch into **Cursor**, **VS Code**, **Zed**, **Xcode**, **Terminal**, or **Finder**.
   - Configurable preferred editor setting.
4. **Search & Command Palette**:
   - Quick switcher (`Cmd+K`) to jump directly to any repository or session worktree.

---

## 2. Files to Touch / Create

- [`app/Sources/FmrApp/Models.swift`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/app/Sources/FmrApp/Models.swift): Update `RepoStatus`, `SyncOutcome`, and add `ConfigResponse`.
- [`app/Sources/FmrApp/WorkspaceViewModel.swift`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/app/Sources/FmrApp/WorkspaceViewModel.swift): Add worktree creation/removal methods, editor launch dispatch, and config query.
- [`app/Sources/FmrApp/Views/CreateWorktreeSheet.swift`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/app/Sources/FmrApp/Views/CreateWorktreeSheet.swift): New modal sheet for worktree creation.
- [`app/Sources/FmrApp/Views/WorktreeDetailView.swift`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/app/Sources/FmrApp/Views/WorktreeDetailView.swift): Detailed worktree session card with editor buttons.
- [`app/Sources/FmrApp/Views/WorkspaceDashboardView.swift`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/app/Sources/FmrApp/Views/WorkspaceDashboardView.swift): Add Worktrees section, `Cmd+K` command palette, and editor menu.
- [`app/Sources/FmrApp/Views/CommandPaletteView.swift`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/app/Sources/FmrApp/Views/CommandPaletteView.swift): `Cmd+K` quick switcher.

---

## 3. Acceptance Criteria

- [ ] Models decode new optional fields (`kind`, `path`, `url`, `before`, `after`, `action`) safely with backwards compatibility.
- [ ] User can click "+ New Worktree" to spin up an agent/developer worktree with custom branch.
- [ ] User can open any repo or worktree session in Cursor / VS Code / Zed / Terminal with a single click.
- [ ] Pressing `Cmd+K` presents the quick search and command palette.
- [ ] `swift test --package-path app` passes.
- [ ] `bash scripts/build_app.sh` packages the updated `dist/Fmr.app`.
