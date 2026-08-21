# Issue 31: Empty States & Delight — Every Empty List Has a CTA (M3 — Polish)

**Milestone**: M3 v0.4 GUI Polish & Help — Make the next person smile (`docs/MILESTONES.md`)  
**Area**: GUI (Swift) — `MenuBarView`, `WorkspaceDashboardView`, `CommandPaletteView`, sheets  
**Size**: S (1–2h)  
**Depends On**: #30 (Welcome view exists, this refines the other empties)

---

## 1. Goal & Context

`#25` added bare CTA text for empty repos (`app/Sources/FmrApp/Views/MenuBarView.swift:64` + `WorkspaceDashboardView.swift:56`). Still bland: centered caption, no illustration, no reason, no next action beyond one button. Empty filtered results, empty worktrees, empty doctor, empty recents, empty search — all show either nothing or a generic `Text`. A polished app makes empty feel intentional. Think Linear's empty states, not `ls` output.

Current empties to upgrade:
- `MenuBarView.swift:62` — no repos `isRefreshing ? loading : no repos`
- `WorkspaceDashboardView.swift:30` — sidebar filtered list `filteredRepos.isEmpty` vs `repos.isEmpty`
- `WorkspaceDashboardView.swift:391` — detail `sessions.isEmpty` ("No active session worktrees")
- `WorkspaceDashboardView.swift:91` — `selectedRepo == nil` `ContentUnavailableView`
- `DoctorSheetView.swift:74` — `doctorChecks.isEmpty` ("No diagnostics run yet")
- `CommandPaletteView.swift:43` — `filteredList.isEmpty` shows nothing
- `AddRepoSheet.swift:176` local drop zone — static dashed rect with no success state

## 2. Specification

### 2.1 Reusable `EmptyStateView`

Create `app/Sources/FmrApp/Views/EmptyStateView.swift` *(new, ~80 lines)*:

```swift
struct EmptyStateView: View {
  let systemImage: String
  let title: String
  let message: String
  let actionTitle: String?
  let action: (() -> Void)?
}
```

- Uses `ContentUnavailableView` (macOS 14) with `label`, `description`, `actions`. Consistent `font(.title3)` + `.secondary` message + accent button.
- Provide 6 presets as static factories to keep copy consistent:
  - `noRepos` — `folder.badge.plus`, "No repositories yet", "Add a repo or drag a folder…", CTAs: `Add Repository...` + `Open workspace.json`
  - `noSearchResults(query)` — `magnifyingglass`, "No matches for 'foo'", "Try another filter or clear search", CTA: `Clear Search`
  - `noWorktrees(repo)` — `point.topleft.down.curvedto.point.filled.bottomright.up`, "No session worktrees", "Create an isolated branch for an agent", CTA: `New Worktree...`
  - `noDoctor` — `stethoscope`, "Diagnostics not run", CTA: `Run Doctor`
  - `noRecents` — `clock.arrow.circlepath`, "No recent repos", message about clone-and-open
  - `dropReady` — `folder.badge.plus` animated when `isTargeted`

### 2.2 Apply per view

- `MenuBarView.swift:62` — replace `VStack { Text(no repos) + Button... }` with `EmptyStateView.noRepos` (compact variant, maxHeight 120, no illustration scaling large). Keep existing `recents` section below.
- `WorkspaceDashboardView.swift:28` — when `model.repos.isEmpty` show `noRepos`; when `!repos.isEmpty && filteredRepos.isEmpty` show `noSearchResults(model.searchQuery)` with `Clear Search` that `model.searchQuery=""` + `model.selectedFilter=.all`.
- `WorkspaceDashboardView.swift:88` detail `selectedRepo==nil` — keep `ContentUnavailableView` but upgrade message to use preset + show `Cmd+K` hint.
- `WorkspaceDashboardView.swift:406` worktrees — replace `Text("No active session...")` with `EmptyStateView.noWorktrees(repoName:)` + `New Worktree...` button already there remains as secondary CTA.
- `DoctorSheetView.swift:74` — doctor empty shows `noDoctor`; when `doctorChecks.count>0` today already rich, keep but add `Copy All` button.
- `CommandPaletteView.swift:90` — when `filteredList.isEmpty && query.isEmpty==false` show `noSearchResults(query)`; when `repos.isEmpty` show compact `noRepos`.
- `AddRepoSheet.swift:183` — when `isTargeted` animate border + `ScaleEffect(1.02)` + checkmark; when `localDirectory != nil` show green `checkmark.circle.fill` + path, not just text.

### Design guardrails

- One shared view, not 6 different empty designs. One SF Symbol set, one copy voice (friendly, not cutesy; no confetti yet — save for #32).
- No new assets — SF Symbols only.
- Keep existing `onDrop` behavior (`WorkspaceDashboardView.swift:57`, `AddRepoSheet.swift:206`) — just polish visuals.
- **Review fixes (2026-08-21):**
  - Provide `EmptyStateView.Style { case compact, regular }` — menu bar popover (320pt) uses `.compact` (smaller `ContentUnavailableView`, no large illustration), dashboard uses `.regular`. Prevents oversized popover.
  - Don't hide filter pills when repos exist but filtered empty — keep `Picker` visible. CTA `Clear Search` must reset both `searchQuery` and `selectedFilter` (not just query).
  - `ContentUnavailableView` is macOS 14+ only — matches `app/Package.swift:7` `.macOS(.v14)`, safe. No `if #available` needed.
  - Drop zone: confirm `isTargeted` binding animates border `.animation(.easeInOut, value:isTargeted)`. Preview test at 100% + 150% scaling.

### Files to touch

- `app/Sources/FmrApp/Views/EmptyStateView.swift` *(new)*
- `app/Sources/FmrApp/Views/MenuBarView.swift:62`
- `app/Sources/FmrApp/Views/WorkspaceDashboardView.swift:28,88,406`
- `app/Sources/FmrApp/Views/DoctorSheetView.swift:74`
- `app/Sources/FmrApp/Views/CommandPaletteView.swift:90`
- `app/Sources/FmrApp/Views/AddRepoSheet.swift:183`
- `app/Tests/FmrAppTests/EmptyStateTests.swift` *(optional, 2 asserts: factory titles non-empty, clear-search works)*

## 3. Acceptance Criteria

- [ ] Every empty state listed in §1 shows an illustrated `ContentUnavailableView` with title + message + at least one CTA; no bare `Text("No...")` remains in those files. Menu bar uses `.compact`, dashboard uses `.regular`.
- [ ] Filter-by-search with no results shows `Clear Search` button that resets `searchQuery` + `selectedFilter` and restores list (manual + unit). Filter pills remain visible while empty.
- [ ] Dragging a folder over dashboard sidebar or AddRepoSheet shows animated `isTargeted` border/scale feedback; drop succeeds and pre-fills `AddRepoSheet`.
- [ ] `swift test --package-path app` green; no layout warnings in Xcode preview for 320pt menu bar + 800pt dashboard sizes. `zig build test` still green (no CLI touch, but verify no doc break).

### Review notes

Sizing is tight (6 touch points). To stay S, land `EmptyStateView` + 3 empties first (noRepos, noSearch, noWorktrees), then do doctor/palette/drop in same PR if time — don't split across PRs. If it spills to 2h+, it's okay to ship 5/7 empties and file follow-up; dashboard + menu bar empties are must.
