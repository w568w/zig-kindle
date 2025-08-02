const std = @import("std");
const builtin = @import("builtin");

/// Copies the contents of `source_dir` to `target_dir`, creating directories as needed.
/// If a file already exists in the target directory, it will be overwritten.
fn copyRecursively(
    b: *std.Build,
    source_dir: []const u8,
    target_dir: []const u8,
) !void {
    const allocator = b.allocator;
    var source = try std.fs.cwd().openDir(source_dir, .{
        .iterate = true,
    });
    defer source.close();

    var target = try std.fs.cwd().makeOpenPath(target_dir, .{});
    defer target.close();

    var it = try source.walk(allocator);
    defer it.deinit();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file => {
                try entry.dir.copyFile(entry.basename, target, entry.path, .{});
            },
            .directory => {
                target.makeDir(entry.path) catch |err| {
                    if (err != std.fs.Dir.MakeError.PathAlreadyExists) return err;
                };
            },
            else => {},
        }
    }
}

/// Compares the modification times of two directories and returns an order.
fn dirMtimeOrder(
    a: []const u8,
    b: []const u8,
) !std.math.Order {
    const stat_a = blk: {
        var dir_a = try std.fs.cwd().openDir(a, .{});
        defer dir_a.close();
        break :blk try dir_a.stat();
    };
    const stat_b = blk: {
        var dir_b = try std.fs.cwd().openDir(b, .{});
        defer dir_b.close();
        break :blk try dir_b.stat();
    };
    return std.math.order(stat_a.mtime, stat_b.mtime);
}

fn addPatchedExecutable(b: *std.Build, options: *std.Build.ExecutableOptions) *std.Build.Step.Compile {
    const std_dir = b.graph.zig_lib_directory.path orelse @panic("zig_lib_directory not set");
    const patch_dir = b.cache_root.join(b.allocator, &[_][]const u8{"zig_kindle_std_patch"}) catch @panic("Failed to create patch path string");
    options.zig_lib_dir = .{ .cwd_relative = patch_dir }; // Safety: leak patch_dir. It will be cleaned up by the build system
    const exe = b.addExecutable(options.*);
    const std_newer_than_patch = (dirMtimeOrder(std_dir, patch_dir) catch std.math.Order.gt) == std.math.Order.gt;
    if (std_newer_than_patch) {
        copyRecursively(
            b,
            std_dir,
            patch_dir,
        ) catch @panic("Failed to copy standard library files");
        std.log.info("Copied standard library files to patch directory: {s}\n", .{patch_dir});
        const patchStep = b.addSystemCommand(&[_][]const u8{
            "git",
            "apply",
            "kindle.patch",
            "--unsafe-paths", // allow to patch files outside the working area
            "--directory",
            patch_dir,
        });
        exe.step.dependOn(&patchStep.step);
    }

    return exe;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .arm,
    } });

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    var exe_options = std.Build.ExecutableOptions{
        .name = "zig_kindle",
        .root_module = exe_mod,
    };
    const exe = addPatchedExecutable(b, &exe_options);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
