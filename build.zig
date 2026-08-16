const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const exe = b.addExecutable(.{
        .name = "fmr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    const run_unit = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "run unit tests");
    test_step.dependOn(&run_unit.step);

    const e2e = b.addExecutable(.{
        .name = "fmr-e2e",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_e2e.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    const install_exe = b.addInstallArtifact(exe, .{});
    const run_e2e = b.addRunArtifact(e2e);
    run_e2e.step.dependOn(&install_exe.step);
    run_e2e.addArg(b.getInstallPath(.bin, "fmr"));
    const e2e_step = b.step("test-e2e", "run end-to-end tests against fixture git repos");
    e2e_step.dependOn(&run_e2e.step);
}