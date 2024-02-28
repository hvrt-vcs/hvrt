const std = @import("std");

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");
const init = @import("init.zig");

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and alloc, if necessary.
pub fn internalMain(args: []const [:0]const u8, alloc: std.mem.Allocator) !void {
    _ = args;
    var cwd_buf: [1024]u8 = undefined;

    const cwd: []u8 = try std.os.getcwd(&cwd_buf);
    try init.init(cwd, alloc);
    // // `alloc` will be used eventually to replace libc allocation for SQLite
    // // and other third party libraries.

    // // Roughly trying to follow this SQLite quickstart guide and translating it
    // // into Zig: https://www.sqlite.org/quickstart.html

    // // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // // Get and print args!
    // std.debug.print("There are {d} args:\n", .{args.len});
    // for (args) |arg| {
    //     std.debug.print("  {s}\n", .{arg});
    // }

    // std.debug.print("The args are of type {}.\n", .{@TypeOf(args)});

    // // https://www.huy.rocks/everyday/01-04-2022-zig-strings-in-5-minutes
    // // https://ziglang.org/documentation/master/#String-Literals-and-Unicode-Code-Point-Literals

    // const db_path = if (args.len > 1) args[1] else ":memory:";
    // std.debug.print("what is db_path: {s}\n", .{db_path});

    // const db = try sqlite.open(db_path);
    // defer sqlite.close(db) catch unreachable;

    // const sqlfiles = sql.sqlite;

    // try sqlite.exec(db, sqlfiles.work_tree.init.tables);

    // // Preparing a statement will only evaluate one statement (semicolon
    // // terminated) at a time. So we can't just compile the whole init script
    // // and run it. Will need to either split the script into multiple pieces,
    // // or add some logic to iterate over the statements/detect when parameters
    // // need to be bound. See link here for an example of this logic:
    // // https://github.com/praeclarum/sqlite-net/issues/84
    // const prepared_stmt1 = try sqlite.prepare(db, sqlfiles.work_tree.init.version);
    // defer sqlite.finalize(prepared_stmt1) catch unreachable;

    // // Version
    // const version = "0.1.0";
    // try sqlite.bind_text(prepared_stmt1, 1, version);

    // rows: while (sqlite.step(prepared_stmt1)) |rc| {
    //     std.debug.print("What is the Result code? {any}\n", .{rc});
    // } else |err| {
    //     std.debug.print("What is the error? {any}\n", .{err});

    //     if (err != error.StopIteration) {
    //         // Address error, then jump back to beginning and try again
    //         break :rows;
    //     }
    // }

    // std.debug.print("Did we insert the version?\n", .{});
    // // // default branch
    // // try sqlite3_bind(prepared_stmt, 2, "master");

    // // // stdout is for the actual output of your application, for example if you
    // // // are implementing gzip, then only the compressed bytes should be sent to
    // // // stdout, not any debugging messages.
    // // const stdout_file = std.io.getStdOut().writer();
    // // var bw = std.io.bufferedWriter(stdout_file);
    // // const stdout = bw.writer();

    // // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // // try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
