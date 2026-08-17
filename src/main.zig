//! Entrypoint for the fmr (Fix My Repository) workspace manager CLI.
//! Handles argument parsing, command dispatch, and exit code aggregation.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const sync = @import("sync.zig");
const status = @import("status.zig");
const doctor = @import("doctor.zig");
const exec = @import("exec.zig");
const rag = @import("rag.zig");
const ui = @import("ui.zig");

pub fn main(init: std.process.Init) u8 {
    const ctx = process.Ctx{
        .alloc = init.arena.allocator(),
        .io = init.io,
        .environ_map = init.environ_map,
    };

    var args_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_it.next();
    var argv = ArrayList([]const u8).init(ctx.alloc);
    while (args_it.next()) |a| argv.append(a) catch return 1;

    var config_path: ?[]const u8 = null;
    var jobs: ?usize = null;
    var force = false;
    var fix = false;
    var gc_keep: ?usize = null;
    var json_out = false;
    var cmd: ?[]const u8 = null;
    var repo_args = ArrayList([]const u8).init(ctx.alloc);

    var i: usize = 0;
    while (i < argv.items.len) : (i += 1) {
        const a = argv.items[i];
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            return help(&ctx);
        } else if (std.mem.eql(u8, a, "--config")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing path after --config");
            config_path = argv.items[i];
        } else if (std.mem.eql(u8, a, "--jobs")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing value after --jobs");
            jobs = std.fmt.parseInt(usize, argv.items[i], 10) catch return usage(&ctx, "--jobs expects a positive integer");
            if (jobs.? == 0) return usage(&ctx, "--jobs expects a positive integer");
        } else if (std.mem.eql(u8, a, "--gc")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing count after --gc");
            gc_keep = std.fmt.parseInt(usize, argv.items[i], 10) catch return usage(&ctx, "--gc expects an integer");
        } else if (std.mem.eql(u8, a, "--force") or std.mem.eql(u8, a, "-f")) {
            force = true;
        } else if (std.mem.eql(u8, a, "--fix")) {
            fix = true;
        } else if (std.mem.eql(u8, a, "--json")) {
            json_out = true;
        } else if (std.mem.eql(u8, a, "-a") or std.mem.eql(u8, a, "--all")) {
            continue;
        } else if (a.len > 0 and a[0] == '-') {
            return usage(&ctx, "unknown flag");
        } else if (cmd == null) {
            cmd = a;
        } else {
            // For `run`, extra args after the command name must not be deduplicated
            // since they are forwarded verbatim to the subprocess.
            const is_run = std.mem.eql(u8, cmd.?, "run");
            if (!is_run) {
                var exists = false;
                for (repo_args.items) |existing| {
                    if (std.mem.eql(u8, existing, a)) {
                        exists = true;
                        break;
                    }
                }
                if (exists) continue;
            }
            repo_args.append(a) catch return 1;
        }
    }

    const path = config_path orelse (defaultConfigPath(&ctx) catch null) orelse {
        process.stderrLineNewline(&ctx, "fmr: HOME not set; cannot find default config", .{});
        return 1;
    };

    var diag = config.Diag.init(ctx.alloc);
    defer diag.deinit();
    var cfg = config.load(&ctx, path, &diag) catch |err| switch (err) {
        error.OutOfMemory => return 1,
        error.InvalidConfig => {
            for (diag.msgs.items) |m| process.stderrLineNewline(&ctx, "{s}", .{m});
            process.stderrLineNewline(&ctx, "fmr: config invalid (exit 5)", .{});
            return 5;
        },
    };

    const c = cmd orelse return usage(&ctx, "missing command");
    var pr = ui.Printer.initFromCtx(&ctx);

    if (std.mem.eql(u8, c, "status")) {
        if (repo_args.items.len > 0) {
            if (unknownRepo(&ctx, &cfg, repo_args.items)) return 2;
        }
        var names = ArrayList([]const u8).init(ctx.alloc);
        if (repo_args.items.len > 0) {
            names.appendSlice(repo_args.items) catch return 1;
        } else {
            for (cfg.repos) |*r| names.append(r.name) catch return 1;
        }
        return status.run(&ctx, &cfg, names.items, json_out, &pr);
    } else if (std.mem.eql(u8, c, "sync")) {
        if (unknownRepo(&ctx, &cfg, repo_args.items)) return 2;
        var names = ArrayList([]const u8).init(ctx.alloc);
        if (repo_args.items.len > 0) {
            names.appendSlice(repo_args.items) catch return 1;
        } else {
            for (cfg.repos) |*r| names.append(r.name) catch return 1;
        }
        return sync.run(&ctx, &cfg, names.items, jobs orelse cfg.parallelism.sync, json_out, &pr);
    } else if (std.mem.eql(u8, c, "doctor")) {
        if (repo_args.items.len > 0) return usage(&ctx, "doctor takes no repo arguments");
        return doctor.run(&ctx, &cfg, fix, json_out, &pr);
    } else if (std.mem.eql(u8, c, "config")) {
        if (repo_args.items.len > 0) return usage(&ctx, "config takes no repo arguments");
        return config.writeCatalogJson(&ctx, &cfg);
    } else if (std.mem.eql(u8, c, "check")) {
        if (repo_args.items.len > 0) {
            if (unknownRepo(&ctx, &cfg, repo_args.items)) return 2;
        }
        var names = ArrayList([]const u8).init(ctx.alloc);
        if (repo_args.items.len > 0) {
            names.appendSlice(repo_args.items) catch return 1;
        } else {
            for (cfg.repos) |*r| names.append(r.name) catch return 1;
        }
        return exec.runCheck(&ctx, &cfg, names.items, json_out, &pr);
    } else if (std.mem.eql(u8, c, "run")) {
        if (repo_args.items.len < 2) return usage(&ctx, "run requires <repo> <command>");
        const run_repo = repo_args.items[0];
        const run_cmd = repo_args.items[1];
        const run_extra = repo_args.items[2..];
        return exec.runCmd(&ctx, &cfg, run_repo, run_cmd, run_extra, &pr);
    } else if (std.mem.eql(u8, c, "rag")) {
        if (repo_args.items.len > 0) {
            if (unknownRepo(&ctx, &cfg, repo_args.items)) return 2;
        }
        var names = ArrayList([]const u8).init(ctx.alloc);
        if (repo_args.items.len > 0) {
            names.appendSlice(repo_args.items) catch return 1;
        } else {
            for (cfg.repos) |*r| names.append(r.name) catch return 1;
        }
        return rag.run(&ctx, &cfg, names.items, force, gc_keep, json_out, &pr);
    } else {
        return usage(&ctx, "unknown command");
    }
}

