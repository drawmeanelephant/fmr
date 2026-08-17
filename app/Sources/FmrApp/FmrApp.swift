import SwiftUI
import AppKit

@main
struct FmrApp: App {
    @State private var model = WorkspaceViewModel()

    init() {
        // Start background auto-refresh
        _model.wrappedValue.startAutoRefresh(interval: 15.0)
    }

    var body: some Scene {
        // 1. Menu Bar Popover
        MenuBarExtra("fmr", systemImage: "arrow.triangle.2.circlepath") {
            MenuBarView(model: model)
        }
        .menuBarExtraStyle(.window)

        // 2. Full Workspace Dashboard Window
        WindowGroup("Workspace Dashboard", id: "dashboard") {
            WorkspaceDashboardView(model: model)
                .frame(minWidth: 800, minHeight: 520)
        }
        .commands {
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
            }
        }
    }
}
