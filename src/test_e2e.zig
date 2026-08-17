const std = @import("std");
const ArrayList = std.array_list.Managed;
const process = @import("process.zig");
const git = @import("git.zig");
const ui = @import("ui.zig");

var failures: usize = 0;
var current: []const u8 = "";

fn expect(ctx: *const process.Ctx, ok: bool, what: []const u8) void {
    const pr = ui.Printer.init();
    if (ok) {
        pr.line(ctx, .green, "PASS {s}: {s}", .{ current, what });
    } else {
        pr.line(ctx, .red, "FAIL {s}: {s}", .{ current, what });
        failures += 1;
    }
}

fn expectExit(ctx: *const process.Ctx, res: process.Result, want: u8, what: []const u8) void {
    const got = res.exited();
    const pr = ui.Printer.init();
    if (got == want) {
        pr.line(ctx, .green, "PASS {s}: {s}", .{ current, what });
    } else {
        pr.line(ctx, .red, "FAIL {s}: {s} (got {?d})", .{ current, what, got });
        failures += 1;
    }
}

fn gitRun(ctx: *const process.Ctx, args: []const []const u8, cwd: ?[]const u8) !process.Result {
    return process.run(ctx, args, .{ .cwd = cwd });
}

fn gitOk(ctx: *const process.Ctx, args: []const []const u8, cwd: ?[]const u8) !bool {
    const res = try gitRun(ctx, args, cwd);
    return res.ok();
}

fn initRepo(ctx: *const process.Ctx, path: []const u8, branch: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(ctx.io, path);
    if (!try gitOk(ctx, &.{ "git", "init", "-b", branch }, path)) return error.Fixture;
    _ = try gitOk(ctx, &.{ "git", "config", "user.email", "t@t" }, path);
    _ = try gitOk(ctx, &.{ "git", "config", "user.name", "T" }, path);
    const f = try std.Io.Dir.path.join(ctx.alloc, &.{ path, "f.txt" });
    var file = try std.Io.Dir.cwd().createFile(ctx.io, f, .{ .truncate = true });
    defer file.close(ctx.io);
    try file.writeStreamingAll(ctx.io, "one\n");
    if (!try gitOk(ctx, &.{ "git", "add", "." }, path)) return error.Fixture;
    if (!try gitOk(ctx, &.{ "git", "commit", "-q", "-m", "c1" }, path)) return error.Fixture;
}

fn addCommit(ctx: *const process.Ctx, path: []const u8, msg: []const u8) !void {
    const f = try std.Io.Dir.path.join(ctx.alloc, &.{ path, "f.txt" });
    var file = try std.Io.Dir.cwd().createFile(ctx.io, f, .{ .truncate = false });
    defer file.close(ctx.io);
    const len = try file.length(ctx.io);
    try file.writePositionalAll(ctx.io, msg, len);
    _ = try gitOk(ctx, &.{ "git", "add", "." }, path);
    if (!try gitOk(ctx, &.{ "git", "commit", "-q", "-m", msg }, path)) return error.Fixture;
}

fn makeBareOrigin(ctx: *const process.Ctx, src: []const u8, bare: []const u8) !void {
    if (!try gitOk(ctx, &.{ "git", "clone", "-q", "--bare", src, bare }, null)) return error.Fixture;
}

