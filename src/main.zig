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

/// Version reported by `fmr --version` and embedded into the packaged app.
/// Bump when the CLI contract or behavior changes materially.
pub const version = "0.1.0";

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
    var add_kind: ?[]const u8 = null;
    var add_branch: ?[]const u8 = null;
    var sync_now = false;
    var delete_files = false;
    var cmd: ?[]const u8 = null;
    var repo_args = ArrayList([]const u8).init(ctx.alloc);

    var i: usize = 0;
    while (i < argv.items.len) : (i += 1) {
        const a = argv.items[i];
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            return help(&ctx);
        } else if (std.mem.eql(u8, a, "--version")) {
            const out = std.fmt.allocPrint(ctx.alloc, "fmr {s}\n", .{version}) catch "fmr\n";
            std.Io.File.stdout().writeStreamingAll(ctx.io, out) catch {};
            return 0;
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
        } else if (std.mem.eql(u8, a, "--kind")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing value after --kind");
            add_kind = argv.items[i];
        } else if (std.mem.eql(u8, a, "--branch")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing value after --branch");
            add_branch = argv.items[i];
        } else if (std.mem.eql(u8, a, "--sync")) {
            sync_now = true;
        } else if (std.mem.eql(u8, a, "--no-sync")) {
            sync_now = false;
        } else if (std.mem.eql(u8, a, "--delete-files")) {
            delete_files = true;
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
        return exec.runCmd(&ctx, &cfg, run_repo, run_cmd, run_extra, json_out, &pr);
    } else if (std.mem.eql(u8, c, "add")) {
        if (repo_args.items.len < 1 or repo_args.items.len > 2) return usage(&ctx, "add requires <name> [<url>]");
        const add_url: ?[]const u8 = if (repo_args.items.len > 1) repo_args.items[1] else null;
        return addRepo(&ctx, &cfg, path, repo_args.items[0], add_url, add_kind, add_branch, sync_now, json_out);
    } else if (std.mem.eql(u8, c, "remove")) {
        if (repo_args.items.len < 1) return usage(&ctx, "remove requires <name>");
        return removeRepo(&ctx, &cfg, path, repo_args.items[0], delete_files);
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

fn addRepo(
    ctx: *const process.Ctx,
    cfg: *const config.Config,
    config_path: []const u8,
    name: []const u8,
    url: ?[]const u8,
    kind_str: ?[]const u8,
    branch: ?[]const u8,
    sync_now: bool,
    json_out: bool,
) u8 {
    var kind: ?config.Kind = null;
    if (kind_str) |ks| {
        kind = config.kindFromString(ks) orelse {
            process.stderrLineNewline(ctx, "fmr: unknown kind '{s}' (expected zig, go, node, site, bash, other)", .{ks});
            return 2;
        };
    } else {
        // Auto-detect from an existing local folder at the primary path.
        const primary = std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.repos, name }) catch return 1;
        kind = config.detectKindFromDir(ctx, primary);
    }

    config.addRepoToConfigFile(ctx, config_path, name, url, kind, branch) catch |err| switch (err) {
        error.InvalidName => {
            process.stderrLineNewline(ctx, "fmr: invalid repo name '{s}'", .{name});
            return 2;
        },
        error.InvalidUrl => {
            process.stderrLineNewline(ctx, "fmr: invalid url", .{});
            return 2;
        },
        error.DuplicateRepo => {
            process.stderrLineNewline(ctx, "fmr: repo '{s}' already exists in config", .{name});
            return 2;
        },
        error.UnknownKind => return 2,
        error.InvalidConfig => {
            process.stderrLineNewline(ctx, "fmr: could not update config (exit 5)", .{});
            return 5;
        },
        error.OutOfMemory => return 1,
    };

    process.stderrLineNewline(ctx, "[ok] added repo '{s}' to {s}", .{ name, config_path });

    if (sync_now) {
        var diag = config.Diag.init(ctx.alloc);
        defer diag.deinit();
        var new_cfg = config.load(ctx, config_path, &diag) catch {
            process.stderrLineNewline(ctx, "fmr: config reload failed after add", .{});
            return 5;
        };
        var names = ArrayList([]const u8).init(ctx.alloc);
        names.append(name) catch return 1;
        var pr = ui.Printer.initFromCtx(ctx);
        return sync.run(ctx, &new_cfg, names.items, 1, json_out, &pr);
    }
    return 0;
}

fn removeRepo(ctx: *const process.Ctx, cfg: *const config.Config, config_path: []const u8, name: []const u8, delete_files: bool) u8 {
    const removed = config.removeRepoFromConfigFile(ctx, config_path, name) catch {
        process.stderrLineNewline(ctx, "fmr: could not update config (exit 5)", .{});
        return 5;
    };
    if (!removed) {
        process.stderrLineNewline(ctx, "fmr: repo '{s}' not found in config", .{name});
        return 2;
    }
    process.stderrLineNewline(ctx, "[ok] removed repo '{s}' from {s}", .{ name, config_path });
    if (delete_files) {
        const primary = std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.repos, name }) catch return 1;
        if (std.Io.Dir.cwd().access(ctx.io, primary, .{})) |_| {
            process.stderrLineNewline(ctx, "fmr: deleting checkout {s}", .{primary});
            std.Io.Dir.cwd().deleteTree(ctx.io, primary) catch {
                process.stderrLineNewline(ctx, "fmr: failed to delete {s}", .{primary});
                return 1;
            };
        } else |_| {}
    }
    return 0;
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
    process.stderrLineNewline(ctx, "commands: status | sync | doctor | config | check | run | rag | add | remove", .{});
    return 0;
}

fn usage(ctx: *const process.Ctx, reason: []const u8) u8 {
    if (reason.len > 0) process.stderrLineNewline(ctx, "fmr: {s}", .{reason});
    process.stderrLineNewline(ctx, "usage: fmr <command> [repo...] [--all] [--config <path>] [--jobs <n>] [--force] [--fix] [--gc <n>] [--json]", .{});
    process.stderrLineNewline(ctx, "commands: status | sync | doctor | config | check | run | rag | add | remove", .{});
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
