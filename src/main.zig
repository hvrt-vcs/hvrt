const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const sql_path = "sql/sqlite/work_tree/init.sql";
const embedded_sql = @embedFile(sql_path);

const sqlite3_abort_error = error{SQLITE_ABORT};
const sqlite3_abort_errors = error{SQLITE_ABORT_ROLLBACK} || sqlite3_abort_error;

const sqlite_errors = error{
    // Primary codes
    SQLITE_ABORT,
    SQLITE_AUTH,
    SQLITE_BUSY,
    SQLITE_CANTOPEN,
    SQLITE_CONSTRAINT,
    SQLITE_CORRUPT,
    SQLITE_EMPTY,
    SQLITE_ERROR,
    SQLITE_FORMAT,
    SQLITE_FULL,
    SQLITE_INTERNAL,
    SQLITE_INTERRUPT,
    SQLITE_IOERR,
    SQLITE_LOCKED,
    SQLITE_MISMATCH,
    SQLITE_MISUSE,
    SQLITE_NOLFS,
    SQLITE_NOMEM,
    SQLITE_NOTADB,
    SQLITE_NOTFOUND,
    SQLITE_NOTICE,
    SQLITE_PERM,
    SQLITE_PROTOCOL,
    SQLITE_RANGE,
    SQLITE_READONLY,
    SQLITE_SCHEMA,
    SQLITE_TOOBIG,
    SQLITE_WARNING,

    // Extended codes
    SQLITE_ABORT_ROLLBACK,
    SQLITE_AUTH_USER,
    SQLITE_BUSY_RECOVERY,
    SQLITE_BUSY_SNAPSHOT,
    SQLITE_BUSY_TIMEOUT,
    SQLITE_CANTOPEN_CONVPATH,
    SQLITE_CANTOPEN_DIRTYWAL,
    SQLITE_CANTOPEN_FULLPATH,
    SQLITE_CANTOPEN_ISDIR,
    SQLITE_CANTOPEN_NOTEMPDIR,
    SQLITE_CANTOPEN_SYMLINK,
    SQLITE_CONSTRAINT_CHECK,
    SQLITE_CONSTRAINT_COMMITHOOK,
    SQLITE_CONSTRAINT_DATATYPE,
    SQLITE_CONSTRAINT_FOREIGNKEY,
    SQLITE_CONSTRAINT_FUNCTION,
    SQLITE_CONSTRAINT_NOTNULL,
    SQLITE_CONSTRAINT_PINNED,
    SQLITE_CONSTRAINT_PRIMARYKEY,
    SQLITE_CONSTRAINT_ROWID,
    SQLITE_CONSTRAINT_TRIGGER,
    SQLITE_CONSTRAINT_UNIQUE,
    SQLITE_CONSTRAINT_VTAB,
    SQLITE_CORRUPT_INDEX,
    SQLITE_CORRUPT_SEQUENCE,
    SQLITE_CORRUPT_VTAB,
    SQLITE_ERROR_MISSING_COLLSEQ,
    SQLITE_ERROR_RETRY,
    SQLITE_ERROR_SNAPSHOT,
    SQLITE_IOERR_ACCESS,
    SQLITE_IOERR_AUTH,
    SQLITE_IOERR_BEGIN_ATOMIC,
    SQLITE_IOERR_BLOCKED,
    SQLITE_IOERR_CHECKRESERVEDLOCK,
    SQLITE_IOERR_CLOSE,
    SQLITE_IOERR_COMMIT_ATOMIC,
    SQLITE_IOERR_CONVPATH,
    SQLITE_IOERR_CORRUPTFS,
    SQLITE_IOERR_DATA,
    SQLITE_IOERR_DELETE,
    SQLITE_IOERR_DELETE_NOENT,
    SQLITE_IOERR_DIR_CLOSE,
    SQLITE_IOERR_DIR_FSYNC,
    SQLITE_IOERR_FSTAT,
    SQLITE_IOERR_FSYNC,
    SQLITE_IOERR_GETTEMPPATH,
    SQLITE_IOERR_LOCK,
    SQLITE_IOERR_MMAP,
    SQLITE_IOERR_NOMEM,
    SQLITE_IOERR_RDLOCK,
    SQLITE_IOERR_READ,
    SQLITE_IOERR_ROLLBACK_ATOMIC,
    SQLITE_IOERR_SEEK,
    SQLITE_IOERR_SHMLOCK,
    SQLITE_IOERR_SHMMAP,
    SQLITE_IOERR_SHMOPEN,
    SQLITE_IOERR_SHMSIZE,
    SQLITE_IOERR_SHORT_READ,
    SQLITE_IOERR_TRUNCATE,
    SQLITE_IOERR_UNLOCK,
    SQLITE_IOERR_VNODE,
    SQLITE_IOERR_WRITE,
    SQLITE_LOCKED_SHAREDCACHE,
    SQLITE_LOCKED_VTAB,
    SQLITE_NOTICE_RECOVER_ROLLBACK,
    SQLITE_NOTICE_RECOVER_WAL,
    SQLITE_OK_LOAD_PERMANENTLY,
    SQLITE_READONLY_CANTINIT,
    SQLITE_READONLY_CANTLOCK,
    SQLITE_READONLY_DBMOVED,
    SQLITE_READONLY_DIRECTORY,
    SQLITE_READONLY_RECOVERY,
    SQLITE_READONLY_ROLLBACK,
    SQLITE_WARNING_AUTOINDEX,
};

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

    return switch (code) {
        // non-error result codes
        c.SQLITE_OK, c.SQLITE_DONE, c.SQLITE_ROW => return,

        // Primary codes
        c.SQLITE_ABORT => sqlite_errors.SQLITE_ABORT,
        c.SQLITE_AUTH => sqlite_errors.SQLITE_AUTH,
        c.SQLITE_BUSY => sqlite_errors.SQLITE_BUSY,
        c.SQLITE_CANTOPEN => sqlite_errors.SQLITE_CANTOPEN,
        c.SQLITE_CONSTRAINT => sqlite_errors.SQLITE_CONSTRAINT,
        c.SQLITE_CORRUPT => sqlite_errors.SQLITE_CORRUPT,
        c.SQLITE_EMPTY => sqlite_errors.SQLITE_EMPTY,
        c.SQLITE_ERROR => sqlite_errors.SQLITE_ERROR,
        c.SQLITE_FORMAT => sqlite_errors.SQLITE_FORMAT,
        c.SQLITE_FULL => sqlite_errors.SQLITE_FULL,
        c.SQLITE_INTERNAL => sqlite_errors.SQLITE_INTERNAL,
        c.SQLITE_INTERRUPT => sqlite_errors.SQLITE_INTERRUPT,
        c.SQLITE_IOERR => sqlite_errors.SQLITE_IOERR,
        c.SQLITE_LOCKED => sqlite_errors.SQLITE_LOCKED,
        c.SQLITE_MISMATCH => sqlite_errors.SQLITE_MISMATCH,
        c.SQLITE_MISUSE => sqlite_errors.SQLITE_MISUSE,
        c.SQLITE_NOLFS => sqlite_errors.SQLITE_NOLFS,
        c.SQLITE_NOMEM => sqlite_errors.SQLITE_NOMEM,
        c.SQLITE_NOTADB => sqlite_errors.SQLITE_NOTADB,
        c.SQLITE_NOTFOUND => sqlite_errors.SQLITE_NOTFOUND,
        c.SQLITE_NOTICE => sqlite_errors.SQLITE_NOTICE,
        c.SQLITE_PERM => sqlite_errors.SQLITE_PERM,
        c.SQLITE_PROTOCOL => sqlite_errors.SQLITE_PROTOCOL,
        c.SQLITE_RANGE => sqlite_errors.SQLITE_RANGE,
        c.SQLITE_READONLY => sqlite_errors.SQLITE_READONLY,
        c.SQLITE_SCHEMA => sqlite_errors.SQLITE_SCHEMA,
        c.SQLITE_TOOBIG => sqlite_errors.SQLITE_TOOBIG,
        c.SQLITE_WARNING => sqlite_errors.SQLITE_WARNING,

        // Extended codes
        c.SQLITE_ABORT_ROLLBACK => sqlite_errors.SQLITE_ABORT_ROLLBACK,
        c.SQLITE_AUTH_USER => sqlite_errors.SQLITE_AUTH_USER,
        c.SQLITE_BUSY_RECOVERY => sqlite_errors.SQLITE_BUSY_RECOVERY,
        c.SQLITE_BUSY_SNAPSHOT => sqlite_errors.SQLITE_BUSY_SNAPSHOT,
        c.SQLITE_BUSY_TIMEOUT => sqlite_errors.SQLITE_BUSY_TIMEOUT,
        c.SQLITE_CANTOPEN_CONVPATH => sqlite_errors.SQLITE_CANTOPEN_CONVPATH,
        c.SQLITE_CANTOPEN_DIRTYWAL => sqlite_errors.SQLITE_CANTOPEN_DIRTYWAL,
        c.SQLITE_CANTOPEN_FULLPATH => sqlite_errors.SQLITE_CANTOPEN_FULLPATH,
        c.SQLITE_CANTOPEN_ISDIR => sqlite_errors.SQLITE_CANTOPEN_ISDIR,
        c.SQLITE_CANTOPEN_NOTEMPDIR => sqlite_errors.SQLITE_CANTOPEN_NOTEMPDIR,
        c.SQLITE_CANTOPEN_SYMLINK => sqlite_errors.SQLITE_CANTOPEN_SYMLINK,
        c.SQLITE_CONSTRAINT_CHECK => sqlite_errors.SQLITE_CONSTRAINT_CHECK,
        c.SQLITE_CONSTRAINT_COMMITHOOK => sqlite_errors.SQLITE_CONSTRAINT_COMMITHOOK,
        c.SQLITE_CONSTRAINT_DATATYPE => sqlite_errors.SQLITE_CONSTRAINT_DATATYPE,
        c.SQLITE_CONSTRAINT_FOREIGNKEY => sqlite_errors.SQLITE_CONSTRAINT_FOREIGNKEY,
        c.SQLITE_CONSTRAINT_FUNCTION => sqlite_errors.SQLITE_CONSTRAINT_FUNCTION,
        c.SQLITE_CONSTRAINT_NOTNULL => sqlite_errors.SQLITE_CONSTRAINT_NOTNULL,
        c.SQLITE_CONSTRAINT_PINNED => sqlite_errors.SQLITE_CONSTRAINT_PINNED,
        c.SQLITE_CONSTRAINT_PRIMARYKEY => sqlite_errors.SQLITE_CONSTRAINT_PRIMARYKEY,
        c.SQLITE_CONSTRAINT_ROWID => sqlite_errors.SQLITE_CONSTRAINT_ROWID,
        c.SQLITE_CONSTRAINT_TRIGGER => sqlite_errors.SQLITE_CONSTRAINT_TRIGGER,
        c.SQLITE_CONSTRAINT_UNIQUE => sqlite_errors.SQLITE_CONSTRAINT_UNIQUE,
        c.SQLITE_CONSTRAINT_VTAB => sqlite_errors.SQLITE_CONSTRAINT_VTAB,
        c.SQLITE_CORRUPT_INDEX => sqlite_errors.SQLITE_CORRUPT_INDEX,
        c.SQLITE_CORRUPT_SEQUENCE => sqlite_errors.SQLITE_CORRUPT_SEQUENCE,
        c.SQLITE_CORRUPT_VTAB => sqlite_errors.SQLITE_CORRUPT_VTAB,
        c.SQLITE_ERROR_MISSING_COLLSEQ => error.SQLITE_ERROR_MISSING_COLLSEQ,
        c.SQLITE_ERROR_RETRY => error.SQLITE_ERROR_RETRY,
        c.SQLITE_ERROR_SNAPSHOT => error.SQLITE_ERROR_SNAPSHOT,
        c.SQLITE_IOERR_ACCESS => sqlite_errors.SQLITE_IOERR_ACCESS,
        c.SQLITE_IOERR_AUTH => sqlite_errors.SQLITE_IOERR_AUTH,
        c.SQLITE_IOERR_BEGIN_ATOMIC => sqlite_errors.SQLITE_IOERR_BEGIN_ATOMIC,
        c.SQLITE_IOERR_BLOCKED => sqlite_errors.SQLITE_IOERR_BLOCKED,
        c.SQLITE_IOERR_CHECKRESERVEDLOCK => sqlite_errors.SQLITE_IOERR_CHECKRESERVEDLOCK,
        c.SQLITE_IOERR_CLOSE => sqlite_errors.SQLITE_IOERR_CLOSE,
        c.SQLITE_IOERR_COMMIT_ATOMIC => sqlite_errors.SQLITE_IOERR_COMMIT_ATOMIC,
        c.SQLITE_IOERR_CONVPATH => sqlite_errors.SQLITE_IOERR_CONVPATH,
        c.SQLITE_IOERR_CORRUPTFS => sqlite_errors.SQLITE_IOERR_CORRUPTFS,
        c.SQLITE_IOERR_DATA => sqlite_errors.SQLITE_IOERR_DATA,
        c.SQLITE_IOERR_DELETE => sqlite_errors.SQLITE_IOERR_DELETE,
        c.SQLITE_IOERR_DELETE_NOENT => sqlite_errors.SQLITE_IOERR_DELETE_NOENT,
        c.SQLITE_IOERR_DIR_CLOSE => sqlite_errors.SQLITE_IOERR_DIR_CLOSE,
        c.SQLITE_IOERR_DIR_FSYNC => sqlite_errors.SQLITE_IOERR_DIR_FSYNC,
        c.SQLITE_IOERR_FSTAT => sqlite_errors.SQLITE_IOERR_FSTAT,
        c.SQLITE_IOERR_FSYNC => sqlite_errors.SQLITE_IOERR_FSYNC,
        c.SQLITE_IOERR_GETTEMPPATH => sqlite_errors.SQLITE_IOERR_GETTEMPPATH,
        c.SQLITE_IOERR_LOCK => sqlite_errors.SQLITE_IOERR_LOCK,
        c.SQLITE_IOERR_MMAP => sqlite_errors.SQLITE_IOERR_MMAP,
        c.SQLITE_IOERR_NOMEM => sqlite_errors.SQLITE_IOERR_NOMEM,
        c.SQLITE_IOERR_RDLOCK => sqlite_errors.SQLITE_IOERR_RDLOCK,
        c.SQLITE_IOERR_READ => sqlite_errors.SQLITE_IOERR_READ,
        c.SQLITE_IOERR_ROLLBACK_ATOMIC => sqlite_errors.SQLITE_IOERR_ROLLBACK_ATOMIC,
        c.SQLITE_IOERR_SEEK => sqlite_errors.SQLITE_IOERR_SEEK,
        c.SQLITE_IOERR_SHMLOCK => sqlite_errors.SQLITE_IOERR_SHMLOCK,
        c.SQLITE_IOERR_SHMMAP => sqlite_errors.SQLITE_IOERR_SHMMAP,
        c.SQLITE_IOERR_SHMOPEN => sqlite_errors.SQLITE_IOERR_SHMOPEN,
        c.SQLITE_IOERR_SHMSIZE => sqlite_errors.SQLITE_IOERR_SHMSIZE,
        c.SQLITE_IOERR_SHORT_READ => sqlite_errors.SQLITE_IOERR_SHORT_READ,
        c.SQLITE_IOERR_TRUNCATE => sqlite_errors.SQLITE_IOERR_TRUNCATE,
        c.SQLITE_IOERR_UNLOCK => sqlite_errors.SQLITE_IOERR_UNLOCK,
        c.SQLITE_IOERR_VNODE => sqlite_errors.SQLITE_IOERR_VNODE,
        c.SQLITE_IOERR_WRITE => sqlite_errors.SQLITE_IOERR_WRITE,
        c.SQLITE_LOCKED_SHAREDCACHE => sqlite_errors.SQLITE_LOCKED_SHAREDCACHE,
        c.SQLITE_LOCKED_VTAB => sqlite_errors.SQLITE_LOCKED_VTAB,
        c.SQLITE_NOTICE_RECOVER_ROLLBACK => sqlite_errors.SQLITE_NOTICE_RECOVER_ROLLBACK,
        c.SQLITE_NOTICE_RECOVER_WAL => sqlite_errors.SQLITE_NOTICE_RECOVER_WAL,
        c.SQLITE_OK_LOAD_PERMANENTLY => sqlite_errors.SQLITE_OK_LOAD_PERMANENTLY,
        c.SQLITE_READONLY_CANTINIT => sqlite_errors.SQLITE_READONLY_CANTINIT,
        c.SQLITE_READONLY_CANTLOCK => sqlite_errors.SQLITE_READONLY_CANTLOCK,
        c.SQLITE_READONLY_DBMOVED => sqlite_errors.SQLITE_READONLY_DBMOVED,
        c.SQLITE_READONLY_DIRECTORY => sqlite_errors.SQLITE_READONLY_DIRECTORY,
        c.SQLITE_READONLY_RECOVERY => sqlite_errors.SQLITE_READONLY_RECOVERY,
        c.SQLITE_READONLY_ROLLBACK => sqlite_errors.SQLITE_READONLY_ROLLBACK,
        c.SQLITE_WARNING_AUTOINDEX => sqlite_errors.SQLITE_WARNING_AUTOINDEX,
        else => sqlite_errors.SQLITE_ERROR,
    };
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
        unreachable;
    }
}

