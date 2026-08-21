import SwiftUI
import AppKit

public struct SettingsView: View {
    @Bindable var model: WorkspaceViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var didCopyDebug = false
    @State private var didCopyConfig = false

    public init(model: WorkspaceViewModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("Version") {
                LabeledContent("App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0")
                LabeledContent("Core Version", value: Bundle.main.infoDictionary?["FMRCoreVersion"] as? String ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-")
                HStack {
                    Button {
                        DebugInfoProvider.copyDebugInfo(model: model)
                        withAnimation { didCopyDebug = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { didCopyDebug = false }
                        }
                    } label: {
                        Label(didCopyDebug ? "Copied ✓" : "Copy Debug Info", systemImage: didCopyDebug ? "checkmark.circle.fill" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy debug info for bug reports")
                    Spacer()
                }
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
                // #34: Config path with Open in Finder + Copy Path
                LabeledContent("Config") {
                    HStack(spacing: 6) {
                        Text(model.resolvedConfigPath)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button {
                            let path = model.resolvedConfigPath
                            if FileManager.default.fileExists(atPath: path) {
                                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                            } else {
                                let parent = (path as NSString).deletingLastPathComponent
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parent)
                            }
                        } label: {
                            Label("Open in Finder", systemImage: "folder")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Reveal workspace.json in Finder")

                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(model.resolvedConfigPath, forType: .string)
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                            withAnimation { didCopyConfig = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                withAnimation { didCopyConfig = false }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: didCopyConfig ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.caption2)
                                Text(didCopyConfig ? "Copied ✓" : "Copy Path")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Copy config path")
                    }
                }
            }
            Section("Shortcuts") {
                VStack(alignment: .leading, spacing: 6) {
                    shortcutRow(keys: "⌘R", action: "Refresh Status")
                    shortcutRow(keys: "⌘S", action: "Sync All Repositories")
                    shortcutRow(keys: "⌘D", action: "Run Doctor Diagnostics")
                    shortcutRow(keys: "⌘K", action: "Command Palette")
                    shortcutRow(keys: "⌘N", action: "Add Repository…")
                    shortcutRow(keys: "⇧⌘O", action: "Recent Repositories")
                    Divider()
                    Button("Open Help…") {
                        openWindow(id: "help")
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    .accessibilityLabel("Open Help window")
                }
                .font(.system(size: 11, design: .monospaced))
            }
            Section("About") {
                Text("Fmr — Fix My Repository / Fuckin' Manage Repos.\nDeterministic, local-first workspace manager for Conductor + agents. No fleet, no cloud, no `reset --hard`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Also expose Copy Debug Info here for parity with About panel
                Button {
                    DebugInfoProvider.copyDebugInfo(model: model)
                    withAnimation { didCopyDebug = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { didCopyDebug = false }
                    }
                } label: {
                    Label(didCopyDebug ? "Copied ✓" : "Copy Debug Info", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 480)
        .padding()
    }

    private func shortcutRow(keys: String, action: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
                .accessibilityLabel("\(keys) \(action)")
            Text(action)
                .font(.system(size: 11))
            Spacer()
        }
    }
}
