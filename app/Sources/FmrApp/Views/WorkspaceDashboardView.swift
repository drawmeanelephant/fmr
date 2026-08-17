import SwiftUI
import AppKit

public struct WorkspaceDashboardView: View {
    @Bindable var model: WorkspaceViewModel

    public init(model: WorkspaceViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Filter Picker
                Picker("Filter", selection: $model.selectedFilter) {
                    ForEach(RepoFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(8)

                // Repositories List
                List(selection: $model.selectedRepo) {
                    Section("Repositories (\(model.filteredRepos.count))") {
                        ForEach(model.filteredRepos) { repo in
                            DashboardRepoRow(repo: repo, model: model)
                                .tag(repo)
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
                                }
                        }
                    }
                }
                .searchable(text: $model.searchQuery, placement: .sidebar, prompt: "Search repos & branches...")

                Divider()

                // Sidebar Footer: Sync All + Doctor
                HStack {
                    Button {
                        model.syncAll()
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
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            // Detail Area
            if let repo = model.selectedRepo {
                RepoDetailView(repo: repo, model: model)
            } else {
                ContentUnavailableView(
                    "No Repository Selected",
                    systemImage: "folder.badge.gearshape",
                    description: Text("Select a repository from the sidebar to inspect status, snapshots, and commands.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
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
                    model.isTerminalDrawerOpen.toggle()
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
                            Text("No active session worktrees. Agents run isolated feature branches here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
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

                            if repo.name == "boris" {
                                Button("Serve (`fmr run boris serve`)") {
                                    model.runCustomCommand(repoName: "boris", commandName: "serve")
                                }
                                .buttonStyle(.bordered)

                                Button("Site Build (`fmr run boris site`)") {
                                    model.runCustomCommand(repoName: "boris", commandName: "site")
                                }
                                .buttonStyle(.bordered)
                            }

                            if repo.name == "rotkeeper" {
                                Button("Init (`fmr run rotkeeper init`)") {
                                    model.runCustomCommand(repoName: "rotkeeper", commandName: "init")
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

            // Terminal Console Drawer
            if model.isTerminalDrawerOpen {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Task Console Output", systemImage: "apple.terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            model.lastTaskOutput = ""
                        } label: {
                            Text("Clear")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)

                        Button {
                            model.isTerminalDrawerOpen = false
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
            }
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
                    model.removeWorktree(session: session, force: false)
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
