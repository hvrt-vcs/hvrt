const std = @import("std");
const sqlite3 = @cImport({
    @cInclude("sqlite3.h");
});

// Cannot embed outside package path (i.e. we cannot go up a directory with `../`)
// const sql_path = "../hvrt/sql/sqlite/work_tree/read_blobs.sql";
const sql_path = "test_embedding.sql";
const embedded_sql = @embedFile(sql_path);

// If we request a value from the map using a constant lookup key, will Zig
// just reduce that at comp time? That way we can *never* have an incorrect
// lookup at runtime based on a typo or something.
const sql_files = std.ComptimeStringMap([]const u8, .{
    .{ sql_path, embedded_sql },
});

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // Args parsing from here: https://ziggit.dev/t/read-command-line-arguments/220/7
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Parse args into string array (error union needs 'try')
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Get and print them!
    std.debug.print("There are {d} args:\n", .{args.len});
    for (args) |arg| {
        std.debug.print("  {s}\n", .{arg});
    }

    // var db: *sqlite3.sqlite3 = null;
    const db_path = args[1];

    std.debug.print("what is db_path: {s}\n", .{db_path});

    std.debug.print("what is embedded sql path: {s}\n", .{sql_path});
    std.debug.print("what is embedded sql value: {s}\n", .{embedded_sql});
    std.debug.print("what is embedded sql path bytes: {any}\n", .{sql_path});
    std.debug.print("what is embedded sql value bytes: {any}\n", .{embedded_sql});
    std.debug.print("what is sql files ComptimeStringMap: {any}\n", .{sql_files.kvs});

    // const rc = sqlite3.sqlite3_open(db_path, db);
    // defer sqlite3.sqlite3_close(db);

    // if (rc) {
    //     std.debug.print("Can't open database: {s}\n", db_path);
    //     return 1;
    // }

    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
