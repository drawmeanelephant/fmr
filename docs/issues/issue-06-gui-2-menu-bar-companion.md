# Issue 6: macOS Menu Bar Companion Popover (`MenuBarView`)

**Slice**: GUI-2 (Menu Bar Companion)  
**Parent Plan**: [`docs/gui/README.md`](../../docs/gui/README.md)  
**Depends On**: GUI-1 (Issue #5)

---

## 1. Goal & Context

Build the lightweight macOS `MenuBarExtra` status bar companion popover that provides at-a-glance repository status, fast 1-click sync/RAG triggers, and the ability to open the full workspace dashboard window.

---

## 2. Technical Specification

### Files to Create / Modify
- [`app/Sources/FmrApp/FmrApp.swift`](../../app/Sources/FmrApp/FmrApp.swift):
  - Declares `MenuBarExtra("fmr", systemImage: "arrow.triangle.2.circlepath")` with `.window` style popover.
  - Declares `WindowGroup(id: "dashboard") { WorkspaceDashboardView(...) }` for the full window.
- [`app/Sources/FmrApp/Views/MenuBarView.swift`](../../app/Sources/FmrApp/Views/MenuBarView.swift):
  - **Summary Banner**: Pills for `Clean (N)`, `Behind (N)`, `Dirty (N)`, `Stale Snap (N)`.
  - **Repository Scroll Area**:
    - Repo row: name, current branch, status pill (green OK, yellow Behind N, orange Dirty N, red Refused).
    - Quick hover action buttons: Sync icon, RAG icon.
  - **Footer Actions**:
    - **Sync All** button (with loading spinner during execution).
    - **RAG All** button.
    - **Open Dashboard Window** button.
    - **Quit** button.

---

## 3. Acceptance Criteria

- [ ] Status bar icon displays in the macOS menu bar.
- [ ] Clicking menu bar item opens the `MenuBarView` popover.
- [ ] Repositories render with accurate status badges and branch labels.
- [ ] Clicking "Sync All" triggers `fmr sync` asynchronously and updates badges upon completion.
- [ ] Clicking "Open Dashboard Window" opens the full dashboard desktop window.
