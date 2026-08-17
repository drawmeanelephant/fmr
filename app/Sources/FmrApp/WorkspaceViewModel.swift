import Foundation
import SwiftUI
import AppKit

public enum RepoFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case dirty = "Needs Attention"
    case zig = "Zig"
    case go = "Go"
    case sites = "Sites"
    case tools = "Tools & Scripts"

    public var id: String { rawValue }
}

@Observable
public final class WorkspaceViewModel: @unchecked Sendable {
    public var repos: [RepoStatus] = []
    public var selectedRepo: RepoStatus? = nil
    public var worktreesByRepo: [String: [WorktreeSession]] = [:]

    public var isRefreshing: Bool = false
    public var activeTaskDescription: String? = nil
    public var lastTaskOutput: String = ""
    public var isTerminalDrawerOpen: Bool = false

    public var doctorChecks: [DoctorCheck] = []
    public var doctorProblemsCount: Int = 0
    public var doctorWarningsCount: Int = 0
    public var isDoctorSheetPresented: Bool = false
    public var isCreateWorktreePresented: Bool = false
    public var isCommandPalettePresented: Bool = false

    public var searchQuery: String = ""
    public var selectedFilter: RepoFilter = .all
    public var lastUpdated: Date? = nil

    // Catalog metadata loaded from `fmr config --json` (paths, commands, kinds).
    public var configPaths: ConfigPaths? = nil
    public var catalog: [String: ConfigRepoItem] = [:]
    public var catalogLoaded: Bool = false

    private let bridge: FMRBridge
    private var timer: Timer?

    public init(bridge: FMRBridge = .shared) {
        self.bridge = bridge
        loadCatalog()
    }

    /// Loads the workspace catalog (`fmr config --json`) so the UI never
    /// hardcodes workspace layout or command lists.
    public func loadCatalog() {
        Task {
            do {
                let response: ConfigResponse = try await bridge.run(["config"])
                await MainActor.run {
                    var map: [String: ConfigRepoItem] = [:]
                    for item in response.repos ?? [] {
                        map[item.name] = item
                    }
                    self.catalog = map
                    self.configPaths = response.paths
                    self.catalogLoaded = true
                }
            } catch {
                await MainActor.run {
                    self.catalogLoaded = false
                }
            }
        }
    }

    /// Primary checkout root from the catalog (falls back to the historical default).
    public var reposRoot: String {
        configPaths?.repos ?? "\(NSHomeDirectory())/dev/drawmeanelephant"
    }

    /// Conductor worktrees root from the catalog (falls back to the historical default).
    public var worktreesRoot: String {
        configPaths?.worktrees ?? "\(NSHomeDirectory())/Code/worktrees"
    }

    /// Configured custom commands (name + argv) for a repo, from the catalog.
    public func customCommands(for name: String) -> [(String, [String])] {
        guard let item = catalog[name], let commands = item.commands else { return [] }
        return commands.keys.sorted().map { ($0, commands[$0] ?? []) }
    }