/// Close and free a pointer to a sqlite database or return an error if the
/// given database pointer cannot be closed for some reason.
fn sqlite3_close(db: ?*sqlite3_db) !void {
    const rc = c.sqlite3_close(db);
    try sqliteReturnCodeToError(db, rc);
}

/// Prepare a sql statement
fn sqlite3_prepare(db: ?*sqlite3_db, stmt: [:0]const u8) !*c.sqlite3_stmt {
    var stmt_opt: ?*c.sqlite3_stmt = null;

    const rc = c.sqlite3_prepare_v2(db, stmt.ptr, @intCast(stmt.len + 1), &stmt_opt, null);
    try sqliteReturnCodeToError(db, rc);

    if (stmt_opt) |stmt_ptr| {
        return stmt_ptr;
    } else {
        std.debug.print("SQLite did not indicate an error, but stmt_opt is still null: {any}\n", .{stmt_opt});
        unreachable;
    }
}

/// Use comptime magic to bind parameters for SQLite prepared statements based
/// on the type passed in. This can't stop the caller from making the mistake
/// of binding values of the incorrect type to parameter indices. See docs here
/// for the bind interface: https://www.sqlite.org/c3ref/bind_blob.html
fn sqlite3_bind(stmt: *c.sqlite3_stmt, index: u16, value: anytype) !void {
    const rc = switch (@TypeOf(value)) {
        @TypeOf(null) => c.sqlite3_bind_null(stmt, index),
        f16, f32, f64, comptime_float => c.sqlite3_bind_double(stmt, index, value),
        u8, i8, u16, i16, i32, u32, i64, comptime_int => c.sqlite3_bind_int64(stmt, index, value),

        // Using text64 should make it so that we don't need to do any casting
        // to pass the len of the slice. Since it is null terminated, we add
        // one to the len for the terminator.
        [:0]u8, [:0]const u8 => c.sqlite3_bind_text64(stmt, index, value.ptr, value.len + 1, c.SQLITE_TRANSIENT, c.SQLITE_UTF8),

        // If a u8 slice is not null terminated, we assume it is meant to be treated as a blob
        []const u8 => c.sqlite3_bind_blob64(stmt, index, value.ptr, value.len, c.SQLITE_TRANSIENT),

        // Failure
        else => {
            std.debug.print("Not given a type that can be bound to SQLite: {any}", .{@TypeOf(value)});
            @compileError("Not given a type that can be bound to SQLite");
        },
    };

    try sqliteReturnCodeToError(null, rc);
}

