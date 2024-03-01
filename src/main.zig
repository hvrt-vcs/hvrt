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

test "invoke with init sub-command" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    const tmp_pathz = try alloc.dupeZ(u8, tmp_path);
    defer alloc.free(tmp_pathz);

    const basic_args = [_][:0]const u8{ "test_prog_name", "init", tmp_pathz };
    try cmd.internalMain(alloc, &basic_args);
}

test "invoke without args" {
    const basic_args = [_][:0]const u8{"test_prog_name"};
    cmd.internalMain(std.testing.allocator, &basic_args) catch |err| {
        const expected_error = error.ArgumentError;
        const actual_error_union: anyerror!void = err;
        try std.testing.expectError(expected_error, actual_error_union);
    };
}
