//! Parallel, read-only status inspector.
//! Displays branches, commit SHAs, ahead/behind counts, dirty states, snapshots, and active Conductor sessions.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const ui = @import("ui.zig");

const Row = struct {
    state: enum { ok, missing, not_repo, worktree, detached, unborn },
    branch: []const u8,
    head: []const u8,
    ahead: usize,
    behind: usize,
    dirty_tracked: usize,
    untracked: usize,
    snap: enum { ok, stale, none },
    wt_sessions: usize,
};

pub fn run(ctx: *const process.Ctx, cfg: *const config.Config, names: []const []const u8, pr: *ui.Printer) u8 {
    var arenas = ArrayList(*std.heap.ArenaAllocator).init(ctx.alloc);
    defer for (arenas.items) |a| a.deinit();
    const rows = statusAll(ctx, cfg, names, cfg.parallelism.status, &arenas) catch {
        process.stderrLineNewline(ctx, "fmr status: internal error", .{});
        return 1;
    };
    var max_name: usize = 4;
    var max_branch: usize = 6;
    var max_head: usize = 4;
    for (names, 0..) |name, i| {
        if (name.len > max_name) max_name = name.len;
        if (rows[i].branch.len > max_branch) max_branch = rows[i].branch.len;
        if (rows[i].head.len > max_head) max_head = rows[i].head.len;
    }
    const widths = [3]usize{ max_name, max_branch, max_head };
    pr.row(ctx, &.{ "repo", "branch", "head" }, &widths);
    pr.row(ctx, &.{ "----", "------", "----" }, &widths);
    for (names, 0..) |name, i| {
        const r = &rows[i];
        const head = if (r.head.len > 0) r.head else "-";
        const branch = if (r.branch.len > 0) r.branch else "-";
        pr.row(ctx, &.{ name, branch, head }, &widths);
        const info = switch (r.state) {
            .missing => "  missing (first sync will clone)",
            .not_repo => "  not a git repo",
            .worktree => "  primary is a git worktree — fmr will refuse sync",
            .detached => "  detached HEAD",
            .unborn => "  unborn (no commits)",
            .ok => blk: {
                var parts = ArrayList([]const u8).init(ctx.alloc);
                if (r.behind > 0) parts.append(std.fmt.allocPrint(ctx.alloc, "behind {d}", .{r.behind}) catch "") catch {};
                if (r.ahead > 0) parts.append(std.fmt.allocPrint(ctx.alloc, "ahead {d}", .{r.ahead}) catch "") catch {};
                if (r.dirty_tracked > 0) parts.append(std.fmt.allocPrint(ctx.alloc, "dirty {d}", .{r.dirty_tracked}) catch "") catch {};
                if (r.untracked > 0) parts.append(std.fmt.allocPrint(ctx.alloc, "{d} untracked", .{r.untracked}) catch "") catch {};
                if (parts.items.len == 0) break :blk "clean";
                break :blk std.mem.join(ctx.alloc, ", ", parts.items) catch "";
            },
        };
        const paused = if (!(cfg.findRepo(name) orelse return 1).sync_enabled) "paused (sync disabled), " else "";
        const snap: []const u8 = switch (r.snap) {
            .ok => "snap ok",
            .stale => "snap stale",
            .none => "snap none",
        };
        const wt = if (r.wt_sessions > 0) std.fmt.allocPrint(ctx.alloc, "{d} sessions", .{r.wt_sessions}) catch "-" else "-";
        pr.raw(ctx, "  {s}{s}   {s}   {s}", .{ paused, info, snap, wt });
    }
    return 0;
}

const WorkerState = struct {
    ctx: *const process.Ctx,
    cfg: *const config.Config,
    names: []const []const u8,
    rows: []Row,
    atomic_idx: *std.atomic.Value(usize),
    arena: *std.heap.ArenaAllocator,
};

fn worker(ws: *WorkerState) void {
    const alloc = ws.arena.allocator();
    const thread_ctx = process.Ctx{
        .alloc = alloc,
        .io = ws.ctx.io,
        .environ_map = ws.ctx.environ_map,
    };
    while (true) {
        const idx = ws.atomic_idx.fetchAdd(1, .monotonic);
        if (idx >= ws.names.len) break;
        const repo = ws.cfg.findRepo(ws.names[idx]);
        if (repo == null) {
            ws.rows[idx] = .{ .state = .missing, .branch = "", .head = "", .ahead = 0, .behind = 0, .dirty_tracked = 0, .untracked = 0, .snap = .none, .wt_sessions = 0 };
            continue;
        }
        ws.rows[idx] = statusOne(&thread_ctx, ws.cfg, repo.?, alloc) catch Row{
            .state = .not_repo,
            .branch = "",
            .head = "",
            .ahead = 0,
            .behind = 0,
            .dirty_tracked = 0,
            .untracked = 0,
            .snap = .none,
            .wt_sessions = 0,
        };
    }
}

