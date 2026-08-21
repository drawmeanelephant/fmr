import SwiftUI
import AppKit

public struct HelpView: View {
    @Bindable var model: WorkspaceViewModel
    @State private var selectedTab: Tab = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case shortcuts = "Shortcuts"
        case concepts = "Concepts"
        var id: String { rawValue }
    }

    public init(model: WorkspaceViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .overview: overviewContent
                    case .shortcuts: shortcutsContent
                    case .concepts: conceptsContent
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 640, height: 520)
    }

    // MARK: - Overview

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Markdown excerpt from README.md §1 Overview + §2 Directory Layout
            let md = """
            ### Overview

            **fmr** — *Fix My Repository* is a fast, safe, deterministic workspace \
            manager for multi-repo development and agentic workflows. Three jobs:

            1. **Repo Catalog** — `workspace.json` declares every repo, URL, branch, kind.
            2. **Safe Primary Sync** — fetch + fast-forward only on primaries. Never clobbers worktrees.
            3. **Deterministic Diagnostics** — `fmr doctor` checks roots, branch hygiene, locks, disk.

            ### Directory Layout

            ```
            ~/dev/drawmeanelephant/   # paths.repos (primaries)
            ~/Code/worktrees/         # paths.worktrees (Conductor sessions)
            ~/Code/source-rag/        # paths.sourceRag (immutable snapshots)
            ~/.fmr/locks/             # per-repo mkdir locks
            ~/config/fmr/workspace.json
            ```

            **Conductor Contract** — primaries hold default_branch; sessions are `git worktree add` \
            under `paths.worktrees/<repo>/<session> -b <branch>`. Agents push branches upstream.
            """
            if let attributed = try? AttributedString(markdown: md) {
                Text(attributed)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            } else {
                Text(.init(md))
                    .font(.system(size: 12))
            }

            HStack(spacing: 10) {
                Button("Open README on GitHub") {
                    if let url = URL(string: "https://github.com/drawmeanelephant/fmr") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Open workspace.example.json") {
                    openWorkspaceExample()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Run fmr doctor") {
                    model.runDoctor(fix: false)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 4)

            // #34 Copy Debug Info — next to panel trigger, as About fallback
            HStack(spacing: 8) {
                Button {
                    DebugInfoProvider.copyDebugInfo(model: model)
                } label: {
                    Label("Copy Debug Info", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy debug info for bug reports")

                Text(DebugInfoProvider.debugString(model: model).components(separatedBy: "\n").first ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Shortcuts

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shortcuts — truth from FmrApp.swift")
                .font(.headline)
            Text("All shortcuts work from the Dashboard window.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Shortcut").font(.caption).bold().foregroundStyle(.secondary)
                    Text("Action").font(.caption).bold().foregroundStyle(.secondary)
                }
                Divider()
                shortcutRow(keys: "⌘R", action: "Refresh Status")
                shortcutRow(keys: "⌘K", action: "Command Palette")
                shortcutRow(keys: "⌘N", action: "Add Repository…")
                shortcutRow(keys: "⇧⌘O", action: "Clone & Open Recent (Recents)")
                shortcutRow(keys: "⌘,", action: "Settings")
                shortcutRow(keys: "⌘?", action: "Fmr Help (this window)")
                shortcutRow(keys: "⌘S", action: "Sync All Repositories")
                shortcutRow(keys: "⌘D", action: "Run Doctor Diagnostics")
            }
            .font(.system(size: 12, design: .monospaced))
        }
    }

    private func shortcutRow(keys: String, action: String) -> some View {
        GridRow {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
            Text(action)
                .font(.system(size: 12))
        }
    }

    // MARK: - Concepts

    private var conceptsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Concepts")
                .font(.headline)

            let pillsMD = """
            **Pills** are derived from `docs/gui/json-contract.md` — never `state == dirty`:

            - **clean** — `state == ok && dirty_tracked == 0 && behind == 0 && ahead == 0`
            - **dirty** — `dirty_tracked > 0` (tracked mods) • pill shows `dirty N`
            - **behind** — `behind > 0` • pill `behind N` • `sync` will `merge --ff-only`
            - **ahead** — `ahead > 0` • refused (exit 3) until pushed
            - **snap ok / stale / none** — `snap == ok` snapshot matches HEAD; `stale` needs `fmr rag`
            - **refused** — `state != ok` (`missing`, `not_repo`, `worktree`, `detached`, `unborn`)
            """

            if let attr = try? AttributedString(markdown: pillsMD) {
                Text(attr).font(.system(size: 11))
            } else {
                Text(.init(pillsMD)).font(.system(size: 11))
            }

            let pausedMD = """
            **Paused vs Enabled** — `paused` is `sync.enabled == false` in config. Paused repos are \
            still shown, but `sync --all` skips them (result `skipped`). Toggle via `workspace.json`.
            """
            if let attr = try? AttributedString(markdown: pausedMD) {
                Text(attr).font(.system(size: 11))
            } else {
                Text(.init(pausedMD)).font(.system(size: 11))
            }

            let primaryMD = """
            **Primary vs Worktree** — `src/state.zig` decision table:

            | Condition | Decision |
            |---|---|
            | missing dir | clone |
            | `.git` is file (is worktree) | refuse `is_worktree` |
            | not a repo | refuse `not_a_repo` |
            | detached / unborn / url_mismatch | refuse |
            | wrong branch (`HEAD != default_branch`) | refuse `wrong_branch` |
            | dirty (`dirty_tracked > 0`) | refuse `dirty` |
            | diverged (`ahead>0 && behind>0`) | refuse `diverged` |
            | ahead only | refuse `ahead` |
            | behind only | `ff_only` |
            | clean & current | `noop` |

            Primaries live in `paths.repos`; worktrees in `paths.worktrees/<repo>/<session>`.
            """
            if let attr = try? AttributedString(markdown: primaryMD, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attr).font(.system(size: 11))
            } else {
                Text(.init(primaryMD)).font(.system(size: 11))
            }
        }
    }

    private func openWorkspaceExample() {
        let candidates = [
            "\(FileManager.default.currentDirectoryPath)/config/workspace.example.json",
            "\(NSHomeDirectory())/config/fmr/workspace.example.json",
            Bundle.main.path(forResource: "workspace.example", ofType: "json") ?? "",
        ]
        for path in candidates where !path.isEmpty {
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return
            }
        }
        // Fallback: open GitHub example
        if let url = URL(string: "https://github.com/drawmeanelephant/fmr/blob/main/config/workspace.example.json") {
            NSWorkspace.shared.open(url)
        }
    }
}