fn sqlite3_bind_text(stmt: *c.sqlite3_stmt, index: u16, value: [:0]const u8) !void {
    // Using text64 should make it so that we don't need to do any casting
    // to pass the len of the slice. Since it is null terminated, we add
    // one to the len for the terminator.
    const rc = c.sqlite3_bind_text64(stmt, index, value.ptr, value.len + 1, c.SQLITE_TRANSIENT, c.SQLITE_UTF8);

    try sqliteReturnCodeToError(null, rc);
}

/// Finalize (i.e. "free") a prepared sql statement
fn sqlite3_finalize(stmt_opt: ?*c.sqlite3_stmt) !void {
    const rc = c.sqlite3_finalize(stmt_opt);
    try sqliteReturnCodeToError(null, rc);
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
                sqlite_errors.SQLITE_ERROR => 3,
                sqlite_errors.SQLITE_CANTOPEN => 4,
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

    // Preparing a statement will only evaluate one statement (semicolon
    // terminated) at a time. So we can't just compile the whole init script
    // and run it. Will need to either split the script into multiple pieces,
    // or add some logic to iterate over the statements/detect when parameters
    // need to be bound. See link here for an example of this logic:
    // https://github.com/praeclarum/sqlite-net/issues/84
    const prepared_stmt = try sqlite3_prepare(db, embedded_sql);
    defer sqlite3_finalize(prepared_stmt) catch unreachable;

    // Version
    const version = "0.1.0";

    std.debug.print("How do you print a type? {any}\n", .{@TypeOf(version)});
    std.debug.print("How do you print a typeinfo? {any}\n", .{@typeInfo(@TypeOf(version))});
    // try sqlite3_bind_text(prepared_stmt, 1, version);

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
    const basic_args = [1][:0]const u8{"test_prog_name"};
    try internalMain(&basic_args, std.testing.allocator);
}
