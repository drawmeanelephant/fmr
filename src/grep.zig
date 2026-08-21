//! Cross-repo ripgrep.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const ui = @import("ui.zig");

const Hit = struct {
    repo: []const u8,
    file: []const u8,
    line: usize,
    col: usize,
    text: []const u8,
};

pub fn run(ctx: *const process.Ctx, cfg: *const config.Config, pattern: []const u8, names: []const []const u8, json_out: bool, jobs: usize, pr: *ui.Printer) u8 {
    // Detect rg
    const has_rg = blk: {
        const res = process.run(ctx, &.{ "which", "rg" }, .{}) catch break :blk false;
        break :blk res.ok();
    };

    var all_hits = ArrayList(Hit).init(ctx.alloc);
    var any_match = false;
    var any_error: ?[]const u8 = null;

    // Sequential for now (parallel adds complexity with allocator sharing)
    // Use bounded parallelism via simple loop; perf is still fine for 13 repos
    _ = jobs;
    for (names) |name| {
        if (cfg.findRepo(name) == null) continue;
        const primary = std.Io.Dir.path.join(ctx.alloc, &.{ cfg.paths.repos, name }) catch continue;
        if (!git.dirExists(ctx, primary)) continue;
        const gk = git.gitDirKind(ctx, primary) catch continue;
        if (gk != .directory) continue;

        var argv = ArrayList([]const u8).init(ctx.alloc);
        if (has_rg) {
            argv.append("rg") catch continue;
            argv.append("--no-heading") catch continue;
            argv.append("--line-number") catch continue;
            argv.append("--column") catch continue;
            argv.append("--color") catch continue;
            argv.append("never") catch continue;
            argv.append("--hidden") catch continue;
            argv.append("--glob") catch continue;
            argv.append("!.git") catch continue;
            argv.append(pattern) catch continue;
            argv.append(primary) catch continue;
        } else {
            argv.append("grep") catch continue;
            argv.append("-R") catch continue;
            argv.append("-n") catch continue;
            argv.append("--") catch continue;
            argv.append(pattern) catch continue;
            argv.append(primary) catch continue;
        }
        const res = process.run(ctx, argv.items, .{}) catch {
            any_error = "spawn failed";
            continue;
        };
        if (res.stdout.len > 0) any_match = true;
        // Parse output
        var it = std.mem.splitScalar(u8, res.stdout, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            // For rg: file:line:col:text ; for grep: file:line:text
            // We prefix with repo
            var hit_file: []const u8 = "";
            var hit_line: usize = 0;
            var hit_col: usize = 0;
            var hit_text: []const u8 = line;
            if (has_rg) {
                // split at ':'
                var parts = std.mem.splitScalar(u8, line, ':');
                const f = parts.next() orelse continue;
                const l = parts.next() orelse continue;
                const c = parts.next() orelse continue;
                const t = parts.rest();
                hit_file = f;
                hit_line = std.fmt.parseInt(usize, l, 10) catch 0;
                hit_col = std.fmt.parseInt(usize, c, 10) catch 0;
                hit_text = t;
                // Strip primary prefix
                if (std.mem.startsWith(u8, hit_file, primary)) {
                    var rest = hit_file[primary.len..];
                    if (rest.len > 0 and rest[0] == '/') rest = rest[1..];
                    hit_file = rest;
                }
            } else {
                var parts = std.mem.splitScalar(u8, line, ':');
                const f = parts.next() orelse continue;
                const l = parts.next() orelse continue;
                const t = parts.rest();
                hit_file = f;
                hit_line = std.fmt.parseInt(usize, l, 10) catch 0;
                hit_text = t;
                if (std.mem.startsWith(u8, hit_file, primary)) {
                    var rest = hit_file[primary.len..];
                    if (rest.len > 0 and rest[0] == '/') rest = rest[1..];
                    hit_file = rest;
                }
            }
            all_hits.append(.{ .repo = name, .file = hit_file, .line = hit_line, .col = hit_col, .text = hit_text }) catch {};
        }
        if (!res.ok() and res.exited() != null and res.exited().? != 1) {
            // rg exit 1 = no match, 0 = match, 2 = error
            // grep exit 0 = match, 1 = no match, 2 = error
            const code = res.exited().?;
            if (code == 2) any_error = res.stderr;
        }
    }

    if (json_out) {
        var buf = ArrayList(u8).init(ctx.alloc);
        buf.appendSlice("{\n  \"version\": 1,\n  \"command\": \"grep\",\n") catch return 1;
        const exit_code: u8 = if (any_match) 0 else if (any_error != null) 2 else 1;
        const header = std.fmt.allocPrint(ctx.alloc, "  \"exit\": {d},\n  \"pattern\": \"{s}\",\n  \"hits\": [\n", .{ exit_code, pattern }) catch return 1;
        buf.appendSlice(header) catch return 1;
        for (all_hits.items, 0..) |h, i| {
            var clean = ArrayList(u8).init(ctx.alloc);
            for (h.text) |ch| {
                if (ch == '"') {
                    clean.appendSlice("\\\"") catch return 1;
                } else if (ch == '\\') {
                    clean.appendSlice("\\\\") catch return 1;
                } else if (ch == '\n') {
                    clean.appendSlice("\\n") catch return 1;
                } else if (ch == '\r') {
                    clean.appendSlice("\\r") catch return 1;
                } else if (ch < 0x20) {} else {
                    clean.append(ch) catch return 1;
                }
            }
            const e = std.fmt.allocPrint(ctx.alloc,
                \\    {{"repo": "{s}", "file": "{s}", "line": {d}, "col": {d}, "text": "{s}"}}{s}
                \\
            , .{ h.repo, h.file, h.line, h.col, clean.items, if (i + 1 < all_hits.items.len) "," else "" }) catch return 1;
            buf.appendSlice(e) catch return 1;
        }
        buf.appendSlice("  ]\n}\n") catch return 1;
        std.Io.File.stdout().writeStreamingAll(ctx.io, buf.items) catch {};
        return if (any_match) 0 else if (any_error != null) 2 else 1;
    }

    if (all_hits.items.len == 0) {
        if (any_error) |e| {
            process.stderrLineNewline(ctx, "grep: {s}", .{e});
            return 2;
        }
        pr.raw(ctx, "no matches for \"{s}\"", .{pattern});
        return 1;
    }
    for (all_hits.items) |h| {
        if (h.col > 0) {
            pr.raw(ctx, "{s}:{s}:{d}:{d}:{s}", .{ h.repo, h.file, h.line, h.col, h.text });
        } else {
            pr.raw(ctx, "{s}:{s}:{d}:{s}", .{ h.repo, h.file, h.line, h.text });
        }
    }
    return 0;
}
