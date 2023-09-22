const std = @import("std");
const sokol = @import("vendor/sokol-zig/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});


    const sokol_build = sokol.buildSokol(b, target, optimize, .{}, "vendor/sokol-zig/");

    const exe = b.addExecutable(.{
        .name = "BabaIsCloned",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });


    exe.addAnonymousModule("sokol", .{ .source_file = .{ .path = "vendor/sokol-zig/src/sokol/sokol.zig" } });
    exe.linkLibrary(sokol_build);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
