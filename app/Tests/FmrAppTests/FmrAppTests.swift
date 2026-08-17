import XCTest
@testable import FmrApp

final class FmrAppTests: XCTestCase {
    func testDecodeStatusJsonWithExtendedFields() throws {
        let json = """
        {
          "version": 1,
          "command": "status",
          "exit": 0,
          "repos": [
            {
              "name": "boris",
              "branch": "afterparty",
              "head": "1234567",
              "state": "ok",
              "paused": false,
              "ahead": 0,
              "behind": 2,
              "dirty_tracked": 1,
              "untracked": 3,
              "snap": "ok",
              "sessions": 2,
              "kind": "zig",
              "path": "/Users/t/dev/drawmeanelephant/boris",
              "url": "git@github.com:drawmeanelephant/boris.git"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(StatusResponse.self, from: json)
        XCTAssertEqual(response.version, 1)
        XCTAssertEqual(response.command, "status")
        XCTAssertEqual(response.repos.count, 1)

        let r = response.repos[0]
        XCTAssertEqual(r.name, "boris")
        XCTAssertEqual(r.branch, "afterparty")
        XCTAssertEqual(r.head, "1234567")
        XCTAssertEqual(r.kind, "zig")
        XCTAssertEqual(r.path, "/Users/t/dev/drawmeanelephant/boris")
        XCTAssertEqual(r.url, "git@github.com:drawmeanelephant/boris.git")
        XCTAssertTrue(r.isDirty)
        XCTAssertTrue(r.isBehind)
        XCTAssertFalse(r.isClean)
        XCTAssertTrue(r.isSnapOk)
        XCTAssertEqual(r.sessions, 2)
    }

    func testDecodeSyncJsonWithDiffMetadata() throws {
        let json = """
        {
          "version": 1,
          "command": "sync",
          "exit": 0,
          "repos": [
            {
              "name": "boris",
              "result": "ok",
              "exit": 0,
              "message": "fast-forward",
              "before": "1234abc",
              "after": "5678def",
              "action": "fast-forward"
            }
          ],
          "summary": {
            "ok": 1,
            "refused": 0,
            "failed": 0,
            "skipped": 0
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncResponse.self, from: json)
        XCTAssertEqual(response.repos.count, 1)
        XCTAssertEqual(response.summary.ok, 1)
        XCTAssertEqual(response.repos[0].before, "1234abc")
        XCTAssertEqual(response.repos[0].after, "5678def")
        XCTAssertEqual(response.repos[0].action, "fast-forward")
    }

    func testDecodeDoctorJson() throws {
        let json = """
        {
          "version": 1,
          "command": "doctor",
          "exit": 0,
          "problems": 0,
          "warnings": 1,
          "checks": [
            {
              "level": "ok",
              "message": "git is available"
            },
            {
              "level": "warn",
              "message": "lock stale"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DoctorResponse.self, from: json)
        XCTAssertEqual(response.checks.count, 2)
        XCTAssertEqual(response.problems, 0)
        XCTAssertEqual(response.warnings, 1)
        XCTAssertTrue(response.checks[0].isOk)
        XCTAssertTrue(response.checks[1].isWarning)
    }

    func testDecodeConfigJsonWithCatalogFields() throws {
        let json = """
        {
          "version": 1,
          "command": "config",
          "exit": 0,
          "paths": {
            "repos": "/Users/t/dev/drawmeanelephant",
            "worktrees": "/Users/t/Code/worktrees",
            "sourceRag": "/Users/t/Code/source-rag"
          },
          "parallelism": { "sync": 4, "status": 4, "check": 1, "rag": 1 },
          "repos": [
            {
              "name": "boris",
              "url": "git@github.com:drawmeanelephant/boris.git",
              "kind": "zig",
              "path": "/Users/t/dev/drawmeanelephant/boris",
              "default_branch": "afterparty",
              "worktree_safe": true,
              "sync_enabled": true,
              "check": ["zig", "build", "test"],
              "rag": { "mode": "command", "argv": ["python3", "export.sh"], "output": "{rag_out}" },
              "env": [],
              "commands": { "serve": ["zig", "build", "run", "--", "serve"], "site": ["zig", "build"] }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ConfigResponse.self, from: json)
        XCTAssertEqual(response.command, "config")
        XCTAssertEqual(response.paths?.repos, "/Users/t/dev/drawmeanelephant")
        XCTAssertEqual(response.paths?.worktrees, "/Users/t/Code/worktrees")

        let repo = response.repos?.first
        XCTAssertEqual(repo?.name, "boris")
        XCTAssertEqual(repo?.kind, "zig")
        XCTAssertEqual(repo?.path, "/Users/t/dev/drawmeanelephant/boris")
        XCTAssertEqual(repo?.syncEnabled, true)
        XCTAssertEqual(repo?.rag?.mode, "command")
        XCTAssertEqual(repo?.commands?["serve"], ["zig", "build", "run", "--", "serve"])
        XCTAssertEqual(repo?.commands?["site"], ["zig", "build"])
    }

    func testWorktreeValidation() throws {
        let model = WorkspaceViewModel(bridge: FMRBridge())

        // Branch names
        XCTAssertNil(model.validateBranchName("feat/auth-flow"))
        XCTAssertNil(model.validateBranchName("main"))
        XCTAssertNotNil(model.validateBranchName(""))
        XCTAssertNotNil(model.validateBranchName("has space"))
        XCTAssertNotNil(model.validateBranchName("a..b"))
        XCTAssertNotNil(model.validateBranchName("-leading"))
        XCTAssertNotNil(model.validateBranchName("trailing/"))
        XCTAssertNotNil(model.validateBranchName("@"))
        XCTAssertNotNil(model.validateBranchName("bad:colon"))

        // Session names
        XCTAssertNil(model.validateSessionName("session-auth-flow"))
        XCTAssertNil(model.validateSessionName("session 1"))
        XCTAssertNotNil(model.validateSessionName(""))
        XCTAssertNotNil(model.validateSessionName("a/b"))
        XCTAssertNotNil(model.validateSessionName("../escape"))
        XCTAssertNotNil(model.validateSessionName(".hidden"))
    }

    func testNameFromURL() throws {
        // ssh git@ style
        XCTAssertEqual(WorkspaceViewModel.nameFromURL("git@github.com:org/my-repo.git"), "my-repo")
        // https style
        XCTAssertEqual(WorkspaceViewModel.nameFromURL("https://github.com/org/my-repo.git"), "my-repo")
        // no .git suffix
        XCTAssertEqual(WorkspaceViewModel.nameFromURL("git@github.com:org/my-repo"), "my-repo")
        // trailing slash
        XCTAssertEqual(WorkspaceViewModel.nameFromURL("https://github.com/org/my-repo/"), "my-repo")
        // nested path
        XCTAssertEqual(WorkspaceViewModel.nameFromURL("https://github.com/org/sub/dir/repo-name.git"), "repo-name")
        // whitespace trimmed
        XCTAssertEqual(WorkspaceViewModel.nameFromURL("  git@github.com:org/repo.git \n"), "repo")
        // empty / degenerate
        XCTAssertNil(WorkspaceViewModel.nameFromURL(""))
        XCTAssertNil(WorkspaceViewModel.nameFromURL("   ")
)
    }

    func testDetectKind() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // no manifest -> nil
        XCTAssertNil(WorkspaceViewModel.detectKind(in: tmp))

        // build.zig -> zig
        try Data().write(to: tmp.appendingPathComponent("build.zig"))
        XCTAssertEqual(WorkspaceViewModel.detectKind(in: tmp), "zig")

        // go.mod -> go
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("build.zig"))
        try Data().write(to: tmp.appendingPathComponent("go.mod"))
        XCTAssertEqual(WorkspaceViewModel.detectKind(in: tmp), "go")

        // package.json -> node
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("go.mod"))
        try Data().write(to: tmp.appendingPathComponent("package.json"))
        XCTAssertEqual(WorkspaceViewModel.detectKind(in: tmp), "node")
    }

