const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const sql_path = "sql/sqlite/work_tree/init.sql";
const embedded_sql = @embedFile(sql_path);

const sqlite3_abort_error = error{SQLITE_ABORT};
const sqlite3_abort_errors = error{SQLITE_ABORT_ROLLBACK} || sqlite3_abort_error;

const sqlite_errors = error{ SQLiteError, SQLiteExecError, SQLiteCantOpen };
const errors = error{AbnormalState} || sqlite_errors;

const ResultCode = enum(c_int) {
    // Primary codes
    ABORT = c.SQLITE_ABORT,
    AUTH = c.SQLITE_AUTH,
    BUSY = c.SQLITE_BUSY,
    CANTOPEN = c.SQLITE_CANTOPEN,
    CONSTRAINT = c.SQLITE_CONSTRAINT,
    CORRUPT = c.SQLITE_CORRUPT,
    DONE = c.SQLITE_DONE, // non-error result code
    EMPTY = c.SQLITE_EMPTY,
    ERROR = c.SQLITE_ERROR,
    FORMAT = c.SQLITE_FORMAT,
    FULL = c.SQLITE_FULL,
    INTERNAL = c.SQLITE_INTERNAL,
    INTERRUPT = c.SQLITE_INTERRUPT,
    IOERR = c.SQLITE_IOERR,
    LOCKED = c.SQLITE_LOCKED,
    MISMATCH = c.SQLITE_MISMATCH,
    MISUSE = c.SQLITE_MISUSE,
    NOLFS = c.SQLITE_NOLFS,
    NOMEM = c.SQLITE_NOMEM,
    NOTADB = c.SQLITE_NOTADB,
    NOTFOUND = c.SQLITE_NOTFOUND,
    NOTICE = c.SQLITE_NOTICE,
    OK = c.SQLITE_OK, // non-error result code
    PERM = c.SQLITE_PERM,
    PROTOCOL = c.SQLITE_PROTOCOL,
    RANGE = c.SQLITE_RANGE,
    READONLY = c.SQLITE_READONLY,
    ROW = c.SQLITE_ROW, // non-error result code
    SCHEMA = c.SQLITE_SCHEMA,
    TOOBIG = c.SQLITE_TOOBIG,
    WARNING = c.SQLITE_WARNING,

    // Extended codes
    ABORT_ROLLBACK = c.SQLITE_ABORT_ROLLBACK,
    AUTH_USER = c.SQLITE_AUTH_USER,
    BUSY_RECOVERY = c.SQLITE_BUSY_RECOVERY,
    BUSY_SNAPSHOT = c.SQLITE_BUSY_SNAPSHOT,
    BUSY_TIMEOUT = c.SQLITE_BUSY_TIMEOUT,
    CANTOPEN_CONVPATH = c.SQLITE_CANTOPEN_CONVPATH,
    CANTOPEN_DIRTYWAL = c.SQLITE_CANTOPEN_DIRTYWAL,
    CANTOPEN_FULLPATH = c.SQLITE_CANTOPEN_FULLPATH,
    CANTOPEN_ISDIR = c.SQLITE_CANTOPEN_ISDIR,
    CANTOPEN_NOTEMPDIR = c.SQLITE_CANTOPEN_NOTEMPDIR,
    CANTOPEN_SYMLINK = c.SQLITE_CANTOPEN_SYMLINK,
    CONSTRAINT_CHECK = c.SQLITE_CONSTRAINT_CHECK,
    CONSTRAINT_COMMITHOOK = c.SQLITE_CONSTRAINT_COMMITHOOK,
    CONSTRAINT_DATATYPE = c.SQLITE_CONSTRAINT_DATATYPE,
    CONSTRAINT_FOREIGNKEY = c.SQLITE_CONSTRAINT_FOREIGNKEY,
    CONSTRAINT_FUNCTION = c.SQLITE_CONSTRAINT_FUNCTION,
    CONSTRAINT_NOTNULL = c.SQLITE_CONSTRAINT_NOTNULL,
    CONSTRAINT_PINNED = c.SQLITE_CONSTRAINT_PINNED,
    CONSTRAINT_PRIMARYKEY = c.SQLITE_CONSTRAINT_PRIMARYKEY,
    CONSTRAINT_ROWID = c.SQLITE_CONSTRAINT_ROWID,
    CONSTRAINT_TRIGGER = c.SQLITE_CONSTRAINT_TRIGGER,
    CONSTRAINT_UNIQUE = c.SQLITE_CONSTRAINT_UNIQUE,
    CONSTRAINT_VTAB = c.SQLITE_CONSTRAINT_VTAB,
    CORRUPT_INDEX = c.SQLITE_CORRUPT_INDEX,
    CORRUPT_SEQUENCE = c.SQLITE_CORRUPT_SEQUENCE,
    CORRUPT_VTAB = c.SQLITE_CORRUPT_VTAB,
    ERROR_MISSING_COLLSEQ = c.SQLITE_ERROR_MISSING_COLLSEQ,
    ERROR_RETRY = c.SQLITE_ERROR_RETRY,
    ERROR_SNAPSHOT = c.SQLITE_ERROR_SNAPSHOT,
    IOERR_ACCESS = c.SQLITE_IOERR_ACCESS,
    IOERR_AUTH = c.SQLITE_IOERR_AUTH,
    IOERR_BEGIN_ATOMIC = c.SQLITE_IOERR_BEGIN_ATOMIC,
    IOERR_BLOCKED = c.SQLITE_IOERR_BLOCKED,
    IOERR_CHECKRESERVEDLOCK = c.SQLITE_IOERR_CHECKRESERVEDLOCK,
    IOERR_CLOSE = c.SQLITE_IOERR_CLOSE,
    IOERR_COMMIT_ATOMIC = c.SQLITE_IOERR_COMMIT_ATOMIC,
    IOERR_CONVPATH = c.SQLITE_IOERR_CONVPATH,
    IOERR_CORRUPTFS = c.SQLITE_IOERR_CORRUPTFS,
    IOERR_DATA = c.SQLITE_IOERR_DATA,
    IOERR_DELETE = c.SQLITE_IOERR_DELETE,
    IOERR_DELETE_NOENT = c.SQLITE_IOERR_DELETE_NOENT,
    IOERR_DIR_CLOSE = c.SQLITE_IOERR_DIR_CLOSE,
    IOERR_DIR_FSYNC = c.SQLITE_IOERR_DIR_FSYNC,
    IOERR_FSTAT = c.SQLITE_IOERR_FSTAT,
    IOERR_FSYNC = c.SQLITE_IOERR_FSYNC,
    IOERR_GETTEMPPATH = c.SQLITE_IOERR_GETTEMPPATH,
    IOERR_LOCK = c.SQLITE_IOERR_LOCK,
    IOERR_MMAP = c.SQLITE_IOERR_MMAP,
    IOERR_NOMEM = c.SQLITE_IOERR_NOMEM,
    IOERR_RDLOCK = c.SQLITE_IOERR_RDLOCK,
    IOERR_READ = c.SQLITE_IOERR_READ,
    IOERR_ROLLBACK_ATOMIC = c.SQLITE_IOERR_ROLLBACK_ATOMIC,
    IOERR_SEEK = c.SQLITE_IOERR_SEEK,
    IOERR_SHMLOCK = c.SQLITE_IOERR_SHMLOCK,
    IOERR_SHMMAP = c.SQLITE_IOERR_SHMMAP,
    IOERR_SHMOPEN = c.SQLITE_IOERR_SHMOPEN,
    IOERR_SHMSIZE = c.SQLITE_IOERR_SHMSIZE,
    IOERR_SHORT_READ = c.SQLITE_IOERR_SHORT_READ,
    IOERR_TRUNCATE = c.SQLITE_IOERR_TRUNCATE,
    IOERR_UNLOCK = c.SQLITE_IOERR_UNLOCK,
    IOERR_VNODE = c.SQLITE_IOERR_VNODE,
    IOERR_WRITE = c.SQLITE_IOERR_WRITE,
    LOCKED_SHAREDCACHE = c.SQLITE_LOCKED_SHAREDCACHE,
    LOCKED_VTAB = c.SQLITE_LOCKED_VTAB,
    NOTICE_RECOVER_ROLLBACK = c.SQLITE_NOTICE_RECOVER_ROLLBACK,
    NOTICE_RECOVER_WAL = c.SQLITE_NOTICE_RECOVER_WAL,
    OK_LOAD_PERMANENTLY = c.SQLITE_OK_LOAD_PERMANENTLY,
    READONLY_CANTINIT = c.SQLITE_READONLY_CANTINIT,
    READONLY_CANTLOCK = c.SQLITE_READONLY_CANTLOCK,
    READONLY_DBMOVED = c.SQLITE_READONLY_DBMOVED,
    READONLY_DIRECTORY = c.SQLITE_READONLY_DIRECTORY,
    READONLY_RECOVERY = c.SQLITE_READONLY_RECOVERY,
    READONLY_ROLLBACK = c.SQLITE_READONLY_ROLLBACK,
    WARNING_AUTOINDEX = c.SQLITE_WARNING_AUTOINDEX,
};

