//! Offline diagnostic suite.
//! Verifies git installation, directory structure, root overlaps, branch hygiene, disk space, and stale locks.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const ui = @import("ui.zig");

const Level = enum { ok, warn, problem };

const Check = struct {
    level: Level,
    msg: []const u8,
};

const min_free_kib: usize = 1 << 20;

pub fn run(ctx: *const process.Ctx, cfg: *const config.Config, fix: bool, json_out: bool, pr: *ui.Printer) u8 {
    if (fix) {
        fixStale(ctx, cfg, pr) catch {
            process.stderrLineNewline(ctx, "fmr doctor --fix: failed during remediation", .{});
        };
    }

    const checks = runChecks(ctx, cfg) catch {
        process.stderrLineNewline(ctx, "fmr doctor: internal error", .{});
        return 1;
    };
    var problems: usize = 0;
    var warns: usize = 0;
    for (checks) |c| {
        if (c.level == .problem) problems += 1;
        if (c.level == .warn) warns += 1;
    }

    if (json_out) {
        var buf = ArrayList(u8).init(ctx.alloc);
        buf.appendSlice("{\n  \"version\": 1,\n  \"command\": \"doctor\",\n") catch return 1;
        const exit_num: u8 = if (problems > 0) 1 else 0;
        const header = std.fmt.allocPrint(ctx.alloc, "  \"exit\": {d},\n  \"problems\": {d},\n  \"warnings\": {d},\n  \"checks\": [\n", .{ exit_num, problems, warns }) catch return 1;
        buf.appendSlice(header) catch return 1;

        for (checks, 0..) |c, i| {
            const level_str = @tagName(c.level);
            // Escape any quotes in message
            var clean_msg = ArrayList(u8).init(ctx.alloc);
            for (c.msg) |ch| {
                if (ch == '"') {
                    clean_msg.appendSlice("\\\"") catch return 1;
                } else if (ch == '\\') {
                    clean_msg.appendSlice("\\\\") catch return 1;
                } else {
                    clean_msg.append(ch) catch return 1;
                }
            }

            const entry = std.fmt.allocPrint(ctx.alloc,
                \\    {{
                \\      "level": "{s}",
                \\      "message": "{s}"
                \\    }}{s}
                \\
            , .{
                level_str,
                clean_msg.items,
                if (i + 1 < checks.len) "," else "",
            }) catch return 1;
            buf.appendSlice(entry) catch return 1;
        }

        buf.appendSlice("  ]\n}\n") catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, buf.items) catch {};
        return exit_num;
    }

    for (checks) |c| {
        const color: ui.Color = switch (c.level) {
            .ok => .green,
            .warn => .yellow,
            .problem => .red,
        };
        const tag: []const u8 = switch (c.level) {
            .ok => "ok",
            .warn => "warn",
            .problem => "problem",
        };
        pr.line(ctx, color, "[{s}] {s}", .{ tag, c.msg });
    }
    pr.raw(ctx, "doctor: {d} problems, {d} warnings", .{ problems, warns });
    return if (problems > 0) 1 else 0;
}

pub fn fixStale(ctx: *const process.Ctx, cfg: *const config.Config, pr: *ui.Printer) !void {
    const home_dir = process.home(ctx) orelse return;

    // 1. Clean stale locks
    inline for (.{ ".fmr", ".yard" }) |base_name| {
        const locks_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ home_dir, base_name, "locks" });
        if (std.Io.Dir.cwd().openDir(ctx.io, locks_dir, .{ .iterate = true })) |dir_val| {
            var dir = dir_val;
            defer dir.close(ctx.io);
            var it = dir.iterate();
            while (it.next(ctx.io) catch null) |entry| {
                if (entry.kind != .directory) continue;
                const lock_path = try std.Io.Dir.path.join(ctx.alloc, &.{ locks_dir, entry.name });
                const pid_path = try std.Io.Dir.path.join(ctx.alloc, &.{ lock_path, "pid" });
                if (std.Io.Dir.cwd().readFileAlloc(ctx.io, pid_path, ctx.alloc, .limited(64))) |pid_text| {
                    defer ctx.alloc.free(pid_text);
                    if (std.fmt.parseInt(i32, std.mem.trim(u8, pid_text, " \t\r\n"), 10)) |pid| {
                        if (!pidAlive(pid)) {
                            std.Io.Dir.cwd().deleteTree(ctx.io, lock_path) catch {};
                            pr.line(ctx, .yellow, "[fix] removed stale lock {s} (dead pid {d})", .{ entry.name, pid });
                        }
                    } else |_| {
                        std.Io.Dir.cwd().deleteTree(ctx.io, lock_path) catch {};
                        pr.line(ctx, .yellow, "[fix] removed invalid lock {s}", .{entry.name});
                    }
                } else |_| {
                    std.Io.Dir.cwd().deleteTree(ctx.io, lock_path) catch {};
                    pr.line(ctx, .yellow, "[fix] removed empty lock {s}", .{entry.name});
                }
            }
        } else |_| {}
    }

    // 2. Clean stale staging directories in source-rag
    for (cfg.repos) |*r| {
        const staging_root = try std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.source_rag, r.name, ".staging" });
        if (std.Io.Dir.cwd().openDir(ctx.io, staging_root, .{ .iterate = true })) |sdir_val| {
            var sdir = sdir_val;
            defer sdir.close(ctx.io);
            var it = sdir.iterate();
            while (it.next(ctx.io) catch null) |entry| {
                const sub_staging = try std.Io.Dir.path.join(ctx.alloc, &.{ staging_root, entry.name });
                std.Io.Dir.cwd().deleteTree(ctx.io, sub_staging) catch {};
                pr.line(ctx, .yellow, "[fix] removed stale staging directory {s}", .{entry.name});
            }
        } else |_| {}
    }
}

