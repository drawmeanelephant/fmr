import SwiftUI

public struct MenuBarView: View {
    @Bindable var model: WorkspaceViewModel
    @Environment(\.openWindow) private var openWindow

    public init(model: WorkspaceViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header: Title & Quick Stats
            HStack {
                Label("fmr", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Status (Cmd+R)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Status Counters Pills
            HStack(spacing: 6) {
                StatusPill(label: "\(model.cleanCount) Clean", color: .green)
                if model.behindCount > 0 {
                    StatusPill(label: "\(model.behindCount) Behind", color: .yellow)
                }
                if model.dirtyCount > 0 {
                    StatusPill(label: "\(model.dirtyCount) Dirty", color: .orange)
                }
                if model.snapStaleCount > 0 {
                    StatusPill(label: "\(model.snapStaleCount) Snap Stale", color: .purple)
                }
                if model.problemCount > 0 {
                    StatusPill(label: "\(model.problemCount) Refused", color: .red)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Repositories List
            ScrollView {
                VStack(spacing: 2) {
                    if model.repos.isEmpty {
                        Text(model.isRefreshing ? "Loading repositories..." : "No repositories configured.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(model.repos) { repo in
                            MenuBarRepoRow(repo: repo, model: model)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)

            // Recent Repositories (remembered onboarding)
            if !model.recentRepos.isEmpty {
                Divider()

                VStack(spacing: 0) {
                    HStack {
                        Text("Recent Repositories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            model.clearRecentRepos()
                        } label: {
                            Text("Clear")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Clear recent repositories")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    ForEach(model.recentRepos) { entry in
                        MenuBarRecentRow(entry: entry, model: model)
                    }
                }
                .padding(.bottom, 4)
            }

            Divider()

            // Footer Actions
            VStack(spacing: 6) {
                if let task = model.activeTaskDescription {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(task)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        model.syncAll()
                    } label: {
                        Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isRefreshing)

                    Button {
                        model.runDoctor(fix: false)
                    } label: {
                        Label("Doctor", systemImage: "stethoscope")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button {
                        openWindow(id: "dashboard")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        Image(systemName: "macwindow.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Open Full Workspace Window")

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Quit")
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 320)
    }
}

// MARK: - Subviews

struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Recent Repository Row

struct MenuBarRecentRow: View {
    let entry: RecentRepoEntry
    let model: WorkspaceViewModel
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    if let kind = entry.kind, !kind.isEmpty {
                        Text(kind)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let url = entry.url, !url.isEmpty {
                        Text(url)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isHovering {
                HStack(spacing: 4) {
                    Button {
                        model.cloneAndOpenRecent(entry)
                    } label: {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Clone & Open \(entry.name)")

                    Button {
                        model.forgetRepo(name: entry.name)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from Recents")
                }
            } else {
                Text(entry.addedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovering ? Color(NSColor.selectedControlColor).opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { isHovering = $0 }
    }
}

struct MenuBarRepoRow: View {
    let repo: RepoStatus
    let model: WorkspaceViewModel
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Status indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(repo.branch.isEmpty ? "default" : repo.branch)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if repo.behind > 0 {
                        Text("↓\(repo.behind)")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if repo.ahead > 0 {
                        Text("↑\(repo.ahead)")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if repo.dirtyTracked > 0 {
                        Text("● \(repo.dirtyTracked)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if repo.untracked > 0 {
                        Text("+\(repo.untracked)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isHovering {
                HStack(spacing: 4) {
                    Button {
                        model.syncRepo(name: repo.name)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Sync \(repo.name)")

                    Button {
                        model.ragRepo(name: repo.name)
                    } label: {
                        Image(systemName: "camera")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Take RAG Snapshot")
                }
            } else {
                Text(repo.snap == "ok" ? "snap ok" : (repo.snap == "stale" ? "snap stale" : ""))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isHovering ? Color(NSColor.selectedControlColor).opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { isHovering = $0 }
    }

    private var statusColor: Color {
        if repo.state != "ok" { return .red }
        if repo.isDirty { return .orange }
        if repo.isBehind { return .yellow }
        return .green
    }
}
