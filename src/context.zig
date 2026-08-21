//! AI-ready workspace context dump.
//! Single-shot markdown / JSON for pasting into LLMs.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const ui = @import("ui.zig");

const CtxRow = struct {
    name: []const u8,
    kind: []const u8,
    path: []const u8,
    url: []const u8,
    branch: []const u8,
    head: []const u8,
    head_full: []const u8,
    default_branch: []const u8,
    ahead: usize,
    behind: usize,
    dirty_tracked: usize,
    untracked: usize,
    snap: []const u8,
    sessions: usize,
    worktrees: [][]const u8,
    commits: [][]const u8,
    check_argv: ?[]const []const u8,
    commands: []const []const u8,
    rag_mode: []const u8,
};

pub fn run(ctx: *const process.Ctx, cfg: *const config.Config, names: []const []const u8, commits_n: usize, json_out: bool, pr: *ui.Printer) u8 {
    var rows = ArrayList(CtxRow).init(ctx.alloc);
    for (names) |name| {
        const repo = cfg.findRepo(name) orelse continue;
        const row = buildRow(ctx, cfg, repo, commits_n) catch CtxRow{
            .name = name,
            .kind = @tagName(repo.kind),
            .path = "",
            .url = repo.url orelse "",
            .branch = "",
            .head = "",
            .head_full = "",
            .default_branch = repo.default_branch orelse "",
            .ahead = 0,
            .behind = 0,
            .dirty_tracked = 0,
            .untracked = 0,
            .snap = "none",
            .sessions = 0,
            .worktrees = &.{},
            .commits = &.{},
            .check_argv = repo.check,
            .commands = repo.cmd_names,
            .rag_mode = if (repo.rag) |r| switch (r) {
                .command => "command",
                .files => "files",
            } else "none",
        };
        rows.append(row) catch return 1;
    }

    if (json_out) {
        var buf = ArrayList(u8).init(ctx.alloc);
        buf.appendSlice("{\n  \"version\": 1,\n  \"command\": \"context\",\n  \"exit\": 0,\n  \"repos\": [\n") catch return 1;
        for (rows.items, 0..) |*r, i| {
            var commits_buf = ArrayList(u8).init(ctx.alloc);
            commits_buf.append('[') catch return 1;
            for (r.commits, 0..) |c, ci| {
                if (ci > 0) commits_buf.appendSlice(", ") catch return 1;
                // json escape
                commits_buf.append('"') catch return 1;
                for (c) |ch| {
                    if (ch == '"') {
                        commits_buf.appendSlice("\\\"") catch return 1;
                    } else if (ch == '\\') {
                        commits_buf.appendSlice("\\\\") catch return 1;
                    } else if (ch == '\n') {
                        commits_buf.appendSlice("\\n") catch return 1;
                    } else {
                        commits_buf.append(ch) catch return 1;
                    }
                }
                commits_buf.append('"') catch return 1;
            }
            commits_buf.append(']') catch return 1;

            var worktrees_buf = ArrayList(u8).init(ctx.alloc);
            worktrees_buf.append('[') catch return 1;
            for (r.worktrees, 0..) |w, wi| {
                if (wi > 0) worktrees_buf.appendSlice(", ") catch return 1;
                worktrees_buf.append('"') catch return 1;
                for (w) |ch| {
                    if (ch == '"') {
                        worktrees_buf.appendSlice("\\\"") catch return 1;
                    } else if (ch == '\\') {
                        worktrees_buf.appendSlice("\\\\") catch return 1;
                    } else {
                        worktrees_buf.append(ch) catch return 1;
                    }
                }
                worktrees_buf.append('"') catch return 1;
            }
            worktrees_buf.append(']') catch return 1;

            var check_json: []const u8 = "null";
            if (r.check_argv) |argv| {
                var cb = ArrayList(u8).init(ctx.alloc);
                cb.append('[') catch return 1;
                for (argv, 0..) |a, ai| {
                    if (ai > 0) cb.appendSlice(", ") catch return 1;
                    cb.append('"') catch return 1;
                    for (a) |ch| {
                        if (ch == '"') {
                            cb.appendSlice("\\\"") catch return 1;
                        } else if (ch == '\\') {
                            cb.appendSlice("\\\\") catch return 1;
                        } else {
                            cb.append(ch) catch return 1;
                        }
                    }
                    cb.append('"') catch return 1;
                }
                cb.append(']') catch return 1;
                check_json = cb.items;
            }

            const entry = std.fmt.allocPrint(ctx.alloc,
                \\    {{
                \\      "name": "{s}",
                \\      "kind": "{s}",
                \\      "path": "{s}",
                \\      "url": "{s}",
                \\      "branch": "{s}",
                \\      "head": "{s}",
                \\      "head_full": "{s}",
                \\      "default_branch": "{s}",
                \\      "ahead": {d},
                \\      "behind": {d},
                \\      "dirty_tracked": {d},
                \\      "untracked": {d},
                \\      "snap": "{s}",
                \\      "sessions": {d},
                \\      "worktrees": {s},
                \\      "commits": {s},
                \\      "check": {s},
                \\      "commands": [{s}],
                \\      "rag_mode": "{s}"
                \\    }}{s}
                \\
            , .{
                r.name,
                r.kind,
                r.path,
                r.url,
                r.branch,
                r.head,
                r.head_full,
                r.default_branch,
                r.ahead,
                r.behind,
                r.dirty_tracked,
                r.untracked,
                r.snap,
                r.sessions,
                worktrees_buf.items,
                commits_buf.items,
                check_json,
                blk: {
                    var cb = ArrayList(u8).init(ctx.alloc);
                    for (r.commands, 0..) |cn, ci| {
                        if (ci > 0) cb.appendSlice(", ") catch break;
                        cb.append('"') catch break;
                        cb.appendSlice(cn) catch break;
                        cb.append('"') catch break;
                    }
                    break :blk cb.items;
                },
                r.rag_mode,
                if (i + 1 < rows.items.len) "," else "",
            }) catch return 1;
            buf.appendSlice(entry) catch return 1;
        }
        buf.appendSlice("  ]\n}\n") catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, buf.items) catch {};
        return 0;
    }

    // human markdown
    for (rows.items) |*r| {
        pr.raw(ctx, "## {s} ({s}) — {s}@{s}", .{ r.name, r.kind, r.branch, r.head });
        pr.raw(ctx, "- path: {s}", .{r.path});
        pr.raw(ctx, "- url: {s}", .{r.url});
        pr.raw(ctx, "- default_branch: {s}", .{r.default_branch});
        pr.raw(ctx, "- state: ahead {d} behind {d} dirty {d} untracked {d} snap {s} sessions {d}", .{ r.ahead, r.behind, r.dirty_tracked, r.untracked, r.snap, r.sessions });
        if (r.check_argv) |argv| {
            pr.raw(ctx, "- check: {s}", .{std.mem.join(ctx.alloc, " ", argv) catch ""});
        } else {
            pr.raw(ctx, "- check: (none)", .{});
        }
        if (r.commands.len > 0) {
            pr.raw(ctx, "- commands: {s}", .{std.mem.join(ctx.alloc, ", ", r.commands) catch ""});
        } else {
            pr.raw(ctx, "- commands: (none)", .{});
        }
        pr.raw(ctx, "- rag: {s}", .{r.rag_mode});
        pr.raw(ctx, "- worktrees ({d}):", .{r.worktrees.len});
        if (r.worktrees.len == 0) pr.raw(ctx, "  (none)", .{}) else for (r.worktrees) |w| pr.raw(ctx, "  - {s}", .{w});
        pr.raw(ctx, "- last {d} commits:", .{r.commits.len});
        if (r.commits.len == 0) pr.raw(ctx, "  (no commits / not a repo)", .{}) else for (r.commits) |c| pr.raw(ctx, "  - {s}", .{c});
        pr.raw(ctx, "", .{});
    }
    return 0;
}

