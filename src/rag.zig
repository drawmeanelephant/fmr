//! RAG snapshot pipeline for `fmr rag`.
//! Creates content-addressed, immutable snapshot directories at `paths.sourceRag/<name>/<sha40>/`,
//! generates `manifest.json`, and atomically swaps the `paths.sourceRag/<name>/current` symlink.
//! Supports `command` (exporter subprocess) and `files` (zero-subprocess glob walk) modes.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const ui = @import("ui.zig");

pub fn run(
    ctx: *const process.Ctx,
    cfg: *const config.Config,
    names: []const []const u8,
    force: bool,
    pr: *const ui.Printer,
) u8 {
    var max_exit: u8 = 0;
    for (names) |name| {
        const repo = cfg.findRepo(name) orelse {
            process.stderrLineNewline(ctx, "fmr: unknown repo '{s}'", .{name});
            return 2;
        };
        const code = snapOne(ctx, cfg, repo, force, pr);
        if (code > max_exit) max_exit = code;
    }
    return max_exit;
}

fn snapOne(
    ctx: *const process.Ctx,
    cfg: *const config.Config,
    repo: *const config.Repo,
    force: bool,
    pr: *const ui.Printer,
) u8 {
    const alloc = ctx.alloc;
    const primary = std.Io.Dir.path.join(alloc, &.{ cfg.paths.repos, repo.name }) catch return 1;

    // 1. Git existence and sanity checks
    if (!git.dirExists(ctx, primary)) {
        pr.line(ctx, .red, "[refuse] {s}: repository directory missing (run 'fmr sync {s}' first)", .{ repo.name, repo.name });
        return 3;
    }

    const gk = git.gitDirKind(ctx, primary) catch return 1;
    if (gk == .absent) {
        pr.line(ctx, .red, "[refuse] {s}: not a git repository", .{repo.name});
        return 3;
    }
    if (gk == .file) {
        pr.line(ctx, .red, "[refuse] {s}: primary is a worktree (refusing)", .{repo.name});
        return 3;
    }

    const commits = git.hasCommits(ctx, primary) catch return 1;
    if (!commits) {
        pr.line(ctx, .red, "[refuse] {s}: repository is unborn (no commits)", .{repo.name});
        return 3;
    }

    // 2. Check dirty state (tracked changes require --force for snapshot reproducibility)
    const p = (git.porcelain(ctx, primary) catch return 1) orelse git.Porcelain{
        .tracked_changes = 0,
        .untracked = 0,
        .lines = &.{},
    };
    if (p.tracked_changes > 0 and !force) {
        pr.line(ctx, .red, "[refuse] {s}: dirty ({d} tracked modifications) — unreproducible snapshot without --force", .{ repo.name, p.tracked_changes });
        return 3;
    }

    // 3. Skip if no rag configured
    const rag_cfg = repo.rag orelse {
        pr.line(ctx, .gray, "[skip] {s}: no rag configured", .{repo.name});
        return 0;
    };

    // 4. Retrieve commit SHA and branch name
    const full_sha = (git.fullSha(ctx, primary) catch return 1) orelse return 1;
    const short_sha = (git.shortSha(ctx, primary) catch return 1) orelse full_sha[0..@min(7, full_sha.len)];
    const branch = (git.headBranch(ctx, primary) catch return 1) orelse "detached";

    // 5. Check if snapshot already exists (idempotency check)
    const repo_rag_dir = std.Io.Dir.path.join(alloc, &.{ cfg.paths.source_rag, repo.name }) catch return 1;
    const target_snap_dir = std.Io.Dir.path.join(alloc, &.{ repo_rag_dir, full_sha }) catch return 1;
    const manifest_path = std.Io.Dir.path.join(alloc, &.{ target_snap_dir, "manifest.json" }) catch return 1;

    if (!force and git.dirExists(ctx, target_snap_dir) and git.dirExists(ctx, manifest_path)) {
        pr.line(ctx, .green, "[ok] {s}: rag up to date ({s})", .{ repo.name, short_sha });
        return 0;
    }

    // 6. Ensure source-rag root and repo-rag root exist
    std.Io.Dir.cwd().createDirPath(ctx.io, repo_rag_dir) catch return 1;

    // 7. Create staging directory (.staging/<name>-<sha>-<pid>)
    const staging_root = std.Io.Dir.path.join(alloc, &.{ repo_rag_dir, ".staging" }) catch return 1;
    std.Io.Dir.cwd().createDirPath(ctx.io, staging_root) catch return 1;

    const pid = std.c.getpid();
    const staging_dir_name = std.fmt.allocPrint(alloc, "{s}-{s}-{d}", .{ repo.name, short_sha, pid }) catch return 1;
    const staging_dir = std.Io.Dir.path.join(alloc, &.{ staging_root, staging_dir_name }) catch return 1;

    // Ensure fresh empty staging dir
    std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
    std.Io.Dir.cwd().createDirPath(ctx.io, staging_dir) catch return 1;

    var recorded_command: ?[]const []const u8 = null;
    const mode_str: []const u8 = switch (rag_cfg) {
        .command => "command",
        .files => "files",
    };

    switch (rag_cfg) {
        .command => |cmd_cfg| {
            const expanded = expandRagArgv(ctx, cmd_cfg.argv, cfg, primary, repo.name, branch, staging_dir) orelse {
                std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
                return 1;
            };
            recorded_command = expanded;

            // Build environment variables
            var env_list = ArrayList([]const u8).init(alloc);
            env_list.append(std.fmt.allocPrint(alloc, "FMR_REPO={s}", .{primary}) catch return 1) catch return 1;
            env_list.append(std.fmt.allocPrint(alloc, "FMR_NAME={s}", .{repo.name}) catch return 1) catch return 1;
            env_list.append(std.fmt.allocPrint(alloc, "FMR_BRANCH={s}", .{branch}) catch return 1) catch return 1;
            env_list.append(std.fmt.allocPrint(alloc, "FMR_RAG_OUT={s}", .{staging_dir}) catch return 1) catch return 1;
            env_list.append(std.fmt.allocPrint(alloc, "YARD_REPO={s}", .{primary}) catch return 1) catch return 1;
            env_list.append(std.fmt.allocPrint(alloc, "YARD_NAME={s}", .{repo.name}) catch return 1) catch return 1;
            env_list.append(std.fmt.allocPrint(alloc, "YARD_BRANCH={s}", .{branch}) catch return 1) catch return 1;
            env_list.append(std.fmt.allocPrint(alloc, "YARD_RAG_OUT={s}", .{staging_dir}) catch return 1) catch return 1;
            for (repo.env) |kv| env_list.append(kv) catch return 1;

            const res = process.run(ctx, expanded, .{
                .cwd = primary,
                .env = env_list.items,
            }) catch {
                std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
                pr.line(ctx, .red, "[fail] {s}: failed to spawn exporter {s}", .{ repo.name, expanded[0] });
                return 4;
            };

            if (!res.ok()) {
                std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
                const code = res.exited() orelse 1;
                pr.line(ctx, .red, "[fail] {s}: {s} exited with code {d}", .{ repo.name, expanded[0], code });
                return 4;
            }

            // If an explicit output directory was specified and is not the staging dir, copy it in
            if (cmd_cfg.output) |out_spec| {
                const expanded_out = expandRagString(ctx, out_spec, cfg, primary, repo.name, branch, staging_dir) orelse {
                    std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
                    return 1;
                };
                if (!std.mem.eql(u8, expanded_out, staging_dir)) {
                    const src_out = if (std.Io.Dir.path.isAbsolute(expanded_out))
                        expanded_out
                    else
                        std.Io.Dir.path.join(alloc, &.{ primary, expanded_out }) catch return 1;

                    copyTree(ctx, src_out, staging_dir) catch {
                        std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
                        pr.line(ctx, .red, "[fail] {s}: failed to copy rag output from {s}", .{ repo.name, src_out });
                        return 4;
                    };
                }
            }
        },
        .files => |files_cfg| {
            const max_depth = files_cfg.max_depth orelse 10;
            var count: usize = 0;
            copyFilesWalk(ctx, primary, staging_dir, primary, files_cfg.globs, max_depth, 0, &count) catch {
                std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
                pr.line(ctx, .red, "[fail] {s}: failed during files mode copy", .{repo.name});
                return 4;
            };
        },
    }

    // 8. Count exported files (excluding manifest.json)
    const files_exported = countExportedFiles(ctx, staging_dir);

    // 9. Write manifest.json
    const manifest_content = createManifestJson(
        alloc,
        repo.name,
        full_sha,
        branch,
        p.tracked_changes > 0,
        p.untracked,
        files_exported,
        mode_str,
        recorded_command,
    ) catch {
        std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
        return 1;
    };
    const staging_manifest_path = std.Io.Dir.path.join(alloc, &.{ staging_dir, "manifest.json" }) catch return 1;
    var mf = std.Io.Dir.cwd().createFile(ctx.io, staging_manifest_path, .{ .truncate = true }) catch {
        std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
        return 1;
    };
    mf.writeStreamingAll(ctx.io, manifest_content) catch {
        mf.close(ctx.io);
        std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
        return 1;
    };
    mf.close(ctx.io);

    // 10. Atomic promotion: staging -> <source_rag>/<name>/<full_sha>/
    if (git.dirExists(ctx, target_snap_dir)) {
        // If force replacing existing snapshot
        const trash_name = std.fmt.allocPrint(alloc, ".trash-{s}-{d}", .{ short_sha, pid }) catch return 1;
        const trash_path = std.Io.Dir.path.join(alloc, &.{ staging_root, trash_name }) catch return 1;
        std.Io.Dir.renameAbsolute(target_snap_dir, trash_path, ctx.io) catch {
            std.Io.Dir.cwd().deleteTree(ctx.io, target_snap_dir) catch {};
        };
        std.Io.Dir.cwd().deleteTree(ctx.io, trash_path) catch {};
    }

    std.Io.Dir.renameAbsolute(staging_dir, target_snap_dir, ctx.io) catch {
        std.Io.Dir.cwd().deleteTree(ctx.io, staging_dir) catch {};
        pr.line(ctx, .red, "[fail] {s}: failed to promote snapshot directory", .{repo.name});
        return 1;
    };

    // 11. Atomic symlink update: current -> <full_sha>
    const current_path = std.Io.Dir.path.join(alloc, &.{ repo_rag_dir, "current" }) catch return 1;
    const current_tmp_name = std.fmt.allocPrint(alloc, "current.tmp.{d}", .{pid}) catch return 1;
    const current_tmp_path = std.Io.Dir.path.join(alloc, &.{ repo_rag_dir, current_tmp_name }) catch return 1;

    // Delete any stale tmp symlink
    std.Io.Dir.cwd().deleteFile(ctx.io, current_tmp_path) catch {};

    std.Io.Dir.cwd().symLink(ctx.io, full_sha, current_tmp_path, .{}) catch {
        pr.line(ctx, .red, "[fail] {s}: failed to create snapshot symlink", .{repo.name});
        return 1;
    };
    std.Io.Dir.renameAbsolute(current_tmp_path, current_path, ctx.io) catch {
        pr.line(ctx, .red, "[fail] {s}: failed to swap snapshot symlink", .{repo.name});
        return 1;
    };

    pr.line(ctx, .green, "[ok] {s}: rag snap {s} ({d} files)", .{ repo.name, short_sha, files_exported });
    return 0;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn expandRagArgv(
    ctx: *const process.Ctx,
    argv: []const []const u8,
    cfg: *const config.Config,
    repo_path: []const u8,
    name: []const u8,
    branch: ?[]const u8,
    rag_out: []const u8,
) ?[]const []const u8 {
    var out = ArrayList([]const u8).init(ctx.alloc);
    for (argv) |token| {
        const exp = expandRagString(ctx, token, cfg, repo_path, name, branch, rag_out) orelse return null;
        out.append(exp) catch return null;
    }
    return out.toOwnedSlice() catch null;
}

fn expandRagString(
    ctx: *const process.Ctx,
    template: []const u8,
    cfg: *const config.Config,
    repo_path: []const u8,
    name: []const u8,
    branch: ?[]const u8,
    rag_out: []const u8,
) ?[]const u8 {
    var buf = ArrayList(u8).init(ctx.alloc);
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{') {
            const end = std.mem.indexOfScalarPos(u8, template, i, '}') orelse {
                buf.append(template[i]) catch return null;
                i += 1;
                continue;
            };
            const key = template[i + 1 .. end];
            if (std.mem.eql(u8, key, "workspace")) {
                buf.appendSlice(cfg.workspace_dir) catch return null;
            } else if (std.mem.eql(u8, key, "repo")) {
                buf.appendSlice(repo_path) catch return null;
            } else if (std.mem.eql(u8, key, "name")) {
                buf.appendSlice(name) catch return null;
            } else if (std.mem.eql(u8, key, "branch")) {
                buf.appendSlice(branch orelse "") catch return null;
            } else if (std.mem.eql(u8, key, "rag_out")) {
                buf.appendSlice(rag_out) catch return null;
            } else {
                buf.appendSlice(template[i .. end + 1]) catch return null;
            }
            i = end + 1;
        } else {
            buf.append(template[i]) catch return null;
            i += 1;
        }
    }
    return buf.toOwnedSlice() catch null;
}

