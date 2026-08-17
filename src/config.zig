//! Configuration parser, validator, and placeholder expansion engine for workspace.json.
//! Handles std.json parsing, path resolution (~/), placeholder replacement, and _ comment keys.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");

pub const Kind = enum { zig, go, node, site, bash, other };

pub fn kindFromString(s: []const u8) ?Kind {
    inline for (std.meta.fields(Kind)) |f| {
        if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
    }
    return null;
}

pub const Paths = struct {
    repos: []const u8,
    worktrees: []const u8,
    source_rag: []const u8,
};

pub const Parallelism = struct {
    sync: usize,
    status: usize,
    check: usize,
    rag: usize,
};

pub const CheckCfg = struct {
    argv: []const []const u8,
};

/// Per-kind defaults resolved once at config load time.
/// Command entries are merged into each repo of that kind (repo-level wins on
/// name collision).
pub const KindDefaults = struct {
    check: ?[]const []const u8 = null,
    cmd_names: []const []const u8 = &.{},
    cmd_argv: []const []const []const u8 = &.{},
};

pub const Rag = union(enum) {
    command: struct {
        argv: []const []const u8,
        output: ?[]const u8,
    },
    files: struct {
        globs: []const []const u8,
        max_depth: ?u32,
    },
};

pub const Repo = struct {
    name: []const u8,
    url: ?[]const u8,
    kind: Kind,
    default_branch: ?[]const u8,
    worktree_safe: bool,
    sync_enabled: bool,
    check: ?[]const []const u8,
    rag: ?Rag,
    cmd_names: []const []const u8,
    cmd_argv: []const []const []const u8,
    env: []const []const u8,
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    paths: Paths,
    parallelism: Parallelism,
    repos: []Repo,
    workspace_dir: []const u8,

    pub fn findRepo(c: *const Config, name: []const u8) ?*const Repo {
        for (c.repos) |*r| {
            if (std.mem.eql(u8, r.name, name)) return r;
        }
        return null;
    }
};

pub const Diag = struct {
    alloc: std.mem.Allocator,
    msgs: ArrayList([]const u8),

    pub fn init(alloc: std.mem.Allocator) Diag {
        return .{ .alloc = alloc, .msgs = ArrayList([]const u8).init(alloc) };
    }

    pub fn deinit(d: *Diag) void {
        for (d.msgs.items) |m| d.alloc.free(m);
        d.msgs.deinit();
    }

    pub fn add(d: *Diag, comptime fmt: []const u8, args: anytype) void {
        const m = std.fmt.allocPrint(d.alloc, fmt, args) catch return;
        d.msgs.append(m) catch return;
    }
};

pub const LoadError = error{InvalidConfig} || std.mem.Allocator.Error;

pub fn load(ctx: *const process.Ctx, path: []const u8, diag: *Diag) LoadError!Config {
    const alloc = ctx.alloc;
    const contents = std.Io.Dir.cwd().readFileAlloc(ctx.io, path, alloc, .limited(1 << 20)) catch |err| {
        diag.add("config {s}: cannot read: {s}", .{ path, @errorName(err) });
        return error.InvalidConfig;
    };
    defer alloc.free(contents);

    const home_dir = process.home(ctx) orelse "";
    return loadSlice(alloc, contents, path, home_dir, diag);
}