fn buildRow(ctx: *const process.Ctx, cfg: *const config.Config, repo: *const config.Repo, commits_n: usize) !CtxRow {
    const alloc = ctx.alloc;
    const primary = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.repos, repo.name });
    const kind_str = @tagName(repo.kind);
    var branch: []const u8 = "";
    var head: []const u8 = "";
    var head_full: []const u8 = "";
    var ahead: usize = 0;
    var behind: usize = 0;
    var dirty_tracked: usize = 0;
    var untracked: usize = 0;
    var snap: []const u8 = "none";
    var sessions: usize = 0;

    if (git.dirExists(ctx, primary)) {
        const gk = try git.gitDirKind(ctx, primary);
        if (gk == .directory) {
            branch = (try git.headBranch(ctx, primary)) orelse "";
            head = (try git.shortSha(ctx, primary)) orelse "";
            head_full = (try git.fullSha(ctx, primary)) orelse "";
            if (branch.len > 0) {
                if (try git.aheadBehind(ctx, primary, branch)) |ab| {
                    ahead = ab.ahead;
                    behind = ab.behind;
                }
            }
            if (try git.porcelain(ctx, primary)) |p| {
                dirty_tracked = p.tracked_changes;
                untracked = p.untracked;
            }
            if (head_full.len > 0) {
                const snap_dir = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.source_rag, repo.name, head_full });
                if (git.dirExists(ctx, snap_dir)) snap = "ok" else {
                    const cur = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.source_rag, repo.name, "current" });
                    var buf: [1024]u8 = undefined;
                    const n = std.Io.Dir.cwd().readLink(ctx.io, cur, &buf) catch 0;
                    if (n > 0) snap = "stale";
                }
            }
            // sessions
            const wt_root = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.worktrees, repo.name });
            if (std.Io.Dir.cwd().openDir(ctx.io, wt_root, .{ .iterate = true })) |dir| {
                var d = dir;
                defer d.close(ctx.io);
                var it = d.iterate();
                while (it.next(ctx.io) catch null) |e| {
                    if (e.kind == .directory and e.name.len > 0 and e.name[0] != '.') sessions += 1;
                }
            } else |_| {}
        }
    }

    // commits
    var commits = ArrayList([]const u8).init(alloc);
    if (git.dirExists(ctx, primary) and commits_n > 0) {
        const n_str = try std.fmt.allocPrint(alloc, "{d}", .{commits_n});
        const res = try process.run(ctx, &.{ "git", "-C", primary, "log", "--oneline", "-n", n_str }, .{});
        if (res.ok()) {
            var it = std.mem.splitScalar(u8, std.mem.trim(u8, res.stdout, " \t\r\n"), '\n');
            while (it.next()) |line| {
                const t = std.mem.trim(u8, line, " \t\r");
                if (t.len > 0) try commits.append(t);
            }
        }
    }

    // worktrees list
    var worktrees = ArrayList([]const u8).init(alloc);
    if (git.dirExists(ctx, primary)) {
        if (try git.worktreeList(ctx, primary)) |out| {
            var block = ArrayList([]const u8).init(alloc);
            var lines = std.mem.splitScalar(u8, out, '\n');
            while (lines.next()) |line| {
                if (line.len == 0) {
                    if (block.items.len > 0) {
                        const s = try worktreeBlockToString(alloc, block.items);
                        if (s.len > 0) try worktrees.append(s);
                        block.clearRetainingCapacity();
                    }
                    continue;
                }
                try block.append(std.mem.trim(u8, line, " \t"));
            }
            if (block.items.len > 0) {
                const s = try worktreeBlockToString(alloc, block.items);
                if (s.len > 0) try worktrees.append(s);
            }
        }
    }

    return .{
        .name = repo.name,
        .kind = kind_str,
        .path = primary,
        .url = repo.url orelse "",
        .branch = branch,
        .head = head,
        .head_full = head_full,
        .default_branch = repo.default_branch orelse "",
        .ahead = ahead,
        .behind = behind,
        .dirty_tracked = dirty_tracked,
        .untracked = untracked,
        .snap = snap,
        .sessions = sessions,
        .worktrees = try worktrees.toOwnedSlice(),
        .commits = try commits.toOwnedSlice(),
        .check_argv = repo.check,
        .commands = repo.cmd_names,
        .rag_mode = if (repo.rag) |r| switch (r) {
            .command => "command",
            .files => "files",
        } else "none",
    };
}

fn worktreeBlockToString(alloc: std.mem.Allocator, block: []const []const u8) ![]const u8 {
    var path: ?[]const u8 = null;
    var branch: ?[]const u8 = null;
    var head: ?[]const u8 = null;
    for (block) |line| {
        if (std.mem.startsWith(u8, line, "worktree ")) {
            path = line["worktree ".len..];
        } else if (std.mem.startsWith(u8, line, "HEAD ")) {
            head = line["HEAD ".len..];
        } else if (std.mem.startsWith(u8, line, "branch ")) {
            branch = line["branch ".len..];
        }
    }
    if (path == null) return "";
    return std.fmt.allocPrint(alloc, "{s} {s} {s}", .{ path.?, branch orelse "", head orelse "" });
}
