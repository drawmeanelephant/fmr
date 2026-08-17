# Issue 17: GUI — Wire `fmr config --json` into the App

**Area**: GUI (Swift)  \
**Parent Plan**: [`docs/gui/README.md`](../gui/README.md)  \
**Depends On**: `fmr config --json` (already implemented in core)

---

## 1. Goal & Context

The GUI defines `ConfigResponse` / `ConfigRepoItem` in `Models.swift` but **never
calls `fmr config`** — the catalog is unused. Meanwhile the dashboard's
`RepoFilter` (`All / Needs Attention / Zig / Go / Sites / Tools & Scripts`) and
the custom-command buttons depend on data that currently comes from ad-hoc
places:

- `kind` is now in `fmr status --json`, but the kind→category mapping
  (`site` → "Sites", `bash`/`other` → "Tools & Scripts") is hardcoded in the
  ViewModel rather than derived from the actual catalog.
- Custom command buttons (serve/site/init/book) and rag mode are not loaded —
  the dashboard can't know which commands a repo has without the catalog.
- `resolvedPath` falls back to a hardcoded `~/dev/drawmeanelephant/<name>` when
  `path` is missing; the catalog's `paths.repos` is the correct source.

This issue makes `fmr config --json` the single source of truth for catalog
metadata, so the UI never hardcodes workspace layout or command lists.

## 2. Technical Specification

### Files to touch

- `app/Sources/FmrApp/WorkspaceViewModel.swift`:
  - Add `loadCatalog()` calling `bridge.run(["config"])` → `ConfigResponse`.
  - Store `configPaths` and per-repo catalog entries (`[String: ConfigRepoItem]`
    keyed by name) as `@Observable` state.
  - Derive the kind→category mapping from the catalog (`ConfigRepoItem.kind`)
    instead of a hardcoded switch; keep a documented default for unknown kinds.
  - Expose `customCommands(for name: String) -> [(String, [String])]` from the
    catalog (falls back to `[]`).
  - Call `loadCatalog()` on init and after each refresh.
- `app/Sources/FmrApp/Models.swift`:
  - Extend `ConfigRepoItem` to decode `path`, `sync_enabled`, `commands`, and
    `rag` (mode) from the real `fmr config` output (they are emitted today but
    not modeled).
- `app/Sources/FmrApp/Views/WorkspaceDashboardView.swift`:
  - Populate the custom-commands section from `customCommands(for:)`.
  - Use `ConfigPaths.repos` in `resolvedPath`-style logic.
- `app/Tests/FmrAppTests/FmrAppTests.swift`: decode a real `fmr config` blob.

## 3. Acceptance Criteria

- [ ] `loadCatalog()` populates kinds, paths, and commands from `fmr config --json`.
- [ ] Kind filters (Zig/Go/Sites/Tools) reflect the actual catalog, not a hardcoded map.
- [ ] Custom-command buttons appear only for repos that define commands, using the catalog argv.
- [ ] `resolvedPath` uses `paths.repos` from the catalog when `RepoStatus.path` is absent.
- [ ] `swift build --package-path app` and `swift test --package-path app` pass.
