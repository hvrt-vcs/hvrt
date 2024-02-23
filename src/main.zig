const std = @import("std");
const sqlite = @import("sqlite.zig");

const sql_path1 = "sql/sqlite/work_tree/init/tables.sql";
const embedded_sql1 = @embedFile(sql_path1);

const sql_path2 = "sql/sqlite/work_tree/init/version.sql";
const embedded_sql2 = @embedFile(sql_path2);

const sql_path3 = "sql/sqlite/work_tree/init/branch.sql";
const embedded_sql3 = @embedFile(sql_path3);

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
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        defer _ = gpa.deinit();

        // Parse args into string array (error union needs 'try')
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        // The only place `exit` should ever be called directly is here in the `main` function
        internalMain(args, allocator) catch |err| {
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

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and alloc, if necessary.
pub fn internalMain(args: []const [:0]const u8, alloc: std.mem.Allocator) !void {
    // `alloc` will be used eventually to replace libc allocation for SQLite
    // and other third party libraries.
    _ = alloc;

    // Roughly trying to follow this SQLite quickstart guide and translating it
    // into Zig: https://www.sqlite.org/quickstart.html

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // Get and print args!
    std.debug.print("There are {d} args:\n", .{args.len});
    for (args) |arg| {
        std.debug.print("  {s}\n", .{arg});
    }

    std.debug.print("The args are of type {}.\n", .{@TypeOf(args)});

    // https://www.huy.rocks/everyday/01-04-2022-zig-strings-in-5-minutes
    // https://ziglang.org/documentation/master/#String-Literals-and-Unicode-Code-Point-Literals

    const db_path = if (args.len > 1) args[1] else ":memory:";
    std.debug.print("what is db_path: {s}\n", .{db_path});

    std.debug.print("what is embedded sql path: {s}\n", .{sql_path1});
    // std.debug.print("what is embedded sql value: {s}\n", .{embedded_sql});
    std.debug.print("what is embedded sql path bytes: {any}\n", .{sql_path1});
    // std.debug.print("what is embedded sql value bytes: {any}\n", .{embedded_sql});
    // std.debug.print("what is sql files ComptimeStringMap: {any}\n", .{sql_files.kvs});

    const db = try sqlite.open(db_path);
    defer sqlite.close(db) catch unreachable;

    try sqlite.exec(db, embedded_sql1);

    // Preparing a statement will only evaluate one statement (semicolon
    // terminated) at a time. So we can't just compile the whole init script
    // and run it. Will need to either split the script into multiple pieces,
    // or add some logic to iterate over the statements/detect when parameters
    // need to be bound. See link here for an example of this logic:
    // https://github.com/praeclarum/sqlite-net/issues/84
    const prepared_stmt1 = try sqlite.prepare(db, embedded_sql2);
    defer sqlite.finalize(prepared_stmt1) catch unreachable;

    // Version
    const version = "0.1.0";
    try sqlite.bind_text(prepared_stmt1, 1, version);

    // // default branch
    // try sqlite3_bind(prepared_stmt, 2, "master");

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

test "invoke without args" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const basic_args = [_][:0]const u8{"test_prog_name"};
    try internalMain(&basic_args, std.testing.allocator);
}
