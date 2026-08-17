import SwiftUI

public struct CreateWorktreeSheet: View {
    let repoName: String
    @Bindable var model: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sessionName: String = ""
    @State private var branchName: String = ""

    public init(repoName: String, model: WorkspaceViewModel) {
        self.repoName = repoName
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label("New Session Worktree", systemImage: "plus.rectangle.on.rectangle")
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

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Repository:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(repoName)
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Folder Name:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. session-auth-flow", text: $sessionName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("New Branch Name:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. feat/auth-flow", text: $branchName)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Worktree will be created under ~/Code/worktrees/\(repoName)/\(sessionName.isEmpty ? "<session>" : sessionName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

                Button("Create Worktree") {
                    let sName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let bName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !sName.isEmpty && !bName.isEmpty else { return }

                    model.createWorktree(repoName: repoName, sessionName: sName, branch: bName)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(sessionName.isEmpty || branchName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            let timestamp = Int(Date().timeIntervalSince1970) % 10000
            sessionName = "session-\(timestamp)"
            branchName = "feat/agent-\(timestamp)"
        }
    }
}
