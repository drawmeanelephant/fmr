import SwiftUI
import UniformTypeIdentifiers

/// Modal sheet for onboarding a repository into the workspace, either from a
/// git remote URL or from an existing local directory (picker or drag-and-drop).
public struct AddRepoSheet: View {
    @Bindable var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    /// When provided (e.g. from drag-and-drop), pre-fills the local-directory fields.
    private let initialDirectory: URL?
    @State private var didApplyInitial = false

    enum Mode: String, CaseIterable, Identifiable {
        case url = "Git URL"
        case local = "Local Directory"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .url
    @State private var urlInput: String = ""
    @State private var name: String = ""
    @State private var kind: String = ""
    @State private var defaultBranch: String = ""
    @State private var syncNow: Bool = true
    @State private var ragNow: Bool = false
    @State private var localDirectory: URL? = nil
    @State private var isTargeted = false
    @State private var errorMessage: String? = nil

    private let kinds = ["zig", "go", "node", "site", "bash", "other"]

    private var derivedName: String {
        if !name.isEmpty { return name }
        if mode == .url {
            return WorkspaceViewModel.nameFromURL(urlInput) ?? ""
        }
        return localDirectory?.lastPathComponent ?? ""
    }

    public init(model: WorkspaceViewModel, initialDirectory: URL? = nil) {
        self.model = model
        self.initialDirectory = initialDirectory
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Add Repository", systemImage: "plus.circle")
                    .font(.title3)
                    .bold()
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Picker("Source", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                switch mode {
                case .url:
                    urlFields
                case .local:
                    localFields
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Repository Name:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. my-project", text: $name)
                        .textFieldStyle(.roundedBorder)
                    if name.isEmpty && !derivedName.isEmpty {
                        Text("Auto-detected: \(derivedName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kind:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Kind", selection: $kind) {
                            Text("(auto)").tag("")
                            ForEach(kinds, id: \.self) { k in
                                Text(k).tag(k)
                            }
                        }
                        .frame(maxWidth: 160)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default Branch (optional):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. main", text: $defaultBranch)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 180)
                    }
                }

                Toggle("Clone & Sync immediately", isOn: $syncNow)
                    .toggleStyle(.switch)
                Toggle("Create initial RAG snapshot", isOn: $ragNow)
                    .toggleStyle(.switch)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add Repository") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(derivedName.isEmpty || (mode == .url && urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let dir = initialDirectory, !didApplyInitial {
                didApplyInitial = true
                mode = .local
                applyLocalDirectory(dir)
            }
        }
    }

    private var urlFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Git Remote URL:")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("git@github.com:org/repo.git or https://github.com/org/repo.git", text: $urlInput)
                .textFieldStyle(.roundedBorder)
                .onChange(of: urlInput) { _, newValue in
                    if name.isEmpty, let n = WorkspaceViewModel.nameFromURL(newValue) {
                        name = n
                    }
                    if kind.isEmpty, let n = WorkspaceViewModel.nameFromURL(newValue), !n.isEmpty {
                        // no kind hint from a URL; leave kind on (auto)
                    }
                }
        }
    }

    private var localFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a local project folder, or drag it here:")
                .font(.caption)
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.15) : (localDirectory != nil ? Color.green.opacity(0.12) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .foregroundStyle(isTargeted ? Color.accentColor : (localDirectory != nil ? Color.green : Color.secondary.opacity(0.5)))
                )
                .frame(height: 64)
                .scaleEffect(isTargeted ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isTargeted)
                .overlay {
                    VStack(spacing: 4) {
                        if let localDirectory {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                Text(localDirectory.path)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                            }
                        } else {
                            Image(systemName: isTargeted ? "folder.badge.plus.fill" : "folder.badge.plus")
                                .font(.title2)
                                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                                .scaleEffect(isTargeted ? 1.15 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isTargeted)
                            Text(isTargeted ? "Drop to add" : "Drop folder here")
                                .font(.caption)
                                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                            if isTargeted {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                }

            Button {
                openPicker()
            } label: {
                Label("Browse...", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
    }

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
                    applyLocalDirectory(url)
                }
            }
        }
        return true
    }

    private func openPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        if panel.runModal() == .OK, let url = panel.url {
            applyLocalDirectory(url)
        }
    }

    private func applyLocalDirectory(_ url: URL) {
        localDirectory = url
        if name.isEmpty {
            name = url.lastPathComponent
        }
        if kind.isEmpty {
            kind = WorkspaceViewModel.detectKind(in: url) ?? ""
        }
        if urlInput.isEmpty {
            urlInput = model.remoteURL(forLocalDirectory: url) ?? ""
        }
        errorMessage = nil
    }

    private func submit() {
        let finalName = derivedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalName.isEmpty else { return }
        let finalURL = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        model.addRepository(
            name: finalName,
            url: finalURL.isEmpty ? nil : finalURL,
            kind: kind.isEmpty ? nil : kind,
            defaultBranch: defaultBranch.isEmpty ? nil : defaultBranch,
            syncNow: syncNow,
            ragNow: ragNow
        )
        dismiss()
    }
}