pub fn loadSlice(alloc: std.mem.Allocator, contents: []const u8, path: []const u8, home_dir: []const u8, diag: *Diag) LoadError!Config {
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, contents, .{ .allocate = .alloc_always }) catch |err| {
        diag.add("config {s}: invalid JSON: {s}", .{ path, @errorName(err) });
        return error.InvalidConfig;
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        diag.add("config {s}: top level must be an object", .{path});
        return error.InvalidConfig;
    }

    const workspace_dir = std.Io.Dir.path.dirname(path) orelse ".";
    var cfg = Config{
        .allocator = alloc,
        .paths = undefined,
        .parallelism = .{ .sync = 4, .status = 4, .check = 1, .rag = 1 },
        .repos = &.{},
        .workspace_dir = workspace_dir,
    };

    var paths: ?Paths = null;
    var defaults: std.array_hash_map.String(KindDefaults) = .empty;
    defer defaults.deinit(alloc);
    var repos = ArrayList(Repo).init(alloc);

    for (parsed.value.object.keys()) |key| {
        if (key.len > 0 and key[0] == '_') continue;
        const v = parsed.value.object.get(key).?;
        if (std.mem.eql(u8, key, "paths")) {
            const o = try obj(v, diag, "paths") orelse return error.InvalidConfig;
            try rejectUnknown(o, &.{ "repos", "worktrees", "sourceRag" }, diag, "paths");
            const repos_p = try reqStr(o, "repos", diag, "paths.repos") orelse return error.InvalidConfig;
            const worktrees_p = try reqStr(o, "worktrees", diag, "paths.worktrees") orelse return error.InvalidConfig;
            const source_rag_p = try reqStr(o, "sourceRag", diag, "paths.sourceRag") orelse return error.InvalidConfig;
            paths = .{
                .repos = try expandPath(alloc, repos_p, home_dir),
                .worktrees = try expandPath(alloc, worktrees_p, home_dir),
                .source_rag = try expandPath(alloc, source_rag_p, home_dir),
            };
        } else if (std.mem.eql(u8, key, "parallelism")) {
            const o = try obj(v, diag, "parallelism") orelse return error.InvalidConfig;
            try rejectUnknown(o, &.{ "sync", "status", "check", "rag" }, diag, "parallelism");
            if (o.get("sync")) |pv| cfg.parallelism.sync = try posInt(pv, diag, "parallelism.sync") orelse return error.InvalidConfig;
            if (o.get("status")) |pv| cfg.parallelism.status = try posInt(pv, diag, "parallelism.status") orelse return error.InvalidConfig;
            if (o.get("check")) |pv| cfg.parallelism.check = try posInt(pv, diag, "parallelism.check") orelse return error.InvalidConfig;
            if (o.get("rag")) |pv| cfg.parallelism.rag = try posInt(pv, diag, "parallelism.rag") orelse return error.InvalidConfig;
        } else if (std.mem.eql(u8, key, "defaults")) {
            const o = try obj(v, diag, "defaults") orelse return error.InvalidConfig;
            for (o.keys()) |k| {
                if (kindFromString(k) == null) {
                    diag.add("defaults: unknown kind {s}", .{k});
                    return error.InvalidConfig;
                }
                const ko = try obj(o.get(k).?, diag, "defaults.kind") orelse return error.InvalidConfig;
                try rejectUnknown(ko, &.{ "check", "commands" }, diag, "defaults.kind");
                var kd = KindDefaults{};
                if (ko.get("check")) |check_v| {
                    const check_o = try obj(check_v, diag, "defaults.kind.check") orelse return error.InvalidConfig;
                    try rejectUnknown(check_o, &.{"argv"}, diag, "defaults.kind.check");
                    const argv_val = check_o.get("argv") orelse {
                        diag.add("defaults.kind.check: missing argv", .{});
                        return error.InvalidConfig;
                    };
                    kd.check = try strArray(argv_val, diag, "defaults.kind.check.argv") orelse return error.InvalidConfig;
                }
                if (ko.get("commands")) |cmds_v| {
                    const cmds_o = try obj(cmds_v, diag, "defaults.kind.commands") orelse return error.InvalidConfig;
                    var def_names = ArrayList([]const u8).init(alloc);
                    var def_argv = ArrayList([]const []const u8).init(alloc);
                    for (cmds_o.keys()) |cn| {
                        if (!validName(cn)) {
                            diag.add("defaults.kind: command name {s} must match [A-Za-z0-9._-]", .{cn});
                            return error.InvalidConfig;
                        }
                        const cmd_o = try obj(cmds_o.get(cn).?, diag, "defaults.kind.commands.name") orelse return error.InvalidConfig;
                        try rejectUnknown(cmd_o, &.{"argv"}, diag, "defaults.kind.commands.name");
                        const argv_val = cmd_o.get("argv") orelse {
                            diag.add("defaults.kind: command {s} must declare argv", .{cn});
                            return error.InvalidConfig;
                        };
                        const argv = try strArray(argv_val, diag, "defaults.kind.commands.name.argv") orelse return error.InvalidConfig;
                        try validateArgvTokens(argv, diag, "defaults.kind.commands.name.argv");
                        try def_names.append(cn);
                        try def_argv.append(argv);
                    }
                    kd.cmd_names = try def_names.toOwnedSlice();
                    kd.cmd_argv = try def_argv.toOwnedSlice();
                }
                try defaults.put(alloc, k, kd);
            }
        } else if (std.mem.eql(u8, key, "repos")) {
            const arr = try array(v, diag, "repos") orelse return error.InvalidConfig;
            for (arr.items) |item| {
                const r = try parseRepo(alloc, item, &defaults, diag) orelse return error.InvalidConfig;
                for (repos.items) |existing| {
                    if (std.mem.eql(u8, existing.name, r.name)) {
                        diag.add("repo {s}: duplicate name", .{r.name});
                        return error.InvalidConfig;
                    }
                }
                try repos.append(r);
            }
        } else {
            diag.add("unknown top-level key {s}", .{key});
            return error.InvalidConfig;
        }
    }

    if (paths == null) {
        diag.add("missing required top-level key paths", .{});
        return error.InvalidConfig;
    }

    var result = cfg;
    result.paths = paths.?;
    result.repos = try repos.toOwnedSlice();
    return result;
}

