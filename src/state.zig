//! Pure decision table mapping git facts to sync decisions.
//! This module has zero I/O or subprocess dependencies and is 100% unit testable.

const std = @import("std");

/// Observed state facts gathered from a repository on disk.
pub const Facts = struct {
    path_exists: bool,
    is_worktree: bool,
    is_repo: bool,
    detached: bool,
    unborn: bool,
    branch: ?[]const u8,
    expected_branch: ?[]const u8,
    dirty_tracked: bool,
    untracked_count: usize,
    ahead: usize,
    behind: usize,
    origin_ref_missing: bool,
    url_ok: bool,
};

pub const Refusal = enum {
    not_a_repo,
    is_worktree,
    detached,
    unborn,
    wrong_branch,
    dirty,
    ahead,
    diverged,
    url_mismatch,
    no_origin_branch,
};

pub const Decision = union(enum) {
    clone,
    noop,
    ff_only,
    refuse: Refusal,
};

pub fn decide(f: Facts) Decision {
    if (!f.path_exists) return .clone;
    if (f.is_worktree) return .{ .refuse = .is_worktree };
    if (!f.is_repo) return .{ .refuse = .not_a_repo };
    if (f.detached) return .{ .refuse = .detached };
    if (f.unborn) return .{ .refuse = .unborn };
    if (!f.url_ok) return .{ .refuse = .url_mismatch };
    if (f.branch) |b| {
        if (f.expected_branch) |e| {
            if (!std.mem.eql(u8, b, e)) return .{ .refuse = .wrong_branch };
        }
    }
    if (f.origin_ref_missing) return .{ .refuse = .no_origin_branch };
    if (f.dirty_tracked) return .{ .refuse = .dirty };
    if (f.ahead > 0 and f.behind > 0) return .{ .refuse = .diverged };
    if (f.ahead > 0) return .{ .refuse = .ahead };
    if (f.behind > 0) return .ff_only;
    return .noop;
}

fn baseFacts() Facts {
    return .{
        .path_exists = false,
        .is_worktree = false,
        .is_repo = false,
        .detached = false,
        .unborn = false,
        .branch = null,
        .expected_branch = null,
        .dirty_tracked = false,
        .untracked_count = 0,
        .ahead = 0,
        .behind = 0,
        .origin_ref_missing = false,
        .url_ok = true,
    };
}

test "missing path clones" {
    try std.testing.expectEqual(Decision.clone, decide(baseFacts()));
}

test "worktree primary refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_worktree = true;
    try std.testing.expectEqual(Decision{ .refuse = .is_worktree }, decide(f));
}

test "not a repo refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = false;
    try std.testing.expectEqual(Decision{ .refuse = .not_a_repo }, decide(f));
}

test "detached head refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.detached = true;
    try std.testing.expectEqual(Decision{ .refuse = .detached }, decide(f));
}

test "unborn refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.unborn = true;
    try std.testing.expectEqual(Decision{ .refuse = .unborn }, decide(f));
}

test "url mismatch refuses before dirtiness" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.url_ok = false;
    f.dirty_tracked = true;
    try std.testing.expectEqual(Decision{ .refuse = .url_mismatch }, decide(f));
}

test "wrong branch refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "wip/foo";
    f.expected_branch = "afterparty";
    try std.testing.expectEqual(Decision{ .refuse = .wrong_branch }, decide(f));
}

test "missing origin ref refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "main";
    f.expected_branch = "main";
    f.origin_ref_missing = true;
    try std.testing.expectEqual(Decision{ .refuse = .no_origin_branch }, decide(f));
}

test "dirty refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "main";
    f.expected_branch = "main";
    f.dirty_tracked = true;
    f.untracked_count = 1;
    try std.testing.expectEqual(Decision{ .refuse = .dirty }, decide(f));
}

test "diverged refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "main";
    f.expected_branch = "main";
    f.ahead = 2;
    f.behind = 3;
    try std.testing.expectEqual(Decision{ .refuse = .diverged }, decide(f));
}

test "ahead refuses" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "main";
    f.expected_branch = "main";
    f.ahead = 1;
    try std.testing.expectEqual(Decision{ .refuse = .ahead }, decide(f));
}

test "behind fast-forwards" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "main";
    f.expected_branch = "main";
    f.behind = 1;
    try std.testing.expectEqual(Decision.ff_only, decide(f));
}

test "clean and current is noop" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "main";
    f.expected_branch = "main";
    try std.testing.expectEqual(Decision.noop, decide(f));
}

test "untracked only is not dirty" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "main";
    f.expected_branch = "main";
    f.untracked_count = 4;
    try std.testing.expectEqual(Decision.noop, decide(f));
}

test "expected branch absent skips wrong branch check" {
    var f = baseFacts();
    f.path_exists = true;
    f.is_repo = true;
    f.branch = "whatever";
    try std.testing.expectEqual(Decision.noop, decide(f));
}
