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
const context_mod = @import("context.zig");
const grep_mod = @import("grep.zig");
const mcp_mod = @import("mcp.zig");
const daemon_mod = @import("daemon.zig");

/// Version reported by `fmr --version` and embedded into the packaged app.
/// Bump when the CLI contract or behavior changes materially.
pub const version = "0.2.0";

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
    var open_worktree: ?[]const u8 = null;
    var open_editor: ?[]const u8 = null;
    var open_finder = false;
    var open_terminal = false;
    var fix_origin = false;
    var commits_n: ?usize = null;
    var interval_str: ?[]const u8 = null;
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
        } else if (std.mem.eql(u8, a, "--worktree")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing value after --worktree");
            open_worktree = argv.items[i];
        } else if (std.mem.eql(u8, a, "--editor")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing value after --editor");
            open_editor = argv.items[i];
        } else if (std.mem.eql(u8, a, "--finder")) {
            open_finder = true;
        } else if (std.mem.eql(u8, a, "--terminal")) {
            open_terminal = true;
        } else if (std.mem.eql(u8, a, "--fix-origin")) {
            fix_origin = true;
        } else if (std.mem.eql(u8, a, "--commits")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing value after --commits");
            commits_n = std.fmt.parseInt(usize, argv.items[i], 10) catch return usage(&ctx, "--commits expects an integer");
        } else if (std.mem.eql(u8, a, "--interval")) {
            i += 1;
            if (i >= argv.items.len) return usage(&ctx, "missing value after --interval");
            interval_str = argv.items[i];
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
            // For `run` and `grep`, extra args must not be deduplicated
            const c = cmd.?;
            const is_nodedup = std.mem.eql(u8, c, "run") or std.mem.eql(u8, c, "grep") or std.mem.eql(u8, c, "context") or std.mem.eql(u8, c, "daemon") or std.mem.eql(u8, c, "mcp");
            if (!is_nodedup) {
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
    } else if (std.mem.eql(u8, c, "list")) {
        return runList(&ctx, &cfg, add_kind, json_out);
    } else if (std.mem.eql(u8, c, "open")) {
        if (repo_args.items.len < 1) return usage(&ctx, "open requires <repo>");
        return runOpen(&ctx, &cfg, repo_args.items[0], open_worktree, open_editor, open_finder, open_terminal);
    } else if (std.mem.eql(u8, c, "completion")) {
        if (repo_args.items.len < 1) return usage(&ctx, "completion requires <shell> (zsh, bash, fish)");
        return runCompletion(&ctx, &cfg, repo_args.items[0]);
    } else if (std.mem.eql(u8, c, "sync")) {
        if (repo_args.items.len > 0) {
            if (unknownRepo(&ctx, &cfg, repo_args.items)) return 2;
        }
        var names = ArrayList([]const u8).init(ctx.alloc);
        if (repo_args.items.len > 0) {
            names.appendSlice(repo_args.items) catch return 1;
        } else {
            for (cfg.repos) |*r| names.append(r.name) catch return 1;
        }
        return sync.run(&ctx, &cfg, names.items, jobs orelse cfg.parallelism.sync, json_out, &pr, fix_origin);
    } else if (std.mem.eql(u8, c, "doctor")) {
        if (repo_args.items.len > 0) return usage(&ctx, "doctor takes no repo arguments");
        return doctor.run(&ctx, &cfg, fix, force, json_out, &pr);
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
    } else if (std.mem.eql(u8, c, "context")) {
        var names = ArrayList([]const u8).init(ctx.alloc);
        if (repo_args.items.len > 0) {
            if (unknownRepo(&ctx, &cfg, repo_args.items)) return 2;
            names.appendSlice(repo_args.items) catch return 1;
        } else {
            for (cfg.repos) |*r| names.append(r.name) catch return 1;
        }
        const n = commits_n orelse 3;
        const capped = if (n > 10) 10 else n;
        return context_mod.run(&ctx, &cfg, names.items, capped, json_out, &pr);
    } else if (std.mem.eql(u8, c, "grep")) {
        if (repo_args.items.len < 1) return usage(&ctx, "grep requires <pattern>");
        const pattern = repo_args.items[0];
        const repo_filter = repo_args.items[1..];
        if (repo_filter.len > 0) {
            if (unknownRepo(&ctx, &cfg, repo_filter)) return 2;
        }
        var names = ArrayList([]const u8).init(ctx.alloc);
        if (repo_filter.len > 0) {
            names.appendSlice(repo_filter) catch return 1;
        } else {
            for (cfg.repos) |*r| names.append(r.name) catch return 1;
        }
        // Filter by kind if --kind given (reuse add_kind)
        if (add_kind) |k| {
            const fk = config.kindFromString(k) orelse {
                process.stderrLineNewline(&ctx, "fmr: unknown kind '{s}'", .{k});
                return 2;
            };
            var filtered = ArrayList([]const u8).init(ctx.alloc);
            for (names.items) |nm| {
                const r = cfg.findRepo(nm) orelse continue;
                if (r.kind == fk) filtered.append(nm) catch return 1;
            }
            names = filtered;
        }
        return grep_mod.run(&ctx, &cfg, pattern, names.items, json_out, jobs orelse cfg.parallelism.status, &pr);
    } else if (std.mem.eql(u8, c, "mcp")) {
        return mcp_mod.run(&ctx, &cfg, path);
    } else if (std.mem.eql(u8, c, "daemon")) {
        if (repo_args.items.len < 1) return usage(&ctx, "daemon requires <install|uninstall|status|run>");
        const sub = repo_args.items[0];
        if (std.mem.eql(u8, sub, "install")) {
            return daemon_mod.install(&ctx, interval_str orelse "10m", path, config_path);
        } else if (std.mem.eql(u8, sub, "uninstall")) {
            return daemon_mod.uninstall(&ctx);
        } else if (std.mem.eql(u8, sub, "status")) {
            return daemon_mod.status(&ctx, json_out, &pr);
        } else if (std.mem.eql(u8, sub, "run")) {
            return daemon_mod.runOnce(&ctx, &cfg);
        } else {
            return usage(&ctx, "unknown daemon subcommand (expected install|uninstall|status|run)");
        }
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
        return sync.run(ctx, &new_cfg, names.items, 1, json_out, &pr, false);
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

fn runList(ctx: *const process.Ctx, cfg: *const config.Config, kind_str: ?[]const u8, json_out: bool) u8 {
    var filter_kind: ?config.Kind = null;
    if (kind_str) |ks| {
        filter_kind = config.kindFromString(ks) orelse {
            process.stderrLineNewline(ctx, "fmr: unknown kind '{s}'", .{ks});
            return 2;
        };
    }
    var filtered = ArrayList(*const config.Repo).init(ctx.alloc);
    for (cfg.repos) |*r| {
        if (filter_kind) |fk| if (r.kind != fk) continue;
        filtered.append(r) catch return 1;
    }
    if (json_out) {
        var buf = ArrayList(u8).init(ctx.alloc);
        buf.appendSlice("{\n  \"version\": 1,\n  \"command\": \"list\",\n  \"exit\": 0,\n  \"repos\": [\n") catch return 1;
        for (filtered.items, 0..) |r, i| {
            const repo_path = std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.repos, r.name }) catch return 1;
            const e = std.fmt.allocPrint(ctx.alloc,
                \\    {{"name": "{s}", "kind": "{s}", "path": "{s}", "url": "{s}"}}{s}
                \\
            , .{ r.name, @tagName(r.kind), repo_path, r.url orelse "", if (i + 1 < filtered.items.len) "," else "" }) catch return 1;
            buf.appendSlice(e) catch return 1;
        }
        buf.appendSlice("  ]\n}\n") catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, buf.items) catch {};
        return 0;
    }
    var pr = ui.Printer.initFromCtx(ctx);
    if (filtered.items.len == 0) {
        pr.raw(ctx, "no repos (kind filter {s})", .{kind_str orelse "all"});
        return 0;
    }
    pr.raw(ctx, "repos ({d}):", .{filtered.items.len});
    for (filtered.items) |r| {
        const repo_path = std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.repos, r.name }) catch continue;
        pr.line(ctx, .reset, "  {s: <20} {s: <6} {s}  {s}", .{ r.name, @tagName(r.kind), repo_path, r.url orelse "(local)" });
    }
    return 0;
}