fn parseRepo(
    alloc: std.mem.Allocator,
    v: std.json.Value,
    defaults: *const std.array_hash_map.String(KindDefaults),
    diag: *Diag,
) LoadError!?Repo {
    const o = try obj(v, diag, "repos[{d}]") orelse return null;
    try rejectUnknown(o, &.{ "name", "url", "kind", "default_branch", "worktree_safe", "sync", "check", "rag", "commands", "env" }, diag, "repos[{d}]");
    const name = try reqStr(o, "name", diag, "repos[{d}].name") orelse return null;
    if (!validRepoName(name)) {
        diag.add("repo {s}: name must match [A-Za-z0-9._-] and must not be . or ..", .{name});
        return null;
    }

    var url: ?[]const u8 = null;
    if (o.get("url")) |uv| {
        const u = try str(uv, diag, "repos[{d}].url") orelse return null;
        if (!validUrl(u)) {
            diag.add("repo {s}: url must be non-empty without whitespace", .{name});
            return null;
        }
        url = u;
    }

    var kind: Kind = .other;
    if (o.get("kind")) |kv| {
        const ks = try str(kv, diag, "repos[{d}].kind") orelse return null;
        kind = kindFromString(ks) orelse {
            diag.add("repo {s}: unknown kind {s} (expected zig, go, node, site, bash, other)", .{ name, ks });
            return null;
        };
    }

    var default_branch: ?[]const u8 = null;
    if (o.get("default_branch")) |bv| {
        const b = try str(bv, diag, "repos[{d}].default_branch") orelse return null;
        if (b.len == 0) {
            diag.add("repo {s}: default_branch must not be empty", .{name});
            return null;
        }
        default_branch = b;
    }

    var worktree_safe = false;
    if (o.get("worktree_safe")) |wv| {
        worktree_safe = try boolean(wv, diag, "repos[{d}].worktree_safe") orelse return null;
    }

    var sync_enabled = true;
    if (o.get("sync")) |sv| {
        const so = try obj(sv, diag, "repos[{d}].sync") orelse return null;
        try rejectUnknown(so, &.{"enabled"}, diag, "repos[{d}].sync");
        if (so.get("enabled")) |ev| {
            sync_enabled = try boolean(ev, diag, "repos[{d}].sync.enabled") orelse return null;
        }
    }

    var check: ?[]const []const u8 = null;
    if (o.get("check")) |cv| {
        const co = try obj(cv, diag, "repos[{d}].check") orelse return null;
        try rejectUnknown(co, &.{"argv"}, diag, "repos[{d}].check");
        const argv_val = co.get("argv") orelse {
            diag.add("repo {s}: check must declare argv", .{name});
            return null;
        };
        const argv = try strArray(argv_val, diag, "repos[{d}].check.argv") orelse return null;
        try validateArgvTokens(argv, diag, "repos[{d}].check.argv");
        check = argv;
    } else if (defaults.get(@tagName(kind))) |kd| {
        check = kd.check;
    }

    var rag: ?Rag = null;
    if (o.get("rag")) |rv| {
        const ro = try obj(rv, diag, "repos[{d}].rag") orelse return null;
        try rejectUnknown(ro, &.{ "command", "files" }, diag, "repos[{d}].rag");
        if (ro.get("command")) |cmd_v| {
            const cmd_o = try obj(cmd_v, diag, "repos[{d}].rag.command") orelse return null;
            try rejectUnknown(cmd_o, &.{ "argv", "output" }, diag, "repos[{d}].rag.command");
            const argv_val = cmd_o.get("argv") orelse {
                diag.add("repo {s}: rag.command must declare argv", .{name});
                return null;
            };
            const argv = try strArray(argv_val, diag, "repos[{d}].rag.command.argv") orelse return null;
            try validateArgvTokens(argv, diag, "repos[{d}].rag.command.argv");
            var output: ?[]const u8 = null;
            if (cmd_o.get("output")) |ov| {
                output = try str(ov, diag, "repos[{d}].rag.command.output") orelse return null;
            }
            rag = .{ .command = .{ .argv = argv, .output = output } };
        } else if (ro.get("files")) |fv| {
            const fo = try obj(fv, diag, "repos[{d}].rag.files") orelse return null;
            try rejectUnknown(fo, &.{ "globs", "max_depth" }, diag, "repos[{d}].rag.files");
            const globs_val = fo.get("globs") orelse {
                diag.add("repo {s}: rag.files must declare globs", .{name});
                return null;
            };
            const globs = try strArray(globs_val, diag, "repos[{d}].rag.files.globs") orelse return null;
            var max_depth: ?u32 = null;
            if (fo.get("max_depth")) |mv| {
                const n = try posInt(mv, diag, "repos[{d}].rag.files.max_depth") orelse return null;
                max_depth = std.math.cast(u32, n) orelse {
                    diag.add("repo {s}: rag.files.max_depth is too large", .{name});
                    return null;
                };
            }
            rag = .{ .files = .{ .globs = globs, .max_depth = max_depth } };
        } else {
            diag.add("repo {s}: rag must declare command or files", .{name});
            return null;
        }
    }

    var cmd_names = ArrayList([]const u8).init(alloc);
    var cmd_argv = ArrayList([]const []const u8).init(alloc);
    if (o.get("commands")) |cv| {
        const co = try obj(cv, diag, "repos[{d}].commands") orelse return null;
        for (co.keys()) |k| {
            if (!validName(k)) {
                diag.add("repo {s}: command name {s} must match [A-Za-z0-9._-]", .{ name, k });
                return null;
            }
            const cmd_o = try obj(co.get(k).?, diag, "repos[{d}].commands.{s}") orelse return null;
            try rejectUnknown(cmd_o, &.{"argv"}, diag, "repos[{d}].commands.{s}");
            const argv_val = cmd_o.get("argv") orelse {
                diag.add("repo {s}: command {s} must declare argv", .{ name, k });
                return null;
            };
            const argv = try strArray(argv_val, diag, "repos[{d}].commands.{s}.argv") orelse return null;
            try validateArgvTokens(argv, diag, "repos[{d}].commands.{s}.argv");
            try cmd_names.append(k);
            try cmd_argv.append(argv);
        }
    }

    // Merge kind-default commands; repo-level entries win on name collision.
    if (defaults.get(@tagName(kind))) |kd| {
        for (kd.cmd_names, 0..) |kn, ki| {
            var already = false;
            for (cmd_names.items) |existing| {
                if (std.mem.eql(u8, existing, kn)) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                try cmd_names.append(kn);
                try cmd_argv.append(kd.cmd_argv[ki]);
            }
        }
    }

    var env = ArrayList([]const u8).init(alloc);
    if (o.get("env")) |ev| {
        const eo = try obj(ev, diag, "repos[{d}].env") orelse return null;
        for (eo.keys()) |k| {
            const val = try str(eo.get(k).?, diag, "repos[{d}].env.{s}") orelse return null;
            try env.append(try std.fmt.allocPrint(alloc, "{s}={s}", .{ k, val }));
        }
    }

    return .{
        .name = name,
        .url = url,
        .kind = kind,
        .default_branch = default_branch,
        .worktree_safe = worktree_safe,
        .sync_enabled = sync_enabled,
        .check = check,
        .rag = rag,
        .cmd_names = try cmd_names.toOwnedSlice(),
        .cmd_argv = try cmd_argv.toOwnedSlice(),
        .env = try env.toOwnedSlice(),
    };
}

