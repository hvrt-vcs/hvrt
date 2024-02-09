const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const sql_path = "sql/sqlite/work_tree/init.sql";
const embedded_sql = @embedFile(sql_path);

const sqlite_errors = error{ SQLiteError, SQLiteExecError, SQLiteCantOpen };
const errors = error{AbnormalState} || sqlite_errors;

// If we request a value from the map using a constant lookup key, will Zig
// just reduce that at comp time? That way we can *never* have an incorrect
// lookup at runtime based on a typo or something.
const sql_files = std.ComptimeStringMap([]const u8, .{
    .{ sql_path, embedded_sql },
});

fn sqliteReturnCodeToError(code: c_int) !void {
    if (code != c.SQLITE_OK) {
        // How to retrieve SQLite error codes: https://www.sqlite.org/c3ref/errcode.html
        std.debug.print("SQLite failed with error code {d} which translates to message: '{s}'\n", .{ code, c.sqlite3_errstr(code) });
    }

    switch (code) {
        c.SQLITE_OK => return,
        c.SQLITE_ERROR => return sqlite_errors.SQLiteError,
        c.SQLITE_CANTOPEN => return sqlite_errors.SQLiteCantOpen,
        else => return sqlite_errors.SQLiteError,
    }
}

/// Open and return a pointer to a sqlite database or return an error if a
/// database pointer cannot be opened for some reason.
fn sqlite_open(filename: []const u8) !*c.sqlite3 {
    var db: *c.sqlite3 = undefined;

    const rc = c.sqlite3_open(filename.ptr, @ptrCast(&db));
    errdefer _ = c.sqlite3_close(db);

    try sqliteReturnCodeToError(rc);
    return db;
}

/// Open and return a pointer to a sqlite database or return an error if a
/// database pointer cannot be opened for some reason.
fn sqlite_close(db: ?*c.sqlite3) !void {
    const rc = c.sqlite3_close(db);
    try sqliteReturnCodeToError(rc);
}

/// All that `main` does is retrieve args and a main allocator for the system,
/// and pass those to `internalMain`. Afterwards, it catches any errors, deals
/// with the error types it explicitly knows how to deal with, and if a
/// different error slips though it just returns that a stack trace is printed
/// and a generic exit code of 1 is returned in that case.
pub fn main() !void {
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
        var exit_code: u8 = switch (err) {
            sqlite_errors.SQLiteError => 3,
            sqlite_errors.SQLiteCantOpen => 4,
            else => {
                // Any error other than the explicitly listed ones in the
                // switch should just bubble up normally, triggering the
                // regularly deferred functions above.
                return err;
            },
        };

        // The `exit` function won't call the deferred functions above, so we
        // call them explicitly here before calling `exit`
        std.process.argsFree(allocator, args);
        _ = gpa.deinit();
        std.process.exit(exit_code);
    };
}

/// It is the responsibility of the caller of `internalMain` to deallocate and
/// deinit args and alloc, if necessary.
pub fn internalMain(args: [][:0]const u8, alloc: std.mem.Allocator) !void {
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

    std.debug.print("what is embedded sql path: {s}\n", .{sql_path});
    // std.debug.print("what is embedded sql value: {s}\n", .{embedded_sql});
    std.debug.print("what is embedded sql path bytes: {any}\n", .{sql_path});
    // std.debug.print("what is embedded sql value bytes: {any}\n", .{embedded_sql});
    // std.debug.print("what is sql files ComptimeStringMap: {any}\n", .{sql_files.kvs});

    const db = try sqlite_open(db_path);
    defer sqlite_close(db) catch unreachable;

    var rc = c.sqlite3_exec(db, embedded_sql, null, null, null);
    try sqliteReturnCodeToError(rc);

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
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    var str_array = try std.testing.allocator.alloc([]u8, 1);
    defer std.testing.allocator.free(str_array); // try commenting this out and see if zig detects the memory leak!
    var str_list = std.ArrayList([]u8).init(std.testing.allocator);
    std.debug.print("what is type of str_list: {any}\n", .{@TypeOf(str_list)});
    std.debug.print("what is type of str_list.items: {any}\n", .{@TypeOf(str_list.items)});
    std.debug.print("what is type of str_list.items.len: {any}\n", .{@TypeOf(str_list.items.len)});
    std.debug.print("what is value of str_list.items.len: {any}\n", .{str_list.items.len});
    std.debug.print("what is type of str_list address of: {any}\n", .{@TypeOf(&str_list)});
    const prog_name = "fake_prog_name";
    var prog_name_copy = std.testing.allocator.alloc(u8, prog_name.len);
    defer std.testing.allocator.free(prog_name_copy); // try commenting this out and see if zig detects the memory leak!

    @memcpy(prog_name_copy[0..prog_name.len], prog_name);
    str_list.append(prog_name_copy);

    const basic_args = [_][:0]const u8{"test_prog"};
    std.debug.print("what is basic args: {s}\n", .{basic_args});
    std.debug.print("what is basic args bytes: {any}\n", .{basic_args});
    std.debug.print("what is type of basic args: {any}\n", .{@TypeOf(basic_args)});
    std.debug.print("what is type of basic args address of: {any}\n", .{@TypeOf(&basic_args)});
    // try std.testing.expectEqual(undefined, internalMain(&basic_args, std.testing.allocator));
}
