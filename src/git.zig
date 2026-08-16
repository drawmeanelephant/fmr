//! Git subprocess interface and fact extraction layer.
//! Wraps rev-parse, status --porcelain, rev-list, clone, fetch, and ff-only merges.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const state = @import("state.zig");

pub const GitDir = enum { absent, directory, file };

pub const Porcelain = struct {
    tracked_changes: usize,
    untracked: usize,
    lines: []const []const u8,
};

const ref_prefix = "refs/remotes/origin/";

pub fn dirExists(ctx: *const process.Ctx, path: []const u8) bool {
    std.Io.Dir.cwd().access(ctx.io, path, .{}) catch return false;
    return true;
}

pub fn gitDirKind(ctx: *const process.Ctx, dir: []const u8) !GitDir {
    const git_path = try std.mem.concat(ctx.alloc, u8, &.{ dir, "/.git" });
    const st = std.Io.Dir.cwd().statFile(ctx.io, git_path, .{}) catch return .absent;
    return switch (st.kind) {
        .directory, .sym_link => .directory,
        .file => .file,
        else => .absent,
    };
}

pub fn gitVersion(ctx: *const process.Ctx) !process.Result {
    return process.run(ctx, &.{ "git", "--version" }, .{});
}

pub fn headBranch(ctx: *const process.Ctx, dir: []const u8) !?[]const u8 {
    const res = try process.run(ctx, &.{ "git", "symbolic-ref", "--short", "HEAD" }, .{ .cwd = dir });
    if (!res.ok()) return null;
    return std.mem.trim(u8, res.stdout, " \t\r\n");
}

pub fn hasCommits(ctx: *const process.Ctx, dir: []const u8) !bool {
    const res = try process.run(ctx, &.{ "git", "rev-parse", "--verify", "--quiet", "HEAD" }, .{ .cwd = dir });
    return res.ok();
}

pub fn shortSha(ctx: *const process.Ctx, dir: []const u8) !?[]const u8 {
    const res = try process.run(ctx, &.{ "git", "rev-parse", "--short", "HEAD" }, .{ .cwd = dir });
    if (!res.ok()) return null;
    return std.mem.trim(u8, res.stdout, " \t\r\n");
}

pub fn fullSha(ctx: *const process.Ctx, dir: []const u8) !?[]const u8 {
    const res = try process.run(ctx, &.{ "git", "rev-parse", "HEAD" }, .{ .cwd = dir });
    if (!res.ok()) return null;
    return std.mem.trim(u8, res.stdout, " \t\r\n");
}

pub fn originHeadBranch(ctx: *const process.Ctx, dir: []const u8) !?[]const u8 {
    const res = try process.run(ctx, &.{ "git", "symbolic-ref", "refs/remotes/origin/HEAD" }, .{ .cwd = dir });
    if (!res.ok()) return null;
    const t = std.mem.trim(u8, res.stdout, " \t\r\n");
    return if (std.mem.startsWith(u8, t, ref_prefix)) t[ref_prefix.len..] else t;
}

pub fn remoteUrl(ctx: *const process.Ctx, dir: []const u8) !?[]const u8 {
    const res = try process.run(ctx, &.{ "git", "remote", "get-url", "origin" }, .{ .cwd = dir });
    if (!res.ok()) return null;
    return std.mem.trim(u8, res.stdout, " \t\r\n");
}

pub fn porcelain(ctx: *const process.Ctx, dir: []const u8) !?Porcelain {
    const res = try process.run(ctx, &.{ "git", "status", "--porcelain", "-z" }, .{ .cwd = dir });
    if (!res.ok()) return null;
    var tracked: usize = 0;
    var untracked: usize = 0;
    var lines = ArrayList([]const u8).init(ctx.alloc);
    var it = std.mem.splitScalar(u8, res.stdout, 0);
    while (it.next()) |entry| {
        if (entry.len < 3) continue;
        const xy = entry[0..2];
        if (std.mem.eql(u8, xy, "??")) {
            untracked += 1;
        } else {
            tracked += 1;
        }
        if (lines.items.len < 8) try lines.append(entry);
        if (xy[0] == 'R' or xy[0] == 'C' or xy[1] == 'R' or xy[1] == 'C') {
            _ = it.next();
        }
    }
    return .{
        .tracked_changes = tracked,
        .untracked = untracked,
        .lines = try lines.toOwnedSlice(),
    };
}

