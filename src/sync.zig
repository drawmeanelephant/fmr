//! Safe repository synchronization engine.
//! Clones missing repos, fetches origin, fast-forwards clean branches, and refuses unsafe states.
//! Employs atomic worker pools and per-repo lock management (~/.fmr/locks/<repo>.sync.lock).

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const state = @import("state.zig");
const ui = @import("ui.zig");

pub const Outcome = struct {
    result: enum { ok, refused, failed, skipped },
    line: []const u8,
    details: []const []const u8,
    exit: u8,
};

const fetch_timeout_ns = 10 * 60 * std.time.ns_per_s;

pub fn run(ctx: *const process.Ctx, cfg: *const config.Config, names: []const []const u8, jobs: usize, json_out: bool, pr: *ui.Printer) u8 {
    var arenas = ArrayList(*std.heap.ArenaAllocator).init(ctx.alloc);
    defer for (arenas.items) |a| a.deinit();
    var max_exit: u8 = 0;
    var counts = [4]usize{ 0, 0, 0, 0 };
    const results = syncAll(ctx, cfg, names, jobs, &arenas) catch {
        process.stderrLineNewline(ctx, "fmr sync: internal error", .{});
        return 1;
    };

    for (results) |o| {
        switch (o.result) {
            .ok => counts[0] += 1,
            .refused => counts[1] += 1,
            .failed => counts[2] += 1,
            .skipped => counts[3] += 1,
        }
        if (o.exit > max_exit) max_exit = o.exit;
    }

    if (json_out) {
        var buf = ArrayList(u8).init(ctx.alloc);
        buf.appendSlice("{\n  \"version\": 1,\n  \"command\": \"sync\",\n") catch return 1;
        const exit_line = std.fmt.allocPrint(ctx.alloc, "  \"exit\": {d},\n  \"repos\": [\n", .{max_exit}) catch return 1;
        buf.appendSlice(exit_line) catch return 1;

        for (results, 0..) |o, i| {
            const name = if (i < names.len) names[i] else "";
            const res_str = @tagName(o.result);
            const entry = std.fmt.allocPrint(ctx.alloc,
                \\    {{
                \\      "name": "{s}",
                \\      "result": "{s}",
                \\      "exit": {d},
                \\      "message": "{s}"
                \\    }}{s}
                \\
            , .{
                name,
                res_str,
                o.exit,
                o.line,
                if (i + 1 < results.len) "," else "",
            }) catch return 1;
            buf.appendSlice(entry) catch return 1;
        }

        const summary = std.fmt.allocPrint(ctx.alloc,
            \\  ],
            \\  "summary": {{
            \\    "ok": {d},
            \\    "refused": {d},
            \\    "failed": {d},
            \\    "skipped": {d}
            \\  }}
            \\}}
            \\
        , .{ counts[0], counts[1], counts[2], counts[3] }) catch return 1;
        buf.appendSlice(summary) catch return 1;

        std.Io.File.stdout().writeStreamingAll(ctx.io, buf.items) catch {};
        return max_exit;
    }

    for (results) |o| {
        const color: ui.Color = switch (o.result) {
            .ok => .green,
            .refused => .yellow,
            .failed => .red,
            .skipped => .gray,
        };
        pr.line(ctx, color, "{s}", .{o.line});
        for (o.details) |d| pr.line(ctx, .gray, "  {s}", .{d});
    }
    pr.raw(ctx, "Summary: {d} ok, {d} refused, {d} failed, {d} skipped (exit {d})", .{
        counts[0], counts[1], counts[2], counts[3], max_exit,
    });
    return max_exit;
}

const WorkerState = struct {
    ctx: *const process.Ctx,
    cfg: *const config.Config,
    names: []const []const u8,
    outcomes: []Outcome,
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
            ws.outcomes[idx] = Outcome{
                .result = .failed,
                .line = std.fmt.allocPrint(alloc, "[fail] {s} - unknown repo", .{ws.names[idx]}) catch "fail",
                .details = &.{},
                .exit = 2,
            };
            continue;
        }
        ws.outcomes[idx] = syncOne(&thread_ctx, ws.cfg, repo.?, alloc) catch Outcome{
            .result = .failed,
            .line = std.fmt.allocPrint(alloc, "[fail] {s} - internal error", .{repo.?.name}) catch "internal error",
            .details = &.{},
            .exit = 1,
        };
    }
}

