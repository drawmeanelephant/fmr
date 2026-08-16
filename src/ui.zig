//! Terminal UI, formatting, color output, and aligned tabular printing.
//! Detects TTY support and honors the NO_COLOR standard environment variable.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");

pub const Color = enum { reset, green, yellow, red, blue, gray };

pub const Printer = struct {
    tty: bool,

    pub fn init() Printer {
        return .{ .tty = std.c.isatty(std.posix.STDOUT_FILENO) == 1 };
    }

    pub fn initFromCtx(ctx: *const process.Ctx) Printer {
        const is_tty = std.c.isatty(std.posix.STDOUT_FILENO) == 1;
        const no_color = if (ctx.environ_map.get("NO_COLOR")) |nc| nc.len > 0 else false;
        return .{ .tty = is_tty and !no_color };
    }

    fn code(self: *const Printer, c: Color) []const u8 {
        if (!self.tty) return "";
        return switch (c) {
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .red => "\x1b[31m",
            .blue => "\x1b[34m",
            .gray => "\x1b[90m",
            .reset => "\x1b[0m",
        };
    }

    pub fn line(self: *const Printer, ctx: *const process.Ctx, c: Color, comptime fmt: []const u8, args: anytype) void {
        const body = std.fmt.allocPrint(ctx.alloc, fmt, args) catch return;
        self.emit(ctx, c, body);
    }

    pub fn raw(self: *const Printer, ctx: *const process.Ctx, comptime fmt: []const u8, args: anytype) void {
        const body = std.fmt.allocPrint(ctx.alloc, fmt, args) catch return;
        self.emit(ctx, .reset, body);
    }

    fn emit(self: *const Printer, ctx: *const process.Ctx, c: Color, body: []const u8) void {
        const out = std.fmt.allocPrint(ctx.alloc, "{s}{s}{s}\n", .{ self.code(c), body, self.code(.reset) }) catch return;
        std.Io.File.stdout().writeStreamingAll(ctx.io, out) catch {};
    }

    pub fn row(_: *const Printer, ctx: *const process.Ctx, cols: []const []const u8, widths: []const usize) void {
        var out = ArrayList(u8).init(ctx.alloc);
        for (cols, 0..) |col, i| {
            if (i > 0) out.append(' ') catch return;
            out.appendSlice(col) catch return;
            if (i + 1 < cols.len) {
                const pad = widths[i] - @min(widths[i], col.len);
                var j: usize = 0;
                while (j < pad) : (j += 1) out.append(' ') catch return;
            }
        }
        out.append('\n') catch return;
        std.Io.File.stdout().writeStreamingAll(ctx.io, out.items) catch {};
    }
};