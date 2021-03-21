const Builder = @import("std").build.Builder;

const version = "0.8.2";

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const cflags = &[_][]const u8{ "-DVERSION=\"" ++ version ++ "\"", "-D_XOPEN_SOURCE=600" };

    const zig_code = b.addObject("st", "src/st.zig");
    zig_code.setTarget(target);
    zig_code.setBuildMode(mode);
    zig_code.linkLibC();

    const exe = b.addExecutable("st", null);

    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addObject(zig_code);
    exe.addCSourceFile("src/st.c", cflags);
    exe.addCSourceFile("src/x.c", cflags);

    const libraries = &[_][]const u8{ "rt", "X11", "util", "Xft", "fontconfig", "freetype" };
    for (libraries) |lib| exe.linkSystemLibrary(lib);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
