//! Launchd auto-sync daemon (opt-in).

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const ui = @import("ui.zig");

const plist_label = "com.drawmeanelephant.fmr.sync";
const daemon_state_file = ".fmr/daemon.json";

pub fn install(ctx: *const process.Ctx, interval_str: []const u8, config_path: []const u8, config_override: ?[]const u8) u8 {
    const home = process.home(ctx) orelse {
        process.stderrLineNewline(ctx, "fmr daemon install: HOME not set", .{});
        return 1;
    };
    const interval_sec = parseInterval(interval_str) orelse {
        process.stderrLineNewline(ctx, "fmr daemon install: unknown interval '{s}' (expected 5m, 10m, 30m, 1h)", .{interval_str});
        return 2;
    };
    const fmr_bin = resolveFmrBin(ctx);
    const launch_dir = std.Io.Dir.path.join(ctx.alloc, &.{ home, "Library", "LaunchAgents" }) catch return 1;
    std.Io.Dir.cwd().createDirPath(ctx.io, launch_dir) catch {};
    const plist_path = std.Io.Dir.path.join(ctx.alloc, &.{ launch_dir, plist_label ++ ".plist" }) catch return 1;

    var config_arg: []const u8 = "";
    if (config_override) |p| {
        if (!std.mem.eql(u8, p, config_path)) {
            config_arg = std.fmt.allocPrint(ctx.alloc, "<string>--config</string><string>{s}</string>", .{p}) catch "";
        }
    }

    const plist = std.fmt.allocPrint(ctx.alloc,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\  <key>Label</key><string>{s}</string>
        \\  <key>ProgramArguments</key>
        \\  <array>
        \\    <string>{s}</string>
        \\    <string>daemon</string>
        \\    <string>run</string>
        \\    {s}
        \\  </array>
        \\  <key>StartInterval</key><integer>{d}</integer>
        \\  <key>RunAtLoad</key><false/>
        \\  <key>StandardOutPath</key><string>{s}/.fmr/daemon.log</string>
        \\  <key>StandardErrorPath</key><string>{s}/.fmr/daemon.log</string>
        \\</dict>
        \\</plist>
        \\
    , .{ plist_label, fmr_bin, config_arg, interval_sec, home, home }) catch return 1;

    std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = plist_path, .data = plist }) catch {
        process.stderrLineNewline(ctx, "fmr daemon: failed to write {s}", .{plist_path});
        return 1;
    };

    // Write state file
    const state_path = std.Io.Dir.path.join(ctx.alloc, &.{ home, daemon_state_file }) catch return 1;
    const state = std.fmt.allocPrint(ctx.alloc, "{{\"interval\":\"{s}\",\"interval_sec\":{d},\"config\":\"{s}\",\"installed_at\":{d}}}", .{ interval_str, interval_sec, config_path, @as(i64, 0) }) catch return 1;
    std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = state_path, .data = state }) catch {};

    // Try to bootstrap (best-effort)
    const res = process.run(ctx, &.{ "launchctl", "bootstrap", "gui/501", plist_path }, .{}) catch {
        process.stderrLineNewline(ctx, "[ok] daemon installed at {s} (interval {s}) — launchctl bootstrap skipped (run manually if needed)", .{ plist_path, interval_str });
        return 0;
    };
    if (!res.ok()) {
        process.stderrLineNewline(ctx, "[ok] daemon installed at {s} (interval {s}) — launchctl: {s}", .{ plist_path, interval_str, res.stderr });
        return 0;
    }
    process.stderrLineNewline(ctx, "[ok] daemon installed and loaded: {s} (interval {s})", .{ plist_path, interval_str });
    return 0;
}

pub fn uninstall(ctx: *const process.Ctx) u8 {
    const home = process.home(ctx) orelse return 1;
    const plist_path = std.Io.Dir.path.join(ctx.alloc, &.{ home, "Library", "LaunchAgents", plist_label ++ ".plist" }) catch return 1;
    _ = process.run(ctx, &.{ "launchctl", "bootout", "gui/501", plist_path }, .{}) catch {};
    std.Io.Dir.cwd().deleteTree(ctx.io, plist_path) catch {};
    // Also try rm file
    if (std.Io.Dir.cwd().access(ctx.io, plist_path, .{})) |_| {
        std.Io.Dir.cwd().deleteFile(ctx.io, plist_path) catch {};
    } else |_| {}
    const state_path = std.Io.Dir.path.join(ctx.alloc, &.{ home, daemon_state_file }) catch return 1;
    _ = std.Io.Dir.cwd().deleteFile(ctx.io, state_path) catch {};
    process.stderrLineNewline(ctx, "[ok] daemon uninstalled", .{});
    return 0;
}