pub const AheadBehind = struct {
    ahead: usize,
    behind: usize,
};

pub fn aheadBehind(ctx: *const process.Ctx, dir: []const u8, branch: []const u8) !?AheadBehind {
    const origin_ref = try std.mem.concat(ctx.alloc, u8, &.{ ref_prefix, branch });
    const range = try std.mem.concat(ctx.alloc, u8, &.{ "HEAD...", origin_ref });
    var argv = ArrayList([]const u8).init(ctx.alloc);
    try argv.append("git");
    try argv.append("rev-list");
    try argv.append("--left-right");
    try argv.append("--count");
    try argv.append(range);
    const res = try process.run(ctx, argv.items, .{ .cwd = dir });
    if (!res.ok()) return null;
    var it = std.mem.tokenizeAny(u8, std.mem.trim(u8, res.stdout, " \t\r\n"), " \t");
    const l = it.next() orelse return null;
    const r = it.next() orelse return null;
    const ahead = std.fmt.parseInt(usize, l, 10) catch return null;
    const behind = std.fmt.parseInt(usize, r, 10) catch return null;
    return .{ .ahead = ahead, .behind = behind };
}

pub fn clone(ctx: *const process.Ctx, url: []const u8, branch: ?[]const u8, dest: []const u8, timeout_ns: u64) !process.Result {
    var argv = ArrayList([]const u8).init(ctx.alloc);
    try argv.append("git");
    try argv.append("clone");
    try argv.append("--quiet");
    if (branch) |b| {
        try argv.append("-b");
        try argv.append(b);
    }
    try argv.append(url);
    try argv.append(dest);
    return process.run(ctx, argv.items, .{ .timeout_ns = timeout_ns });
}

pub fn fetch(ctx: *const process.Ctx, dir: []const u8, timeout_ns: u64) !process.Result {
    return process.run(ctx, &.{ "git", "fetch", "--quiet", "origin" }, .{ .cwd = dir, .timeout_ns = timeout_ns });
}

pub fn ffOnly(ctx: *const process.Ctx, dir: []const u8, branch: []const u8) !process.Result {
    const origin_ref = try std.mem.concat(ctx.alloc, u8, &.{ ref_prefix, branch });
    return process.run(ctx, &.{ "git", "merge", "--ff-only", origin_ref }, .{ .cwd = dir });
}

pub fn worktreeList(ctx: *const process.Ctx, dir: []const u8) !?[]const u8 {
    const res = try process.run(ctx, &.{ "git", "worktree", "list", "--porcelain" }, .{ .cwd = dir });
    if (!res.ok()) return null;
    return std.mem.trim(u8, res.stdout, " \t\r\n");
}

pub fn gather(ctx: *const process.Ctx, dir: []const u8, cfg_url: ?[]const u8, expected_branch: ?[]const u8) !state.Facts {
    const url_ok = if (cfg_url) |cu|
        if (try remoteUrl(ctx, dir)) |ru| std.mem.eql(u8, cu, ru) else false
    else
        true;

    const branch = try headBranch(ctx, dir);
    const commits = try hasCommits(ctx, dir);
    const detached = branch == null and commits;
    const unborn = !commits;

    var tracked: usize = 0;
    var untracked: usize = 0;
    if (commits) {
        if (try porcelain(ctx, dir)) |p| {
            tracked = p.tracked_changes;
            untracked = p.untracked;
        }
    }

    var ahead: usize = 0;
    var behind: usize = 0;
    var origin_ref_missing = false;
    if (!unborn and !detached) {
        if (try aheadBehind(ctx, dir, branch.?)) |ab| {
            ahead = ab.ahead;
            behind = ab.behind;
        } else {
            origin_ref_missing = true;
        }
    }

    return .{
        .path_exists = true,
        .is_worktree = false,
        .is_repo = true,
        .detached = detached,
        .unborn = unborn,
        .branch = branch,
        .expected_branch = expected_branch,
        .dirty_tracked = tracked > 0,
        .untracked_count = untracked,
        .ahead = ahead,
        .behind = behind,
        .origin_ref_missing = origin_ref_missing,
        .url_ok = url_ok,
    };
}