fn runOpen(ctx: *const process.Ctx, cfg: *const config.Config, name: []const u8, worktree: ?[]const u8, editor: ?[]const u8, finder: bool, terminal: bool) u8 {
    const repo = cfg.findRepo(name) orelse {
        process.stderrLineNewline(ctx, "fmr: unknown repo '{s}'", .{name});
        return 2;
    };
    _ = repo;
    var target: []const u8 = undefined;
    if (worktree) |wt| {
        target = std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.worktrees, name, wt }) catch return 1;
        std.Io.Dir.cwd().access(ctx.io, target, .{}) catch {
            process.stderrLineNewline(ctx, "fmr: worktree not found: {s}", .{target});
            return 1;
        };
    } else {
        target = std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.repos, name }) catch return 1;
    }
    // Finder / Terminal take precedence
    if (finder) {
        const res = process.run(ctx, &.{ "open", target }, .{}) catch return 1;
        if (!res.ok()) {
            process.stderrLineNewline(ctx, "fmr: open failed: {s}", .{res.stderr});
            return 1;
        }
        process.stderrLineNewline(ctx, "[ok] opened {s} in Finder", .{target});
        return 0;
    }
    if (terminal) {
        const script = std.fmt.allocPrint(ctx.alloc, "tell application \"Terminal\" to do script \"cd {s}\"", .{target}) catch return 1;
        const res = process.run(ctx, &.{ "osascript", "-e", script }, .{}) catch return 1;
        if (!res.ok()) {
            process.stderrLineNewline(ctx, "fmr: terminal open failed", .{});
            return 1;
        }
        return 0;
    }
    if (editor) |ed| {
        // Try bundle-style open -a
        const app_name = switch (std.hash_map.hashString(ed)) {
            else => ed,
        };
        // Map common aliases
        const resolved = if (std.mem.eql(u8, ed, "cursor")) "Cursor"
        else if (std.mem.eql(u8, ed, "vscode") or std.mem.eql(u8, ed, "code")) "Visual Studio Code"
        else if (std.mem.eql(u8, ed, "zed")) "Zed"
        else if (std.mem.eql(u8, ed, "xcode")) "Xcode"
        else ed;
        _ = app_name;
        const res = process.run(ctx, &.{ "open", "-a", resolved, target }, .{}) catch return 1;
        if (!res.ok()) {
            // Fallback to direct open
            const res2 = process.run(ctx, &.{ "open", target }, .{}) catch return 1;
            if (!res2.ok()) return 1;
        }
        process.stderrLineNewline(ctx, "[ok] opened {s} in {s}", .{ target, resolved });
        return 0;
    }
    // Default: open with default handler (Finder on macOS, xdg-open on Linux)
    const open_cmd = if (@import("builtin").os.tag == .macos) "open" else "xdg-open";
    const res = process.run(ctx, &.{ open_cmd, target }, .{}) catch return 1;
    if (!res.ok()) {
        process.stderrLineNewline(ctx, "fmr: open failed", .{});
        return 1;
    }
    process.stderrLineNewline(ctx, "[ok] opened {s}", .{target});
    return 0;
}

