# Issue 15: Repository Onboarding, `fmr add` CLI, & Native GUI Import Sheet

**Slice**: Onboarding & Repo Lifecycle  
**Parent Plan**: [`docs/gui/README.md`](../../docs/gui/README.md)  
**Spec Document**: `docs/issues/issue-10-repo-management-and-import.md`

---

## 1. Goal & Context

Eliminate the friction of manually modifying `workspace.json` by providing streamlined repository onboarding across both the **Zig Core CLI** and the **Native macOS SwiftUI App**:

1. **Core CLI (`fmr add` / `fmr remove`)**:
   - Add new repos via CLI: `fmr add <name> <url> [--kind <kind>] [--branch <branch>] [--sync]`.
   - Modifies `workspace.json` safely (preserving existing fields and structure).
   - Auto-detects `kind` if existing local folder is inspected (`build.zig` -> `zig`, `go.mod` -> `go`, `package.json` -> `node`).
   - `fmr remove <name> [--delete-files]` to cleanly unregister repositories.

2. **Native GUI Onboarding Experience (`AddRepoSheet`)**:
   - **`[+ Add Repository]`** button in sidebar header and toolbar.
   - Modal sheet supporting two onboarding flows:
     1. **From Git URL**: Paste SSH or HTTPS URL (e.g. `git@github.com:org/repo.git`), automatically extracts name, probes remote default branch, and lets user select kind with auto-suggestion.
     2. **From Existing Local Directory**: Native macOS Folder Picker or **Drag-and-Drop** a folder directly from Finder into the app sidebar!
   - Toggles to:
     - 🚀 **Clone & Sync immediately**
     - 📸 **Create initial RAG Snapshot**
   - Context menu action on sidebar repo rows: **"Remove Repository from Workspace..."**.

---

## 2. Technical Specification

### A. Core CLI Engine Updates
- [`src/config.zig`](../../src/config.zig):
  - Add `addRepoToConfigFile(allocator, config_path, repo_entry)` that parses JSON, appends to `repos`, and serializes back with pretty indentation.
  - Add `removeRepoFromConfigFile(allocator, config_path, repo_name)`.
- [`src/main.zig`](../../src/main.zig):
  - Parse `fmr add <name> <url> [--kind <kind>] [--branch <branch>] [--no-sync]` and dispatch.
  - Parse `fmr remove <name>`.

### B. Swift GUI Updates
- [`app/Sources/FmrApp/Views/AddRepoSheet.swift`](../../app/Sources/FmrApp/Views/AddRepoSheet.swift):
  - Tabbed or unified input: Git Remote URL vs Local Directory.
  - Auto-detection heuristics for repo name and kind.
  - Checkboxes for "Sync immediately" and "Generate RAG snapshot".
- [`app/Sources/FmrApp/WorkspaceViewModel.swift`](../../app/Sources/FmrApp/WorkspaceViewModel.swift):
  - Add `addRepository(name: String, url: String, kind: String, defaultBranch: String, syncNow: Bool, ragNow: Bool)`
  - Add `removeRepository(name: String)`
  - Add `isAddRepoPresented: Bool`
- [`app/Sources/FmrApp/Views/WorkspaceDashboardView.swift`](../../app/Sources/FmrApp/Views/WorkspaceDashboardView.swift):
  - Add `+` button in sidebar header.
  - Add `.onDrop(of: [.fileURL], isTargeted: ...)` to allow dragging folders from Finder into sidebar.

---

## 3. Acceptance Criteria

- [ ] `fmr add test-repo git@github.com:org/test-repo.git --kind zig` adds entry to `workspace.json` and clones when synced.
- [ ] In macOS App: clicking `+` opens `AddRepoSheet`.
- [ ] Pasting `git@github.com:drawmeanelephant/foobar.git` automatically populates Name: `foobar`.
- [ ] Dragging a local folder into the app auto-detects `kind` (e.g. Zig if `build.zig` is found).
- [ ] Submitting the sheet updates `workspace.json`, updates the sidebar list, and triggers initial sync.
- [ ] `swift test --package-path app` & `zig build test && zig build test-e2e` pass cleanly.