fn obj(v: std.json.Value, diag: *Diag, ctx: []const u8) LoadError!?std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
        else => blk: {
            diag.add("{s}: expected an object", .{ctx});
            break :blk null;
        },
    };
}

fn array(v: std.json.Value, diag: *Diag, ctx: []const u8) LoadError!?std.json.Array {
    return switch (v) {
        .array => |a| a,
        else => blk: {
            diag.add("{s}: expected an array", .{ctx});
            break :blk null;
        },
    };
}

fn str(v: std.json.Value, diag: *Diag, ctx: []const u8) LoadError!?[]const u8 {
    return switch (v) {
        .string => |s| s,
        else => blk: {
            diag.add("{s}: expected a string", .{ctx});
            break :blk null;
        },
    };
}

fn boolean(v: std.json.Value, diag: *Diag, ctx: []const u8) LoadError!?bool {
    return switch (v) {
        .bool => |b| b,
        else => blk: {
            diag.add("{s}: expected a boolean", .{ctx});
            break :blk null;
        },
    };
}

fn posInt(v: std.json.Value, diag: *Diag, ctx: []const u8) LoadError!?usize {
    return switch (v) {
        .integer => |n| blk: {
            if (n < 1) {
                diag.add("{s}: must be a positive integer", .{ctx});
                break :blk null;
            }
            break :blk @intCast(n);
        },
        else => blk: {
            diag.add("{s}: expected a positive integer", .{ctx});
            break :blk null;
        },
    };
}