pub fn matchGlob(pattern: []const u8, name: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.startsWith(u8, pattern, "*.")) {
        const ext = pattern[1..];
        return std.mem.endsWith(u8, name, ext);
    }
    if (std.mem.endsWith(u8, pattern, "*")) {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, name, prefix);
    }
    return std.mem.eql(u8, pattern, name);
}

fn matchesAnyGlob(globs: []const []const u8, name: []const u8) bool {
    for (globs) |g| {
        if (matchGlob(g, name)) return true;
    }
    return false;
}

fn copyFilesWalk(
    ctx: *const process.Ctx,
    root_repo_path: []const u8,
    staging_dir: []const u8,
    current_path: []const u8,
    globs: []const []const u8,
    max_depth: u32,
    current_depth: u32,
    count: *usize,
) !void {
    if (current_depth > max_depth) return;

    var dir = std.Io.Dir.cwd().openDir(ctx.io, current_path, .{ .iterate = true }) catch return;
    defer dir.close(ctx.io);

    var it = dir.iterate();
    while (it.next(ctx.io) catch null) |entry| {
        if (std.mem.eql(u8, entry.name, ".git") or
            std.mem.eql(u8, entry.name, ".staging") or
            std.mem.eql(u8, entry.name, "zig-cache") or
            std.mem.eql(u8, entry.name, ".zig-cache") or
            std.mem.eql(u8, entry.name, "zig-out") or
            std.mem.eql(u8, entry.name, "node_modules"))
        {
            continue;
        }

        const full_src_path = try std.Io.Dir.path.join(ctx.alloc, &.{ current_path, entry.name });

        if (entry.kind == .directory) {
            if (current_depth < max_depth) {
                try copyFilesWalk(ctx, root_repo_path, staging_dir, full_src_path, globs, max_depth, current_depth + 1, count);
            }
        } else if (entry.kind == .file or entry.kind == .sym_link) {
            if (matchesAnyGlob(globs, entry.name)) {
                // Compute relative path from root_repo_path
                const rel_path = if (std.mem.startsWith(u8, full_src_path, root_repo_path)) blk: {
                    var sub = full_src_path[root_repo_path.len..];
                    if (sub.len > 0 and sub[0] == '/') sub = sub[1..];
                    break :blk sub;
                } else entry.name;

                const dest_path = try std.Io.Dir.path.join(ctx.alloc, &.{ staging_dir, rel_path });
                if (std.Io.Dir.path.dirname(dest_path)) |dest_dir| {
                    try std.Io.Dir.cwd().createDirPath(ctx.io, dest_dir);
                }

                try copyFile(ctx, full_src_path, dest_path);
                count.* += 1;
            }
        }
    }
}