fn syncAll(ctx: *const process.Ctx, cfg: *const config.Config, names: []const []const u8, jobs: usize, arenas: *ArrayList(*std.heap.ArenaAllocator)) ![]Outcome {
    const n = names.len;
    const outcomes = try ctx.alloc.alloc(Outcome, n);
    if (n == 0) return outcomes;
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
            .outcomes = outcomes,
            .atomic_idx = &atomic_idx,
            .arena = arena,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ws});
    }
    for (threads) |t| t.join();
    return outcomes;
}

fn syncOne(ctx: *const process.Ctx, cfg: *const config.Config, repo: *const config.Repo, alloc: std.mem.Allocator) !Outcome {
    const primary = try std.Io.Dir.path.join(alloc, &.{ cfg.paths.repos, repo.name });
    if (!repo.sync_enabled) {
        return Outcome{ .result = .skipped, .line = try std.fmt.allocPrint(alloc, "[skip] {s} - paused (sync disabled)", .{repo.name}), .details = &.{}, .exit = 0 };
    }
    if (repo.url == null) {
        return Outcome{ .result = .skipped, .line = try std.fmt.allocPrint(alloc, "[skip] {s} - no url (local-only)", .{repo.name}), .details = &.{}, .exit = 0 };
    }

    const lock = Lock.acquire(ctx, repo.name) catch {
        return Outcome{ .result = .failed, .line = try std.fmt.allocPrint(alloc, "[fail] {s} - cannot acquire lock", .{repo.name}), .details = &.{}, .exit = 1 };
    };
    if (lock) |owner| {
        var det = ArrayList([]const u8).init(alloc);
        det.append(std.fmt.allocPrint(alloc, "retry when it exits, or remove ~/.fmr/locks/{s}.sync.lock if it is stale", .{repo.name}) catch "") catch {};
        return Outcome{
            .result = .refused,
            .line = try std.fmt.allocPrint(alloc, "[refuse] {s} - another fmr sync holds this repo (pid {d})", .{ repo.name, owner }),
            .details = det.items,
            .exit = 3,
        };
    }
    defer lockRelease(ctx, repo.name);

    if (!git.dirExists(ctx, primary)) {
        const branch = repo.default_branch;
        std.Io.Dir.cwd().createDirPath(ctx.io, cfg.paths.repos) catch {};
        const res = try git.clone(ctx, repo.url.?, branch, primary, fetch_timeout_ns);
        if (!res.ok()) {
            return failOutcome(ctx, alloc, repo.name, "git clone", res);
        }
        const short = (try git.shortSha(ctx, primary)) orelse "?";
        return Outcome{
            .result = .ok,
            .line = try std.fmt.allocPrint(alloc, "[ok] {s} - cloned (fresh, HEAD {s})", .{ repo.name, short }),
            .details = &.{},
            .exit = 0,
        };
    }

    const gk = try git.gitDirKind(ctx, primary);
    if (gk == .file) {
        return refuseOutcome(ctx, alloc, repo.name, .is_worktree, primary, null, null);
    }
    if (gk == .absent) {
        return refuseOutcome(ctx, alloc, repo.name, .not_a_repo, primary, null, null);
    }

    const actual_url = try git.remoteUrl(ctx, primary);
    if (repo.url) |u| {
        if (actual_url == null or !std.mem.eql(u8, actual_url.?, u)) {
            var det = ArrayList([]const u8).init(alloc);
            det.append(std.fmt.allocPrint(alloc, "fix config or run: git -C {s} remote set-url origin {s}", .{ primary, u }) catch "") catch {};
            return Outcome{
                .result = .refused,
                .line = try std.fmt.allocPrint(alloc, "[refuse] {s} - url mismatch (config {s}, origin {s})", .{ repo.name, u, actual_url orelse "<missing>" }),
                .details = det.items,
                .exit = 3,
            };
        }
    }

    const fetch_res = try git.fetch(ctx, primary, fetch_timeout_ns);
    if (!fetch_res.ok()) {
        return failOutcome(ctx, alloc, repo.name, "git fetch --quiet origin", fetch_res);
    }

    const branch = repo.default_branch orelse (try git.originHeadBranch(ctx, primary)) orelse {
        return refuseOutcome(ctx, alloc, repo.name, .no_origin_branch, primary, null, null);
    };

    const facts = try git.gather(ctx, primary, repo.url, branch);
    const decision = state.decide(facts);
    return switch (decision) {
        .clone => unreachable,
        .noop => Outcome{
            .result = .ok,
            .line = try std.fmt.allocPrint(alloc, "[ok] {s} {s} - up to date", .{ repo.name, branch }),
            .details = &.{},
            .exit = 0,
        },
        .ff_only => blk: {
            const before = (try git.shortSha(ctx, primary)) orelse "?";
            const res = try git.ffOnly(ctx, primary, branch);
            if (!res.ok()) {
                break :blk failOutcome(ctx, alloc, repo.name, try std.fmt.allocPrint(alloc, "git merge --ff-only origin/{s}", .{branch}), res);
            }
            const after = (try git.shortSha(ctx, primary)) orelse "?";
            break :blk Outcome{
                .result = .ok,
                .line = try std.fmt.allocPrint(alloc, "[ok] {s} {s} - {s} → {s} (fast-forward)", .{ repo.name, branch, before, after }),
                .details = &.{},
                .exit = 0,
            };
        },
        .refuse => |r| refuseOutcome(ctx, alloc, repo.name, r, primary, branch, facts),
    };
}

