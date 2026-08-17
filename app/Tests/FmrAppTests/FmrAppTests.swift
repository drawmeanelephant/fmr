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