fn copyTree(ctx: *const process.Ctx, src_dir_path: []const u8, dst_dir_path: []const u8) !void {
    var dir = std.Io.Dir.cwd().openDir(ctx.io, src_dir_path, .{ .iterate = true }) catch return;
    defer dir.close(ctx.io);

    var it = dir.iterate();
    while (it.next(ctx.io) catch null) |entry| {
        const src_child = try std.Io.Dir.path.join(ctx.alloc, &.{ src_dir_path, entry.name });
        const dst_child = try std.Io.Dir.path.join(ctx.alloc, &.{ dst_dir_path, entry.name });

        if (entry.kind == .directory) {
            try std.Io.Dir.cwd().createDirPath(ctx.io, dst_child);
            try copyTree(ctx, src_child, dst_child);
        } else if (entry.kind == .file or entry.kind == .sym_link) {
            if (std.Io.Dir.path.dirname(dst_child)) |p| {
                try std.Io.Dir.cwd().createDirPath(ctx.io, p);
            }
            try copyFile(ctx, src_child, dst_child);
        }
    }
}

fn copyFile(ctx: *const process.Ctx, src: []const u8, dst: []const u8) !void {
    const data = try std.Io.Dir.cwd().readFileAlloc(ctx.io, src, ctx.alloc, .limited(50 * 1024 * 1024));
    defer ctx.alloc.free(data);

    var f = try std.Io.Dir.cwd().createFile(ctx.io, dst, .{ .truncate = true });
    defer f.close(ctx.io);
    try f.writeStreamingAll(ctx.io, data);
}