fn defaultConfigPath(ctx: *const process.Ctx) !?[]u8 {
    const home_dir = process.home(ctx) orelse return null;
    const fmr_path = try std.Io.Dir.path.join(ctx.alloc, &.{ home_dir, "config", "fmr", "workspace.json" });
    if (std.Io.Dir.cwd().access(ctx.io, fmr_path, .{})) |_| {
        return fmr_path;
    } else |_| {}
    const yard_path = try std.Io.Dir.path.join(ctx.alloc, &.{ home_dir, "config", "yard", "workspace.json" });
    if (std.Io.Dir.cwd().access(ctx.io, yard_path, .{})) |_| {
        return yard_path;
    } else |_| {}
    return fmr_path;
}

fn unknownRepo(ctx: *const process.Ctx, cfg: *const config.Config, names: []const []const u8) bool {
    for (names) |n| {
        if (cfg.findRepo(n) == null) {
            var known = ArrayList([]const u8).init(ctx.alloc);
            for (cfg.repos) |*r| known.append(r.name) catch {};
            process.stderrLineNewline(ctx, "fmr: unknown repo '{s}'", .{n});
            process.stderrLineNewline(ctx, "known repos: {s}", .{std.mem.join(ctx.alloc, ", ", known.items) catch ""});
            return true;
        }
    }
    return false;
}

fn help(ctx: *const process.Ctx) u8 {
    process.stderrLineNewline(ctx, "fmr — Workspace Manager in Zig", .{});
    process.stderrLineNewline(ctx, "usage: fmr <command> [repo...] [--all] [--config <path>] [--jobs <n>] [--force] [--fix] [--gc <n>] [--json]", .{});
    process.stderrLineNewline(ctx, "commands: status | sync | doctor | config | check | run | rag", .{});
    return 0;
}

fn usage(ctx: *const process.Ctx, reason: []const u8) u8 {
    if (reason.len > 0) process.stderrLineNewline(ctx, "fmr: {s}", .{reason});
    process.stderrLineNewline(ctx, "usage: fmr <command> [repo...] [--all] [--config <path>] [--jobs <n>] [--force] [--fix] [--gc <n>] [--json]", .{});
    process.stderrLineNewline(ctx, "commands: status | sync | doctor | config | check | run | rag", .{});
    return 2;
}

test {
    _ = @import("config.zig");
    _ = @import("state.zig");
    _ = @import("git.zig");
    _ = @import("process.zig");
    _ = @import("sync.zig");
    _ = @import("status.zig");
    _ = @import("doctor.zig");
    _ = @import("exec.zig");
    _ = @import("rag.zig");
    _ = @import("ui.zig");
}
