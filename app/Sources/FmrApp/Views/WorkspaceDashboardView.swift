import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct WorkspaceDashboardView: View {
    @Bindable var model: WorkspaceViewModel
    @State private var pendingRemoveRepo: RepoStatus? = nil
    @State private var pendingAddDirectory: URL? = nil
    @State private var showWelcome: Bool = false
    @State private var isSidebarTargeted: Bool = false
    @State private var sidebarSyncFeedback: String? = nil
    @Environment(\.openWindow) private var openWindow

    public init(model: WorkspaceViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Filter Picker — keep visible even when filtered empty (#31)
                Picker("Filter", selection: $model.selectedFilter) {
                    ForEach(RepoFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)

                // Repositories List — #31 empties, #32 skeletons + transitions
                Group {
                    if model.isRefreshing && model.repos.isEmpty && !model.catalogLoaded {
                        RedactedPlaceholderView()
                            .transition(.opacity)
                            .padding(.horizontal, 8)
                    } else if model.repos.isEmpty {
                        EmptyStateView.noRepos(style: .regular, onAdd: {
                            model.isAddRepoPresented = true
                        }, onOpenWorkspace: {
                            let path = model.resolvedConfigPath
                            let url = URL(fileURLWithPath: path)
                            if FileManager.default.fileExists(atPath: path) {
                                NSWorkspace.shared.open(url)
                            } else {
                                NSWorkspace.shared.open(url.deletingLastPathComponent())
                            }
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if model.filteredRepos.isEmpty {
                        EmptyStateView.noSearchResults(query: model.searchQuery, style: .regular, onClear: {
                            model.searchQuery = ""
                            model.selectedFilter = .all
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selection: $model.selectedRepo) {
                            Section("Repositories (\(model.filteredRepos.count))") {
                                ForEach(model.filteredRepos) { repo in
                                    DashboardRepoRow(repo: repo, model: model)
                                        .tag(repo)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                        .contextMenu {
                                            Button("Sync") { model.syncRepo(name: repo.name) }
                                            Button("Check") { model.checkRepo(name: repo.name) }
                                            Button("RAG Snapshot") { model.ragRepo(name: repo.name) }
                                            Divider()
                                            Button("New Worktree...") {
                                                model.selectedRepo = repo
                                                model.isCreateWorktreePresented = true
                                            }
                                            Divider()
                                            Button("Open in Cursor") { model.openIn(editor: .cursor, path: repo.resolvedPath) }
                                            Button("Open in VS Code") { model.openIn(editor: .vscode, path: repo.resolvedPath) }
                                            Button("Open in Zed") { model.openIn(editor: .zed, path: repo.resolvedPath) }
                                            Button("Open in Terminal") { model.openIn(editor: .terminal, path: repo.resolvedPath) }
                                            Button("Reveal in Finder") { model.openIn(editor: .finder, path: repo.resolvedPath) }
                                            Divider()
                                            Button("Remove Repository...", role: .destructive) {
                                                pendingRemoveRepo = repo
                                            }
                                        }
                                }
                            }
                        }
                        .animation(.spring(duration: 0.35), value: model.repos.map(\.id))
                    }
                }
                .searchable(text: $model.searchQuery, placement: .sidebar, prompt: "Search repos & branches...")
                .onDrop(of: [UTType.fileURL], isTargeted: $isSidebarTargeted) { providers in
                    handleDrop(providers)
                }
                .animation(.easeInOut(duration: 0.2), value: isSidebarTargeted)
                .overlay {
                    if isSidebarTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .background(Color.accentColor.opacity(0.08))
                            .scaleEffect(1.02)
                            .padding(4)
                            .allowsHitTesting(false)
                    }
                }
                Divider()

                // Sidebar Footer: Sync All + Doctor + Freshness (#32)
                VStack(spacing: 6) {
                    if let sidebarSyncFeedback {
                        HStack(spacing: 4) {
                            Image(systemName: sidebarSyncFeedback.contains("refused") ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(sidebarSyncFeedback.contains("refused") ? Color.orange : Color.green)
                            Text(sidebarSyncFeedback)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .transition(.opacity)
                    }
                    HStack {
                        Button {
                            triggerSidebarSyncAll()
                        } label: {
                            Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isRefreshing)

                        Spacer()

                        Button {
                            model.runDoctor(fix: false)
                        } label: {
                            Label("Doctor", systemImage: "stethoscope")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("Last synced: \(model.relativeLastUpdated)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            // Detail Area
            if let repo = model.selectedRepo {
                RepoDetailView(repo: repo, model: model)
            } else {
                EmptyStateView.noSelection(style: .regular, onOpenPalette: {
                    model.paletteFilter = .all
                    model.isCommandPalettePresented = true
                })
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    model.isAddRepoPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Repository (Cmd+N)")
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    model.paletteFilter = .all
                    model.isCommandPalettePresented = true
                } label: {
                    Image(systemName: "command")
                }
                .help("Command Palette (Cmd+K)")
                .keyboardShortcut("k", modifiers: .command)

                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Status (Cmd+R)")

                Button {
                    model.runDoctor(fix: false)
                } label: {
                    Image(systemName: "stethoscope")
                }
                .help("Run Offline Diagnostics")

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        model.isTerminalDrawerOpen.toggle()
                    }
                } label: {
                    Image(systemName: "terminal")
                }
                .help("Toggle Terminal Output Drawer")
            }
        }
        .sheet(isPresented: $model.isDoctorSheetPresented) {
            DoctorSheetView(model: model)
        }
        .sheet(isPresented: $model.isCreateWorktreePresented) {
            if let repo = model.selectedRepo {
                CreateWorktreeSheet(repoName: repo.name, model: model)
            }
        }
        .sheet(isPresented: $model.isCommandPalettePresented) {
            CommandPaletteView(model: model)
        }
        .sheet(isPresented: $model.isAddRepoPresented) {
            AddRepoSheet(model: model, initialDirectory: pendingAddDirectory)
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView(model: model, isPresented: $showWelcome)
        }
        .onAppear {
            if model.shouldShowWelcome {
                showWelcome = true
            }
        }
        .onChange(of: model.shouldShowWelcome) { _, newValue in
            if newValue { showWelcome = true }
        }
        .onChange(of: model.isWelcomeForced) { _, newValue in
            if newValue {
                showWelcome = true
                model.clearForcedWelcome()
            }
        }
        .confirmationDialog(
            "Remove repository '\(pendingRemoveRepo?.name ?? "")' from the workspace?",
            isPresented: Binding(
                get: { pendingRemoveRepo != nil },
                set: { if !$0 { pendingRemoveRepo = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let repo = pendingRemoveRepo {
                    model.removeRepository(name: repo.name)
                }
                pendingRemoveRepo = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoveRepo = nil
            }
        } message: {
            Text("This removes '\(pendingRemoveRepo?.name ?? "")' from workspace.json. The repository folder on disk is left untouched.")
        }
    }

    private func triggerSidebarSyncAll() {
        model.syncAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let out = model.lastTaskOutput
            let feedback: String
            if out.contains("refused") || out.contains("failed") {
                let problems = model.problemCount
                feedback = problems > 0 ? "\(problems) refused → see banner" : "Sync finished with issues"
            } else {
                feedback = "Synced ✓"
            }
            withAnimation { sidebarSyncFeedback = feedback }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation { sidebarSyncFeedback = nil }
            }
        }
    }

    /// Handles dropping a folder (or git URL file) onto the sidebar to onboard it.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL? = if let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                URL(fileURLWithPath: s)
            } else if let u = item as? URL {
                u
            } else { nil }
            if let url {
                DispatchQueue.main.async {
                    pendingAddDirectory = url
                    model.isAddRepoPresented = true
                }
            }
        }
        return true
    }
}

// MARK: - Sidebar Row with Nested Worktrees

struct DashboardRepoRow: View {
    let repo: RepoStatus
    let model: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(repo.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if repo.isClean {
                    Text("clean")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if repo.isDirty {
                    Text("dirty \(repo.dirtyTracked)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if repo.isBehind {
                    Text("behind \(repo.behind)")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }

            HStack {
                Label(repo.branch.isEmpty ? "default" : repo.branch, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if repo.snap == "ok" {
                    Label("snap ok", systemImage: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Nested active worktrees if any
            if let sessions = model.worktreesByRepo[repo.name], !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sessions) { s in
                        HStack(spacing: 4) {
                            Image(systemName: "point.topleft.down.curvedto.point.filled.bottomright.up")
                                .font(.system(size: 9))
                                .foregroundStyle(.blue)
                            Text(s.sessionName)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 12)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if repo.state != "ok" { return .red }
        if repo.isDirty { return .orange }
        if repo.isBehind { return .yellow }
        return .green
    }
}

// MARK: - Repo Detail View

struct RepoDetailView: View {
    let repo: RepoStatus
    @Bindable var model: WorkspaceViewModel
    @State private var forceRag = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(repo.name)
                                    .font(.system(size: 26, weight: .bold))

                                if let k = repo.kind {
                                    Text(k.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                            }

                            HStack(spacing: 8) {
                                Label(repo.branch.isEmpty ? "default_branch" : repo.branch, systemImage: "arrow.triangle.branch")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if !repo.head.isEmpty {
                                    Text(repo.head)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                if let url = repo.url {
                                    Text(url)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer()

                        // Action Buttons
                        HStack(spacing: 8) {
                            Button {
                                model.syncRepo(name: repo.name)
                            } label: {
                                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                model.checkRepo(name: repo.name)
                            } label: {
                                Label("Check", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.bordered)

                            Menu {
                                Section("Open Repository in:") {
                                    ForEach(CodeEditor.allCases) { editor in
                                        Button {
                                            model.openIn(editor: editor, path: repo.resolvedPath)
                                        } label: {
                                            Label(editor.rawValue, systemImage: editor.iconName)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    .padding(.bottom, 4)

                    // Cards Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(
                            title: "Working Tree",
                            value: repo.isClean ? "Clean" : "\(repo.dirtyTracked) Modified",
                            subtitle: "\(repo.untracked) untracked files",
                            icon: "doc.badge.gearshape",
                            color: repo.isClean ? .green : .orange
                        )

                        MetricCard(
                            title: "Remote Sync",
                            value: repo.behind > 0 ? "\(repo.behind) Behind" : (repo.ahead > 0 ? "\(repo.ahead) Ahead" : "Up to Date"),
                            subtitle: repo.state == "ok" ? "Fast-forwardable" : "State: \(repo.state)",
                            icon: "icloud.and.arrow.down",
                            color: repo.behind > 0 ? .yellow : (repo.state == "ok" ? .green : .red)
                        )

                        MetricCard(
                            title: "Conductor Sessions",
                            value: "\(sessions.count) Active",
                            subtitle: "Session worktrees in ~/Code",
                            icon: "person.2.badge.gearshape",
                            color: .blue
                        )
                    }

                    // Conductor Worktrees Management Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Conductor Worktrees (\(sessions.count))", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                                .font(.headline)

                            Spacer()

                            Button {
                                model.isCreateWorktreePresented = true
                            } label: {
                                Label("New Worktree...", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }

                        if sessions.isEmpty {
                            EmptyStateView.noWorktrees(repoName: repo.name, style: .regular, onCreate: {
                                model.isCreateWorktreePresented = true
                            })
                        } else {
                            VStack(spacing: 8) {
                                ForEach(sessions) { s in
                                    WorktreeSessionRow(session: s, model: model)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // RAG Snapshot Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Immutable RAG Snapshots", systemImage: "camera")
                                .font(.headline)

                            Spacer()

                            Toggle("Force Re-export", isOn: $forceRag)
                                .toggleStyle(.switch)
                                .controlSize(.small)

                            Button {
                                model.ragRepo(name: repo.name, force: forceRag)
                            } label: {
                                Label("Take Snapshot (`fmr rag`)", systemImage: "arrow.up.doc")
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Text("Current status:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(repo.snap.uppercased())
                                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                .foregroundStyle(repo.snap == "ok" ? .green : .purple)
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    // Custom Commands Section
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Custom Commands", systemImage: "terminal")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Button("Run Check (`fmr check`)") {
                                model.checkRepo(name: repo.name)
                            }
                            .buttonStyle(.bordered)

                            ForEach(model.customCommands(for: repo.name), id: \.0) { command, _ in
                                Button(command.localizedCapitalized) {
                                    model.runCustomCommand(repoName: repo.name, commandName: command)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding(20)
            }

            // Terminal Console Drawer — animated + copy feedback
            if model.isTerminalDrawerOpen {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Task Console Output", systemImage: "apple.terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyOutput()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.caption2)
                                Text(copied ? "Copied ✓" : "Copy")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.borderless)
                        .help("Copy console output")
                        Button {
                            model.lastTaskOutput = ""
                        } label: {
                            Text("Clear")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)

                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                model.isTerminalDrawerOpen = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }

                    ScrollView {
                        Text(model.lastTaskOutput.isEmpty ? "No task execution output yet." : model.lastTaskOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .background(Color.black.opacity(0.04))
                    .cornerRadius(6)
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor))
                .transition(.move(edge: .bottom))
            }
        }
        .confirmationDialog(
            "Remove worktree '\(model.pendingRemoveSession?.sessionName ?? "")'?",
            isPresented: $model.isConfirmRemoveWorktreePresented,
            titleVisibility: .visible
        ) {
            Button("Remove (discard uncommitted changes)", role: .destructive) {
                model.confirmRemoveWorktree(force: true)
            }
            Button("Cancel", role: .cancel) {
                model.isConfirmRemoveWorktreePresented = false
                model.pendingRemoveSession = nil
            }
        } message: {
            Text("This worktree has uncommitted changes. Removing with --force discards them.")
        }
    }

    private func copyOutput() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(model.lastTaskOutput, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { copied = false }
        }
    }

    private var sessions: [WorktreeSession] {
        model.worktreesByRepo[repo.name] ?? []
    }
}

// MARK: - Worktree Session Row

struct WorktreeSessionRow: View {
    let session: WorktreeSession
    let model: WorkspaceViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.sessionName)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                Text(session.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                ForEach(CodeEditor.allCases) { editor in
                    Button {
                        model.openIn(editor: editor, path: session.path)
                    } label: {
                        Label("Open in \(editor.rawValue)", systemImage: editor.iconName)
                    }
                }

                Divider()

                Button("Remove Worktree", role: .destructive) {
                    model.requestRemoveWorktree(session)
                }
            } label: {
                Label("Open in...", systemImage: "arrow.up.right.square")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