// If we request a value from the map using a constant lookup key, will Zig
// just reduce that at comp time? That way we can *never* have an incorrect
// lookup at runtime based on a typo or something.
const sql_files = std.ComptimeStringMap([]const u8, .{
    .{ sql_path, embedded_sql },
});

fn sqliteReturnCodeToError(db_optional: ?*sqlite3_db, code: c_int) !void {
    if (code != c.SQLITE_OK) {
        // How to retrieve SQLite error codes: https://www.sqlite.org/c3ref/errcode.html
        std.debug.print("SQLite failed with error code {d} which translates to message: '{s}'\n", .{ code, c.sqlite3_errstr(code) });
        if (db_optional) |db| {
            std.debug.print("SQLite message for non-null DB pointer: '{s}'\n", .{c.sqlite3_errmsg(db)});
        }
    }

    switch (code) {
        c.SQLITE_OK => return,
        c.SQLITE_ERROR => return sqlite_errors.SQLiteError,
        c.SQLITE_CANTOPEN => return sqlite_errors.SQLiteCantOpen,
        else => return sqlite_errors.SQLiteError,
    }
}

/// Alias opaque struct_sqlite3 type.
const sqlite3_db = c.sqlite3;

/// Open and return a pointer to a sqlite database or return an error if a
/// database pointer cannot be opened for some reason.
fn sqlite3_open(filename: []const u8) !*sqlite3_db {
    var db_optional: ?*c.sqlite3 = null;
    var rc: c_int = 0;

    rc = c.sqlite3_open(filename.ptr, @ptrCast(&db_optional));
    errdefer sqlite3_close(db_optional) catch unreachable;
    try sqliteReturnCodeToError(db_optional, rc);

    // Enable extended error codes
    rc = c.sqlite3_extended_result_codes(db_optional, 1);
    try sqliteReturnCodeToError(db_optional, rc);

    if (db_optional) |db| {
        return db;
    } else {
        std.debug.print("SQLite did not indicate an error, but db_optional is still null: {any}\n", .{db_optional});
        return sqlite_errors.SQLiteError;
    }
}