fn statusAll(ctx: *const process.Ctx, cfg: *const config.Config, names: []const []const u8, jobs: usize, arenas: *ArrayList(*std.heap.ArenaAllocator)) ![]Row {
    const n = names.len;
    const rows = try ctx.alloc.alloc(Row, n);
    if (n == 0) return rows;
    const worker_count = @max(1, @min(jobs, n));
    var atomic_idx = std.atomic.Value(usize).init(0);
    const worker_states = try ctx.alloc.alloc(WorkerState, worker_count);
    const threads = try ctx.alloc.alloc(std.Thread, worker_count);

    for (worker_states, 0..) |*ws, i| {
        const arena = try ctx.alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(ctx.alloc);
        try arenas.append(arena);
        ws.* = .{
            .ctx = ctx,
            .cfg = cfg,
            .names = names,
            .rows = rows,
            .atomic_idx = &atomic_idx,
            .arena = arena,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ws});
    }
    for (threads) |t| t.join();
    return rows;
}

fn statusOne(ctx: *const process.Ctx, cfg: *const config.Config, repo: *const config.Repo, alloc: std.mem.Allocator) !Row {
    const primary = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.repos, repo.name });
    if (!git.dirExists(ctx, primary)) {
        return .{ .state = .missing, .branch = "", .head = "", .ahead = 0, .behind = 0, .dirty_tracked = 0, .untracked = 0, .snap = .none, .wt_sessions = 0 };
    }
    const gk = try git.gitDirKind(ctx, primary);
    if (gk == .absent) {
        return .{ .state = .not_repo, .branch = "", .head = "", .ahead = 0, .behind = 0, .dirty_tracked = 0, .untracked = 0, .snap = .none, .wt_sessions = 0 };
    }
    if (gk == .file) {
        const branch = (try git.headBranch(ctx, primary)) orelse "";
        const head = (try git.shortSha(ctx, primary)) orelse "";
        return .{ .state = .worktree, .branch = branch, .head = head, .ahead = 0, .behind = 0, .dirty_tracked = 0, .untracked = 0, .snap = .none, .wt_sessions = 0 };
    }

    const branch = (try git.headBranch(ctx, primary)) orelse "";
    const head = (try git.shortSha(ctx, primary)) orelse "";
    const commits = try git.hasCommits(ctx, primary);
    if (!commits) {
        return .{ .state = .unborn, .branch = branch, .head = "", .ahead = 0, .behind = 0, .dirty_tracked = 0, .untracked = 0, .snap = .none, .wt_sessions = 0 };
    }

    var row = Row{
        .state = .ok,
        .branch = branch,
        .head = head,
        .ahead = 0,
        .behind = 0,
        .dirty_tracked = 0,
        .untracked = 0,
        .snap = .none,
        .wt_sessions = 0,
    };
    if (branch.len == 0) {
        row.state = .detached;
    }

    if (branch.len > 0) {
        if (try git.aheadBehind(ctx, primary, branch)) |ab| {
            row.ahead = ab.ahead;
            row.behind = ab.behind;
        }
    }
    if (try git.porcelain(ctx, primary)) |p| {
        row.dirty_tracked = p.tracked_changes;
        row.untracked = p.untracked;
    }

    if (try git.fullSha(ctx, primary)) |sha| {
        const snap_dir = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.source_rag, repo.name, sha });
        if (git.dirExists(ctx, snap_dir)) {
            row.snap = .ok;
        } else {
            const current_path = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.source_rag, repo.name, "current" });
            var buf: [1024]u8 = undefined;
            const n = std.Io.Dir.cwd().readLink(ctx.io, current_path, &buf) catch 0;
            if (n > 0) row.snap = .stale;
        }
    }

    const wt_root = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.worktrees, repo.name });
    var count: usize = 0;
    if (std.Io.Dir.cwd().openDir(ctx.io, wt_root, .{ .iterate = true })) |dir| {
        defer dir.close(ctx.io);
        var it = dir.iterate();
        while (it.next(ctx.io) catch null) |entry| {
            if (entry.kind == .directory and entry.name.len > 0 and entry.name[0] != '.') count += 1;
        }
    } else |_| {}
    row.wt_sessions = count;

    return row;
}
