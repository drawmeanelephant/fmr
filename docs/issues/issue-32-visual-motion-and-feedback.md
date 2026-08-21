# Issue 32: Visual Motion & Feedback — Alive, Not Static (M3 — Polish)

**Milestone**: M3 v0.4 GUI Polish & Help — Make the next person smile (`docs/MILESTONES.md`)  
**Area**: GUI (Swift) — `FmrApp`, `WorkspaceViewModel`, `MenuBarView`, `WorkspaceDashboardView`, `StatusPill`  
**Size**: S (1–2h)  
**Depends On**: #31 (empty states done, now motion)

---

## 1. Goal & Context

The app works but feels *static*: list appears instantly, menu bar icon is always `arrow.triangle.2.circlepath`, pills snap without transition, terminal drawer toggles without animation, and there's no sense of "freshness". Compare T3/Linear: icon reflects state, rows animate in, last-synced recency is humanized, and actions have micro-feedback. Goal is perceived speed + aliveness with <150 lines of SwiftUI modifiers.

Today:
- `app/Sources/FmrApp/FmrApp.swift:15` `MenuBarExtra` systemImage fixed.
- `app/Sources/FmrApp/WorkspaceViewModel.swift:154` `startAutoRefresh(interval:15)` refreshes but `lastUpdated: Date?` only set, never displayed as relative string.
- `app/Sources/FmrApp/Views/MenuBarView.swift:12` pills have no animation.
- `app/Sources/FmrApp/Views/WorkspaceDashboardView.swift:120` toolbar buttons no progress UX beyond `ProgressView` when `isRefreshing`.
- No skeletons — first `refresh()` shows blank list until `bridge.run(["status"])` returns.
- Terminal drawer `isTerminalDrawerOpen:32` toggles without animation; no copy-feedback.

## 2. Specification

### 2.1 Dynamic menu bar icon

- In `FmrApp.swift:15` compute `menuBarImage` from `model.problemCount / behindCount / dirtyCount` (mirrors `statusColor` in `MenuBarRepoRow.swift:348`):
  - `problemCount>0` → `exclamationmark.octagon.fill` 
  - `behindCount>0` → `arrow.down.circle.fill`
  - `dirtyCount>0` → `pencil.circle.fill`
  - else `checkmark.circle.fill`
  - **Limitation flagged in review:** `MenuBarExtra(systemImage:)` is monochrome template — color tint via `.foregroundStyle(.red)` is ignored in menu bar. So we use *shape* change, not color, for at-a-glance. Keep pills (`StatusPill` in `MenuBarView.swift:40`) as the colored signal. Document this in code comment: "icon shape signals, pills signal color" so future doesn't chase tint hack.
- Add `.animation(.easeInOut(duration:0.3), value: model.problemCount)` to pills and icon. Use `value: model.repos.map(\.id)` for list, not `model.problemCount` alone, so bulk sync animates rows.
- Keep `LSUIElement` (menu bar only) — no dock bounce yet.

### 2.2 Humanized freshness

- New `relativeLastUpdated: String` in `WorkspaceViewModel.swift:48` using `RelativeDateTimeFormatter` ("just now", "2m ago", "12:04 PM"). Add `freshnessTimer: Timer?` that fires every 30s and triggers `objectWillChange.send()` (not `refresh()`) so SwiftUI re-renders relative string. Invalidate in `stopAutoRefresh()` + `deinit`.
- Show in `MenuBarView.swift:35` header subtitle + `WorkspaceDashboardView.swift:14` sidebar footer: `Last synced: 2m ago` with `Image(systemName: "clock")`.
- Also show in `SettingsView.swift:18` Paths section. When `lastUpdated==nil` (never synced) show "never" not blank.

### 2.3 Skeletons + transitions

