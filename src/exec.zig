//! Sequential named-command execution for `fmr check` and `fmr run`.
//! Handles placeholder expansion, sequential policy enforcement, environment
//! injection, subprocess output forwarding, and exit code aggregation per the
//! slice-1 specification.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const ui = @import("ui.zig");

/// Run check commands sequentially across the given repo names.
///
/// Resolution order per repo (already applied by the config loader):
///   1. `repo.check` set from explicit repo-level `check.argv`.
///   2. `repo.check` set from `defaults[kind].check.argv`.
///   3. null → print `[skip]` and continue.
///
/// Exit codes:
///   0 — all executed checks exited 0.
///   4 — any subprocess exited non-zero.
pub fn runCheck(
    ctx: *const process.Ctx,
    cfg: *const config.Config,
    names: []const []const u8,
    json_out: bool,
    pr: *const ui.Printer,
) u8 {
    var max_exit: u8 = 0;
    const Entry = struct {
        name: []const u8,
        status: []const u8,
        exit: u8,
        message: []const u8,
    };
    var entries = ArrayList(Entry).init(ctx.alloc);

    for (names) |name| {
        const repo = cfg.findRepo(name) orelse {
            // Caller (main.zig) pre-validates names; this is a safety net.
            process.stderrLineNewline(ctx, "fmr: unknown repo '{s}'", .{name});
            return 2;
        };
        const check_argv = repo.check orelse {
            if (!json_out) pr.line(ctx, .gray, "[skip] {s}: no check defined", .{name});
            entries.append(.{ .name = name, .status = "skipped", .exit = 0, .message = "no check defined" }) catch return 1;
            continue;
        };
        const repo_path = buildRepoPath(ctx, cfg, name) orelse return 1;
        const expanded = expandArgv(ctx, check_argv, cfg, repo_path, name, repo.default_branch) orelse return 1;
        const res = process.run(ctx, expanded, .{
            .cwd = repo_path,
            .env = repo.env,
        }) catch {
            if (!json_out) process.stderrLineNewline(ctx, "fmr: failed to spawn check for '{s}'", .{name});
            entries.append(.{ .name = name, .status = "failed", .exit = 4, .message = "failed to spawn check" }) catch return 1;
            if (4 > max_exit) max_exit = 4;
            continue;
        };
        if (res.ok()) {
            if (!json_out) pr.line(ctx, .green, "[ok] {s}", .{name});
            entries.append(.{ .name = name, .status = "ok", .exit = 0, .message = "check passed" }) catch return 1;
        } else {
            const code = res.exited() orelse 1;
            if (!json_out) pr.line(ctx, .red, "[fail] {s}: {s} exited with code {d}", .{ name, expanded[0], code });
            const msg = std.fmt.allocPrint(ctx.alloc, "{s} exited with code {d}", .{ expanded[0], code }) catch "failed";
            entries.append(.{ .name = name, .status = "failed", .exit = 4, .message = msg }) catch return 1;
            if (4 > max_exit) max_exit = 4;
        }
    }

    if (json_out) {
        var buf = ArrayList(u8).init(ctx.alloc);
        buf.appendSlice("{\n  \"version\": 1,\n  \"command\": \"check\",\n") catch return 1;
        const exit_line = std.fmt.allocPrint(ctx.alloc, "  \"exit\": {d},\n  \"repos\": [\n", .{max_exit}) catch return 1;
        buf.appendSlice(exit_line) catch return 1;

        for (entries.items, 0..) |e, i| {
            const item = std.fmt.allocPrint(ctx.alloc,
                \\    {{
                \\      "name": "{s}",
                \\      "status": "{s}",
                \\      "exit": {d},
                \\      "message": "{s}"
                \\    }}{s}
                \\
            , .{
                e.name,
                e.status,
                e.exit,
                e.message,
                if (i + 1 < entries.items.len) "," else "",
            }) catch return 1;
            buf.appendSlice(item) catch return 1;
        }
        buf.appendSlice("  ]\n}\n") catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, buf.items) catch {};
    }

    return max_exit;
}