    public func startAutoRefresh(interval: TimeInterval = 15.0) {
        Task { @MainActor in
            self.refresh()
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(silent: true)
            }
        }
    }

    public func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Computed Properties

    public var filteredRepos: [RepoStatus] {
        repos.filter { repo in
            let matchesSearch = searchQuery.isEmpty ||
                repo.name.localizedCaseInsensitiveContains(searchQuery) ||
                repo.branch.localizedCaseInsensitiveContains(searchQuery)

            guard matchesSearch else { return false }

            switch selectedFilter {
            case .all:
                return true
            case .dirty:
                return repo.isDirty || repo.isBehind || repo.isSnapStale || repo.state != "ok"
            case .zig:
                return repo.kind == "zig"
            case .go:
                return repo.kind == "go"
            case .sites:
                return repo.kind == "site"
            case .tools:
                return repo.kind == "bash" || repo.kind == "other"
            }
        }
    }

    public var cleanCount: Int { repos.filter(\.isClean).count }
    public var behindCount: Int { repos.filter(\.isBehind).count }
    public var dirtyCount: Int { repos.filter(\.isDirty).count }
    public var snapStaleCount: Int { repos.filter(\.isSnapStale).count }
    public var problemCount: Int { repos.filter { $0.state != "ok" }.count }

    // MARK: - Actions

    @MainActor
    public func refresh(silent: Bool = false) {
        if !silent {
            isRefreshing = true
        }

        Task {
            do {
                let response: StatusResponse = try await bridge.run(["status"])
                await MainActor.run {
                    self.repos = response.repos
                    if self.selectedRepo == nil && !response.repos.isEmpty {
                        self.selectedRepo = response.repos.first
                    } else if let sel = self.selectedRepo {
                        self.selectedRepo = response.repos.first { $0.name == sel.name }
                    }
                    self.lastUpdated = Date()
                    self.isRefreshing = false
                    self.discoverWorktrees()
                    if !self.catalogLoaded { self.loadCatalog() }
                }
            } catch {
                await MainActor.run {
                    self.isRefreshing = false
                    if !silent {
                        self.lastTaskOutput = "Status refresh error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    @MainActor
    public func syncAll() {
        runTask(description: "Syncing All Repositories...") {
            let res: SyncResponse = try await self.bridge.run(["sync", "--all"])
            return "Sync complete: \(res.summary.ok) ok, \(res.summary.refused) refused, \(res.summary.failed) failed."
        }
    }

    @MainActor
    public func syncRepo(name: String) {
        runTask(description: "Syncing \(name)...") {
            let res: SyncResponse = try await self.bridge.run(["sync", name])
            let msg = res.repos.first?.message ?? "Done"
            return "\(name): \(msg)"
        }
    }

    @MainActor
    public func ragAll(force: Bool = false) {
        runTask(description: "Generating RAG Snapshots for All Repos...") {
            var args = ["rag", "--all"]
            if force { args.append("--force") }
            let res: RagResponse = try await self.bridge.run(args)
            return "RAG snapshot finished for \(res.repos.count) repo(s)."
        }
    }

    @MainActor
    public func ragRepo(name: String, force: Bool = false) {
        runTask(description: "Generating RAG Snapshot for \(name)...") {
            var args = ["rag", name]
            if force { args.append("--force") }
            let res: RagResponse = try await self.bridge.run(args)
            let item = res.repos.first
            return "\(name): \(item?.action ?? "done") (sha: \(item?.sha ?? "-"))"
        }
    }

    @MainActor
    public func checkRepo(name: String) {
        runTask(description: "Running Check for \(name)...") {
            let res: CheckResponse = try await self.bridge.run(["check", name])
            let item = res.repos.first
            return "\(name): \(item?.status ?? "done") - \(item?.message ?? "")"
        }
    }

    @MainActor
    public func runDoctor(fix: Bool = false) {
        isRefreshing = true
        activeTaskDescription = fix ? "Remediating System Issues..." : "Running Diagnostics..."

        Task {
            do {
                var args = ["doctor"]
                if fix { args.append("--fix") }
                let response: DoctorResponse = try await self.bridge.run(args)
                await MainActor.run {
                    self.doctorChecks = response.checks
                    self.doctorProblemsCount = response.problems
                    self.doctorWarningsCount = response.warnings
                    self.isRefreshing = false
                    self.activeTaskDescription = nil
                    self.isDoctorSheetPresented = true
                    self.refresh(silent: true)
                }
            } catch {
                await MainActor.run {
                    self.isRefreshing = false
                    self.activeTaskDescription = nil
                    self.lastTaskOutput = "Doctor error: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    public func runCustomCommand(repoName: String, commandName: String) {
        isTerminalDrawerOpen = true
        activeTaskDescription = "Running '\(commandName)' on \(repoName)..."
        lastTaskOutput = "=== Running fmr run \(repoName) \(commandName) ===\n"

        Task {
            do {
                let res = try await self.bridge.execute(
                    arguments: ["run", repoName, commandName],
                    onOutput: { text in
                        Task { @MainActor in
                            self.lastTaskOutput.append(text)
                        }
                    }
                )
                await MainActor.run {
                    self.activeTaskDescription = nil
                    self.lastTaskOutput.append("\n[Process exited with code \(res.exitCode)]\n")
                    self.refresh(silent: true)
                }
            } catch {
                await MainActor.run {
                    self.activeTaskDescription = nil
                    self.lastTaskOutput.append("\nFailed to run: \(error.localizedDescription)\n")
                }
            }
        }
    }

    // MARK: - Worktree Management

    @MainActor
    public func createWorktree(repoName: String, sessionName: String, branch: String) {
        let repoPath = "\(reposRoot)/\(repoName)"
        let targetPath = "\(worktreesRoot)/\(repoName)/\(sessionName)"

        runTask(description: "Creating worktree '\(sessionName)' for \(repoName)...") {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", repoPath, "worktree", "add", targetPath, "-b", branch]
            try proc.run()
            proc.waitUntilExit()

            if proc.terminationStatus == 0 {
                return "Worktree created at \(targetPath)"
            } else {
                throw NSError(domain: "fmr", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Git worktree add failed with exit \(proc.terminationStatus)"])
            }
        }
    }

    @MainActor
    public func removeWorktree(session: WorktreeSession, force: Bool = false) {
        let repoPath = "\(reposRoot)/\(session.repoName)"

        runTask(description: "Removing worktree '\(session.sessionName)'...") {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            var args = ["-C", repoPath, "worktree", "remove", session.path]
            if force { args.append("--force") }
            proc.arguments = args
            try proc.run()
            proc.waitUntilExit()

            if proc.terminationStatus == 0 {
                return "Worktree removed: \(session.sessionName)"
            } else {
                throw NSError(domain: "fmr", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Git worktree remove failed with exit \(proc.terminationStatus)"])
            }
        }
    }

    private func discoverWorktrees() {
        let worktreesRoot = self.worktreesRoot
        let fm = FileManager.default

        guard let repoDirs = try? fm.contentsOfDirectory(atPath: worktreesRoot) else { return }

        var map: [String: [WorktreeSession]] = [:]
        for repoName in repoDirs {
            let repoWorktreesPath = "\(worktreesRoot)/\(repoName)"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: repoWorktreesPath, isDirectory: &isDir), isDir.boolValue {
                if let sessions = try? fm.contentsOfDirectory(atPath: repoWorktreesPath) {
                    var sessionList: [WorktreeSession] = []
                    for s in sessions {
                        if s.hasPrefix(".") { continue }
                        let sPath = "\(repoWorktreesPath)/\(s)"

                        // Query branch
                        var branchName: String? = nil
                        let headFile = "\(sPath)/.git"
                        if let content = try? String(contentsOfFile: headFile, encoding: .utf8) {
                            branchName = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        }

                        sessionList.append(WorktreeSession(
                            repoName: repoName,
                            sessionName: s,
                            path: sPath,
                            branch: branchName,
                            headSha: nil
                        ))
                    }
                    map[repoName] = sessionList
                }
            }
        }
        self.worktreesByRepo = map
    }

    // MARK: - Editor Launchers

    public func openIn(editor: CodeEditor, path: String) {
        switch editor {
        case .finder:
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        case .terminal:
            let script = "tell application \"Terminal\" to do script \"cd \(path)\""
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        default:
            if let bundleId = editor.bundleIdentifier,
               let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appUrl, configuration: config, completionHandler: nil)
            } else {
                let url = URL(fileURLWithPath: path)
                NSWorkspace.shared.open(url)
            }
        }
    }

    public func openInFinder(path: String) {
        openIn(editor: .finder, path: path)
    }

    public func openInTerminal(path: String) {
        openIn(editor: .terminal, path: path)
    }

    public func openInEditor(path: String) {
        openIn(editor: .cursor, path: path)
    }

    // MARK: - Helper

    @MainActor
    private func runTask(description: String, operation: @escaping () async throws -> String) {
        isRefreshing = true
        activeTaskDescription = description
        lastTaskOutput = "\(description)\n"

        Task {
            do {
                let summary = try await operation()
                await MainActor.run {
                    self.lastTaskOutput.append("\(summary)\n")
                    self.activeTaskDescription = nil
                    self.isRefreshing = false
                    self.refresh(silent: true)
                }
            } catch {
                await MainActor.run {
                    self.lastTaskOutput.append("Error: \(error.localizedDescription)\n")
                    self.activeTaskDescription = nil
                    self.isRefreshing = false
                }
            }
        }
    }
}
