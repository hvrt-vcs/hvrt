const std = @import("std");
const sqlite = @import("sqlite.zig");

const cmd = @import("cmd.zig");

/// All that `main` does is retrieve args and a main allocator for the system,
/// and pass those to `internalMain`. Afterwards, it catches any errors, deals
/// with the error types it explicitly knows how to deal with, and if a
/// different error slips though it just prints a stack trace and exits with a
/// generic exit code of 1.
pub fn main() !void {

    // assume successful exit until we know otherwise
    var status_code: u8 = 0;

    {
        // Args parsing from here: https://ziggit.dev/t/read-command-line-arguments/220/7

        // Get allocator
        // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        // const allocator = gpa.allocator();
        // defer _ = gpa.deinit();

        // Vastly faster, but less safe than DebugAllocator/current GeneralPurposeAllocator.
        const allocator = std.heap.c_allocator;

        // Parse args into string array (error union needs 'try')
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        // The only place `exit` should ever be called directly is here in the `main` function
        cmd.internalMain(allocator, args) catch |err| {
            status_code = switch (err) {
                sqlite.errors.SQLITE_ERROR => 3,
                sqlite.errors.SQLITE_CANTOPEN => 4,
                else => {
                    // Any error other than the explicitly listed ones in the
                    // switch should just bubble up normally, printing a stack
                    // trace.
                    return err;
                },
            };
        };
    }

    // All resources are cleaned up after the block above, so now we can safely
    // call the `exit` function, which does not return.
    std.process.exit(status_code);
}

const test_alloc = std.testing.allocator;

fn test_init(tmp: *std.testing.TmpDir) !void {
    var tmp_path = try tmp.dir.realpathAlloc(test_alloc, ".");
    defer test_alloc.free(tmp_path);

    const tmp_pathz = try test_alloc.dupeZ(u8, tmp_path);
    defer test_alloc.free(tmp_pathz);

    const basic_args = [_][:0]const u8{ "hvrt", "init", tmp_pathz };
    try cmd.internalMain(test_alloc, &basic_args);
}

fn test_add(tmp: *std.testing.TmpDir) !void {
    var tmp_path = try tmp.dir.realpathAlloc(test_alloc, ".");
    defer test_alloc.free(tmp_path);

    const tmp_pathz = try test_alloc.dupeZ(u8, tmp_path);
    defer test_alloc.free(tmp_pathz);

    const files = [_][:0]const u8{ "foo.txt", "bar.txt" };

    for (&files) |file| {
        std.debug.print("\nWhat is filename? {s}\n", .{file});

        var fp = try tmp.dir.createFile(file, .{ .exclusive = true });
        defer fp.close();

        try fp.writer().print("The filename of this file is '{s}'.", .{file});
    }

    const basic_args = [_][:0]const u8{ "hvrt", "add", tmp_pathz, files[0], files[1] };
    try cmd.internalMain(test_alloc, &basic_args);
}

test "invoke with init sub-command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try test_init(&tmp);
}

test "invoke with add sub-command" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try test_init(&tmp);
    try test_add(&tmp);
}

test "invoke without args" {
    const basic_args = [_][:0]const u8{"test_prog_name"};
    cmd.internalMain(std.testing.allocator, &basic_args) catch |err| {
        const expected_error = error.ArgumentError;
        const actual_error_union: anyerror!void = err;
        try std.testing.expectError(expected_error, actual_error_union);
    };
}