    func testRecentReposDedupeAndCap() throws {
        let suite = "fmr-test-recents-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = WorkspaceViewModel(bridge: FMRBridge(), defaults: defaults)
        XCTAssertTrue(model.recentRepos.isEmpty)

        model.rememberRepo(name: "boris", url: "git@github.com:drawmeanelephant/boris.git", kind: "zig", defaultBranch: "main")
        model.rememberRepo(name: "oliver", url: "git@github.com:drawmeanelephant/oliver.git", kind: "go", defaultBranch: nil)
        XCTAssertEqual(model.recentRepos.count, 2)
        // newest first
        XCTAssertEqual(model.recentRepos.first?.name, "oliver")

        // re-adding dedupes and bumps to front
        model.rememberRepo(name: "boris", url: "git@github.com:drawmeanelephant/boris.git", kind: "zig", defaultBranch: "main")
        XCTAssertEqual(model.recentRepos.count, 2)
        XCTAssertEqual(model.recentRepos.first?.name, "boris")

        // cap at limit
        for i in 0..<20 {
            model.rememberRepo(name: "repo-\(i)", url: nil, kind: nil, defaultBranch: nil)
        }
        XCTAssertEqual(model.recentRepos.count, 10)
        XCTAssertEqual(model.recentRepos.first?.name, "repo-19")
        XCTAssertFalse(model.recentRepos.contains { $0.name == "boris" })

        // forget + clear
        model.forgetRepo(name: "repo-19")
        XCTAssertEqual(model.recentRepos.count, 9)
        model.clearRecentRepos()
        XCTAssertTrue(model.recentRepos.isEmpty)
    }

    func testRecentReposPersistAcrossInstances() throws {
        let suite = "fmr-test-recents-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = WorkspaceViewModel(bridge: FMRBridge(), defaults: defaults)
        first.rememberRepo(name: "boris", url: "git@github.com:drawmeanelephant/boris.git", kind: "zig", defaultBranch: "main")

        // a fresh instance loads what the first one persisted
        let second = WorkspaceViewModel(bridge: FMRBridge(), defaults: defaults)
        XCTAssertEqual(second.recentRepos.count, 1)
        XCTAssertEqual(second.recentRepos.first?.name, "boris")
        XCTAssertEqual(second.recentRepos.first?.url, "git@github.com:drawmeanelephant/boris.git")
        XCTAssertEqual(second.recentRepos.first?.kind, "zig")
        XCTAssertEqual(second.recentRepos.first?.defaultBranch, "main")
    }

    func testDecodeRagJson() throws {
        let json = """
        {
          "version": 1,
          "command": "rag",
          "exit": 0,
          "repos": [
            {
              "name": "boris",
              "status": "ok",
              "action": "snap",
              "sha": "1234567",
              "exit": 0,
              "message": "snapshot created"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(RagResponse.self, from: json)
        XCTAssertEqual(response.repos.count, 1)
        XCTAssertEqual(response.repos[0].name, "boris")
        XCTAssertEqual(response.repos[0].action, "snap")
    }
}