fn reqStr(o: std.json.ObjectMap, key: []const u8, diag: *Diag, ctx: []const u8) LoadError!?[]const u8 {
    const v = o.get(key) orelse blk: {
        diag.add("{s}: missing required field", .{ctx});
        break :blk null;
    } orelse return null;
    return str(v, diag, ctx);
}

fn rejectUnknown(o: std.json.ObjectMap, allowed: []const []const u8, diag: *Diag, ctx: []const u8) LoadError!void {
    for (o.keys()) |k| {
        if (k.len > 0 and k[0] == '_') continue;
        var known = false;
        for (allowed) |a| {
            if (std.mem.eql(u8, k, a)) {
                known = true;
                break;
            }
        }
        if (!known) {
            diag.add("{s}: unknown key {s}", .{ ctx, k });
            return error.InvalidConfig;
        }
    }
}

fn strArray(v: std.json.Value, diag: *Diag, ctx: []const u8) LoadError!?[]const []const u8 {
    const arr = try array(v, diag, ctx) orelse return null;
    if (arr.items.len == 0) {
        diag.add("{s}: must not be empty", .{ctx});
        return null;
    }
    var list = ArrayList([]const u8).init(diag.alloc);
    for (arr.items, 0..) |item, i| {
        const s = try str(item, diag, ctx) orelse return null;
        if (s.len == 0) {
            diag.add("{s}: entry {d} must not be empty", .{ ctx, i });
            return null;
        }
        try list.append(s);
    }
    return try list.toOwnedSlice();
}

const known_tokens = [_][]const u8{ "workspace", "repo", "name", "branch", "rag_out" };

fn validateArgvTokens(argv: []const []const u8, diag: *Diag, ctx: []const u8) LoadError!void {
    for (argv, 0..) |a, i| {
        var j: usize = 0;
        while (j < a.len) {
            if (a[j] == '{') {
                const end = std.mem.indexOfScalarPos(u8, a, j + 1, '}') orelse {
                    diag.add("{s}: entry {d} has an unmatched '{{'", .{ ctx, i });
                    return error.InvalidConfig;
                };
                const tok = a[j + 1 .. end];
                var known = false;
                for (known_tokens) |kt| {
                    if (std.mem.eql(u8, tok, kt)) known = true;
                }
                if (!known) {
                    diag.add("{s}: entry {d} uses unknown placeholder {{{s}}}", .{ ctx, i, tok });
                    return error.InvalidConfig;
                }
                j = end + 1;
            } else {
                j += 1;
            }
        }
    }
}

pub const ExpandCtx = struct {
    workspace: []const u8,
    repo: []const u8,
    name: []const u8,
    branch: []const u8,
    rag_out: []const u8,
};