- When `isRefreshing && repos.isEmpty && catalogLoaded==false` show `RedactedPlaceholderView` (3 rows with `.redacted(reason: .placeholder)` + shimmer via `opacity` pulse at 1.2s). Replace today blank menu bar until load. **Do NOT show skeleton when filtered empty** (`repos.count>0 && filteredRepos.isEmpty`) — that's #31's empty state, not a loading state. Guard is `isRefreshing && repos.isEmpty` only.
- List inserts: `ForEach(...).transition(.opacity.combined(with: .move(edge: .top)))` + `.animation(.spring(duration:0.35), value: model.repos)` inside `List`, not wrapping `ScrollView` (otherwise scroll jitter). Keep performant — animate only row opacity, not layout.

### 2.4 Micro-feedback

- `MenuBarView.swift:134` `Sync All` / `WorkspaceDashboardView.swift:64` `Sync All` — after `syncAll()` completes, store `@State private var syncFeedback: String?` in view, show `checkmark.circle.fill` + "Synced" for 1.2s via `withAnimation` then fade via `DispatchQueue.main.asyncAfter`. If `refused||failed>0` show `exclamation` + compact `RemediationBanner` preview (don't repeat full banner from #33 — just "2 refused → see banner").
- Terminal drawer `WorkspaceDashboardView.swift:485` — animate `if isTerminalDrawerOpen` with `.transition(.move(edge: .bottom))` + copy button that shows "Copied ✓" for 1s (`Pasteboard` + local `@State copied` Bool). Haptics via `NSHapticFeedbackManager.perform(.generic)` on success/fail. Use `NSHapticFeedbackManager` not `NSHaptics` (macOS 14 name).

### Refinement from review

- Scope is view-only mutations — safe to land mid-sprint even with other M3 work in flight. No `FMRBridge` logic change. If perf regresses (animation jank with 13 rows), gate animation with `withAnimation(.easeInOut(duration:0.2))` instead of spring.

### Design guardrails

- No heavy animation libs. Use SwiftUI `.animation` + `.transition` only. Keep auto-refresh 15s (`FmrApp.swift:10`) — motion must not trigger extra `fmr` calls.
- Keep tests green: motion code is view-only; no logic change to `FMRBridge`.

### Files to touch

- `app/Sources/FmrApp/FmrApp.swift:15` — dynamic icon
- `app/Sources/FmrApp/WorkspaceViewModel.swift:46` — `relativeLastUpdated` + timer
- `app/Sources/FmrApp/Views/MenuBarView.swift:35,40,62` — pills animation, freshness, redacted
- `app/Sources/FmrApp/Views/WorkspaceDashboardView.swift:485,14` — skeletons, transitions, drawer animation
- `app/Sources/FmrApp/Views/RedactedPlaceholderView.swift` *(new, ~40 lines)*
- `app/Sources/FmrApp/Views/SettingsView.swift:18` — show lastUpdated

## 3. Acceptance Criteria

- [ ] Menu bar icon changes shape when `problemCount` goes 0→>0 without app restart (manual: dirty a repo, observe icon `checkmark.circle.fill` → `exclamationmark.octagon.fill`). Color stays template; pills provide color.
- [ ] Dashboard sidebar and menu bar header show `Last synced: X` (e.g. "just now"), updating every 30s without extra `fmr status` calls; shows "never" when `lastUpdated==nil`.
- [ ] Cold launch (`repos.isEmpty && isRefreshing`) shows 3 redacted placeholder rows then crossfades to real list (no flash of empty). Filtered empty shows #31 empty state, not skeleton.
- [ ] `Sync All` tap shows transient "Synced ✓" or "2 refused" feedback for 1.2s; `Copy` in terminal drawer shows "Copied ✓" with haptic.
- [ ] `swift test --package-path app` green; no SwiftUI runtime warnings; dark/light both checked via Xcode preview or `t3-code_preview_set_appearance`. Timers invalidated on `deinit`.

### Review notes

This is the most visible "slickness" slice — keep it small. If dynamic icon proves flaky with `MenuBarExtra`, fallback is static icon + colored dots in popover — still a win. Don't block on icon tint investigation >20min.
