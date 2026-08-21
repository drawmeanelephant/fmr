import SwiftUI
import AppKit

public struct CommandPaletteView: View {
    @Bindable var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var recentsOnly: Bool

    public init(model: WorkspaceViewModel) {
        self.model = model
        // Cmd+Shift+O opens the palette focused on recent repositories.
        self._recentsOnly = State(initialValue: model.paletteFilter == .recents)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search repositories, branches, or commands...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Hint when query empty — #34 discoverability
            if query.isEmpty {
                HStack {
                    Text("Try “Sync All” or type a repo name")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(model.repos.count) repos")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            }

            // Results List — #31 empty states
            Group {
                if !query.isEmpty && filteredList.isEmpty && model.repos.isEmpty {
                    EmptyStateView.noRepos(style: .regular, onAdd: {
                        model.isAddRepoPresented = true
                        dismiss()
                    }, onOpenWorkspace: {
                        let path = model.resolvedConfigPath
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    })
                    .frame(maxHeight: .infinity)
                } else if !query.isEmpty && filteredList.isEmpty && model.repos.count > 0 {
                    EmptyStateView.noSearchResults(query: query, style: .regular, onClear: {
                        query = ""
                    })
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        if recentsOnly {
                            if !filteredRecents.isEmpty {
                                Section("Recent Repositories (\(filteredRecents.count))") {
                                    ForEach(filteredRecents) { entry in
                                        recentRow(entry)
                                    }
                                }
                            } else if !query.isEmpty {
                                Section {
                                    EmptyStateView.noSearchResults(query: query, style: .regular, onClear: { query = "" })
                                        .listRowInsets(EdgeInsets())
                                }
                            } else {
                                Section {
                                    EmptyStateView.noRecents(style: .regular, onBrowse: nil)
                                        .listRowInsets(EdgeInsets())
                                }
                            }

                            Section {
                                Button {
                                    recentsOnly = false
                                    query = ""
                                } label: {
                                    Label("Show All Repositories", systemImage: "list.bullet")
                                }
                            }
                        } else {
                            Section("Quick Actions") {
                                Button {
                                    model.syncAll()
                                    dismiss()
                                } label: {
                                    Label("Sync All Repositories", systemImage: "arrow.triangle.2.circlepath")
                                }

                                Button {
                                    model.ragAll()
                                    dismiss()
                                } label: {
                                    Label("Generate RAG Snapshots for All", systemImage: "camera")
                                }

                                Button {
                                    model.runDoctor(fix: false)
                                dismiss()
                                } label: {
                                    Label("Run Doctor Diagnostics", systemImage: "stethoscope")
                                }

                                Button {
                                    model.runDoctor(fix: true)
                                    dismiss()
                                } label: {
                                    Label("Fix Stale Locks & Staging Directories", systemImage: "wrench.and.screwdriver")
                                }
                            }

                            Section("Repositories (\(filteredList.count))") {
                                ForEach(filteredList) { repo in
                                    Button {
                                        model.selectedRepo = repo
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Circle()
                                                .fill(repo.isClean ? Color.green : (repo.isDirty ? Color.orange : Color.yellow))
                                                .frame(width: 8, height: 8)
                                            Text(repo.name)
                                                .font(.headline)
                                            Spacer()
                                            Text(repo.branch)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }

                            if !filteredRecents.isEmpty {
                                Section("Recent Repositories (\(filteredRecents.count))") {
                                    ForEach(filteredRecents) { entry in
                                        recentRow(entry)
                                    }
                                }
                            } else if query.isEmpty && model.recentRepos.isEmpty {
                                // keep palette quiet when no recents; #31 noRecents only shown in recentsOnly mode
                            }
                        }
                    }
                    .listStyle(.inset)
                    .focusable(true)
                    .onMoveCommand { _ in }
                    .accessibilityLabel("Command palette results")
                }
            }
            .frame(minHeight: 200)

            Divider()
            // Footer legend — #34 discoverability
            HStack(spacing: 8) {
                Text("⌘K palette • ⌘R refresh • ⌘N add • ⇧⌘O recents • ? help")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Text("\(model.repos.count) repos")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("\(model.repos.count) repositories")
            }
            .padding(8)
            .background(.bar)
        }
        .frame(width: 500, height: 420)
    }

    private var filteredList: [RepoStatus] {
        if query.isEmpty { return model.repos }
        return model.repos.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.branch.localizedCaseInsensitiveContains(query)
        }
    }

    /// Recent repos matching the query (falls back to all recents when empty).
    private var filteredRecents: [RecentRepoEntry] {
        if query.isEmpty { return model.recentRepos }
        return model.recentRepos.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.kind ?? "").localizedCaseInsensitiveContains(query) ||
            ($0.url ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private func recentRow(_ entry: RecentRepoEntry) -> some View {
        Button {
            model.cloneAndOpenRecent(entry)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text(entry.name)
                    .font(.headline)
                if let kind = entry.kind, !kind.isEmpty {
                    Text(kind)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                Spacer()
                Label("Clone & Open", systemImage: "arrow.up.right.square.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
