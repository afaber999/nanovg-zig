const std = @import("std");

fn getRootDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

const root_dir = getRootDir();

pub fn addCSourceFiles(artifact: *std.build.CompileStep) void {
    artifact.addIncludePath(root_dir ++ "/src");
    artifact.addCSourceFile(root_dir ++ "/src/fontstash.c", &.{ "-DFONS_NO_STDIO", "-fno-stack-protector" });
    artifact.addCSourceFile(root_dir ++ "/src/stb_image.c", &.{ "-DSTBI_NO_STDIO", "-fno-stack-protector" });
    artifact.linkLibC();
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const target_wasm = if (target.cpu_arch) |arch| arch == .wasm32 or arch == .wasm64 else false;
    const artifact = init: {
        if (target_wasm) {
            break :init b.addSharedLibrary(.{
                .name = "main",
                .root_source_file = .{ .path = "examples/example_wasm.zig" },
                .target = target,
                .optimize = optimize,
            });
        } else {
            break :init b.addExecutable(.{
                .name = "main",
                .root_source_file = .{ .path = "examples/example_glfw.zig" },
                .target = target,
                .optimize = optimize,
            });
        }
    };

    const module = b.addModule("nanovg", .{ .source_file = .{ .path = root_dir ++ "/src/nanovg.zig" } });
    artifact.addModule("nanovg", module);
    addCSourceFiles(artifact);

    if (target_wasm) {
        artifact.rdynamic = true;
    } else {
        artifact.addIncludePath("lib/gl2/include");
        artifact.addCSourceFile("lib/gl2/src/glad.c", &.{});
        if (target.isWindows()) {
            // artifact.addVcpkgPaths(.dynamic) catch @panic("vcpkg not installed");
            // if (artifact.vcpkg_bin_path) |bin_path| {
            //     for (&[_][]const u8{"glfw3.dll"}) |dll| {
            //         const src_dll = try std.fs.path.join(b.allocator, &.{ bin_path, dll });
            //         b.installBinFile(src_dll, dll);
            //     }
            // }

            const glfw_path = "D:\\zig\\glfw-3.3.8.bin.WIN64\\";
            artifact.addIncludePath(glfw_path ++ "include");
            artifact.addLibraryPath(glfw_path ++ "lib-static-ucrt");
            b.installBinFile(glfw_path ++ "lib-static-ucrt\\glfw3.dll", "glfw3.dll");

            //artifact.addIncludePath("D:\\zig\\glfw-3.3.8.bin.WIN64\\include");
            artifact.linkSystemLibrary("glfw3dll");
            artifact.linkSystemLibrary("opengl32");
        } else if (target.isDarwin()) {
            artifact.linkSystemLibrary("glfw3");
            artifact.linkFramework("OpenGL");
        } else if (target.isLinux()) {
            artifact.linkSystemLibrary("glfw3");
            artifact.linkSystemLibrary("GL");
            artifact.linkSystemLibrary("X11");
        } else {
            std.log.warn("Unsupported target: {}", .{target});
            artifact.linkSystemLibrary("glfw3");
            artifact.linkSystemLibrary("GL");
        }
    }
    artifact.addIncludePath("examples");
    artifact.addCSourceFile("examples/stb_image_write.c", &.{ "-DSTBI_NO_STDIO", "-fno-stack-protector" });
    b.installArtifact(artifact);

    const run_cmd = b.addRunArtifact(artifact);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
