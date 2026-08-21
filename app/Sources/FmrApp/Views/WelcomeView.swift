import SwiftUI
import AppKit

/// First-run welcome sheet. Shown when `model.shouldShowWelcome` or via
/// Help > Welcome to Fmr... (forced). Never blocks after hasSeenWelcome.
public struct WelcomeView: View {
    @Bindable var model: WorkspaceViewModel
    @Binding var isPresented: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var dontShowAgain: Bool = false

    public init(model: WorkspaceViewModel, isPresented: Binding<Bool>) {
        self.model = model
        self._isPresented = isPresented
    }

    // Convenience init for previews/tests where binding is constant
    public init(model: WorkspaceViewModel) {
        self.model = model
        self._isPresented = .constant(false)
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Title
            VStack(spacing: 4) {
                Text("Fix My Repository — deterministic workspaces for Conductor + agents")
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Safe, fast-forward workspace manager — never runs reset --hard / checkout --force")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            // 3 cards
            HStack(spacing: 12) {
                WelcomeCard(
                    icon: "folder.badge.plus",
                    title: "1. Add a repo",
                    description: "Drag a folder or use Add Repository… to register a checkout."
                )
                WelcomeCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "2. Sync safely",
                    description: "fmr sync never reset --hard. Refuses on dirty/ahead/diverged."
                )
                WelcomeCard(
                    icon: "point.topleft.down.curvedto.point.filled.bottomright.up",
                    title: "3. Work in worktrees",
                    description: "Conductor contract: primaries in repos/, sessions in worktrees/."
                )
            }

            // CTAs
            HStack(spacing: 10) {
                Button("Add Repository...") {
                    model.isAddRepoPresented = true
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Open workspace.json") {
                    openWorkspaceJSON()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("View Help (⌘?)") {
                    openWindow(id: "help")
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            // Copy line + Dismiss
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("Tip for Claude/Cursor:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("fmr mcp")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                    Button {
                        copyToPasteboard("fmr mcp")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy fmr mcp")
                    Spacer()
                }

                HStack {
                    Toggle("Don't show again", isOn: $dontShowAgain)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .onChange(of: dontShowAgain) { _, newValue in
                            if newValue {
                                model.markWelcomeSeen()
                            } else {
                                model.resetWelcome()
                            }
                        }
                    Spacer()
                    Button("Close") {
                        if dontShowAgain { model.markWelcomeSeen() }
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    Button("Get Started") {
                        if dontShowAgain { model.markWelcomeSeen() }
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            dontShowAgain = model.hasSeenWelcome
        }
    }

    private func openWorkspaceJSON() {
        // Resolve via configPaths fallback or FMRBridge helper that mirrors src/main.zig:578.
        let path: String
        if let reposRoot = model.configPaths?.repos, !reposRoot.isEmpty {
            // Derive parent of repos root is not reliable for config location;
            // use the bridge fallback which checks file existence.
            path = model.resolvedConfigPath
        } else {
            path = FMRBridge.shared.resolveConfigPath()
        }
        let url = URL(fileURLWithPath: path)
        // Ensure parent exists so open reveals file; if file missing, open parent dir.
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(url)
        } else {
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.open(parent)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        isPresented = false
    }

    private func copyToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

private struct WelcomeCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.blue)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// Preview-friendly init wrapper
extension WelcomeView {
    static func preview(model: WorkspaceViewModel) -> some View {
        WelcomeView(model: model, isPresented: .constant(true))
    }
}