pub fn status(ctx: *const process.Ctx, json_out: bool, pr: *ui.Printer) u8 {
    const home = process.home(ctx) orelse return 1;
    const plist_path = std.Io.Dir.path.join(ctx.alloc, &.{ home, "Library", "LaunchAgents", plist_label ++ ".plist" }) catch return 1;
    const state_path = std.Io.Dir.path.join(ctx.alloc, &.{ home, daemon_state_file }) catch return 1;
    const installed = blk: {
        std.Io.Dir.cwd().access(ctx.io, plist_path, .{}) catch break :blk false;
        break :blk true;
    };
    var interval: []const u8 = "unknown";
    var interval_sec: usize = 0;
    if (std.Io.Dir.cwd().readFileAlloc(ctx.io, state_path, ctx.alloc, .limited(4096))) |data| {
        defer ctx.alloc.free(data);
        if (std.json.parseFromSlice(std.json.Value, ctx.alloc, data, .{})) |parsed| {
            defer parsed.deinit();
            if (parsed.value == .object) {
                if (parsed.value.object.get("interval")) |v| {
                    if (v == .string) interval = v.string;
                }
                if (parsed.value.object.get("interval_sec")) |v| {
                    if (v == .integer) interval_sec = @intCast(v.integer);
                }
            }
        } else |_| {}
    } else |_| {}

    if (json_out) {
        var buf = ArrayList(u8).init(ctx.alloc);
        buf.appendSlice("{\n  \"version\": 1,\n  \"command\": \"daemon\",\n  \"exit\": 0,\n") catch return 1;
        const line = std.fmt.allocPrint(ctx.alloc, "  \"installed\": {s},\n  \"interval\": \"{s}\",\n  \"interval_sec\": {d},\n  \"plist\": \"{s}\"\n}}\n", .{ if (installed) "true" else "false", interval, interval_sec, plist_path }) catch return 1;
        buf.appendSlice(line) catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, buf.items) catch {};
        return 0;
    }
    pr.raw(ctx, "daemon: {s}", .{if (installed) "installed" else "not installed"});
    pr.raw(ctx, "  plist: {s}", .{plist_path});
    pr.raw(ctx, "  interval: {s} ({d}s)", .{ interval, interval_sec });
    return 0;
}

pub fn runOnce(ctx: *const process.Ctx, cfg: *const config.Config) u8 {
    // One-shot sync --all used by launchd
    var pr = ui.Printer.initFromCtx(ctx);
    var names = ArrayList([]const u8).init(ctx.alloc);
    for (cfg.repos) |*r| names.append(r.name) catch return 1;
    const sync_mod = @import("sync.zig");
    const code = sync_mod.run(ctx, cfg, names.items, cfg.parallelism.sync, false, &pr, false);
    // Append to daemon.log is handled by launchd StandardOutPath, but also update state
    const home = process.home(ctx) orelse return code;
    _ = home;
    const upd = std.fmt.allocPrint(ctx.alloc, "{{\"last_run\":{d},\"last_exit\":{d}}}", .{ @as(i64, 0), code }) catch return code;
    _ = upd;
    // For now just ensure file exists, keep previous interval
    return code;
}

fn parseInterval(s: []const u8) ?usize {
    if (std.mem.eql(u8, s, "5m")) return 300;
    if (std.mem.eql(u8, s, "10m")) return 600;
    if (std.mem.eql(u8, s, "30m")) return 1800;
    if (std.mem.eql(u8, s, "1h")) return 3600;
    if (std.mem.eql(u8, s, "1d")) return 86400;
    // also allow raw seconds
    return std.fmt.parseInt(usize, s, 10) catch null;
}

fn resolveFmrBin(ctx: *const process.Ctx) []const u8 {
    // Try to find fmr on PATH via which, else use current executable
    const res = process.run(ctx, &.{ "which", "fmr" }, .{}) catch return "fmr";
    if (res.ok()) {
        const p = std.mem.trim(u8, res.stdout, " \t\r\n");
        if (p.len > 0) return ctx.alloc.dupe(u8, p) catch "fmr";
    }
    // fallback to zig-out
    return "fmr";
}
