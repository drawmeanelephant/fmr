//! Subprocess execution, environment management, and output capture.
//! Isolates std.process differences and manages execution timeouts and captured buffers.

const std = @import("std");
const ArrayList = std.array_list.Managed;

pub const Ctx = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
};

pub const Result = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,
    timed_out: bool = false,
    truncated: bool = false,

    pub fn exited(r: *const Result) ?u8 {
        return switch (r.term) {
            .exited => |c| c,
            else => null,
        };
    }

    pub fn ok(r: *const Result) bool {
        return (r.exited() orelse 1) == 0;
    }

    pub fn describe(r: *const Result, alloc: std.mem.Allocator) ![]const u8 {
        return switch (r.term) {
            .exited => |c| std.fmt.allocPrint(alloc, "exited {d}", .{c}),
            .signal => |s| std.fmt.allocPrint(alloc, "killed by signal {s}", .{@tagName(s)}),
            .stopped => |s| std.fmt.allocPrint(alloc, "stopped by signal {s}", .{@tagName(s)}),
            .unknown => |u| std.fmt.allocPrint(alloc, "terminated (code {d})", .{u}),
        };
    }
};

pub const Options = struct {
    cwd: ?[]const u8 = null,
    timeout_ns: ?u64 = null,
    env: []const []const u8 = &.{},
};

const capture_limit = 1 << 20;
const fetch_timeout_ns = 10 * 60 * std.time.ns_per_s;

pub fn run(ctx: *const Ctx, argv: []const []const u8, opts: Options) !Result {
    var env_map: ?std.process.Environ.Map = null;
    if (opts.env.len > 0) {
        const m = try mapWithOverrides(ctx, opts.env);
        env_map = m;
    }
    defer if (env_map) |*m| m.deinit();

    const result = std.process.run(ctx.alloc, ctx.io, .{
        .argv = argv,
        .cwd = if (opts.cwd) |cwd| .{ .path = cwd } else .inherit,
        .environ_map = if (env_map) |*m| m else ctx.environ_map,
        .stdout_limit = .limited(capture_limit),
        .stderr_limit = .limited(capture_limit),
        .timeout = if (opts.timeout_ns) |ns| .{ .duration = .{ .raw = .{ .nanoseconds = @intCast(ns) }, .clock = .real } } else .none,
    }) catch |err| {
        return switch (err) {
            error.Timeout => Result{
                .term = .{ .exited = 1 },
                .stdout = &.{},
                .stderr = &.{},
                .timed_out = true,
            },
            error.StreamTooLong => Result{
                .term = .{ .exited = 1 },
                .stdout = &.{},
                .stderr = &.{},
                .truncated = true,
            },
            else => Result{
                .term = .{ .exited = 127 },
                .stdout = &.{},
                .stderr = try std.fmt.allocPrint(ctx.alloc, "failed to spawn {s}: {s}", .{ argv[0], @errorName(err) }),
            },
        };
    };
    return .{ .term = result.term, .stdout = result.stdout, .stderr = result.stderr };
}

fn mapWithOverrides(ctx: *const Ctx, overrides: []const []const u8) !std.process.Environ.Map {
    var m = std.process.Environ.Map.init(ctx.alloc);
    errdefer m.deinit();
    var it = ctx.environ_map.iterator();
    while (it.next()) |entry| {
        try m.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    for (overrides) |kv| {
        const eq = std.mem.indexOfScalar(u8, kv, '=') orelse continue;
        try m.put(kv[0..eq], kv[eq + 1 ..]);
    }
    return m;
}

pub fn home(ctx: *const Ctx) ?[]const u8 {
    return ctx.environ_map.get("HOME");
}

pub fn stderrLine(ctx: *const Ctx, comptime fmt: []const u8, args: anytype) void {
    const body = std.fmt.allocPrint(ctx.alloc, fmt, args) catch return;
    std.Io.File.stderr().writeStreamingAll(ctx.io, body) catch {};
}

pub fn stderrLineNewline(ctx: *const Ctx, comptime fmt: []const u8, args: anytype) void {
    const body = std.fmt.allocPrint(ctx.alloc, fmt, args) catch return;
    var buf: ArrayList(u8) = .init(ctx.alloc);
    buf.appendSlice(body) catch return;
    buf.append('\n') catch return;
    std.Io.File.stderr().writeStreamingAll(ctx.io, buf.items) catch {};
}
