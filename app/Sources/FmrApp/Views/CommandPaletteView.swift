import SwiftUI

public struct CommandPaletteView: View {
    @Bindable var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    public init(model: WorkspaceViewModel) {
        self.model = model
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

            // Results List
            List {
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
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 500, height: 380)
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
}
