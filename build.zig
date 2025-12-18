const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Igor's library as a vendored module
    const ws_module = b.addModule("ws", .{
        .root_source_file = b.path("src/vendor/ws/src/main.zig"),
    });

    // The zws-client module
    const lib_module = b.addModule("zws-client", .{
        .root_source_file = b.path("src/root.zig"),
    });
    lib_module.addImport("ws", ws_module);

    // Build the library as a static artifact
    const lib = b.addLibrary(.{
        .name = "zws-client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.addImport("ws", ws_module);
    b.installArtifact(lib);

    // Add a test step
    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    main_tests.root_module.addImport("ws", ws_module);

    const run_main_tests = b.addRunArtifact(main_tests);
    // Add a test step for the vendored ws module
    const ws_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/vendor/ws/src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_ws_tests = b.addRunArtifact(ws_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_ws_tests.step);
}