fn runChecks(ctx: *const process.Ctx, cfg: *const config.Config) ![]Check {
    var checks = ArrayList(Check).init(ctx.alloc);

    const ver = try git.gitVersion(ctx);
    if (ver.ok()) {
        try checks.append(.{ .level = .ok, .msg = std.mem.trim(u8, ver.stdout, " \t\r\n") });
    } else {
        try checks.append(.{ .level = .problem, .msg = "git is not available on PATH" });
    }

    try checks.appendSlice(try rootChecks(ctx, cfg));
    try checks.appendSlice(try overlapChecks(ctx, cfg));
    try checks.appendSlice(try repoChecks(ctx, cfg));
    try checks.appendSlice(try lockChecks(ctx));
    try checks.appendSlice(try diskChecks(ctx, cfg));

    return checks.toOwnedSlice();
}

fn rootChecks(ctx: *const process.Ctx, cfg: *const config.Config) ![]Check {
    var checks = ArrayList(Check).init(ctx.alloc);
    inline for (.{ "repos", "worktrees", "source-rag" }) |label| {
        const path: []const u8 = if (std.mem.eql(u8, label, "repos"))
            cfg.paths.repos
        else if (std.mem.eql(u8, label, "worktrees"))
            cfg.paths.worktrees
        else
            cfg.paths.source_rag;
        if (git.dirExists(ctx, path)) {
            try checks.append(.{ .level = .ok, .msg = try std.fmt.allocPrint(ctx.alloc, "{s} root exists: {s}", .{ label, path }) });
        } else {
            try checks.append(.{ .level = .problem, .msg = try std.fmt.allocPrint(ctx.alloc, "{s} root missing: {s} (created on demand by fmr sync)", .{ label, path }) });
        }
    }
    return checks.toOwnedSlice();
}

fn overlapChecks(ctx: *const process.Ctx, cfg: *const config.Config) ![]Check {
    var checks = ArrayList(Check).init(ctx.alloc);
    const pairs = [_][2][]const u8{
        .{ cfg.paths.repos, cfg.paths.worktrees },
        .{ cfg.paths.repos, cfg.paths.source_rag },
        .{ cfg.paths.worktrees, cfg.paths.source_rag },
    };
    inline for (pairs) |pair| {
        if (pathsOverlap(pair[0], pair[1])) {
            try checks.append(.{ .level = .problem, .msg = try std.fmt.allocPrint(ctx.alloc, "path overlap: {s} and {s} must be separate roots", .{ pair[0], pair[1] }) });
        }
    }
    if (checks.items.len == 0) {
        try checks.append(.{ .level = .ok, .msg = "roots do not overlap" });
    }
    return checks.toOwnedSlice();
}

fn pathsOverlap(a: []const u8, b: []const u8) bool {
    const na = std.mem.trimEnd(u8, a, "/");
    const nb = std.mem.trimEnd(u8, b, "/");
    if (std.mem.eql(u8, na, nb)) return true;
    if (na.len > nb.len and std.mem.startsWith(u8, na, nb) and na[nb.len] == '/') return true;
    if (nb.len > na.len and std.mem.startsWith(u8, nb, na) and nb[na.len] == '/') return true;
    return false;
}

