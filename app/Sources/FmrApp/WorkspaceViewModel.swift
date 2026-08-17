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

    public var searchQuery: String = ""
    public var selectedFilter: RepoFilter = .all
    public var lastUpdated: Date? = nil

    private let bridge: FMRBridge
    private var timer: Timer?

    public init(bridge: FMRBridge = .shared) {
        self.bridge = bridge
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
                return ["boris", "oliver", "DipshitOS"].contains(repo.name)
            case .go:
                return ["know", "codex-limits"].contains(repo.name)
            case .sites:
                return ["fullonrogues.org", "thermalextractiondevices.com", "corgifever.com"].contains(repo.name)
            case .tools:
                return ["rotkeeper", "minutes-without-motion", "la-famille", "filed.fyi", "apex"].contains(repo.name)
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

    // MARK: - Worktree Discovery

    private func discoverWorktrees() {
        let home = NSHomeDirectory()
        let worktreesRoot = "\(home)/Code/worktrees"
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
                        sessionList.append(WorktreeSession(
                            repoName: repoName,
                            sessionName: s,
                            path: sPath,
                            branch: nil
                        ))
                    }
                    map[repoName] = sessionList
                }
            }
        }
        self.worktreesByRepo = map
    }

    // MARK: - Openers

    public func openInFinder(path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    public func openInTerminal(path: String) {
        let script = "tell application \"Terminal\" to do script \"cd \(path)\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    public func openInEditor(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
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
