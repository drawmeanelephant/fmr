import XCTest
@testable import FmrApp

final class RemediationTests: XCTestCase {
    func testExtractFixCommandQuotedPath() throws {
        let msg = #"boris: url mismatch (config git@github.com:org/repo.git, origin git@github.com:org/other.git) — fix: git -C "/Users/tbuddy/Code/My Repo" remote set-url origin git@github.com:org/repo.git or fmr sync --fix-origin"#
        let cmd = RemediationHelper.extractFixCommand(from: msg)
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd!.contains("git -C \"/Users/tbuddy/Code/My Repo\" remote set-url"))
        XCTAssertTrue(cmd!.contains("origin"))
    }

    func testExtractFixCommandUnquotedStatus() throws {
        let msg = "dirty: commit or stash before syncing; inspect: git -C /tmp/repo status"
        let cmd = RemediationHelper.extractFixCommand(from: msg)
        XCTAssertEqual(cmd, "git -C /tmp/repo status")
    }

    func testExtractFixCommandFmrSync() throws {
        let msg = "not cloned yet — try fmr sync myrepo"
        let cmd = RemediationHelper.extractFixCommand(from: msg)
        XCTAssertEqual(cmd, "fmr sync myrepo")
    }

    func testExtractFixCommandNoMatch() throws {
        let msg = "no fix here — just a plain message"
        let cmd = RemediationHelper.extractFixCommand(from: msg)
        XCTAssertNil(cmd)
    }

    func testRemediationIdStable() throws {
        let model = WorkspaceViewModel(bridge: FMRBridge(), defaults: UserDefaults(suiteName: "fmr-test-remediation-\(UUID().uuidString)")!)
        let msg = "test message"
        let id1 = model.remediationId(for: msg)
        let id2 = model.remediationId(for: msg)
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id1, msg)
    }

    func testDoctorFixableRepoName() throws {
        let suite = "fmr-test-doctor-fix-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = WorkspaceViewModel(bridge: FMRBridge(), defaults: defaults)
        // Simulate catalog entry
        model.catalog["boris"] = ConfigRepoItem(name: "boris", url: "git@github.com:org/boris.git", kind: "zig", defaultBranch: "main", worktreeSafe: true, syncEnabled: true, path: "/tmp/boris", commands: nil, rag: nil)
        XCTAssertEqual(model.doctorFixableRepoName(from: "boris: url mismatch — fix: git -C /tmp/boris remote set-url origin ..."), "boris")
        XCTAssertNil(model.doctorFixableRepoName(from: "global: low disk space on repos root"))
        XCTAssertNil(model.doctorFixableRepoName(from: "no colon message"))
    }
}