fn mainImpl(init: std.process.Init) !u8 {
    const ctx = process.Ctx{
        .alloc = init.arena.allocator(),
        .io = init.io,
        .environ_map = init.environ_map,
    };
    var args_it = std.process.Args.Iterator.init(init.minimal.args);
    _ = args_it.next();
    const fmr_bin = args_it.next() orelse {
        process.stderrLineNewline(&ctx, "fmr-e2e: missing fmr binary path argument", .{});
        return 1;
    };

    const pr = ui.Printer.init();
    const tmp_base = init.environ_map.get("FMR_TEST_DIR") orelse init.environ_map.get("YARD_TEST_DIR") orelse init.environ_map.get("TMPDIR") orelse "/tmp";
    const tmp = try std.fmt.allocPrint(ctx.alloc, "{s}/fmr-e2e-{d}", .{ std.mem.trimEnd(u8, tmp_base, "/"), std.c.getpid() });
    std.Io.Dir.cwd().deleteTree(ctx.io, tmp) catch {};
    const keep = std.mem.eql(u8, init.environ_map.get("FMR_E2E_KEEP") orelse init.environ_map.get("YARD_E2E_KEEP") orelse "", "1");
    if (!keep) {
        defer std.Io.Dir.cwd().deleteTree(ctx.io, tmp) catch {};
    }

    const home = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "home" });
    const repos_root = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "repos" });
    const wt_root = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "worktrees" });
    const rag_root = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "source-rag" });
    const origins = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "origins" });
    const config_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "config", "fmr" });
    const config_path = try std.Io.Dir.path.join(ctx.alloc, &.{ config_dir, "workspace.json" });
    try std.Io.Dir.cwd().createDirPath(ctx.io, config_dir);
    try std.Io.Dir.cwd().createDirPath(ctx.io, origins);

    const home_env = try std.fmt.allocPrint(ctx.alloc, "HOME={s}", .{home});
    const pr_env = [_][]const u8{home_env};

    const config_json = try std.fmt.allocPrint(ctx.alloc,
        \\{{
        \\  "paths": {{
        \\    "repos": "{s}",
        \\    "worktrees": "{s}",
        \\    "sourceRag": "{s}"
        \\  }},
        \\  "defaults": {{
        \\    "zig": {{
        \\      "check": {{ "argv": ["true"] }},
        \\      "commands": {{
        \\        "test-default": {{ "argv": ["echo", "kind-default-ok"] }}
        \\      }}
        \\    }}
        \\  }},
        \\  "repos": [
        \\    {{ "name": "alpha", "url": "{s}/alpha.git", "kind": "zig", "default_branch": "afterparty" }},
        \\    {{ "name": "unborn", "url": "{s}/unborn.git", "default_branch": "afterparty" }},
        \\    {{ "name": "wt", "url": "{s}/wt.git" }},
        \\    {{ "name": "wt2", "url": "{s}/wt.git" }},
        \\    {{ "name": "badurl", "url": "{s}/nope.git" }},
        \\    {{ "name": "paused", "url": "{s}/wt.git", "sync": {{ "enabled": false }},
        \\       "rag": {{ "command": {{ "argv": ["true"], "output": "x" }} }} }},
        \\    {{ "name": "check-kd", "url": "{s}/check-kd.git", "kind": "zig", "default_branch": "main" }},
        \\    {{ "name": "check-ex", "url": "{s}/check-ex.git", "default_branch": "main",
        \\       "check": {{ "argv": ["true"] }} }},
        \\    {{ "name": "check-skip", "url": "{s}/check-skip.git", "default_branch": "main" }},
        \\    {{ "name": "check-fail", "url": "{s}/check-fail.git", "default_branch": "main",
        \\       "check": {{ "argv": ["false"] }} }},
        \\    {{ "name": "cmd-repo", "url": "{s}/cmd-repo.git", "default_branch": "main",
        \\       "commands": {{
        \\         "show-env": {{ "argv": ["sh", "-c", "echo FMR=$FMR_REPO"] }},
        \\         "echo-it": {{ "argv": ["echo"] }},
        \\         "fail": {{ "argv": ["false"] }}
        \\       }} }},
        \\    {{ "name": "rag-cmd", "url": "{s}/rag-cmd.git", "default_branch": "main",
        \\       "rag": {{ "command": {{ "argv": ["sh", "-c", "echo hello > $FMR_RAG_OUT/test.txt"] }} }} }},
        \\    {{ "name": "rag-files", "url": "{s}/rag-files.git", "default_branch": "main",
        \\       "rag": {{ "files": {{ "globs": ["*.txt", "*.md"], "max_depth": 2 }} }} }},
        \\    {{ "name": "rag-fail", "url": "{s}/rag-fail.git", "default_branch": "main",
        \\       "rag": {{ "command": {{ "argv": ["false"] }} }} }},
        \\    {{ "name": "rag-skip", "url": "{s}/rag-skip.git", "default_branch": "main" }}
        \\  ]
        \\}}
    , .{ repos_root, wt_root, rag_root, origins, origins, origins, origins, origins, origins, origins, origins, origins, origins, origins, origins, origins, origins, origins });
    try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = config_path, .data = config_json });

    const init_src = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "init-src" });
    try initRepo(&ctx, init_src, "afterparty");
    try addCommit(&ctx, init_src, "c2");
    if (!try gitOk(&ctx, &.{ "git", "branch", "main" }, init_src)) return error.Fixture;
    const alpha_bare = try std.Io.Dir.path.join(ctx.alloc, &.{ origins, "alpha.git" });
    _ = try gitOk(&ctx, &.{ "git", "remote", "add", "origin", alpha_bare }, init_src);
    try makeBareOrigin(&ctx, init_src, alpha_bare);

    const unborn_src = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "unborn-src" });
    try std.Io.Dir.cwd().createDirPath(ctx.io, unborn_src);
    _ = try gitOk(&ctx, &.{ "git", "init", "-q", "-b", "main", unborn_src }, unborn_src);
    try makeBareOrigin(&ctx, unborn_src, try std.Io.Dir.path.join(ctx.alloc, &.{ origins, "unborn.git" }));

    try initRepo(&ctx, try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "wt-src" }), "main");
    try makeBareOrigin(&ctx, try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "wt-src" }), try std.Io.Dir.path.join(ctx.alloc, &.{ origins, "wt.git" }));

    // Create bare origins for check/run/rag fixture repos (reuse init_src history).
    for (&[_][]const u8{ "check-kd", "check-ex", "check-skip", "check-fail", "cmd-repo", "rag-cmd", "rag-files", "rag-fail", "rag-skip" }) |rn| {
        const bare = try std.fmt.allocPrint(ctx.alloc, "{s}/{s}.git", .{ origins, rn });
        try makeBareOrigin(&ctx, init_src, bare);
    }

    const fmr = [_][]const u8{fmr_bin};
    var base_args = ArrayList([]const u8).init(ctx.alloc);
    base_args.appendSlice(&fmr) catch return 1;
    base_args.append("--config") catch return 1;
    base_args.append(config_path) catch return 1;

    pr.line(&ctx, .gray, "e2e tmp dir: {s}", .{tmp});

    current = "clone missing repo";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expect(&ctx, res.ok(), "sync alpha exits 0");
        const alpha_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "alpha" });
        expect(&ctx, git.dirExists(&ctx, alpha_dir), "primary created");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "cloned") != null, "reports cloned");
        const got_branch = (try git.headBranch(&ctx, alpha_dir)) orelse "?";
        expect(&ctx, std.mem.eql(u8, got_branch, "afterparty"), "clone used configured branch");
    }

    current = "up to date is a noop";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expect(&ctx, res.ok(), "second sync exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "up to date") != null, "reports up to date");
    }

    current = "behind fast-forwards";
    {
        const src = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "init-src" });
        try addCommit(&ctx, src, "c3");
        if (!try gitOk(&ctx, &.{ "git", "push", "-q", "origin", "afterparty" }, src)) return error.Fixture;
        const alpha_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "alpha" });
        const before = (try git.fullSha(&ctx, alpha_dir)) orelse "";
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expect(&ctx, res.ok(), "sync behind exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "fast-forward") != null, "reports fast-forward");
        const after = (try git.fullSha(&ctx, alpha_dir)) orelse "";
        expect(&ctx, before.len > 0 and after.len > 0 and !std.mem.eql(u8, before, after), "HEAD moved");
    }

    current = "dirty tracked changes refuse";
    {
        const alpha_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "alpha" });
        const f = try std.Io.Dir.path.join(ctx.alloc, &.{ alpha_dir, "f.txt" });
        var file = try std.Io.Dir.cwd().createFile(ctx.io, f, .{ .truncate = false });
        defer file.close(ctx.io);
        const len = try file.length(ctx.io);
        try file.writePositionalAll(ctx.io, "dirty", len);
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "dirty") != null, "mentions dirty");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "worktrees untouched") != null, "mentions worktrees untouched");
        _ = try gitOk(&ctx, &.{ "git", "checkout", "--", "f.txt" }, alpha_dir);
    }

    current = "untracked only is allowed";
    {
        const alpha_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "alpha" });
        const f = try std.Io.Dir.path.join(ctx.alloc, &.{ alpha_dir, "untracked.txt" });
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = f, .data = "x" });
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expect(&ctx, res.ok(), "untracked-only sync exits 0");
    }

    current = "ahead refuses";
    {
        const alpha_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "alpha" });
        _ = try gitOk(&ctx, &.{ "git", "config", "user.email", "t@t" }, alpha_dir);
        _ = try gitOk(&ctx, &.{ "git", "config", "user.name", "T" }, alpha_dir);
        const f = try std.Io.Dir.path.join(ctx.alloc, &.{ alpha_dir, "f.txt" });
        var file = try std.Io.Dir.cwd().createFile(ctx.io, f, .{ .truncate = false });
        defer file.close(ctx.io);
        const len = try file.length(ctx.io);
        try file.writePositionalAll(ctx.io, "local", len);
        _ = try gitOk(&ctx, &.{ "git", "add", "." }, alpha_dir);
        _ = try gitOk(&ctx, &.{ "git", "commit", "-q", "-m", "local" }, alpha_dir);
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "ahead") != null, "mentions ahead");
    }

    current = "diverged refuses";
    {
        const src = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "init-src" });
        try addCommit(&ctx, src, "c4");
        if (!try gitOk(&ctx, &.{ "git", "push", "-q", "origin", "afterparty" }, src)) return error.Fixture;
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "diverged") != null, "mentions diverged");
    }

    current = "detached head refuses";
    {
        const alpha_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "alpha" });
        std.Io.Dir.cwd().deleteTree(ctx.io, alpha_dir) catch {};
        const args = base_args.items;
        _ = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        const sha = (try git.fullSha(&ctx, alpha_dir)) orelse "";
        _ = try gitOk(&ctx, &.{ "git", "checkout", "-q", sha }, alpha_dir);
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "detached") != null, "mentions detached");
        _ = try gitOk(&ctx, &.{ "git", "checkout", "-q", "afterparty" }, alpha_dir);
    }

    current = "wrong branch refuses";
    {
        const alpha_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "alpha" });
        _ = try gitOk(&ctx, &.{ "git", "switch", "-q", "main" }, alpha_dir);
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "wrong branch") != null, "mentions wrong branch");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "afterparty") != null, "names expected branch");
        _ = try gitOk(&ctx, &.{ "git", "switch", "-q", "afterparty" }, alpha_dir);
    }

    current = "unborn repo refuses";
    {
        const unborn_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "unborn" });
        try std.Io.Dir.cwd().createDirPath(ctx.io, unborn_dir);
        if (!try gitOk(&ctx, &.{ "git", "init", "-q", "-b", "main" }, unborn_dir)) return error.Fixture;
        if (!try gitOk(&ctx, &.{ "git", "remote", "add", "origin", try std.Io.Dir.path.join(ctx.alloc, &.{ origins, "unborn.git" }) }, unborn_dir)) return error.Fixture;
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "unborn" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "unborn") != null, "mentions unborn");
    }

    current = "primary that is a worktree refuses";
    {
        const args = base_args.items;
        const wt_repo = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "wt" });
        _ = try fmrRun(&ctx, args, &.{ "sync", "wt" }, &pr_env);
        const wt2 = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "wt2" });
        _ = try gitOk(&ctx, &.{ "git", "worktree", "add", "-q", "-b", "sess1", wt2 }, wt_repo);
        const wt_session = try std.Io.Dir.path.join(ctx.alloc, &.{ wt_root, "wt", "sess2" });
        std.Io.Dir.cwd().createDirPath(ctx.io, wt_root) catch {};
        _ = try gitOk(&ctx, &.{ "git", "worktree", "add", "-q", "-b", "sess2", wt_session }, wt_repo);
        const res = try fmrRun(&ctx, args, &.{ "sync", "wt2" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "worktree") != null, "mentions worktree");
        _ = try gitOk(&ctx, &.{ "git", "worktree", "remove", "-f", wt2 }, wt_repo);
    }

    current = "url mismatch refuses";
    {
        const alpha_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "alpha" });
        _ = try gitOk(&ctx, &.{ "git", "remote", "set-url", "origin", "/nonexistent" }, alpha_dir);
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "url mismatch") != null, "mentions url mismatch");
        _ = try gitOk(&ctx, &.{ "git", "remote", "set-url", "origin", try std.Io.Dir.path.join(ctx.alloc, &.{ origins, "alpha.git" }) }, alpha_dir);
        const res2 = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expect(&ctx, res2.ok(), "restored url syncs again");
    }

    current = "clone failure is exit 4";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "badurl" }, &pr_env);
        expectExit(&ctx, res, 4, "exit 4");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "git clone") != null, "names the command");
    }

    current = "contended lock refuses with pid";
    {
        const locks_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ home, ".fmr", "locks" });
        const lock_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ locks_dir, "alpha.sync.lock" });
        try std.Io.Dir.cwd().createDirPath(ctx.io, lock_dir);
        const pid_path = try std.Io.Dir.path.join(ctx.alloc, &.{ lock_dir, "pid" });
        const pid_text = try std.fmt.allocPrint(ctx.alloc, "{d}", .{std.c.getpid()});
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = pid_path, .data = pid_text });
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "another fmr sync") != null, "mentions another fmr sync");
        std.Io.Dir.cwd().deleteTree(ctx.io, lock_dir) catch {};
        const res2 = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expect(&ctx, res2.ok(), "releases after lock removed");
    }

    current = "lock with unreadable pid refuses without stealing it";
    {
        const locks_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ home, ".fmr", "locks" });
        const lock_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ locks_dir, "alpha.sync.lock" });
        try std.Io.Dir.cwd().createDirPath(ctx.io, lock_dir);
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expect(&ctx, res.exited() == 1, "exit 1 (cannot acquire lock)");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "cannot acquire lock") != null, "reports lock failure");
        std.Io.Dir.cwd().deleteTree(ctx.io, lock_dir) catch {};
        const res2 = try fmrRun(&ctx, args, &.{ "sync", "alpha" }, &pr_env);
        expect(&ctx, res2.ok(), "syncs after lock removed");
    }

    current = "status reports all repos";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{"status"}, &pr_env);
        expect(&ctx, res.ok(), "status exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "alpha") != null, "lists alpha");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "unborn") != null, "lists unborn");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "badurl") != null, "lists badurl");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "missing") != null, "marks missing repos");
    }

    current = "doctor flags missing root then passes";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{"doctor"}, &pr_env);
        expectExit(&ctx, res, 1, "exit 1 with missing source-rag root");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "source-rag") != null, "names the missing root");
        try std.Io.Dir.cwd().createDirPath(ctx.io, rag_root);
        const res2 = try fmrRun(&ctx, args, &.{"doctor"}, &pr_env);
        expect(&ctx, res2.ok(), "exit 0 after creating roots");
    }

    current = "unknown command and repo are exit 2";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{"frobnicate"}, &pr_env);
        expectExit(&ctx, res, 2, "unknown command exits 2");
        const res2 = try fmrRun(&ctx, args, &.{ "sync", "nope" }, &pr_env);
        expectExit(&ctx, res2, 2, "unknown repo exits 2");
        expect(&ctx, std.mem.indexOf(u8, res2.stderr, "nope") != null, "names the unknown repo");
    }

    current = "invalid config is exit 5";
    {
        const bad_path = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "bad.json" });
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = bad_path, .data = "{ \"repos\": 5 }" });
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "status", "--config", bad_path }, &pr_env);
        expectExit(&ctx, res, 5, "exit 5");
    }

    current = "unknown nested config key is exit 5 naming the field";
    {
        const bad_path = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "badkey.json" });
        const bad_json = try std.fmt.allocPrint(ctx.alloc,
            \\{{ "paths": {{ "repos": "{s}", "worktrees": "{s}", "sourceRag": "{s}" }},
            \\  "repos": [ {{ "name": "a", "typo": 1 }} ] }}
        , .{ repos_root, wt_root, rag_root });
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = bad_path, .data = bad_json });
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "status", "--config", bad_path }, &pr_env);
        expectExit(&ctx, res, 5, "exit 5");
        expect(&ctx, std.mem.indexOf(u8, res.stderr, "typo") != null, "names the unknown key");
    }

    current = "dot repo names are exit 5";
    {
        const bad_path = try std.Io.Dir.path.join(ctx.alloc, &.{ tmp, "dotname.json" });
        const bad_json = try std.fmt.allocPrint(ctx.alloc,
            \\{{ "paths": {{ "repos": "{s}", "worktrees": "{s}", "sourceRag": "{s}" }},
            \\  "repos": [ {{ "name": "..", "url": "x" }} ] }}
        , .{ repos_root, wt_root, rag_root });
        try std.Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = bad_path, .data = bad_json });
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "status", "--config", bad_path }, &pr_env);
        expectExit(&ctx, res, 5, "exit 5");
    }

    current = "paused repo syncs skipped and status shows paused";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "paused" }, &pr_env);
        expect(&ctx, res.ok(), "sync paused exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "skipped") != null, "reports skipped");
        const res2 = try fmrRun(&ctx, args, &.{ "status", "paused" }, &pr_env);
        expect(&ctx, res2.ok(), "status paused exits 0");
        expect(&ctx, std.mem.indexOf(u8, res2.stdout, "paused") != null, "shows paused");
        expect(&ctx, std.mem.indexOf(u8, res2.stdout, "alpha") == null, "does not list other repos");
    }

    current = "status filters to named repos";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "status", "alpha" }, &pr_env);
        expect(&ctx, res.ok(), "status alpha exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "alpha") != null, "lists alpha");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "unborn") == null, "does not list unborn");
    }

    current = "jobs flag works";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha", "--jobs", "1" }, &pr_env);
        expect(&ctx, res.ok(), "sync with --jobs 1 exits 0");
    }

    current = "help flag exits 0";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{"--help"}, &pr_env);
        expect(&ctx, res.ok(), "--help exits 0");
        const res2 = try fmrRun(&ctx, args, &.{"-h"}, &pr_env);
        expect(&ctx, res2.ok(), "-h exits 0");
    }

    current = "duplicate repo arguments deduplicate";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", "alpha", "alpha" }, &pr_env);
        expect(&ctx, res.ok(), "sync alpha alpha exits 0");
    }

    // -------------------------------------------------------------------
    // Slice-1: check and run scenarios
    // -------------------------------------------------------------------

    // Sync check/run fixture repos before running check or run against them.
    for (&[_][]const u8{ "check-kd", "check-ex", "check-skip", "check-fail", "cmd-repo" }) |rn| {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", rn }, &pr_env);
        expect(&ctx, res.ok(), try std.fmt.allocPrint(ctx.alloc, "sync {s} exits 0", .{rn}));
    }

    current = "check using kind default (zig defaults check argv)";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "check", "check-kd" }, &pr_env);
        expectExit(&ctx, res, 0, "exit 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[ok]") != null, "reports [ok]");
    }

    current = "check using repo-specific argv";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "check", "check-ex" }, &pr_env);
        expectExit(&ctx, res, 0, "exit 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[ok]") != null, "reports [ok]");
    }

    current = "check skip when no check defined";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "check", "check-skip" }, &pr_env);
        expectExit(&ctx, res, 0, "exit 0 (skip is not a failure)");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[skip]") != null, "reports [skip]");
    }

    current = "check failing command returns exit 4";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "check", "check-fail" }, &pr_env);
        expectExit(&ctx, res, 4, "exit 4 on subprocess failure");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[fail]") != null, "reports [fail]");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "check-fail") != null, "names the repo");
    }

    current = "run with env injection and arg forwarding";
    {
        const args = base_args.items;
        // show-env echoes FMR=$FMR_REPO — verify the env var is set to the repo path.
        const cmd_repo_path = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "cmd-repo" });
        const res = try fmrRun(&ctx, args, &.{ "run", "cmd-repo", "show-env" }, &pr_env);
        expectExit(&ctx, res, 0, "exit 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "FMR=") != null, "FMR env var present");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, cmd_repo_path) != null, "FMR_REPO points to repo path");
        // echo-it with extra args — verify args are forwarded.
        const res2 = try fmrRun(&ctx, args, &.{ "run", "cmd-repo", "echo-it", "hello-world" }, &pr_env);
        expectExit(&ctx, res2, 0, "exit 0 with extra arg");
        expect(&ctx, std.mem.indexOf(u8, res2.stdout, "hello-world") != null, "extra arg forwarded");
    }

    current = "run with kind-default command";
    {
        const args = base_args.items;
        // check-kd is kind=zig; zig defaults include test-default command.
        const res = try fmrRun(&ctx, args, &.{ "run", "check-kd", "test-default" }, &pr_env);
        expectExit(&ctx, res, 0, "exit 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "kind-default-ok") != null, "kind-default command ran");
    }

    current = "run with unknown command returns exit 2";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "run", "cmd-repo", "nope" }, &pr_env);
        expectExit(&ctx, res, 2, "exit 2 for unknown command");
        expect(&ctx, std.mem.indexOf(u8, res.stderr, "nope") != null, "names the unknown command");
        expect(&ctx, std.mem.indexOf(u8, res.stderr, "available commands") != null, "lists available commands");
    }

    // -------------------------------------------------------------------
    // Slice-2: rag snapshot scenarios
    // -------------------------------------------------------------------

    // Sync rag fixture repos before running rag against them.
    for (&[_][]const u8{ "rag-cmd", "rag-files", "rag-fail", "rag-skip" }) |rn| {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "sync", rn }, &pr_env);
        expect(&ctx, res.ok(), try std.fmt.allocPrint(ctx.alloc, "sync {s} exits 0", .{rn}));
    }

    current = "rag command mode creates snapshot and current symlink";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "rag", "rag-cmd" }, &pr_env);
        expectExit(&ctx, res, 0, "rag rag-cmd exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[ok]") != null, "reports [ok]");

        const rag_cmd_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "rag-cmd" });
        const sha = (try git.fullSha(&ctx, rag_cmd_dir)) orelse "";
        const snap_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_root, "rag-cmd", sha });
        const snap_file = try std.Io.Dir.path.join(ctx.alloc, &.{ snap_dir, "test.txt" });
        expect(&ctx, git.dirExists(&ctx, snap_file), "test.txt exported in snapshot");

        const snap_manifest = try std.Io.Dir.path.join(ctx.alloc, &.{ snap_dir, "manifest.json" });
        expect(&ctx, git.dirExists(&ctx, snap_manifest), "manifest.json created");

        const cur_link = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_root, "rag-cmd", "current" });
        var buf: [1024]u8 = undefined;
        const n = std.Io.Dir.cwd().readLink(ctx.io, cur_link, &buf) catch 0;
        expect(&ctx, n > 0, "current symlink created");
        expect(&ctx, std.mem.eql(u8, buf[0..n], sha), "current points to full sha");
    }

    current = "rag idempotency on unchanged HEAD";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "rag", "rag-cmd" }, &pr_env);
        expectExit(&ctx, res, 0, "second rag exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "up to date") != null, "reports up to date");
    }

    current = "rag --force replaces snapshot";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "rag", "rag-cmd", "--force" }, &pr_env);
        expectExit(&ctx, res, 0, "forced rag exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "rag snap") != null, "reports rag snap");
    }

    current = "rag failure returns exit 4 and leaves current untouched";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "rag", "rag-fail" }, &pr_env);
        expectExit(&ctx, res, 4, "failing exporter exits 4");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[fail]") != null, "reports [fail]");
    }

    current = "rag skip when no rag configured";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "rag", "rag-skip" }, &pr_env);
        expectExit(&ctx, res, 0, "skip rag exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[skip]") != null, "reports [skip]");
    }

    current = "rag files mode copies matching globs";
    {
        const rf_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "rag-files" });
        const doc_path = try std.Io.Dir.path.join(ctx.alloc, &.{ rf_dir, "doc.md" });
        var df = try std.Io.Dir.cwd().createFile(ctx.io, doc_path, .{ .truncate = true });
        try df.writeStreamingAll(ctx.io, "# Markdown Doc");
        df.close(ctx.io);

        const sub_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ rf_dir, "sub" });
        try std.Io.Dir.cwd().createDirPath(ctx.io, sub_dir);
        const note_path = try std.Io.Dir.path.join(ctx.alloc, &.{ sub_dir, "notes.txt" });
        var nf = try std.Io.Dir.cwd().createFile(ctx.io, note_path, .{ .truncate = true });
        try nf.writeStreamingAll(ctx.io, "notes");
        nf.close(ctx.io);

        const bin_path = try std.Io.Dir.path.join(ctx.alloc, &.{ rf_dir, "binary.bin" });
        var bf = try std.Io.Dir.cwd().createFile(ctx.io, bin_path, .{ .truncate = true });
        try bf.writeStreamingAll(ctx.io, "raw binary");
        bf.close(ctx.io);

        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "rag", "rag-files" }, &pr_env);
        expectExit(&ctx, res, 0, "files mode rag exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[ok]") != null, "reports [ok]");

        const rf_sha = (try git.fullSha(&ctx, rf_dir)) orelse "";
        const snap_doc = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_root, "rag-files", rf_sha, "doc.md" });
        const snap_note = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_root, "rag-files", rf_sha, "sub", "notes.txt" });
        const snap_bin = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_root, "rag-files", rf_sha, "binary.bin" });

        expect(&ctx, git.dirExists(&ctx, snap_doc), "doc.md copied into snapshot");
        expect(&ctx, git.dirExists(&ctx, snap_note), "sub/notes.txt copied into snapshot");
        expect(&ctx, !git.dirExists(&ctx, snap_bin), "binary.bin excluded from snapshot");
    }

    current = "rag dirty repo refuses without --force";
    {
        const rag_cmd_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, "rag-cmd" });
        const f = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_cmd_dir, "f.txt" });
        var file = try std.Io.Dir.cwd().createFile(ctx.io, f, .{ .truncate = false });
        const len = try file.length(ctx.io);
        try file.writePositionalAll(ctx.io, "dirty", len);
        file.close(ctx.io);

        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "rag", "rag-cmd" }, &pr_env);
        expectExit(&ctx, res, 3, "exit 3 on dirty rag");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "dirty") != null, "mentions dirty");

        const res_forced = try fmrRun(&ctx, args, &.{ "rag", "rag-cmd", "--force" }, &pr_env);
        expectExit(&ctx, res_forced, 0, "forced dirty rag exits 0");
        expect(&ctx, std.mem.indexOf(u8, res_forced.stdout, "rag snap") != null, "forced rag reports snap");

        _ = try gitOk(&ctx, &.{ "git", "checkout", "--", "f.txt" }, rag_cmd_dir);
    }

    current = "status reports snap ok after rag";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "status", "rag-cmd" }, &pr_env);
        expectExit(&ctx, res, 0, "status rag-cmd exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "snap ok") != null, "status shows snap ok");
    }

    // -------------------------------------------------------------------
    // Slices 3 & 4: doctor --fix, rag --gc, and --json output
    // -------------------------------------------------------------------

    current = "doctor --fix cleans stale locks and staging directories";
    {
        // 1. Create a fake stale lock directory with dead pid
        const stale_lock_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ home, ".fmr", "locks", "test-stale.sync.lock" });
        try std.Io.Dir.cwd().createDirPath(ctx.io, stale_lock_dir);
        const stale_pid_file = try std.Io.Dir.path.join(ctx.alloc, &.{ stale_lock_dir, "pid" });
        var pf = try std.Io.Dir.cwd().createFile(ctx.io, stale_pid_file, .{ .truncate = true });
        try pf.writeStreamingAll(ctx.io, "99999999\n");
        pf.close(ctx.io);

        // 2. Create a fake stale staging directory
        const stale_staging_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_root, "rag-cmd", ".staging", "stale-pid-99999" });
        try std.Io.Dir.cwd().createDirPath(ctx.io, stale_staging_dir);

        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "doctor", "--fix" }, &pr_env);
        expectExit(&ctx, res, 0, "doctor --fix exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[fix]") != null, "doctor --fix reports fix actions");
        expect(&ctx, !git.dirExists(&ctx, stale_lock_dir), "stale lock removed by doctor --fix");
        expect(&ctx, !git.dirExists(&ctx, stale_staging_dir), "stale staging removed by doctor --fix");
    }

    current = "rag --gc prunes older snapshots while preserving current";
    {
        const rag_cmd_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_root, "rag-cmd" });
        const old_snap1 = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_cmd_dir, "0000000000000000000000000000000000000001" });
        const old_snap2 = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_cmd_dir, "0000000000000000000000000000000000000002" });
        try std.Io.Dir.cwd().createDirPath(ctx.io, old_snap1);
        try std.Io.Dir.cwd().createDirPath(ctx.io, old_snap2);

        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "rag", "rag-cmd", "--gc", "1" }, &pr_env);
        expectExit(&ctx, res, 0, "rag --gc exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "[gc]") != null, "reports [gc]");

        // Current symlink must still exist
        const cur_link = try std.Io.Dir.path.join(ctx.alloc, &.{ rag_root, "rag-cmd", "current" });
        expect(&ctx, git.dirExists(&ctx, cur_link), "current symlink preserved after gc");
    }

    current = "json flag outputs structured json across commands";
    {
        const args = base_args.items;

        // 1. status --json
        const res_status = try fmrRun(&ctx, args, &.{ "status", "rag-cmd", "--json" }, &pr_env);
        expectExit(&ctx, res_status, 0, "status --json exits 0");
        expect(&ctx, std.mem.indexOf(u8, res_status.stdout, "\"command\": \"status\"") != null, "status JSON has command status");
        expect(&ctx, std.mem.indexOf(u8, res_status.stdout, "\"name\": \"rag-cmd\"") != null, "status JSON names repo");
        expect(&ctx, std.mem.indexOf(u8, res_status.stdout, "\"kind\": \"other\"") != null, "status JSON carries repo kind");
        expect(&ctx, std.mem.indexOf(u8, res_status.stdout, "\"path\":") != null, "status JSON carries repo path");
        expect(&ctx, std.mem.indexOf(u8, res_status.stdout, "\"url\":") != null, "status JSON carries repo url");

        // 2. sync --json
        const res_sync = try fmrRun(&ctx, args, &.{ "sync", "rag-cmd", "--json" }, &pr_env);
        expectExit(&ctx, res_sync, 0, "sync --json exits 0");
        expect(&ctx, std.mem.indexOf(u8, res_sync.stdout, "\"command\": \"sync\"") != null, "sync JSON has command sync");
        expect(&ctx, std.mem.indexOf(u8, res_sync.stdout, "\"action\": \"noop\"") != null, "sync JSON carries action");
        expect(&ctx, std.mem.indexOf(u8, res_sync.stdout, "\"before\":") != null, "sync JSON carries before sha");
        expect(&ctx, std.mem.indexOf(u8, res_sync.stdout, "\"after\":") != null, "sync JSON carries after sha");
        expect(&ctx, std.mem.indexOf(u8, res_sync.stdout, "\"summary\":") != null, "sync JSON has summary");

        // 3. doctor --json
        const res_doc = try fmrRun(&ctx, args, &.{ "doctor", "--json" }, &pr_env);
        expectExit(&ctx, res_doc, 0, "doctor --json exits 0");
        expect(&ctx, std.mem.indexOf(u8, res_doc.stdout, "\"command\": \"doctor\"") != null, "doctor JSON has command doctor");

        // 4. check --json
        const res_chk = try fmrRun(&ctx, args, &.{ "check", "check-kd", "--json" }, &pr_env);
        expectExit(&ctx, res_chk, 0, "check --json exits 0");
        expect(&ctx, std.mem.indexOf(u8, res_chk.stdout, "\"command\": \"check\"") != null, "check JSON has command check");

        // 5. rag --json
        const res_rag = try fmrRun(&ctx, args, &.{ "rag", "rag-cmd", "--json" }, &pr_env);
        expectExit(&ctx, res_rag, 0, "rag --json exits 0");
        expect(&ctx, std.mem.indexOf(u8, res_rag.stdout, "\"command\": \"rag\"") != null, "rag JSON has command rag"); // 6. config --json (catalog dump)
        const res_cfg = try fmrRun(&ctx, args, &.{"config"}, &pr_env);
        expectExit(&ctx, res_cfg, 0, "config exits 0");
        expect(&ctx, std.mem.indexOf(u8, res_cfg.stdout, "\"command\": \"config\"") != null, "config JSON has command config");
        expect(&ctx, std.mem.indexOf(u8, res_cfg.stdout, "\"name\": \"rag-cmd\"") != null, "config JSON lists repos");
        expect(&ctx, std.mem.indexOf(u8, res_cfg.stdout, "\"kind\": \"other\"") != null, "config JSON carries kinds");
        expect(&ctx, std.mem.indexOf(u8, res_cfg.stdout, "\"mode\": \"command\"") != null, "config JSON carries rag mode");
        expect(&ctx, std.mem.indexOf(u8, res_cfg.stdout, "\"echo-it\"") != null, "config JSON lists named commands");

        // 7. run --json (structured completion)
        const res_run_ok = try fmrRun(&ctx, args, &.{ "run", "cmd-repo", "echo-it", "--json" }, &pr_env);
        expectExit(&ctx, res_run_ok, 0, "run --json ok exits 0");
        expect(&ctx, std.mem.indexOf(u8, res_run_ok.stdout, "\"command\": \"run\"") != null, "run JSON has command run");
        expect(&ctx, std.mem.indexOf(u8, res_run_ok.stdout, "\"result\": \"ok\"") != null, "run JSON reports ok");

        const res_run_fail = try fmrRun(&ctx, args, &.{ "run", "cmd-repo", "fail", "--json" }, &pr_env);
        expectExit(&ctx, res_run_fail, 4, "run --json failing exits 4");
        expect(&ctx, std.mem.indexOf(u8, res_run_fail.stdout, "\"result\": \"failed\"") != null, "run JSON reports failed");
    }

    current = "--version prints a version string";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{"--version"}, &pr_env);
        expectExit(&ctx, res, 0, "--version exits 0");
        expect(&ctx, std.mem.indexOf(u8, res.stdout, "fmr ") != null, "--version prints fmr prefix");
    }

    current = "add appends repo to config and sync clones it";
    {
        const args = base_args.items;
        const new_repo = "imported";
        const new_url = try std.Io.Dir.path.join(ctx.alloc, &.{ origins, "alpha.git" });

        const res = try fmrRun(&ctx, args, &.{ "add", new_repo, new_url, "--kind", "zig", "--sync" }, &pr_env);
        expectExit(&ctx, res, 0, "add --sync exits 0");

        const cfg_text = try std.Io.Dir.cwd().readFileAlloc(ctx.io, config_path, ctx.alloc, .limited(1 << 20));
        expect(&ctx, std.mem.indexOf(u8, cfg_text, new_repo) != null, "config contains new repo");
        expect(&ctx, std.mem.indexOf(u8, cfg_text, "\"kind\": \"zig\"") != null, "config carries kind");

        const imported_dir = try std.Io.Dir.path.join(ctx.alloc, &.{ repos_root, new_repo });
        expect(&ctx, git.dirExists(&ctx, imported_dir), "add --sync cloned the repo");
    }

    current = "add duplicate repo is refused";
    {
        const args = base_args.items;
        const dup_url = try std.Io.Dir.path.join(ctx.alloc, &.{ origins, "alpha.git" });
        const res = try fmrRun(&ctx, args, &.{ "add", "alpha", dup_url }, &pr_env);
        expectExit(&ctx, res, 2, "duplicate add exits 2");
    }

    current = "remove unregisters repo from config";
    {
        const args = base_args.items;
        const res = try fmrRun(&ctx, args, &.{ "remove", "imported" }, &pr_env);
        expectExit(&ctx, res, 0, "remove exits 0");

        const cfg_text = try std.Io.Dir.cwd().readFileAlloc(ctx.io, config_path, ctx.alloc, .limited(1 << 20));
        expect(&ctx, std.mem.indexOf(u8, cfg_text, "imported") == null, "config no longer contains removed repo");

        const res2 = try fmrRun(&ctx, args, &.{ "status", "imported" }, &pr_env);
        expectExit(&ctx, res2, 2, "status on removed repo exits 2");

        const res3 = try fmrRun(&ctx, args, &.{ "remove", "imported" }, &pr_env);
        expectExit(&ctx, res3, 2, "removing a missing repo exits 2");
    }

    pr.line(&ctx, .gray, "e2e tmp dir kept for inspection on failure: {s}", .{tmp});
    if (failures > 0) {
        pr.line(&ctx, .red, "{d} e2e scenario(s) failed", .{failures});
        return 1;
    }
    pr.line(&ctx, .green, "all e2e scenarios passed", .{});
    return 0;
}

fn fmrRun(ctx: *const process.Ctx, base: []const []const u8, extra: []const []const u8, env: []const []const u8) !process.Result {
    var argv = ArrayList([]const u8).init(ctx.alloc);
    try argv.appendSlice(base);
    try argv.appendSlice(extra);
    return process.run(ctx, argv.items, .{ .env = env });
}

pub fn main(init: std.process.Init) u8 {
    const ctx = process.Ctx{
        .alloc = init.arena.allocator(),
        .io = init.io,
        .environ_map = init.environ_map,
    };
    _ = mainImpl(init) catch |err| {
        process.stderrLineNewline(&ctx, "fmr-e2e: setup failed: {s}", .{@errorName(err)});
        return 1;
    };
    return if (failures > 0) 1 else 0;
}