pub fn expand(alloc: std.mem.Allocator, input: []const u8, ctx: ExpandCtx) ![]const u8 {
    var out = ArrayList(u8).init(alloc);
    defer out.deinit();
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '{') {
            if (std.mem.indexOfScalarPos(u8, input, i + 1, '}')) |end| {
                const tok = input[i + 1 .. end];
                if (knownToken(tok)) {
                    const val: []const u8 = if (std.mem.eql(u8, tok, "workspace"))
                        ctx.workspace
                    else if (std.mem.eql(u8, tok, "repo"))
                        ctx.repo
                    else if (std.mem.eql(u8, tok, "name"))
                        ctx.name
                    else if (std.mem.eql(u8, tok, "branch"))
                        ctx.branch
                    else
                        ctx.rag_out;
                    try out.appendSlice(val);
                    i = end + 1;
                    continue;
                }
            }
        }
        try out.append(input[i]);
        i += 1;
    }
    return out.toOwnedSlice();
}

fn knownToken(tok: []const u8) bool {
    for (known_tokens) |kt| {
        if (std.mem.eql(u8, tok, kt)) return true;
    }
    return false;
}

fn expandPath(alloc: std.mem.Allocator, s: []const u8, home_dir: []const u8) ![]const u8 {
    if (s.len > 0 and s[0] == '~') {
        if (s.len == 1 or s[1] == '/') {
            return std.mem.concat(alloc, u8, &.{ home_dir, s[1..] });
        }
    }
    return alloc.dupe(u8, s);
}

fn validName(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '_' and c != '-') return false;
    }
    return true;
}

fn validRepoName(s: []const u8) bool {
    if (!validName(s)) return false;
    if (std.mem.eql(u8, s, ".") or std.mem.eql(u8, s, "..")) return false;
    return true;
}

fn validUrl(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (std.ascii.isWhitespace(c)) return false;
    }
    return true;
}

test "expand replaces known placeholders" {
    const alloc = std.testing.allocator;
    const ctx = ExpandCtx{
        .workspace = "/w",
        .repo = "/r",
        .name = "boris",
        .branch = "afterparty",
        .rag_out = "/s",
    };
    const out = try expand(alloc, "{workspace}/scripts/x.py {name} {branch}", ctx);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("/w/scripts/x.py boris afterparty", out);
}

test "expand leaves unknown tokens literal" {
    const alloc = std.testing.allocator;
    const ctx = ExpandCtx{ .workspace = "/w", .repo = "/r", .name = "n", .branch = "b", .rag_out = "/s" };
    const out = try expand(alloc, "a {nope} b", ctx);
    defer alloc.free(out);
    try std.testing.expectEqualStrings("a {nope} b", out);
}

test "expand tilde path" {
    const alloc = std.testing.allocator;
    const p = try expandPath(alloc, "~/Code/repos", "/Users/t");
    defer alloc.free(p);
    try std.testing.expectEqualStrings("/Users/t/Code/repos", p);
    const q = try expandPath(alloc, "/abs", "/Users/t");
    defer alloc.free(q);
    try std.testing.expectEqualStrings("/abs", q);
}

test "kind parse" {
    try std.testing.expectEqual(Kind.zig, kindFromString("zig").?);
    try std.testing.expectEqual(Kind.other, kindFromString("other").?);
    try std.testing.expect(kindFromString("rust") == null);
}

test "name and url validation" {
    try std.testing.expect(validName("boris"));
    try std.testing.expect(validName("DipshitOS"));
    try std.testing.expect(validName("codex-limits"));
    try std.testing.expect(validName("filed.fyi"));
    try std.testing.expect(!validName("has space"));
    try std.testing.expect(!validName(""));
    try std.testing.expect(validUrl("git@github.com:drawmeanelephant/boris.git"));
    try std.testing.expect(!validUrl("bad url"));
    try std.testing.expect(!validUrl(""));
}

test "dot names are rejected as path traversal" {
    try std.testing.expect(!validRepoName("."));
    try std.testing.expect(!validRepoName(".."));
    try std.testing.expect(validRepoName("boris"));
    try std.testing.expect(validRepoName("filed.fyi"));
    try std.testing.expect(!validRepoName("a/b"));
}

test "rejectUnknown rejects unknown nested keys" {
    const alloc = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, "{\"a\": 1, \"typo\": 2}", .{ .allocate = .alloc_always });
    defer parsed.deinit();
    var diag = Diag.init(alloc);
    defer diag.deinit();
    try std.testing.expectError(error.InvalidConfig, rejectUnknown(parsed.value.object, &.{"a"}, &diag, "repos[0]"));
}

