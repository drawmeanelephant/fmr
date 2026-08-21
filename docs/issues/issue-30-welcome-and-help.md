# Issue 30: Welcome & Help — First-Run Guidance and In-App Help (M3 — Polish)

**Milestone**: M3 v0.4 GUI Polish & Help — Make the next person smile (`docs/MILESTONES.md`)  
**Area**: GUI (Swift) — onboarding + help  
**Size**: S (1–2h)  
**Depends On**: None — can land first; others reference its Help window

---

## 1. Goal & Context

A stranger `git clone`s fmr, builds `Fmr.app`, opens it and sees 13 gray pills. No guidance what `fmr` is, what `clean/dirty/behind/snap` mean, or how `repos` vs `worktrees` vs `source-rag` play together. Today there is no `Help` menu at all (`app/Sources/FmrApp/FmrApp.swift:25` only replaces `.appInfo` + `.newItem`), no welcome sheet, and `fmr --help` (`src/main.zig:604`) is 2 lines.

T3 wins on polish because it *teaches* you. fmr should make the next person smile with a 30-second "aha": what this tool is, where repos live, and how to add one.

## 2. Specification

### 2.1 First-run Welcome Sheet

- Show once (persist `hasSeenWelcome_v1` in `UserDefaults`) when `repos.isEmpty && catalogLoaded && !isRefreshing`, or via `Help > Welcome to Fmr...`.
- Content (SwiftUI `WelcomeView.swift`, presented `.sheet` from `WorkspaceDashboardView.swift:1`):
  - Title: "Fix My Repository — deterministic workspaces for Conductor + agents"
  - 3 cards with SF Symbols: `1. Add a repo` (drag folder or `Add Repository...`), `2. Sync safely` (`fmr sync` never `reset --hard`, `docs/ARCHITECTURE.md:64`), `3. Work in worktrees` (Conductor contract `README.md:52`)
  - CTAs: `Add Repository...` (`model.isAddRepoPresented = true`), `Open workspace.json` (`NSWorkspace.open(configPath)` from `model.configPaths` or derived `~/config/fmr/workspace.json`), `View Help (⌘?)`
  - Dismiss: `Don't show again` checkbox. Copy line: `fmr mcp` for Claude/Cursor.
- No onboarding flow that blocks — dismissable, never modal on empty workspace after first seen.

### 2.2 In-App Help Window

- New `HelpView.swift` + `Help > Fmr Help (⌘?)` menu (`FmrApp.swift:25` `.commands { CommandGroup(replacing: .help) }`).
- WindowGroup `help` id, sized 640×520, `help` command palette entry.
- Tabs (Segmented Picker): `Overview`, `Shortcuts`, `Concepts`.
  - **Overview**: renders markdown excerpt from `README.md:1` (1. Overview + 2. Directory Layout) + link buttons: `Open README on GitHub` (`https://github.com/drawmeanelephant/fmr`), `Open workspace.example.json` (`config/workspace.example.json:1`), `Run fmr doctor`.
  - **Shortcuts**: table of `Cmd+R` refresh, `Cmd+K` palette, `Cmd+N` add, `Cmd+Shift+O` recents, `Cmd+,` settings. Pull from `FmrApp.swift:38` shortcuts so Help is truth.
  - **Concepts**: explain pills (`clean`/`dirty`/`behind`/`snap ok/stale`/`refused` from `docs/gui/json-contract.md:58`), paused vs enabled, primary vs worktree (`src/state.zig` decision table).
- Keep markdown simple: use `Text(.init(markdown))` or `AttributedString(markdown:)` — no third-party dep.

### 2.3 CLI `--help` same lesson

- `src/main.zig:604 help()` — extend from 3 lines to ~15: include one-line safety promise, list all commands grouped (`inspect: status/list/context/grep` `mutate: sync/rag` `run: check/run/open` `system: doctor/config/completion/mcp/daemon`), and a `Tips:` line: `fmr context | pbcopy  •  fmr grep TODO --kind zig  •  eval "$(fmr completion zsh)"`.

### Design guardrails

- No new dependencies. No network. Help content is bundled strings + local file open; GitHub links are `NSWorkspace.open(url)`.
- TipKit optional — if added, keep tips dismissable and <2 total (welcome + palette).
- Respect `UserDefaults` for `hasSeenWelcome`; no telemetry.
- **Review fixes (2026-08-21):**
  - Welcome sheet is owned by this issue; #34 must not recreate `CommandGroup(replacing:.help)` — it only *adds* items to the Help menu created here. This avoids duplicate `replacing:.help` conflict.
  - Key is namespaced `fmr.hasSeenWelcome.v1` (not bare `hasSeenWelcome_v1`). Reset via `defaults remove fmr.hasSeenWelcome.v1` and via `Help > Welcome...` always forces show.
  - Welcome must NOT fire in SwiftUI previews or tests: guard with `ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil` and `#if DEBUG` preview check. Otherwise CI screenshots get stuck.
  - "Open workspace.json" button resolves path via `model.configPaths?.configFilePath` if available, else `FMRBridge.resolveConfigPath()` (`~/config/fmr/workspace.json` → `~/config/yard/workspace.json` fallback from `src/main.zig:578`). Copy the fallback logic; don't hardcode `~/config/fmr/workspace.json`.
  - CLI `--help` enhancement stays color-aware via `src/ui.zig:10` `Printer` (respects `NO_COLOR` + TTY). Keep line length <100 for `less` paging.

### Files to touch

- `app/Sources/FmrApp/FmrApp.swift:25` — add `CommandGroup(replacing: .help)` + `WindowGroup("Fmr Help", id: "help")`.
- `app/Sources/FmrApp/Views/WelcomeView.swift` *(new, ~120 lines)* — welcome sheet.
- `app/Sources/FmrApp/Views/HelpView.swift` *(new, ~180 lines)* — help window.
- `app/Sources/FmrApp/Views/WorkspaceDashboardView.swift:1` — trigger welcome sheet on appear when empty.
- `app/Sources/FmrApp/WorkspaceViewModel.swift:60` — `hasSeenWelcome` UserDefaults key, `shouldShowWelcome` computed.
- `src/main.zig:604` — richer `help()` output.
- Optional: `app/Tests/FmrAppTests/HelpViewTests.swift` — welcome flag persistence.

## 3. Acceptance Criteria

- [ ] Fresh `UserDefaults` (`defaults delete fmr.hasSeenWelcome.v1`) + empty catalog → opening Dashboard shows Welcome sheet with 3 cards + `Add Repository...` works; checking `Don't show again` persists and welcome doesn't reappear on next launch. `Help > Welcome to Fmr...` always forces it.
- [ ] `Help > Fmr Help (⌘?)` opens Help window (distinct `WindowGroup(id:"help")` from Settings) with 3 tabs; Shortcuts tab matches actual `FmrApp.swift` shortcuts; Concepts tab correctly derives pills from `docs/gui/json-contract.md` (e.g. `dirty = dirty_tracked>0` not `state==dirty`). No preview/test triggers welcome.
- [ ] `fmr --help` / `fmr -h` prints grouped commands + `Tips:` line and still exits 0; `fmr --help | cat` has no ANSI when not TTY is fine, but `NO_COLOR` respected. `zig fmt --check` clean.
- [ ] No App Sandbox added; `swift test --package-path app` + `zig build test` green. No duplicate `CommandGroup(replacing:.help)` in codebase after #30+#34.

### Review notes (why this is S, not M)

Welcome is 1 view + 1 flag + help menu. Keeping markdown via `AttributedString(markdown:)` prevents adding a renderer dep. If Help grows (searchable), split out — don't bloate this issue.