/// Close and free a pointer to a sqlite database or return an error if the
/// given database pointer cannot be closed for some reason.
fn sqlite3_close(db: ?*sqlite3_db) !void {
    const rc = c.sqlite3_close(db);
    try sqliteReturnCodeToError(db, rc);
}

/// Execute a SQL statement held in a string.
fn sqlite3_exec(db: ?*sqlite3_db, sql: [:0]const u8, callback: ?*const fn (?*anyopaque, c_int, [*c][*c]u8, [*c][*c]u8) callconv(.C) c_int) !void {
    var errmsg: [100]u8 = undefined;

    // FIXME: Figure out pointer cast for local byte array
    // const rc = c.sqlite3_exec(db, sql, callback, null, @alignCast(@ptrCast(&errmsg)));

    const rc = c.sqlite3_exec(db, sql, callback, null, null);
    sqliteReturnCodeToError(db, rc) catch |err| {
        std.debug.print("sqlite failed with error message: {s}\n", .{errmsg});
        return err;
    };
}

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
                sqlite_errors.SQLiteError => 3,
                sqlite_errors.SQLiteCantOpen => 4,
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

    std.debug.print("what is embedded sql path: {s}\n", .{sql_path});
    // std.debug.print("what is embedded sql value: {s}\n", .{embedded_sql});
    std.debug.print("what is embedded sql path bytes: {any}\n", .{sql_path});
    // std.debug.print("what is embedded sql value bytes: {any}\n", .{embedded_sql});
    // std.debug.print("what is sql files ComptimeStringMap: {any}\n", .{sql_files.kvs});

    const db = try sqlite3_open(db_path);
    defer sqlite3_close(db) catch unreachable;

    try sqlite3_exec(db, embedded_sql, null);

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
    const basic_args = [1][:0]const u8{"test_prog_name"};
    try internalMain(&basic_args, std.testing.allocator);
}
