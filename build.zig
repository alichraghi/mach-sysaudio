const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const mach_sysjs_dep = b.dependency("mach_sysjs", .{
        .target = target,
        .optimize = optimize,
    });
    const module = b.addModule("mach-sysaudio", .{
        .source_file = .{ .path = sdkPath("/src/main.zig") },
        .dependencies = &.{
            .{ .name = "sysjs", .module = mach_sysjs_dep.module("mach-sysjs") },
        },
    });

    const main_tests = b.addTest(.{
        .name = "test",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    link(b, main_tests);
    b.installArtifact(main_tests);

    const test_run_cmd = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_run_cmd.step);

    inline for ([_][]const u8{
        "sine",
        "record",
    }) |example| {
        const example_exe = b.addExecutable(.{
            .name = example,
            .root_source_file = .{ .path = "examples/" ++ example ++ ".zig" },
            .target = target,
            .optimize = optimize,
        });
        example_exe.addModule("mach-sysaudio", module);
        link(b, example_exe);
        b.installArtifact(example_exe);

        const example_compile_step = b.step(example, "Compile '" ++ example ++ "' example");
        example_compile_step.dependOn(b.getInstallStep());

        const example_run_cmd = b.addRunArtifact(example_exe);
        example_run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| example_run_cmd.addArgs(args);

        const example_run_step = b.step("run-" ++ example, "Run '" ++ example ++ "' example");
        example_run_step.dependOn(&example_run_cmd.step);
    }
}

pub fn link(b: *std.Build, step: *std.build.CompileStep) void {
    if (step.target.toTarget().cpu.arch != .wasm32) {
        if (step.target.toTarget().isDarwin()) {
            @import("xcode_frameworks").addPaths(step);

            // Transitive dependencies, explicit linkage of these works around
            // ziglang/zig#17130
            step.linkSystemLibrary("objc");

            // Direct dependencies
            step.linkFramework("AudioToolbox");
            step.linkFramework("CoreFoundation");
            step.linkFramework("CoreAudio");
        } else if (step.target.toTarget().os.tag == .linux) {
            step.linkLibrary(b.dependency("linux_audio_headers", .{
                .target = step.target,
                .optimize = step.optimize,
            }).artifact("linux-audio-headers"));
            step.addCSourceFile(.{
                .file = .{ .path = sdkPath("/src/pipewire/sysaudio.c") },
                .flags = &.{"-std=gnu99"},
            });
            step.linkLibC();
        }
    }
}

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}
