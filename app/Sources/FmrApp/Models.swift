import Foundation

// MARK: - Status Models

public struct StatusResponse: Codable, Sendable {
    public let version: Int
    public let command: String
    public let exit: Int
    public let repos: [RepoStatus]
}

public struct RepoStatus: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let branch: String
    public let head: String
    public let state: String
    public let paused: Bool
    public let ahead: Int
    public let behind: Int
    public let dirtyTracked: Int
    public let untracked: Int
    public let snap: String
    public let sessions: Int

    // Extended optional fields from upcoming core CLI updates
    public let kind: String?
    public let path: String?
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case name
        case branch
        case head
        case state
        case paused
        case ahead
        case behind
        case dirtyTracked = "dirty_tracked"
        case untracked
        case snap
        case sessions
        case kind
        case path
        case url
    }

    public var isClean: Bool {
        return state == "ok" && ahead == 0 && behind == 0 && dirtyTracked == 0
    }

    public var isDirty: Bool {
        return dirtyTracked > 0
    }

    public var isBehind: Bool {
        return behind > 0
    }

    public var isAhead: Bool {
        return ahead > 0
    }

    public var isSnapOk: Bool {
        return snap == "ok"
    }

    public var isSnapStale: Bool {
        return snap == "stale"
    }

    public var resolvedPath: String {
        if let p = path, !p.isEmpty { return p }
        return "\(NSHomeDirectory())/dev/drawmeanelephant/\(name)"
    }
}

// MARK: - Sync Models

public struct SyncResponse: Codable, Sendable {
    public let version: Int
    public let command: String
    public let exit: Int
    public let repos: [SyncOutcome]
    public let summary: SyncSummary
}

public struct SyncOutcome: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let result: String
    public let exit: Int
    public let message: String
    public let before: String?
    public let after: String?
    public let action: String?
}

public struct SyncSummary: Codable, Sendable {
    public let ok: Int
    public let refused: Int
    public let failed: Int
    public let skipped: Int
}

// MARK: - Doctor Models

public struct DoctorResponse: Codable, Sendable {
    public let version: Int
    public let command: String
    public let exit: Int
    public let problems: Int
    public let warnings: Int
    public let checks: [DoctorCheck]
}

public struct DoctorCheck: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(level)-\(message)" }
    public let level: String
    public let message: String

    public var isProblem: Bool { level == "problem" }
    public var isWarning: Bool { level == "warn" }
    public var isOk: Bool { level == "ok" }
}

// MARK: - Check Models

public struct CheckResponse: Codable, Sendable {
    public let version: Int
    public let command: String
    public let exit: Int
    public let repos: [CheckOutcome]
}

public struct CheckOutcome: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let status: String
    public let exit: Int
    public let message: String
}

// MARK: - RAG Models

public struct RagResponse: Codable, Sendable {
    public let version: Int
    public let command: String
    public let exit: Int
    public let repos: [RagOutcome]
}

public struct RagOutcome: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let status: String
    public let action: String
    public let sha: String
    public let exit: Int
    public let message: String
}

// MARK: - Config Models

public struct ConfigResponse: Codable, Sendable {
    public let version: Int?
    public let paths: ConfigPaths?
    public let repos: [ConfigRepoItem]?
}

public struct ConfigPaths: Codable, Sendable {
    public let repos: String
    public let worktrees: String
    public let sourceRag: String
}

public struct ConfigRepoItem: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let url: String?
    public let kind: String?
    public let defaultBranch: String?
    public let worktreeSafe: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case kind
        case defaultBranch = "default_branch"
        case worktreeSafe = "worktree_safe"
    }
}

// MARK: - Session / Worktree Model

public struct WorktreeSession: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let repoName: String
    public let sessionName: String
    public let path: String
    public var branch: String?
    public var headSha: String?
}

public enum CodeEditor: String, CaseIterable, Identifiable, Sendable {
    case cursor = "Cursor"
    case vscode = "VS Code"
    case zed = "Zed"
    case xcode = "Xcode"
    case sublime = "Sublime Text"
    case terminal = "Terminal"
    case finder = "Finder"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .cursor: return "chevron.left.forwardslash.chevron.right"
        case .vscode: return "curlybraces"
        case .zed: return "bolt.fill"
        case .xcode: return "hammer.fill"
        case .sublime: return "doc.text.fill"
        case .terminal: return "terminal.fill"
        case .finder: return "folder.fill"
        }
    }

    public var bundleIdentifier: String? {
        switch self {
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .vscode: return "com.microsoft.VSCode"
        case .zed: return "dev.zed.Zed"
        case .xcode: return "com.apple.dt.Xcode"
        case .sublime: return "com.sublimetext.4"
        case .terminal: return "com.apple.Terminal"
        case .finder: return "com.apple.finder"
        }
    }
}