fn failOutcome(ctx: *const process.Ctx, alloc: std.mem.Allocator, name: []const u8, cmd: []const u8, res: process.Result) Outcome {
    const tail = tailLines(ctx, res);
    var details = ArrayList([]const u8).init(alloc);
    if (res.timed_out) {
        details.append("timed out") catch {};
    } else if (res.truncated) {
        details.append("output exceeded capture limit") catch {};
    }
    for (tail) |l| details.append(l) catch {};
    const desc = res.describe(alloc) catch "unknown termination";
    return .{
        .result = .failed,
        .line = std.fmt.allocPrint(alloc, "[fail] {s} - {s} {s}", .{ name, cmd, desc }) catch "fail",
        .details = details.items,
        .exit = 4,
    };
}

fn tailLines(ctx: *const process.Ctx, res: process.Result) []const []const u8 {
    const combined = if (res.stderr.len > 0) res.stderr else res.stdout;
    var lines = ArrayList([]const u8).init(ctx.alloc);
    var it = std.mem.splitScalar(u8, combined, '\n');
    var collected = ArrayList([]const u8).init(ctx.alloc);
    while (it.next()) |l| {
        const t = std.mem.trim(u8, l, " \t\r");
        if (t.len > 0) collected.append(t) catch {};
    }
    const items = collected.items;
    var i: usize = if (items.len > 3) items.len - 3 else 0;
    while (i < items.len) : (i += 1) {
        if (items[i].len > 300) {
            lines.append(items[i][0..300]) catch {};
        } else {
            lines.append(items[i]) catch {};
        }
    }
    return lines.items;
}

fn refuseOutcome(
    _: *const process.Ctx,
    alloc: std.mem.Allocator,
    name: []const u8,
    refusal: state.Refusal,
    primary: []const u8,
    branch: ?[]const u8,
    facts: ?state.Facts,
) Outcome {
    const line = std.fmt.allocPrint(alloc, "[refuse] {s} - {s}", .{ name, reasonText(refusal) }) catch "refuse";
    var details = ArrayList([]const u8).init(alloc);
    const detail = struct {
        fn add(list: *ArrayList([]const u8), a: std.mem.Allocator, comptime fmt: []const u8, args: anytype) void {
            list.append(std.fmt.allocPrint(a, fmt, args) catch "") catch {};
        }
    }.add;
    switch (refusal) {
        .is_worktree => {
            detail(&details, alloc, "this primary path is a git worktree (.git is a file)", .{});
            detail(&details, alloc, "fmr syncs primaries only; agent sessions live in worktrees", .{});
        },
        .not_a_repo => {
            detail(&details, alloc, "directory exists but is not a git repository", .{});
            detail(&details, alloc, "fix it manually; fmr never deletes checkouts", .{});
        },
        .detached => {
            detail(&details, alloc, "primary is detached; run: git -C {s} switch {s}", .{ primary, branch orelse "<branch>" });
        },
        .unborn => {
            detail(&details, alloc, "repository has no commits yet", .{});
            detail(&details, alloc, "commit something, or remove the directory manually and re-sync", .{});
        },
        .wrong_branch => {
            const actual = if (facts) |f| f.branch orelse "?" else "?";
            detail(&details, alloc, "primary is on {s}, expected {s}", .{ actual, branch orelse "?" });
            detail(&details, alloc, "agents must use Conductor worktree session branches, not the primary", .{});
            detail(&details, alloc, "fix: git -C {s} switch {s}", .{ primary, branch orelse "<branch>" });
        },
        .dirty => {
            if (facts) |f| {
                detail(&details, alloc, "commit or stash before syncing; worktrees untouched (tracked changes, {d} untracked)", .{f.untracked_count});
            } else {
                detail(&details, alloc, "commit or stash before syncing; worktrees untouched", .{});
            }
            detail(&details, alloc, "inspect: git -C {s} status", .{primary});
        },
        .ahead => {
            detail(&details, alloc, "push from a Conductor worktree, or: git -C {s} push origin {s}", .{ primary, branch orelse "<branch>" });
        },
        .diverged => {
            detail(&details, alloc, "do the rebase in a Conductor worktree, or force-with-lease if intentional", .{});
            detail(&details, alloc, "git -C {s} rebase origin/{s}", .{ primary, branch orelse "<branch>" });
        },
        .url_mismatch => {
            detail(&details, alloc, "config url differs from actual origin remote", .{});
        },
        .no_origin_branch => {
            detail(&details, alloc, "origin/{s} does not exist on origin; check default_branch in config", .{branch orelse "<branch>"});
            detail(&details, alloc, "inspect: git -C {s} branch -r", .{primary});
        },
    }
    return .{ .result = .refused, .line = line, .details = details.items, .exit = 3 };
}

