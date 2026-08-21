# Issue 25: GUI Menubar Polish — Notifications, About, Empty States (M1 — Ship)

**Milestone**: M1 v0.2 Ship (`docs/MILESTONES.md`)  
**Area**: GUI (Swift)  
**Size**: S (1–2h)  
**Depends On**: #22 (version), #23 (open)

---

## 1. Goal & Context

The menu-bar app (`app/Sources/FmrApp/FmrApp.swift:15` `MenuBarExtra`) already has pills, sync, doctor sheet, worktree sheets, and Cmd+Shift+O palette. Three papercuts keep it from being a daily driver vs T3’s menu bar:

1. **No feedback when background sync fails** — `syncAll()` (`WorkspaceViewModel.swift:237`) silently updates `lastTaskOutput`; you miss a `refused 3` unless the window is open.
2. **No About/version** — `scripts/build_app.sh` already stamps `CFBundleShortVersionString` from `fmr --version`, but the UI never shows it (`FmrApp.swift:1` has no About).
3. **Empty states are bland** — “No repositories configured.” with no CTA; T3 would prompt “Add repo”.

## 2. Specification

### Files to touch

- `app/Sources/FmrApp/WorkspaceViewModel.swift` — after `syncAll()` / `syncRepo()` completes with `summary.refused > 0 || summary.failed > 0`, post a `NSUserNotification` / `UNUserNotificationCenter` notification: “fmr: 2 refused, 1 failed — click to open Dashboard”. Only when app is in background (`NSApp.isActive == false`). Add `requestNotificationPermission()` on first sync.

- `app/Sources/FmrApp/Views/MenuBarView.swift` — empty-state block (`MenuBarView.swift:50` approx): when `model.repos.isEmpty && !model.isRefreshing`, show “No repositories — Add one” with `Button("Add Repository...") { model.isAddRepoPresented = true }`. Same for `WorkspaceDashboardView.swift` sidebar empty state.

- `app/Sources/FmrApp/FmrApp.swift` — add `.commands` `About` replacement or small `AboutView.swift`: reads `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` and `FMRCoreVersion` (written by `build_app.sh`) and shows “Fmr 0.2.0 (core 0.2.0)”. Add `SettingsLink` → `SettingsView` with paths (`model.reposRoot`, `model.worktreesRoot`).

- `app/Sources/FmrApp/Views/WorkspaceDashboardView.swift` — toolbar `plus` button already there; ensure `Cmd+N` (`FmrApp.swift:26` style) opens AddRepoSheet even from menu bar.

### Design guardrails

- Notifications are opt-in (permission request) and only for failures/refusals, not every sync.
- About view is 2 labels + copy button, not a full preferences pane.
- No App Sandbox — keep `FMRBridge` as today (`FMRBridge.swift:13` helper path first).

## 3. Acceptance Criteria

- [ ] `syncAll` with a mocked failing repo posts a notification when app is backgrounded (manual verify + unit test for notification payload builder).
- [ ] Menu bar popover and dashboard show “Add Repository...” CTA when `repos.isEmpty`.
- [ ] `Fmr > About Fmr` shows `0.2.0` matching `fmr --version`.
- [ ] `swift build --package-path app && swift test --package-path app` green.