/// Run a named custom command for a specific repo.
///
/// Looks up `cmd_name` in `repo.cmd_names` (which already includes kind-default
/// commands merged at config-load time). Appends `extra_args` to the resolved
/// argv and sets `FMR_REPO` / `YARD_REPO` in the subprocess environment.
///
/// Exit codes:
///   0 — subprocess completed successfully.
///   2 — unknown repo or command not defined for that repo.
///   4 — subprocess exited non-zero.
pub fn runCmd(
    ctx: *const process.Ctx,
    cfg: *const config.Config,
    repo_name: []const u8,
    cmd_name: []const u8,
    extra_args: []const []const u8,
    pr: *const ui.Printer,
) u8 {
    _ = pr;
    const repo = cfg.findRepo(repo_name) orelse {
        process.stderrLineNewline(ctx, "fmr: unknown repo '{s}'", .{repo_name});
        var known = ArrayList([]const u8).init(ctx.alloc);
        for (cfg.repos) |*r| known.append(r.name) catch {};
        process.stderrLineNewline(ctx, "known repos: {s}", .{std.mem.join(ctx.alloc, ", ", known.items) catch ""});
        return 2;
    };

    var found_argv: ?[]const []const u8 = null;
    for (repo.cmd_names, 0..) |n, i| {
        if (std.mem.eql(u8, n, cmd_name)) {
            found_argv = repo.cmd_argv[i];
            break;
        }
    }
    if (found_argv == null) {
        process.stderrLineNewline(ctx, "fmr: command '{s}' not defined for repo '{s}'", .{ cmd_name, repo_name });
        if (repo.cmd_names.len > 0) {
            process.stderrLineNewline(ctx, "available commands: {s}", .{std.mem.join(ctx.alloc, ", ", repo.cmd_names) catch ""});
        } else {
            process.stderrLineNewline(ctx, "available commands: (none)", .{});
        }
        return 2;
    }

    const repo_path = buildRepoPath(ctx, cfg, repo_name) orelse return 1;
    const base = expandArgv(ctx, found_argv.?, cfg, repo_path, repo_name, repo.default_branch) orelse return 1;

    var full_argv = ArrayList([]const u8).init(ctx.alloc);
    full_argv.appendSlice(base) catch return 1;
    for (extra_args) |a| full_argv.append(a) catch return 1;

    // Build env: FMR_REPO + YARD_REPO (compat alias) + any repo.env overrides.
    var env_list = ArrayList([]const u8).init(ctx.alloc);
    const fmr_kv = std.fmt.allocPrint(ctx.alloc, "FMR_REPO={s}", .{repo_path}) catch return 1;
    env_list.append(fmr_kv) catch return 1;
    const yard_kv = std.fmt.allocPrint(ctx.alloc, "YARD_REPO={s}", .{repo_path}) catch return 1;
    env_list.append(yard_kv) catch return 1;
    for (repo.env) |kv| env_list.append(kv) catch return 1;

    const res = process.run(ctx, full_argv.items, .{
        .cwd = repo_path,
        .env = env_list.items,
    }) catch {
        process.stderrLineNewline(ctx, "fmr: failed to spawn '{s}' for repo '{s}'", .{ cmd_name, repo_name });
        return 4;
    };

    // Forward subprocess stdout/stderr to our own streams so the caller sees output.
    if (res.stdout.len > 0) std.Io.File.stdout().writeStreamingAll(ctx.io, res.stdout) catch {};
    if (res.stderr.len > 0) std.Io.File.stderr().writeStreamingAll(ctx.io, res.stderr) catch {};

    return if (res.ok()) 0 else 4;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn buildRepoPath(ctx: *const process.Ctx, cfg: *const config.Config, name: []const u8) ?[]const u8 {
    return std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.repos, name }) catch {
        process.stderrLineNewline(ctx, "fmr: out of memory", .{});
        return null;
    };
}

fn expandArgv(
    ctx: *const process.Ctx,
    argv: []const []const u8,
    cfg: *const config.Config,
    repo_path: []const u8,
    name: []const u8,
    branch: ?[]const u8,
) ?[]const []const u8 {
    const exp_ctx = config.ExpandCtx{
        .workspace = cfg.workspace_dir,
        .repo = repo_path,
        .name = name,
        .branch = branch orelse "",
        .rag_out = "",
    };
    var out = ArrayList([]const u8).init(ctx.alloc);
    for (argv) |tok| {
        const e = config.expand(ctx.alloc, tok, exp_ctx) catch {
            process.stderrLineNewline(ctx, "fmr: out of memory", .{});
            return null;
        };
        out.append(e) catch {
            process.stderrLineNewline(ctx, "fmr: out of memory", .{});
            return null;
        };
    }
    return out.toOwnedSlice() catch null;
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

test "exec: repo and name placeholder expansion" {
    const alloc = std.testing.allocator;
    const exp_ctx = config.ExpandCtx{
        .workspace = "/ws",
        .repo = "/repos/boris",
        .name = "boris",
        .branch = "main",
        .rag_out = "",
    };
    const out = try config.expand(alloc, "{repo}/run.sh {name}", exp_ctx);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("/repos/boris/run.sh boris", out);
}

test "exec: workspace and branch placeholder expansion" {
    const alloc = std.testing.allocator;
    const exp_ctx = config.ExpandCtx{
        .workspace = "/ws",
        .repo = "/r",
        .name = "n",
        .branch = "afterparty",
        .rag_out = "",
    };
    const out = try config.expand(alloc, "{workspace}/scripts/{name}@{branch}.sh", exp_ctx);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("/ws/scripts/n@afterparty.sh", out);
}

test "exec: unknown token is left literal" {
    const alloc = std.testing.allocator;
    const exp_ctx = config.ExpandCtx{
        .workspace = "/ws",
        .repo = "/r",
        .name = "n",
        .branch = "b",
        .rag_out = "",
    };
    const out = try config.expand(alloc, "{unknown} {name}", exp_ctx);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("{unknown} n", out);
}
