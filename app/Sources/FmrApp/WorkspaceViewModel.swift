import Foundation
import SwiftUI
import AppKit
import UserNotifications

/// What the command palette should focus on when opened.
public enum PaletteFilter: Sendable {
    case all
    case recents
}

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
    public var isAddRepoPresented: Bool = false

    /// Which section the command palette should lead with when opened.
    public var paletteFilter: PaletteFilter = .all

    public var searchQuery: String = ""
    public var selectedFilter: RepoFilter = .all
    public var lastUpdated: Date? = nil
    private var freshnessTimer: Timer?
    /// Tick incremented every 30s to force SwiftUI re-render of `relativeLastUpdated` without extra `fmr` calls.
    /// Needed because `@Observable` (Observation) has no `objectWillChange`; mutating any `@Observable` var triggers update.
    private var freshnessTick: Int = 0

    // MARK: - Remediation (#33)

    public var lastSyncOutcomes: [SyncOutcome] = []
    public var showRemediationBanner: Bool = false
    public var remediationMessage: String = ""
    private static let dismissedRemediationIdKey = "fmr.dismissedRemediationId"

    public var remediationFixCommand: String? {
        RemediationHelper.extractFixCommand(from: remediationMessage)
    }

    public func remediationId(for message: String) -> String {
        // Stable id — use the message itself (truncated to 500 chars to avoid huge defaults).
        // Hasher is randomized per launch, so not suitable for persistence.
        if message.count > 500 { return String(message.prefix(500)) }
        return message
    }

    @MainActor
    public func dismissRemediationBanner() {
        let id = remediationId(for: remediationMessage)
        defaults.set(id, forKey: Self.dismissedRemediationIdKey)
        showRemediationBanner = false
    }

    public func copyFixCommand(from message: String) -> String? {
        RemediationHelper.extractFixCommand(from: message)
    }

    /// Returns the repo name from a doctor message if it matches a known repo/catalog entry.
    public func doctorFixableRepoName(from message: String) -> String? {
        // Doctor messages are "<repo>: ..." — extract prefix before colon.
        guard let colon = message.firstIndex(of: ":") else { return nil }
        let raw = String(message[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if repos.contains(where: { $0.name == raw }) { return raw }
        if worktreesByRepo[raw] != nil { return raw }
        if catalog[raw] != nil { return raw }
        return nil
    }

    public func isUrlMismatchMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("url mismatch")
    }

    public func isNotARepoMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("not a git repo") || message.localizedCaseInsensitiveContains("not_a_repo")
    }

    @MainActor
    private func updateRemediationBanner(with outcomes: [SyncOutcome]) {
        lastSyncOutcomes = outcomes
        guard let failing = outcomes.first(where: { $0.result == "refused" || $0.result == "failed" }) else {
            showRemediationBanner = false
            remediationMessage = ""
            return
        }
        let msg = failing.message
        let id = remediationId(for: msg)
        let dismissedId = defaults.string(forKey: Self.dismissedRemediationIdKey)
        if dismissedId == id {
            showRemediationBanner = false
            remediationMessage = msg
            return
        }
        remediationMessage = msg
        showRemediationBanner = true
    }

    /// Attempt to fix a url-mismatch via `fmr sync <repo> --fix-origin`.
    public func fixUrlMismatch(for repoName: String) {
        guard doctorFixableRepoName(from: "\(repoName): dummy") != nil || repos.contains(where: { $0.name == repoName }) || catalog[repoName] != nil else { return }
        Task {
            do {
                _ = try await self.bridge.execute(arguments: ["sync", repoName, "--fix-origin"])
                await MainActor.run {
                    self.runDoctor(fix: false)
                    self.refresh(silent: true)
                }
            } catch {
                await MainActor.run {
                    self.lastTaskOutput = "Fix failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Humanized freshness string for "Last synced: X". Updates every 30s via `freshnessTimer`.
    /// When `lastUpdated == nil` (never synced) returns "never" per #32.
    public var relativeLastUpdated: String {
        _ = freshnessTick // track tick for Observation invalidation
        guard let lastUpdated else { return "never" }
        let interval = Date().timeIntervalSince(lastUpdated)
        if interval < 60 { return "just now" }
        if interval < 3600 {
            let m = Int(interval / 60)
            return "\(m)m ago"
        }
        if interval < 86400 {
            let comps = Calendar.current.dateComponents([.hour], from: lastUpdated, to: Date())
            let h = comps.hour ?? 1
            return "\(h)h ago"
        }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: lastUpdated, relativeTo: Date())
    }

    /// More precise relative string using `RelativeDateTimeFormatter` for >24h; kept for tests.
    public func formattedRelativeLastUpdated() -> String { relativeLastUpdated }

    // Catalog metadata loaded from `fmr config --json` (paths, commands, kinds).
    public var configPaths: ConfigPaths? = nil
    public var catalog: [String: ConfigRepoItem] = [:]
    public var catalogLoaded: Bool = false

    // Repositories the user has onboarded through the app (persisted).
    public private(set) var recentRepos: [RecentRepoEntry] = []

    private let bridge: FMRBridge
    private let defaults: UserDefaults
    private var timer: Timer?
    private static let recentReposKey = "fmr.recentRepos.v1"
    private static let recentReposLimit = 10
    private static let hasSeenWelcomeKey = "fmr.hasSeenWelcome.v1"

    /// Whether the welcome sheet has been dismissed permanently.
    public var hasSeenWelcome: Bool {
        get { defaults.bool(forKey: Self.hasSeenWelcomeKey) }
        set { defaults.set(newValue, forKey: Self.hasSeenWelcomeKey) }
    }

    /// Guards previews and tests from showing the welcome sheet.
    private var isPreview: Bool {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil { return true }
        // XCTest injects this env var; also fallback to class check for unit tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        if NSClassFromString("XCTestCase") != nil { return true }
        return false
    }

    /// True when the welcome sheet should be shown automatically on launch.
    public var shouldShowWelcome: Bool {
        if isPreview { return false }
        return repos.isEmpty && catalogLoaded && !isRefreshing && !hasSeenWelcome
    }

    /// Transient override so Help > Welcome always forces the sheet even after
    /// hasSeenWelcome is true or repos is non-empty. Reset after presentation.
    public var isWelcomeForced: Bool = false

    public func markWelcomeSeen() {
        hasSeenWelcome = true
    }

    public func resetWelcome() {
        defaults.removeObject(forKey: Self.hasSeenWelcomeKey)
    }

    public func forceShowWelcome() {
        isWelcomeForced = true
    }

    public func clearForcedWelcome() {
        isWelcomeForced = false
    }

    /// Resolve the workspace.json path using the same fallback as
    /// src/main.zig:578 (~/config/fmr/workspace.json → ~/config/yard/workspace.json).
    public var resolvedConfigPath: String {
        bridge.resolveConfigPath()
    }

    public init(bridge: FMRBridge = .shared, defaults: UserDefaults = .standard) {
        self.bridge = bridge
        self.defaults = defaults
        loadRecentRepos()
        loadCatalog()
    }

    // MARK: - Recent Repositories (persisted)

    private func loadRecentRepos() {
        guard let data = defaults.data(forKey: Self.recentReposKey),
              let decoded = try? JSONDecoder().decode([RecentRepoEntry].self, from: data) else {
            return
        }
        recentRepos = decoded
    }

    private func persistRecentRepos() {
        if let data = try? JSONEncoder().encode(recentRepos) {
            defaults.set(data, forKey: Self.recentReposKey)
        }
    }

    /// Records a repo in the recents list (deduped by name, newest first, capped).
    public func rememberRepo(name: String, url: String?, kind: String?, defaultBranch: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentRepos.removeAll { $0.name == trimmed }
        recentRepos.insert(RecentRepoEntry(
            name: trimmed,
            url: url?.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            defaultBranch: defaultBranch
        ), at: 0)
        if recentRepos.count > Self.recentReposLimit {
            recentRepos = Array(recentRepos.prefix(Self.recentReposLimit))
        }
        persistRecentRepos()
    }

    /// Removes a repo from the recents list.
    public func forgetRepo(name: String) {
        recentRepos.removeAll { $0.name == name }
        persistRecentRepos()
    }

    /// Clears the recents list.
    public func clearRecentRepos() {
        recentRepos = []
        persistRecentRepos()
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
        // #32: freshness timer — re-renders `relativeLastUpdated` every 30s without extra fmr calls.
        // `objectWillChange` is for ObservableObject; @Observable uses mutation tracking, so we bump `freshnessTick`.
        freshnessTimer?.invalidate()
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.freshnessTick += 1
            }
        }
    }

    public func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
        freshnessTimer?.invalidate()
        freshnessTimer = nil
    }

    deinit {
        timer?.invalidate()
        freshnessTimer?.invalidate()
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
                    self.loadCatalog()
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
            // Store outcomes + banner on main
            await MainActor.run {
                self.updateRemediationBanner(with: res.repos)
            }
            let summary = "Sync complete: \(res.summary.ok) ok, \(res.summary.refused) refused, \(res.summary.failed) failed."
            if res.summary.refused > 0 || res.summary.failed > 0 {
                self.notify(title: "fmr sync", body: summary)
            }
            return summary
        }
    }

    @MainActor
    public func syncRepo(name: String) {
        runTask(description: "Syncing \(name)...") {
            let res: SyncResponse = try await self.bridge.run(["sync", name])
            await MainActor.run {
                self.updateRemediationBanner(with: res.repos)
            }
            let msg = res.repos.first?.message ?? "Done"
            if res.summary.refused > 0 || res.summary.failed > 0 {
                self.notify(title: "fmr sync: \(name)", body: msg)
            }
            return "\(name): \(msg)"
        }
    }

    private func notify(title: String, body: String) {
        // Best-effort: post notification even when app is active; system will coalesce
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(req)
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

    // MARK: - Repository Onboarding

    /// Extract a repo name from a git remote URL.
    /// `git@github.com:org/repo.git` -> `repo`; `https://github.com/org/repo.git` -> `repo`.
    public static func nameFromURL(_ url: String) -> String? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        if let at = s.lastIndex(of: "@"), s[at...].contains(":") {
            s = String(s[s.index(after: at)...])
        }
        var rest = s
        if let idx = s.firstIndex(where: { $0 == ":" || $0 == "/" }) {
            rest = String(s[s.index(after: idx)...])
        }
        while rest.hasSuffix("/") { rest = String(rest.dropLast()) }
        if let slash = rest.lastIndex(of: "/") { rest = String(rest[rest.index(after: slash)...]) }
        return rest.isEmpty ? nil : rest
    }

    /// Detect a repo kind from a local directory by probing manifest files.
    public static func detectKind(in directory: URL) -> String? {
        let fm = FileManager.default
        let probes: [(String, String)] = [
            ("build.zig", "zig"),
            ("go.mod", "go"),
            ("package.json", "node"),
            ("pyproject.toml", "other"),
        ]
        for (file, kind) in probes where fm.fileExists(atPath: directory.appendingPathComponent(file).path) {
            return kind
        }
        return nil
    }

    /// Read the origin remote URL of a local git directory, if any.
    public func remoteURL(forLocalDirectory url: URL) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", url.path, "remote", "get-url", "origin"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (proc.terminationStatus == 0 && !(out ?? "").isEmpty) ? out : nil
        } catch {
            return nil
        }
    }

    @MainActor
    public func addRepository(name: String, url: String?, kind: String?, defaultBranch: String?, syncNow: Bool, ragNow: Bool) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var args = ["add", trimmedName]
        if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(url.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let kind, !kind.isEmpty { args += ["--kind", kind] }
        if let defaultBranch, !defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["--branch", defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        if syncNow { args.append("--sync") }

        runTask(description: "Adding repository '\(trimmedName)'...") {
            let res = try await self.bridge.execute(arguments: args)
            guard res.exitCode == 0 else {
                let msg = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(domain: "fmr", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "fmr add failed" : msg])
            }
            if ragNow {
                let _: RagResponse? = try? await self.bridge.run(["rag", trimmedName])
            }
            self.rememberRepo(name: trimmedName, url: url, kind: kind, defaultBranch: defaultBranch)
            return "Added repository '\(trimmedName)' to workspace."
        }
    }

    /// Clone (if not already present) and open a recent repo in the default editor.
    /// If the repo is unregistered, runs `fmr add <name> <url> --sync` to clone it;
    /// otherwise just opens the existing checkout.
    /// Clone (if not already present) and open a recent repo in the default editor.
    /// If the repo is unregistered, runs `fmr add <name> <url> --sync` to clone it;
    /// otherwise just opens the existing checkout.
    @MainActor
    public func cloneAndOpenRecent(_ entry: RecentRepoEntry) {
        let alreadyRegistered = repos.contains { $0.name == entry.name }
        let targetPath = "\(reposRoot)/\(entry.name)"

        runTask(description: "Opening '\(entry.name)'...", onSuccess: { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: targetPath) {
                self.openIn(editor: .cursor, path: targetPath)
            } else {
                self.lastTaskOutput.append("Checkout not found at \(targetPath)\n")
            }
        }) {
            if !alreadyRegistered, let url = entry.url, !url.isEmpty {
                var args = ["add", entry.name, url, "--sync"]
                if let kind = entry.kind, !kind.isEmpty { args += ["--kind", kind] }
                if let branch = entry.defaultBranch, !branch.isEmpty { args += ["--branch", branch] }
                let res = try await self.bridge.execute(arguments: args)
                guard res.exitCode == 0 else {
                    let msg = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    throw NSError(domain: "fmr", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Failed to clone \(entry.name)" : msg])
                }
                self.rememberRepo(name: entry.name, url: entry.url, kind: entry.kind, defaultBranch: entry.defaultBranch)
            }
            return "Opening \(entry.name) at \(targetPath)"
        }
    }

    @MainActor
    public func removeRepository(name: String) {
        runTask(description: "Removing repository '\(name)'...") {
            let res = try await self.bridge.execute(arguments: ["remove", name])
            guard res.exitCode == 0 else {
                let msg = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(domain: "fmr", code: Int(res.exitCode), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "fmr remove failed" : msg])
            }
            return "Removed repository '\(name)' from workspace."
        }
    }

    // MARK: - Worktree Management

    // Confirmation state for removing a dirty worktree.
    public var pendingRemoveSession: WorktreeSession? = nil
    public var isConfirmRemoveWorktreePresented: Bool = false

    @MainActor
    public func createWorktree(repoName: String, sessionName: String, branch: String) {
        let sName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let bName = branch.trimmingCharacters(in: .whitespacesAndNewlines)

        if let err = validateSessionName(sName) {
            lastTaskOutput = "Cannot create worktree: \(err)"
            return
        }
        if let err = validateBranchName(bName) {
            lastTaskOutput = "Cannot create worktree: \(err)"
            return
        }
        if let err = gitCheckRef(bName) {
            lastTaskOutput = "Cannot create worktree: \(err)"
            return
        }

        let repoPath = "\(reposRoot)/\(repoName)"
        let targetPath = "\(worktreesRoot)/\(repoName)/\(sName)"

        runTask(description: "Creating worktree '\(sName)' for \(repoName)...") {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", repoPath, "worktree", "add", targetPath, "-b", bName]
            try proc.run()
            proc.waitUntilExit()

            if proc.terminationStatus == 0 {
                return "Worktree created at \(targetPath)"
            } else {
                throw NSError(domain: "fmr", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Git worktree add failed with exit \(proc.terminationStatus)"])
            }
        }
    }

    /// Entry point for removal: if the worktree is dirty, present a
    /// confirmation dialog (removing with --force discards uncommitted work).
    @MainActor
    public func requestRemoveWorktree(_ session: WorktreeSession) {
        if isWorktreeDirty(session.path) {
            pendingRemoveSession = session
            isConfirmRemoveWorktreePresented = true
        } else {
            removeWorktree(session: session, force: false)
        }
    }

    /// Called from the confirmation dialog once the user approves removal.
    @MainActor
    public func confirmRemoveWorktree(force: Bool) {
        defer {
            pendingRemoveSession = nil
            isConfirmRemoveWorktreePresented = false
        }
        guard let session = pendingRemoveSession else { return }
        removeWorktree(session: session, force: force)
    }

    @MainActor
    public func removeWorktree(session: WorktreeSession, force: Bool = false) {
        // A session that no longer exists on disk is a no-op (stale row).
        if !FileManager.default.fileExists(atPath: session.path) {
            lastTaskOutput = "Worktree '\(session.sessionName)' no longer exists; removed from list."
            discoverWorktrees()
            return
        }

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

    // MARK: - Worktree Validation

    /// Returns an error message if `session` is not a safe session folder name, else nil.
    public func validateSessionName(_ session: String) -> String? {
        let trimmed = session.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Session name is required." }
        guard trimmed != "." && trimmed != ".." else { return "'\(trimmed)' is not a valid session name." }
        guard !trimmed.hasPrefix(".") else { return "Session name cannot start with '.'." }
        guard !trimmed.contains("/") && !trimmed.contains("\\") else { return "Session name cannot contain path separators." }
        return nil
    }

    /// Returns an error message if `branch` is not a valid git branch name, else nil.
    public func validateBranchName(_ branch: String) -> String? {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Branch name is required." }
        guard !trimmed.hasPrefix("-") else { return "Branch name cannot start with '-'." }
        guard !trimmed.hasSuffix("/") && !trimmed.hasSuffix(".") else { return "Branch name cannot end with '/' or '.'." }
        guard trimmed != "@" else { return "'@' is not a valid branch name." }
        guard !trimmed.contains("..") else { return "Branch name cannot contain '..'." }
        let forbidden = CharacterSet(charactersIn: " ~^:?*[\\")
        for scalar in trimmed.unicodeScalars {
            if forbidden.contains(scalar) || scalar.value < 0x20 || scalar.value == 0x7F {
                return "Branch name contains invalid characters."
            }
        }
        return nil
    }

    /// Authoritative git check (`git check-ref-format --branch`). Returns nil if valid.
    public func gitCheckRef(_ branch: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["check-ref-format", "--branch", branch]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? nil : "git rejected branch name '\(branch)'."
        } catch {
            return "Could not run git check-ref-format."
        }
    }

    /// True when the worktree has uncommitted changes (status --porcelain non-empty).
    private func isWorktreeDirty(_ path: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", path, "status", "--porcelain"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return !data.isEmpty
        } catch {
            return true // conservative: if we cannot check, ask before removing
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
    private func runTask(description: String, onSuccess: (@MainActor () -> Void)? = nil, operation: @escaping () async throws -> String) {
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
                    onSuccess?()
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
