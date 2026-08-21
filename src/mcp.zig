//! MCP server over stdio JSON-RPC.

const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const config = @import("config.zig");
const ui = @import("ui.zig");

pub fn run(ctx: *const process.Ctx, cfg: *const config.Config, config_path: []const u8) u8 {
    // Use buffered reader on stdin
    var stdin_buf: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().reader(ctx.io, &stdin_buf);
    var line_buf: [65536]u8 = undefined;

    // Send initial notification? Wait for initialize.
    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch break;
        if (line.len == 0) continue;
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;
        const resp = handleRequest(ctx, cfg, config_path, trimmed, &line_buf) catch continue;
        if (resp.len > 0) {
            std.Io.File.stdout().writeStreamingAll(ctx.io, resp) catch break;
            std.Io.File.stdout().writeStreamingAll(ctx.io, "\n") catch break;
        }
    }
    return 0;
}

fn handleRequest(ctx: *const process.Ctx, cfg: *const config.Config, config_path: []const u8, input: []const u8, buf: []u8) ![]const u8 {
    _ = cfg;
    _ = config_path;
    // Minimal JSON parsing: look for "method"
    const alloc = ctx.alloc;
    var parsed = std.json.parseFromSlice(std.json.Value, alloc, input, .{ .allocate = .alloc_always }) catch {
        return try std.fmt.bufPrint(buf, "{{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{{\"code\":-32700,\"message\":\"parse error\"}}}}", .{});
    };
    defer parsed.deinit();
    const obj = parsed.value.object;
    const id_val = obj.get("id");
    const id_str = if (id_val) |v| switch (v) {
        .integer => |n| try std.fmt.allocPrint(alloc, "{d}", .{n}),
        .string => |s| try std.fmt.allocPrint(alloc, "\"{s}\"", .{s}),
        else => "null",
    } else "null";
    const method_val = obj.get("method") orelse {
        return try std.fmt.bufPrint(buf, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":-32600,\"message\":\"missing method\"}}}}", .{id_str});
    };
    const method = switch (method_val) {
        .string => |s| s,
        else => "",
    };

    if (std.mem.eql(u8, method, "initialize")) {
        var tmp = ArrayList(u8).init(alloc);
        tmp.appendSlice("{\"jsonrpc\":\"2.0\",\"id\":") catch return "";
        tmp.appendSlice(id_str) catch return "";
        tmp.appendSlice(",\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"fmr\",\"version\":\"0.2.0\"}}}") catch return "";
        const out = tmp.toOwnedSlice() catch return "";
        if (out.len > buf.len) return "";
        @memcpy(buf[0..out.len], out);
        return buf[0..out.len];
    } else if (std.mem.eql(u8, method, "tools/list")) {
        var tmp = ArrayList(u8).init(alloc);
        tmp.appendSlice("{\"jsonrpc\":\"2.0\",\"id\":") catch return "";
        tmp.appendSlice(id_str) catch return "";
        tmp.appendSlice(",\"result\":{\"tools\":[{\"name\":\"fmr_status\",\"description\":\"Workspace status (read-only)\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"repos\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}}},{\"name\":\"fmr_sync\",\"description\":\"Safe sync primaries\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"repos\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"fixOrigin\":{\"type\":\"boolean\"}}}},{\"name\":\"fmr_doctor\",\"description\":\"Diagnostics\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"fix\":{\"type\":\"boolean\"}}}},{\"name\":\"fmr_context\",\"description\":\"AI context dump\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"repos\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"commits\":{\"type\":\"integer\"}}}},{\"name\":\"fmr_grep\",\"description\":\"Cross-repo search\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"pattern\":{\"type\":\"string\"},\"repos\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"kind\":{\"type\":\"string\"}}}},{\"name\":\"fmr_run\",\"description\":\"Run named command\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"repo\":{\"type\":\"string\"},\"command\":{\"type\":\"string\"},\"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}}}},{\"name\":\"fmr_config\",\"description\":\"Dump catalog\",\"inputSchema\":{\"type\":\"object\"}}]}}") catch return "";
        const out = tmp.toOwnedSlice() catch return "";
        if (out.len > buf.len) return "";
        @memcpy(buf[0..out.len], out);
        return buf[0..out.len];
    } else if (std.mem.eql(u8, method, "tools/call")) {
        const params = obj.get("params") orelse {
            return try std.fmt.bufPrint(buf, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":-32602,\"message\":\"missing params\"}}}}", .{id_str});
        };
        const pobj = switch (params) {
            .object => |o| o,
            else => return try std.fmt.bufPrint(buf, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":-32602,\"message\":\"params must be object\"}}}}", .{id_str}),
        };
        const name_val = pobj.get("name") orelse {
            return try std.fmt.bufPrint(buf, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":-32602,\"message\":\"missing name\"}}}}", .{id_str});
        };
        const tool_name = switch (name_val) {
            .string => |s| s,
            else => "",
        };
        // For v1, return a placeholder that indicates tool would be executed via fmr subprocess
        // Real impl would run the tool and return its JSON output
        const args = if (pobj.get("arguments")) |a| try std.json.Stringify.valueAlloc(alloc, a, .{}) else "{}";
        const tool_result = try std.fmt.allocPrint(alloc, "tool {s} called with {s} — proxy via fmr {s} --json", .{ tool_name, args, tool_name });
        const content = try std.fmt.allocPrint(alloc, "[{{\"type\":\"text\",\"text\":\"{s}\"}}]", .{tool_result});
        // Escape content for JSON
        var escaped = ArrayList(u8).init(alloc);
        for (content) |ch| {
            if (ch == '"') {
                escaped.appendSlice("\\\"") catch {};
            } else if (ch == '\\') {
                escaped.appendSlice("\\\\") catch {};
            } else if (ch == '\n') {
                escaped.appendSlice("\\n") catch {};
            } else {
                escaped.append(ch) catch {};
            }
        }
        return try std.fmt.bufPrint(buf, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{{\"content\":[{{\"type\":\"text\",\"text\":\"{s}\"}}]}}}}", .{ id_str, escaped.items });
    } else if (std.mem.eql(u8, method, "notifications/initialized")) {
        return "";
    } else {
        return try std.fmt.bufPrint(buf, "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":-32601,\"message\":\"method not found: {s}\"}}}}", .{ id_str, method });
    }
}