test "rejectUnknown allows underscore keys and known keys" {
    const alloc = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, "{\"a\": 1, \"_note\": \"x\"}", .{ .allocate = .alloc_always });
    defer parsed.deinit();
    var diag = Diag.init(alloc);
    defer diag.deinit();
    try rejectUnknown(parsed.value.object, &.{"a"}, &diag, "repos[0]");
}

test "parse full 13 repo production catalog example" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const example_json = @embedFile("workspace.example.json");
    var diag = Diag.init(alloc);

    const cfg = loadSlice(alloc, example_json, "/Users/t/config/fmr/workspace.json", "/Users/t", &diag) catch |err| {
        if (diag.msgs.items.len > 0) {
            std.debug.print("parse error: {s}\n", .{diag.msgs.items[0]});
        }
        return err;
    };

    try std.testing.expectEqual(@as(usize, 13), cfg.repos.len);
    try std.testing.expect(cfg.findRepo("boris") != null);
    try std.testing.expect(cfg.findRepo("DipshitOS") != null);
    try std.testing.expect(cfg.findRepo("oliver") != null);
    try std.testing.expect(cfg.findRepo("know") != null);
    try std.testing.expect(cfg.findRepo("codex-limits") != null);
    try std.testing.expect(cfg.findRepo("fullonrogues.org") != null);
    try std.testing.expect(cfg.findRepo("rotkeeper") != null);
    try std.testing.expect(cfg.findRepo("minutes-without-motion") != null);
    try std.testing.expect(cfg.findRepo("la-famille") != null);
    try std.testing.expect(cfg.findRepo("filed.fyi") != null);
    try std.testing.expect(cfg.findRepo("apex") != null);
    try std.testing.expect(cfg.findRepo("thermalextractiondevices.com") != null);
    try std.testing.expect(cfg.findRepo("corgifever.com") != null);
    try std.testing.expect(cfg.findRepo("rustodian") == null);

    // Verify kind-default inheritance on zig and go
    const boris = cfg.findRepo("boris").?;
    try std.testing.expect(boris.check != null);
    try std.testing.expectEqualStrings("afterparty", boris.default_branch.?);
    try std.testing.expect(boris.worktree_safe);

    const know = cfg.findRepo("know").?;
    try std.testing.expect(know.check != null);
    try std.testing.expectEqualStrings("go", know.check.?[0]);
}

// ---------------------------------------------------------------------------
// Catalog JSON emission (fmr config --json)
// ---------------------------------------------------------------------------

