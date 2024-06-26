const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const third_party_path = "third_party";
    const sqlite_include_path = third_party_path ++ "/sqlite3";

    // Since Zig uses utf8 strings, we'll use pcre with 8bit support.
    const pcre_code_unit_width_name = "PCRE2_CODE_UNIT_WIDTH";
    const pcre_code_unit_width_value = "8";
    const pcre_prefix = "pcre2";
    const pcre_include_path = third_party_path ++ "/" ++ pcre_prefix;

    const sqlite = b.addStaticLibrary(.{
        .name = "sqlite",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sqlite.addCSourceFile(.{
        .file = b.path(sqlite_include_path ++ "/sqlite3.c"),
        .flags = &[_][]const u8{
            "-std=c99",
        },
    });
    sqlite.addIncludePath(b.path(sqlite_include_path));

    const pcreCopyFiles = b.addWriteFiles();
    _ = pcreCopyFiles.addCopyFile(b.path(pcre_include_path ++ "/src/config.h.generic"), "config.h");
    _ = pcreCopyFiles.addCopyFile(b.path(pcre_include_path ++ "/src/pcre2.h.generic"), "pcre2.h");

    const pcre = b.addStaticLibrary(.{
        .name = b.fmt("pcre2-{s}", .{pcre_code_unit_width_value}),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    pcre.root_module.addCMacro(pcre_code_unit_width_name, pcre_code_unit_width_value);

    pcre.addCSourceFile(.{
        .file = pcreCopyFiles.addCopyFile(b.path(pcre_include_path ++ "/src/pcre2_chartables.c.dist"), "pcre2_chartables.c"),
        .flags = &.{
            "-DHAVE_CONFIG_H",
        },
    });

    pcre.addIncludePath(b.path(pcre_include_path ++ "/src"));
    pcre.addIncludePath(pcreCopyFiles.getDirectory());

    pcre.addCSourceFiles(.{
        .files = &.{
            pcre_include_path ++ "/src/pcre2_auto_possess.c",
            pcre_include_path ++ "/src/pcre2_chkdint.c",
            pcre_include_path ++ "/src/pcre2_compile.c",
            pcre_include_path ++ "/src/pcre2_config.c",
            pcre_include_path ++ "/src/pcre2_context.c",
            pcre_include_path ++ "/src/pcre2_convert.c",
            pcre_include_path ++ "/src/pcre2_dfa_match.c",
            pcre_include_path ++ "/src/pcre2_error.c",
            pcre_include_path ++ "/src/pcre2_extuni.c",
            pcre_include_path ++ "/src/pcre2_find_bracket.c",
            pcre_include_path ++ "/src/pcre2_maketables.c",
            pcre_include_path ++ "/src/pcre2_match.c",
            pcre_include_path ++ "/src/pcre2_match_data.c",
            pcre_include_path ++ "/src/pcre2_newline.c",
            pcre_include_path ++ "/src/pcre2_ord2utf.c",
            pcre_include_path ++ "/src/pcre2_pattern_info.c",
            pcre_include_path ++ "/src/pcre2_script_run.c",
            pcre_include_path ++ "/src/pcre2_serialize.c",
            pcre_include_path ++ "/src/pcre2_string_utils.c",
            pcre_include_path ++ "/src/pcre2_study.c",
            pcre_include_path ++ "/src/pcre2_substitute.c",
            pcre_include_path ++ "/src/pcre2_substring.c",
            pcre_include_path ++ "/src/pcre2_tables.c",
            pcre_include_path ++ "/src/pcre2_ucd.c",
            pcre_include_path ++ "/src/pcre2_valid_utf.c",
            pcre_include_path ++ "/src/pcre2_xclass.c",
        },
        .flags = &.{
            "-DHAVE_CONFIG_H",
            "-DPCRE2_STATIC",
        },
    });

    pcre.installHeader(b.path(pcre_include_path ++ "/src/pcre2.h.generic"), "pcre2.h");

    const exe = b.addExecutable(.{
        .name = "hvrt",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(sqlite);
    exe.linkLibrary(pcre);
    exe.addIncludePath(b.path(sqlite_include_path));

    // We use c_allocator from libc for allocator implementation, since it is
    // the fastest builtin allocator currently offered by zig.
    exe.linkLibC();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.linkLibrary(sqlite);
    unit_tests.linkLibrary(pcre);
    unit_tests.addIncludePath(b.path(sqlite_include_path));

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
