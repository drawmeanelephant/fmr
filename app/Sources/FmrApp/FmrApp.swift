import SwiftUI
import AppKit

/// Helper view that provides the Help menu buttons with openWindow environment.
/// This is the single owner of the Help menu (CommandGroup(replacing: .help))
/// for M3 #30. Future #34 must only add items inside this group, not create
/// another CommandGroup(replacing: .help), to avoid duplicate replacement conflict.
private struct HelpCommandsView: View {
    @Bindable var model: WorkspaceViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Fmr Help...") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
        Button("Keyboard Shortcuts...") { openWindow(id: "help") }
        Button("Welcome to Fmr...") { model.forceShowWelcome() }
        Divider()
        Button("Copy Debug Info") {
            DebugInfoProvider.copyDebugInfo(model: model)
        }
    }
}

@main
struct FmrApp: App {
    @State private var model = WorkspaceViewModel()

    init() {
        // Start background auto-refresh
        _model.wrappedValue.startAutoRefresh(interval: 15.0)
    }

    /// Dynamic menu bar icon — shape signals state, pills signal color.
    /// `MenuBarExtra(systemImage:)` is monochrome template so we do not attempt tint;
    /// shape change carries the signal: exclamation > down > pencil > checkmark.
    private var menuBarImage: String {
        if model.problemCount > 0 { return "exclamationmark.octagon.fill" }
        if model.behindCount > 0 { return "arrow.down.circle.fill" }
        if model.dirtyCount > 0 { return "pencil.circle.fill" }
        return "checkmark.circle.fill"
    }

    var body: some Scene {
        // 1. Menu Bar Popover — icon shape signals, pills signal color (#32)
        MenuBarExtra("fmr", systemImage: menuBarImage) {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)

        // 2. Full Workspace Dashboard Window
        WindowGroup("Workspace Dashboard", id: "dashboard") {
            WorkspaceDashboardView(model: model)
                .frame(minWidth: 800, minHeight: 520)
        }
        // 3. Help Window (M3 #30) — distinct from Settings and Dashboard
        WindowGroup("Fmr Help", id: "help") {
            HelpView(model: model)
                .frame(width: 640, height: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 640, height: 520)

        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Fmr") {
                    let core = Bundle.main.infoDictionary?["FMRCoreVersion"] as? String ?? "0.2.0"
                    NSApp.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Fmr",
                            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0",
                            .version: core,
                            .credits: NSAttributedString(string: "Fix My Repository — deterministic workspace manager.\nCore: fmr \(core)\n\nfmr status  •  fmr sync  •  fmr context | pbcopy\nDocs: github.com/drawmeanelephant/fmr\nConfig: ~/config/fmr/workspace.json"),
                        ]
                    )
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Refresh Status") {
                    model.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Sync All Repositories") {
                    model.syncAll()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Run Doctor Diagnostics") {
                    model.runDoctor(fix: false)
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Add Repository...") {
                    model.isAddRepoPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Clone & Open Recent Repository...") {
                    model.paletteFilter = .recents
                    model.isCommandPalettePresented = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            // Help menu — single CommandGroup(replacing: .help) for M3 #30.
            // Future #34 must add items inside this group, not recreate it.
            CommandGroup(replacing: .help) {
                HelpCommandsView(model: model)
            }
            // #34 discoverability — palette commands after toolbar
            CommandGroup(after: .toolbar) {
                Button("Command Palette...") {
                    model.isCommandPalettePresented = true
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("Recent Repositories...") {
                    model.paletteFilter = .recents
                    model.isCommandPalettePresented = true
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsView(model: model)
        }
    }
}