/// Emit the parsed workspace catalog as structured JSON (`fmr config --json`).
/// Lets GUI clients render repo kinds, configured commands, and rag modes
/// without re-parsing workspace.json. Output is additive and stable across
/// releases.
pub fn writeCatalogJson(ctx: *const process.Ctx, cfg: *const Config) u8 {
    const alloc = ctx.alloc;
    var buf = ArrayList(u8).init(alloc);

    buf.appendSlice("{\n  \"version\": 1,\n  \"command\": \"config\",\n  \"exit\": 0,\n") catch return 1;
    buf.appendSlice("  \"paths\": {\n") catch return 1;
    buf.appendSlice("    \"repos\": ") catch return 1;
    jsonStr(&buf, cfg.paths.repos) catch return 1;
    buf.appendSlice(",\n    \"worktrees\": ") catch return 1;
    jsonStr(&buf, cfg.paths.worktrees) catch return 1;
    buf.appendSlice(",\n    \"sourceRag\": ") catch return 1;
    jsonStr(&buf, cfg.paths.source_rag) catch return 1;
    buf.appendSlice("\n  },\n") catch return 1;
    const par = std.fmt.allocPrint(alloc, "  \"parallelism\": {{\"sync\": {d}, \"status\": {d}, \"check\": {d}, \"rag\": {d}}},\n", .{
        cfg.parallelism.sync,
        cfg.parallelism.status,
        cfg.parallelism.check,
        cfg.parallelism.rag,
    }) catch return 1;
    buf.appendSlice(par) catch return 1;
    buf.appendSlice("  \"repos\": [\n") catch return 1;

    for (cfg.repos, 0..) |*r, i| {
        buf.appendSlice("    {\n") catch return 1;
        buf.appendSlice("      \"name\": ") catch return 1;
        jsonStr(&buf, r.name) catch return 1;
        buf.appendSlice(",\n      \"url\": ") catch return 1;
        if (r.url) |u| jsonStr(&buf, u) catch return 1 else buf.appendSlice("null") catch return 1;
        buf.appendSlice(",\n      \"kind\": ") catch return 1;
        jsonStr(&buf, @tagName(r.kind)) catch return 1;
        buf.appendSlice(",\n      \"path\": ") catch return 1;
        const repo_path = std.Io.Dir.path.join(alloc, &.{ cfg.paths.repos, r.name }) catch return 1;
        jsonStr(&buf, repo_path) catch return 1;
        buf.appendSlice(",\n      \"default_branch\": ") catch return 1;
        if (r.default_branch) |b| jsonStr(&buf, b) catch return 1 else buf.appendSlice("null") catch return 1;
        buf.appendSlice(",\n      \"worktree_safe\": ") catch return 1;
        buf.appendSlice(if (r.worktree_safe) "true" else "false") catch return 1;
        buf.appendSlice(",\n      \"sync_enabled\": ") catch return 1;
        buf.appendSlice(if (r.sync_enabled) "true" else "false") catch return 1;

        buf.appendSlice(",\n      \"check\": ") catch return 1;
        if (r.check) |argv| {
            appendJsonArray(&buf, argv) catch return 1;
        } else {
            buf.appendSlice("null") catch return 1;
        }

        buf.appendSlice(",\n      \"rag\": ") catch return 1;
        if (r.rag) |*rag| {
            switch (rag.*) {
                .command => |c| {
                    buf.appendSlice("{\"mode\": \"command\", \"argv\": ") catch return 1;
                    appendJsonArray(&buf, c.argv) catch return 1;
                    buf.appendSlice(", \"output\": ") catch return 1;
                    if (c.output) |o| jsonStr(&buf, o) catch return 1 else buf.appendSlice("null") catch return 1;
                    buf.appendSlice("}") catch return 1;
                },
                .files => |f| {
                    buf.appendSlice("{\"mode\": \"files\", \"globs\": ") catch return 1;
                    appendJsonArray(&buf, f.globs) catch return 1;
                    buf.appendSlice(", \"max_depth\": ") catch return 1;
                    if (f.max_depth) |md| {
                        const depth = std.fmt.allocPrint(alloc, "{d}", .{md}) catch return 1;
                        buf.appendSlice(depth) catch return 1;
                    } else {
                        buf.appendSlice("null") catch return 1;
                    }
                    buf.appendSlice("}") catch return 1;
                },
            }
        } else {
            buf.appendSlice("null") catch return 1;
        }

        buf.appendSlice(",\n      \"env\": ") catch return 1;
        appendJsonArray(&buf, r.env) catch return 1;

        buf.appendSlice(",\n      \"commands\": {") catch return 1;
        for (r.cmd_names, 0..) |cn, ci| {
            if (ci > 0) buf.appendSlice(",") catch return 1;
            buf.appendSlice("\n        ") catch return 1;
            jsonStr(&buf, cn) catch return 1;
            buf.appendSlice(": ") catch return 1;
            appendJsonArray(&buf, r.cmd_argv[ci]) catch return 1;
        }
        if (r.cmd_names.len > 0) buf.appendSlice("\n      ") catch return 1;
        buf.appendSlice("}") catch return 1;

        buf.appendSlice("\n    }") catch return 1;
        if (i + 1 < cfg.repos.len) buf.appendSlice(",") catch return 1;
        buf.appendSlice("\n") catch return 1;
    }
    buf.appendSlice("  ]\n}\n") catch return 1;

    std.Io.File.stdout().writeStreamingAll(ctx.io, buf.items) catch {};
    return 0;
}

fn jsonStr(buf: *ArrayList(u8), s: []const u8) !void {
    try buf.append('"');
    for (s) |ch| {
        switch (ch) {
            '"' => try buf.appendSlice("\\\""),
            '\\' => try buf.appendSlice("\\\\"),
            '\n' => try buf.appendSlice("\\n"),
            '\t' => try buf.appendSlice("\\t"),
            '\r' => try buf.appendSlice("\\r"),
            else => try buf.append(ch),
        }
    }
    try buf.append('"');
}

fn appendJsonArray(buf: *ArrayList(u8), items: []const []const u8) !void {
    try buf.append('[');
    for (items, 0..) |it, i| {
        if (i > 0) try buf.appendSlice(", ");
        try jsonStr(buf, it);
    }
    try buf.append(']');
}
