# Issue 7: Full Workspace Dashboard Window (`WorkspaceDashboardView`)

**Slice**: GUI-3 (Full Workspace Dashboard)  
**Parent Plan**: [`docs/gui/README.md`](../../docs/gui/README.md)  
**Depends On**: GUI-1 (Issue #5), GUI-2 (Issue #6)

---

## 1. Goal & Context

Build the full-featured macOS multi-pane dashboard window for managing the 13 workspace repositories, visualizing working tree states, inspecting RAG snapshots, and running project-specific commands with live output.

---

## 2. Technical Specification

### Files to Create
- [`app/Sources/FmrApp/Views/WorkspaceDashboardView.swift`](../../app/Sources/FmrApp/Views/WorkspaceDashboardView.swift):
  - **Sidebar (`NavigationSplitView`)**:
    - Search field for filtering repos by name or branch.
    - Category filters: All (13), Zig, Go, Sites, Tools, Problem/Dirty.
    - Repo list rows with status dots and badges.
  - **Detail View**:
    - **Header**: Repository name, kind tag, branch badge, commit SHA, remote URL link.
    - **Status Cards**:
      - Working Tree: clean/dirty counter, untracked files count.
      - Upstream: ahead / behind commits counter.
      - Conductor Sessions: active worktree count.
    - **RAG Snapshot Card**:
      - Current snapshot status (`snap ok`, `snap stale`, `none`).
      - "Create Snapshot (`fmr rag`)" button (with `--force` toggle).
    - **Custom Commands Runner**:
      - Buttons for configured commands (e.g. `serve`, `site`, `init`, `book`).
      - Collapsible Terminal Output Console showing live stdout/stderr streams.
    - **External Openers**: Quick buttons to open repository in Finder, Terminal, or default Code Editor.

---

## 3. Acceptance Criteria

- [ ] Sidebar cleanly displays all 13 workspace repositories with search and kind filtering.
- [ ] Selecting a repository displays detailed state cards and commit SHA.
- [ ] Clicking "Sync" or "RAG" on a specific repository runs the command and refreshes UI.
- [ ] Running a custom command displays output in the live console drawer.
- [ ] "Open in Finder" and "Open in Terminal" open the correct primary checkout directory.