fn runCompletion(ctx: *const process.Ctx, cfg: *const config.Config, shell: []const u8) u8 {
    var repo_names = ArrayList([]const u8).init(ctx.alloc);
    for (cfg.repos) |*r| repo_names.append(r.name) catch return 1;
    const repos_str = std.mem.join(ctx.alloc, " ", repo_names.items) catch "";
    const commands = "status sync doctor config check run rag add remove list open completion context grep mcp daemon";
    const kinds = "zig go node site bash other";
    // Collect run command names across all repos (unique)
    var cmd_names = ArrayList([]const u8).init(ctx.alloc);
    for (cfg.repos) |*r| {
        for (r.cmd_names) |cn| {
            var exists = false;
            for (cmd_names.items) |e| {
                if (std.mem.eql(u8, e, cn)) {
                    exists = true;
                    break;
                }
            }
            if (!exists) cmd_names.append(cn) catch {};
        }
    }
    const run_cmds = std.mem.join(ctx.alloc, " ", cmd_names.items) catch "";

    if (std.mem.eql(u8, shell, "zsh")) {
        const tmpl =
            \\#compdef fmr
            \\_fmr() {{
            \\  local -a commands
            \\  commands=(status:"read-only status" sync:"fetch + ff-only" doctor:"diagnostics" config:"dump catalog" check:"run checks" run:"run named command" rag:"RAG snapshots" add:"add repo" remove:"remove repo" list:"list repos" open:"open repo" completion:"shell completions" context:"AI context dump" grep:"cross-repo search" mcp:"MCP server" daemon:"auto-sync daemon")
            \\  local -a repos
            \\  repos=({s})
            \\  local -a kinds
            \\  kinds=({s})
            \\  local -a run_cmds
            \\  run_cmds=({s})
            \\  _arguments -C \
            \\    "--config[config path]: :_files" \
            \\    "--jobs[jobs]: " \
            \\    "--json[json output]" \
            \\    "--force[force]" \
            \\    "--fix[fix]" \
            \\    "--gc[gc]: " \
            \\    "1: :_describe 'command' commands" \
            \\    "*:: :->args"
            \\  case $state in
            \\    args)
            \\      case $words[1] in
            \\        sync|status|check|rag) _values 'repo' $repos ;;
            \\        run) _values 'repo' $repos; _values 'command' $run_cmds ;;
            \\        open) _values 'repo' $repos ;;
            \\        list) _values 'kind' $kinds ;;
            \\      esac
            \\      ;;
            \\  esac
            \\}}
            \\_fmr
            \\
        ;
        const out = std.fmt.allocPrint(ctx.alloc, tmpl, .{ repos_str, kinds, run_cmds }) catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, out) catch {};
        return 0;
    } else if (std.mem.eql(u8, shell, "bash")) {
        const tmpl =
            \\_fmr_complete() {{
            \\  local cur="${{COMP_WORDS[COMP_CWORD]}}"
            \\  local prev="${{COMP_WORDS[COMP_CWORD-1]}}"
            \\  local commands="{s}"
            \\  local repos="{s}"
            \\  local kinds="{s}"
            \\  if [[ $COMP_CWORD -eq 1 ]]; then COMPREPLY=( $(compgen -W "$commands" -- "$cur") ); return; fi
            \\  case "${{COMP_WORDS[1]}}" in
            \\    sync|status|check|rag|open) COMPREPLY=( $(compgen -W "$repos" -- "$cur") ) ;;
            \\    list) COMPREPLY=( $(compgen -W "$kinds" -- "$cur") ) ;;
            \\    run) if [[ $COMP_CWORD -eq 2 ]]; then COMPREPLY=( $(compgen -W "$repos" -- "$cur") ); else COMPREPLY=( $(compgen -W "{s}" -- "$cur") ); fi ;;
            \\  esac
            \\}}
            \\complete -F _fmr_complete fmr
            \\
        ;
        const out = std.fmt.allocPrint(ctx.alloc, tmpl, .{ commands, repos_str, kinds, run_cmds }) catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, out) catch {};
        return 0;
    } else if (std.mem.eql(u8, shell, "fish")) {
        const tmpl =
            \\complete -c fmr -f
            \\complete -c fmr -n "not __fish_seen_subcommand_from {s}" -a "{s}" -d "command"
            \\complete -c fmr -n "__fish_seen_subcommand_from sync status check rag open context" -a "{s}"
            \\complete -c fmr -n "__fish_seen_subcommand_from list" -a "{s}"
            \\
        ;
        const out = std.fmt.allocPrint(ctx.alloc, tmpl, .{ commands, commands, repos_str, kinds }) catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, out) catch {};
        return 0;
    } else {
        process.stderrLineNewline(ctx, "fmr: unknown shell '{s}' (expected zsh, bash, fish)", .{shell});
        return 2;
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
    process.stderrLineNewline(ctx, "usage: fmr <command> [repo...] [--all] [--config <path>] [--jobs <n>] [--force] [--fix] [--fix-origin] [--gc <n>] [--json]", .{});
    process.stderrLineNewline(ctx, "commands: status | sync | doctor | config | check | run | rag | add | remove | list | open | completion | context | grep | mcp | daemon", .{});
    process.stderrLineNewline(ctx, "  fmr list [--kind <kind>] [--json]                list repos (config-only, instant)", .{});
    process.stderrLineNewline(ctx, "  fmr open <repo> [--worktree <s>] [--editor <e>]  open checkout (Finder/Terminal/Editor)", .{});
    process.stderrLineNewline(ctx, "  fmr completion <zsh|bash|fish>                   shell completions", .{});
    process.stderrLineNewline(ctx, "  fmr context [repo...] [--json]                   AI-ready workspace dump", .{});
    process.stderrLineNewline(ctx, "  fmr grep <pattern> [repo...] [--kind <k>]       cross-repo search", .{});
    process.stderrLineNewline(ctx, "  fmr mcp [--config <path>]                        MCP server (stdio)", .{});
    process.stderrLineNewline(ctx, "  fmr daemon <install|uninstall|status|run>        optional launchd auto-sync", .{});
    return 0;
}

fn usage(ctx: *const process.Ctx, reason: []const u8) u8 {
    if (reason.len > 0) process.stderrLineNewline(ctx, "fmr: {s}", .{reason});
    process.stderrLineNewline(ctx, "usage: fmr <command> [repo...] [--all] [--config <path>] [--jobs <n>] [--force] [--fix] [--fix-origin] [--gc <n>] [--json]", .{});
    process.stderrLineNewline(ctx, "commands: status | sync | doctor | config | check | run | rag | add | remove | list | open | completion | context | grep | mcp | daemon", .{});
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
    _ = @import("context.zig");
    _ = @import("grep.zig");
    _ = @import("mcp.zig");
    _ = @import("daemon.zig");
}