fn reasonText(r: state.Refusal) []const u8 {
    return switch (r) {
        .is_worktree => "primary is a git worktree",
        .not_a_repo => "not a git repository",
        .detached => "detached HEAD",
        .unborn => "unborn branch (no commits)",
        .wrong_branch => "primary is on the wrong branch",
        .dirty => "dirty working tree",
        .ahead => "primary is ahead of origin",
        .diverged => "primary diverged from origin",
        .url_mismatch => "url mismatch",
        .no_origin_branch => "origin branch missing",
    };
}

const Lock = struct {
    fn acquire(ctx: *const process.Ctx, name: []const u8) !?i32 {
        const home_dir = process.home(ctx) orelse return null;
        const locks_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ home_dir, ".fmr", "locks" });
        std.Io.Dir.cwd().createDirPath(ctx.io, locks_dir) catch return error.LockFailed;
        const lock_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ locks_dir, try std.fmt.allocPrint(ctx.alloc, "{s}.sync.lock", .{name}) });
        const pid_path = try std.Io.Dir.path.join(ctx.alloc, &.{ lock_dir, "pid" });
        var attempt: usize = 0;
        while (attempt < 5) : (attempt += 1) {
            if (std.Io.Dir.cwd().createDir(ctx.io, lock_dir, .default_dir)) |_| {
                var f = std.Io.Dir.cwd().createFile(ctx.io, pid_path, .{ .truncate = true }) catch return error.LockFailed;
                defer f.close(ctx.io);
                var buf: [32]u8 = undefined;
                const s = try std.fmt.bufPrint(&buf, "{d}", .{std.c.getpid()});
                f.writeStreamingAll(ctx.io, s) catch return error.LockFailed;
                return null;
            } else |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return error.LockFailed,
            }
            const pid_text = std.Io.Dir.cwd().readFileAlloc(ctx.io, pid_path, ctx.alloc, .limited(64)) catch {
                sleepMs(25);
                continue;
            };
            const pid = std.fmt.parseInt(i32, std.mem.trim(u8, pid_text, " \t\r\n"), 10) catch {
                sleepMs(25);
                continue;
            };
            if (pidAlive(pid)) return pid;
            std.Io.Dir.cwd().deleteTree(ctx.io, lock_dir) catch {};
            sleepMs(10);
        }
        return error.LockFailed;
    }
};

fn sleepMs(ms: u64) void {
    const ts = std.posix.timespec{
        .sec = @intCast(ms / 1000),
        .nsec = @intCast((ms % 1000) * 1_000_000),
    };
    _ = std.posix.system.nanosleep(&ts, null);
}

fn lockRelease(ctx: *const process.Ctx, name: []const u8) void {
    const home_dir = process.home(ctx) orelse return;
    const lock_name = std.fmt.allocPrint(ctx.alloc, "{s}.sync.lock", .{name}) catch return;
    const lock_dir = std.Io.Dir.path.join(ctx.alloc, &.{ home_dir, ".fmr", "locks", lock_name }) catch return;
    std.Io.Dir.cwd().deleteTree(ctx.io, lock_dir) catch {};
}

fn pidAlive(pid: i32) bool {
    if (pid <= 0) return false;
    _ = std.posix.kill(pid, @enumFromInt(0)) catch |err| switch (err) {
        error.PermissionDenied => return true,
        else => return false,
    };
    return true;
}
