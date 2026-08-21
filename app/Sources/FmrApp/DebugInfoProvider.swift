import Foundation
import AppKit

/// Shared helper that formats a copyable debug string for About and Settings.
/// Used by `SettingsView` and `HelpView` Overview tab per #34.
public enum DebugInfoProvider {
    private static var cachedGitVersion: String?

    /// Synchronously fetches `git --version` via `/usr/bin/git`, cached.
    public static func gitVersion() -> String {
        if let cached = cachedGitVersion { return cached }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // "git version 2.54.0" → "2.54.0"
            let ver = out.replacingOccurrences(of: "git version ", with: "")
            let trimmed = ver.isEmpty ? "unknown" : ver
            cachedGitVersion = trimmed
            return trimmed
        } catch {
            return "unknown"
        }
    }

    /// macOS version string via `ProcessInfo.operatingSystemVersion`.
    public static func macOSVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Formats the multi-line debug string.
    /// Example:
    /// ```
    /// Fmr 0.2.0 (core 0.2.0) build 14
    /// repos: ~/dev/drawmeanelephant  worktrees: ~/Code/worktrees
    /// git 2.54.0  macOS 14.5.0  13 repos  2 behind  1 dirty
    /// ```
    public static func debugString(model: WorkspaceViewModel) -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        let coreVersion = Bundle.main.infoDictionary?["FMRCoreVersion"] as? String ?? appVersion
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        let git = gitVersion()
        let mac = macOSVersionString()
        let repos = model.repos.count
        let behind = model.behindCount
        let dirty = model.dirtyCount
        let reposRoot = model.reposRoot.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let worktreesRoot = model.worktreesRoot.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return """
        Fmr \(appVersion) (core \(coreVersion)) build \(build)
        repos: \(reposRoot)  worktrees: \(worktreesRoot)
        git \(git)  macOS \(mac)  \(repos) repos  \(behind) behind  \(dirty) dirty
        """
    }

    /// Copies the debug string to the pasteboard with haptic feedback.
    @discardableResult
    public static func copyDebugInfo(model: WorkspaceViewModel) -> String {
        let s = debugString(model: model)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        return s
    }
}
