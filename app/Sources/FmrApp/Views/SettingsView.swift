import SwiftUI

public struct SettingsView: View {
    @Bindable var model: WorkspaceViewModel

    public init(model: WorkspaceViewModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("Version") {
                LabeledContent("App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0")
                LabeledContent("Core Version", value: Bundle.main.infoDictionary?["FMRCoreVersion"] as? String ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
            }
            Section("Paths") {
                LabeledContent("Repos Root", value: model.reposRoot)
                LabeledContent("Worktrees Root", value: model.worktreesRoot)
                LabeledContent {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(model.relativeLastUpdated)
                            .font(.caption)
                    }
                } label: {
                    Text("Last Synced")
                }
            }
            Section("About") {
                Text("Fmr — Fix My Repository / Fuckin' Manage Repos.\nDeterministic, local-first workspace manager for Conductor + agents. No fleet, no cloud, no `reset --hard`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
        .padding()
    }
}