fn countExportedFiles(ctx: *const process.Ctx, dir_path: []const u8) usize {
    var total: usize = 0;
    countFilesWalk(ctx, dir_path, &total);
    return total;
}

fn countFilesWalk(ctx: *const process.Ctx, dir_path: []const u8, total: *usize) void {
    var dir = std.Io.Dir.cwd().openDir(ctx.io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(ctx.io);

    var it = dir.iterate();
    while (it.next(ctx.io) catch null) |entry| {
        if (std.mem.eql(u8, entry.name, "manifest.json")) continue;
        if (entry.kind == .directory) {
            const sub = std.Io.Dir.path.join(ctx.alloc, &.{ dir_path, entry.name }) catch continue;
            countFilesWalk(ctx, sub, total);
        } else if (entry.kind == .file or entry.kind == .sym_link) {
            total.* += 1;
        }
    }
}

fn createManifestJson(
    alloc: std.mem.Allocator,
    name: []const u8,
    sha: []const u8,
    branch: []const u8,
    dirty: bool,
    untracked_count: usize,
    files_exported: usize,
    mode: []const u8,
    command: ?[]const []const u8,
) ![]const u8 {
    const c_time = struct {
        extern "c" fn time(t: ?*anyopaque) c_long;
    }.time;
    const ts = c_time(null);
    const iso_timestamp = formatIsoTimestamp(alloc, @intCast(ts)) catch "2026-08-16T00:00:00Z";

    var buf = ArrayList(u8).init(alloc);

    try buf.appendSlice("{\n");
    const name_line = try std.fmt.allocPrint(alloc, "  \"name\": \"{s}\",\n", .{name});
    try buf.appendSlice(name_line);
    const sha_line = try std.fmt.allocPrint(alloc, "  \"sha\": \"{s}\",\n", .{sha});
    try buf.appendSlice(sha_line);
    const branch_line = try std.fmt.allocPrint(alloc, "  \"branch\": \"{s}\",\n", .{branch});
    try buf.appendSlice(branch_line);
    const time_line = try std.fmt.allocPrint(alloc, "  \"created_at\": \"{s}\",\n", .{iso_timestamp});
    try buf.appendSlice(time_line);
    const dirty_line = try std.fmt.allocPrint(alloc, "  \"dirty\": {s},\n", .{if (dirty) "true" else "false"});
    try buf.appendSlice(dirty_line);
    const untracked_line = try std.fmt.allocPrint(alloc, "  \"untracked_count\": {d},\n", .{untracked_count});
    try buf.appendSlice(untracked_line);
    const files_line = try std.fmt.allocPrint(alloc, "  \"files_exported\": {d},\n", .{files_exported});
    try buf.appendSlice(files_line);
    const mode_line = try std.fmt.allocPrint(alloc, "  \"mode\": \"{s}\"", .{mode});
    try buf.appendSlice(mode_line);

    if (command) |cmd| {
        try buf.appendSlice(",\n  \"command\": [");
        for (cmd, 0..) |c, idx| {
            if (idx > 0) try buf.appendSlice(", ");
            const cmd_elem = try std.fmt.allocPrint(alloc, "\"{s}\"", .{c});
            try buf.appendSlice(cmd_elem);
        }
        try buf.appendSlice("]\n");
    } else {
        try buf.appendSlice("\n");
    }

    try buf.appendSlice("}\n");
    return buf.toOwnedSlice();
}

fn formatIsoTimestamp(alloc: std.mem.Allocator, ts_sec: i64) ![]const u8 {
    const secs: u64 = if (ts_sec < 0) 0 else @intCast(ts_sec);
    const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
    const epoch_day = epoch.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    const hours = day_seconds.getHoursIntoDay();
    const minutes = day_seconds.getMinutesIntoHour();
    const seconds = day_seconds.getSecondsIntoMinute();

    return std.fmt.allocPrint(
        alloc,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ year_day.year, month_day.month.numeric(), month_day.day_index + 1, hours, minutes, seconds },
    );
}

test "glob matching" {
    try std.testing.expect(matchGlob("*.md", "README.md"));
    try std.testing.expect(matchGlob("*.md", "yard-plan.md"));
    try std.testing.expect(!matchGlob("*.md", "README.txt"));
    try std.testing.expect(matchGlob("*.json", "workspace.json"));
    try std.testing.expect(matchGlob("*", "anything.xyz"));
    try std.testing.expect(matchGlob("Package.swift", "Package.swift"));
    try std.testing.expect(!matchGlob("Package.swift", "Other.swift"));
}