fn repoChecks(ctx: *const process.Ctx, cfg: *const config.Config) ![]Check {
    var checks = ArrayList(Check).init(ctx.alloc);
    for (cfg.repos) |*repo| {
        const primary = try std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.repos, repo.name });
        if (!git.dirExists(ctx, primary)) {
            try checks.append(.{ .level = .ok, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: not cloned yet (fine)", .{repo.name}) });
            continue;
        }
        const gk = try git.gitDirKind(ctx, primary);
        if (gk == .file) {
            try checks.append(.{ .level = .problem, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: primary is a git worktree — fmr will refuse sync", .{repo.name}) });
            continue;
        }
        if (gk == .absent) {
            try checks.append(.{ .level = .problem, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: directory exists but is not a git repo", .{repo.name}) });
            continue;
        }

        if (repo.url) |u| {
            const actual = try git.remoteUrl(ctx, primary);
            if (actual == null or !std.mem.eql(u8, actual.?, u)) {
                try checks.append(.{ .level = .problem, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: url mismatch (config {s}, origin {s})", .{ repo.name, u, actual orelse "<missing>" }) });
            } else {
                try checks.append(.{ .level = .ok, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: origin url matches config", .{repo.name}) });
            }
        } else {
            try checks.append(.{ .level = .ok, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: local-only repo (no url)", .{repo.name}) });
        }

        if (repo.default_branch) |expected| {
            const branch = try git.headBranch(ctx, primary);
            if (branch == null) {
                try checks.append(.{ .level = .warn, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: detached HEAD; primary should sit on {s}", .{ repo.name, expected }) });
            } else if (!std.mem.eql(u8, branch.?, expected)) {
                try checks.append(.{ .level = .warn, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: on {s}, expected {s}", .{ repo.name, branch.?, expected }) });
            }
            try checks.appendSlice(try worktreeDefaultBranchChecks(ctx, repo, primary, expected));
        }

        const snap_root = try std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.source_rag, repo.name });
        if (git.dirExists(ctx, snap_root)) {
            const current_path = try std.Io.Dir.path.join(ctx.alloc, &.{ snap_root, "current" });
            var buf: [1024]u8 = undefined;
            const n = std.Io.Dir.cwd().readLink(ctx.io, current_path, &buf) catch 0;
            if (n == 0) {
                try checks.append(.{ .level = .warn, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: source-rag current symlink missing (rag not run yet?)", .{repo.name}) });
            } else {
                const target_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ snap_root, buf[0..n] });
                if (!git.dirExists(ctx, target_dir)) {
                    try checks.append(.{ .level = .warn, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: source-rag current points at missing snapshot {s}", .{ repo.name, buf[0..n] }) });
                }
            }
        }
    }
    return checks.toOwnedSlice();
}

fn worktreeDefaultBranchChecks(
    ctx: *const process.Ctx,
    repo: *const config.Repo,
    primary: []const u8,
    expected: []const u8,
) ![]Check {
    var checks = ArrayList(Check).init(ctx.alloc);
    const out = (try git.worktreeList(ctx, primary)) orelse return checks.toOwnedSlice();
    var block = ArrayList([]const u8).init(ctx.alloc);
    var lines = std.mem.splitScalar(u8, out, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) {
            try checks.appendSlice(try worktreeBlockChecks(ctx, repo, primary, expected, block.items));
            block.clearRetainingCapacity();
            continue;
        }
        try block.append(std.mem.trim(u8, line, " \t"));
    }
    try checks.appendSlice(try worktreeBlockChecks(ctx, repo, primary, expected, block.items));
    return checks.toOwnedSlice();
}

fn worktreeBlockChecks(
    ctx: *const process.Ctx,
    repo: *const config.Repo,
    primary: []const u8,
    expected: []const u8,
    block: []const []const u8,
) ![]Check {
    var checks = ArrayList(Check).init(ctx.alloc);
    var path: ?[]const u8 = null;
    var branch: ?[]const u8 = null;
    const branch_prefix = "branch refs/heads/";
    for (block) |line| {
        if (std.mem.startsWith(u8, line, "worktree ")) {
            path = line["worktree ".len..];
        } else if (std.mem.startsWith(u8, line, branch_prefix)) {
            branch = line[branch_prefix.len..];
        }
    }
    if (path == null) return checks.toOwnedSlice();
    if (std.mem.eql(u8, path.?, primary)) return checks.toOwnedSlice();
    if (branch == null) return checks.toOwnedSlice();
    if (std.mem.eql(u8, branch.?, expected)) {
        try checks.append(.{ .level = .warn, .msg = try std.fmt.allocPrint(ctx.alloc, "{s}: worktree {s} holds the default branch {s}; primary must keep it, agents use session branches", .{ repo.name, path.?, branch.? }) });
    }
    return checks.toOwnedSlice();
}

fn lockChecks(ctx: *const process.Ctx) ![]Check {
    var checks = ArrayList(Check).init(ctx.alloc);
    const home_dir = process.home(ctx) orelse return checks.toOwnedSlice();
    const locks_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ home_dir, ".fmr", "locks" });
    var dir = std.Io.Dir.cwd().openDir(ctx.io, locks_dir, .{ .iterate = true }) catch {
        const yard_locks = try std.Io.Dir.path.join(ctx.alloc, &.{ home_dir, ".yard", "locks" });
        return if (std.Io.Dir.cwd().openDir(ctx.io, yard_locks, .{ .iterate = true })) |ydir| blk: {
            var y = ydir;
            defer y.close(ctx.io);
            var it = y.iterate();
            while (it.next(ctx.io) catch null) |entry| {
                if (entry.kind != .directory) continue;
                const pid_path = try std.Io.Dir.path.join(ctx.alloc, &.{ yard_locks, entry.name, "pid" });
                const pid_text = std.Io.Dir.cwd().readFileAlloc(ctx.io, pid_path, ctx.alloc, .limited(64)) catch continue;
                const pid = std.fmt.parseInt(i32, std.mem.trim(u8, pid_text, " \t\r\n"), 10) catch continue;
                const alive = pidAlive(pid);
                try checks.append(.{ .level = .warn, .msg = try std.fmt.allocPrint(ctx.alloc, "lock {s}: {s} (pid {d})", .{ entry.name, if (alive) "held by a running process" else "stale — remove manually or use doctor --fix (v2)", pid }) });
            }
            break :blk checks.toOwnedSlice();
        } else |_| checks.toOwnedSlice();
    };
    defer dir.close(ctx.io);
    var it = dir.iterate();
    while (it.next(ctx.io) catch null) |entry| {
        if (entry.kind != .directory) continue;
        const pid_path = try std.Io.Dir.path.join(ctx.alloc, &.{ locks_dir, entry.name, "pid" });
        const pid_text = std.Io.Dir.cwd().readFileAlloc(ctx.io, pid_path, ctx.alloc, .limited(64)) catch continue;
        const pid = std.fmt.parseInt(i32, std.mem.trim(u8, pid_text, " \t\r\n"), 10) catch continue;
        const alive = pidAlive(pid);
        try checks.append(.{ .level = .warn, .msg = try std.fmt.allocPrint(ctx.alloc, "lock {s}: {s} (pid {d})", .{ entry.name, if (alive) "held by a running process" else "stale — remove manually or use doctor --fix (v2)", pid }) });
    }
    return checks.toOwnedSlice();
}

fn diskChecks(ctx: *const process.Ctx, cfg: *const config.Config) ![]Check {
    var checks = ArrayList(Check).init(ctx.alloc);
    const roots = [_]struct { label: []const u8, path: []const u8 }{
        .{ .label = "repos", .path = cfg.paths.repos },
        .{ .label = "source-rag", .path = cfg.paths.source_rag },
    };
    for (roots) |root| {
        if (!git.dirExists(ctx, root.path)) continue;
        const avail = try freeKib(ctx, root.path);
        if (avail) |kib| {
            if (kib < min_free_kib) {
                try checks.append(.{ .level = .problem, .msg = try std.fmt.allocPrint(ctx.alloc, "low disk space on {s} root: {d} MiB free", .{ root.label, kib / 1024 }) });
            } else {
                try checks.append(.{ .level = .ok, .msg = try std.fmt.allocPrint(ctx.alloc, "{s} root disk: {d} MiB free", .{ root.label, kib / 1024 }) });
            }
        }
    }
    return checks.toOwnedSlice();
}

fn freeKib(ctx: *const process.Ctx, path: []const u8) !?usize {
    const res = try process.run(ctx, &.{ "df", "-k", path }, .{});
    if (!res.ok()) return null;
    var it = std.mem.splitScalar(u8, res.stdout, '\n');
    _ = it.next() orelse return null;
    const fields = it.next() orelse return null;
    var f = std.mem.tokenizeScalar(u8, std.mem.trim(u8, fields, " \t"), ' ');
    _ = f.next() orelse return null;
    _ = f.next() orelse return null;
    _ = f.next() orelse return null;
    const avail = f.next() orelse return null;
    return std.fmt.parseInt(usize, avail, 10) catch null;
}

fn pidAlive(pid: i32) bool {
    if (pid <= 0) return false;
    _ = std.posix.kill(pid, @enumFromInt(0)) catch |err| switch (err) {
        error.PermissionDenied => return true,
        else => return false,
    };
    return true;
}
