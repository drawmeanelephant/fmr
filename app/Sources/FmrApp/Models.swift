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

// MARK: - Session / Worktree Model

public struct WorktreeSession: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let repoName: String
    public let sessionName: String
    public let path: String
    public let branch: String?
}
