const std = @import("std");
const c = @import("c.zig");

/// Alias opaque sqlite3 type.
pub const DataBase = c.sqlite3;

/// Alias opaque sqlite3_stmt type.
pub const PreparedStatement = c.sqlite3_stmt;

/// All SQLite error codes as Zig errors
pub const errors = error{
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

/// Map Result codes as an enum
pub const ResultCode = enum(c_int) {
    // Primary codes
    SQLITE_ABORT = c.SQLITE_ABORT,
    SQLITE_AUTH = c.SQLITE_AUTH,
    SQLITE_BUSY = c.SQLITE_BUSY,
    SQLITE_CANTOPEN = c.SQLITE_CANTOPEN,
    SQLITE_CONSTRAINT = c.SQLITE_CONSTRAINT,
    SQLITE_CORRUPT = c.SQLITE_CORRUPT,
    SQLITE_DONE = c.SQLITE_DONE, // non-error result code
    SQLITE_EMPTY = c.SQLITE_EMPTY,
    SQLITE_ERROR = c.SQLITE_ERROR,
    SQLITE_FORMAT = c.SQLITE_FORMAT,
    SQLITE_FULL = c.SQLITE_FULL,
    SQLITE_INTERNAL = c.SQLITE_INTERNAL,
    SQLITE_INTERRUPT = c.SQLITE_INTERRUPT,
    SQLITE_IOERR = c.SQLITE_IOERR,
    SQLITE_LOCKED = c.SQLITE_LOCKED,
    SQLITE_MISMATCH = c.SQLITE_MISMATCH,
    SQLITE_MISUSE = c.SQLITE_MISUSE,
    SQLITE_NOLFS = c.SQLITE_NOLFS,
    SQLITE_NOMEM = c.SQLITE_NOMEM,
    SQLITE_NOTADB = c.SQLITE_NOTADB,
    SQLITE_NOTFOUND = c.SQLITE_NOTFOUND,
    SQLITE_NOTICE = c.SQLITE_NOTICE,
    SQLITE_OK = c.SQLITE_OK, // non-error result code
    SQLITE_PERM = c.SQLITE_PERM,
    SQLITE_PROTOCOL = c.SQLITE_PROTOCOL,
    SQLITE_RANGE = c.SQLITE_RANGE,
    SQLITE_READONLY = c.SQLITE_READONLY,
    SQLITE_ROW = c.SQLITE_ROW, // non-error result code
    SQLITE_SCHEMA = c.SQLITE_SCHEMA,
    SQLITE_TOOBIG = c.SQLITE_TOOBIG,
    SQLITE_WARNING = c.SQLITE_WARNING,

    // Extended codes
    SQLITE_ABORT_ROLLBACK = c.SQLITE_ABORT_ROLLBACK,
    SQLITE_AUTH_USER = c.SQLITE_AUTH_USER,
    SQLITE_BUSY_RECOVERY = c.SQLITE_BUSY_RECOVERY,
    SQLITE_BUSY_SNAPSHOT = c.SQLITE_BUSY_SNAPSHOT,
    SQLITE_BUSY_TIMEOUT = c.SQLITE_BUSY_TIMEOUT,
    SQLITE_CANTOPEN_CONVPATH = c.SQLITE_CANTOPEN_CONVPATH,
    SQLITE_CANTOPEN_DIRTYWAL = c.SQLITE_CANTOPEN_DIRTYWAL,
    SQLITE_CANTOPEN_FULLPATH = c.SQLITE_CANTOPEN_FULLPATH,
    SQLITE_CANTOPEN_ISDIR = c.SQLITE_CANTOPEN_ISDIR,
    SQLITE_CANTOPEN_NOTEMPDIR = c.SQLITE_CANTOPEN_NOTEMPDIR,
    SQLITE_CANTOPEN_SYMLINK = c.SQLITE_CANTOPEN_SYMLINK,
    SQLITE_CONSTRAINT_CHECK = c.SQLITE_CONSTRAINT_CHECK,
    SQLITE_CONSTRAINT_COMMITHOOK = c.SQLITE_CONSTRAINT_COMMITHOOK,
    SQLITE_CONSTRAINT_DATATYPE = c.SQLITE_CONSTRAINT_DATATYPE,
    SQLITE_CONSTRAINT_FOREIGNKEY = c.SQLITE_CONSTRAINT_FOREIGNKEY,
    SQLITE_CONSTRAINT_FUNCTION = c.SQLITE_CONSTRAINT_FUNCTION,
    SQLITE_CONSTRAINT_NOTNULL = c.SQLITE_CONSTRAINT_NOTNULL,
    SQLITE_CONSTRAINT_PINNED = c.SQLITE_CONSTRAINT_PINNED,
    SQLITE_CONSTRAINT_PRIMARYKEY = c.SQLITE_CONSTRAINT_PRIMARYKEY,
    SQLITE_CONSTRAINT_ROWID = c.SQLITE_CONSTRAINT_ROWID,
    SQLITE_CONSTRAINT_TRIGGER = c.SQLITE_CONSTRAINT_TRIGGER,
    SQLITE_CONSTRAINT_UNIQUE = c.SQLITE_CONSTRAINT_UNIQUE,
    SQLITE_CONSTRAINT_VTAB = c.SQLITE_CONSTRAINT_VTAB,
    SQLITE_CORRUPT_INDEX = c.SQLITE_CORRUPT_INDEX,
    SQLITE_CORRUPT_SEQUENCE = c.SQLITE_CORRUPT_SEQUENCE,
    SQLITE_CORRUPT_VTAB = c.SQLITE_CORRUPT_VTAB,
    SQLITE_ERROR_MISSING_COLLSEQ = c.SQLITE_ERROR_MISSING_COLLSEQ,
    SQLITE_ERROR_RETRY = c.SQLITE_ERROR_RETRY,
    SQLITE_ERROR_SNAPSHOT = c.SQLITE_ERROR_SNAPSHOT,
    SQLITE_IOERR_ACCESS = c.SQLITE_IOERR_ACCESS,
    SQLITE_IOERR_AUTH = c.SQLITE_IOERR_AUTH,
    SQLITE_IOERR_BEGIN_ATOMIC = c.SQLITE_IOERR_BEGIN_ATOMIC,
    SQLITE_IOERR_BLOCKED = c.SQLITE_IOERR_BLOCKED,
    SQLITE_IOERR_CHECKRESERVEDLOCK = c.SQLITE_IOERR_CHECKRESERVEDLOCK,
    SQLITE_IOERR_CLOSE = c.SQLITE_IOERR_CLOSE,
    SQLITE_IOERR_COMMIT_ATOMIC = c.SQLITE_IOERR_COMMIT_ATOMIC,
    SQLITE_IOERR_CONVPATH = c.SQLITE_IOERR_CONVPATH,
    SQLITE_IOERR_CORRUPTFS = c.SQLITE_IOERR_CORRUPTFS,
    SQLITE_IOERR_DATA = c.SQLITE_IOERR_DATA,
    SQLITE_IOERR_DELETE = c.SQLITE_IOERR_DELETE,
    SQLITE_IOERR_DELETE_NOENT = c.SQLITE_IOERR_DELETE_NOENT,
    SQLITE_IOERR_DIR_CLOSE = c.SQLITE_IOERR_DIR_CLOSE,
    SQLITE_IOERR_DIR_FSYNC = c.SQLITE_IOERR_DIR_FSYNC,
    SQLITE_IOERR_FSTAT = c.SQLITE_IOERR_FSTAT,
    SQLITE_IOERR_FSYNC = c.SQLITE_IOERR_FSYNC,
    SQLITE_IOERR_GETTEMPPATH = c.SQLITE_IOERR_GETTEMPPATH,
    SQLITE_IOERR_LOCK = c.SQLITE_IOERR_LOCK,
    SQLITE_IOERR_MMAP = c.SQLITE_IOERR_MMAP,
    SQLITE_IOERR_NOMEM = c.SQLITE_IOERR_NOMEM,
    SQLITE_IOERR_RDLOCK = c.SQLITE_IOERR_RDLOCK,
    SQLITE_IOERR_READ = c.SQLITE_IOERR_READ,
    SQLITE_IOERR_ROLLBACK_ATOMIC = c.SQLITE_IOERR_ROLLBACK_ATOMIC,
    SQLITE_IOERR_SEEK = c.SQLITE_IOERR_SEEK,
    SQLITE_IOERR_SHMLOCK = c.SQLITE_IOERR_SHMLOCK,
    SQLITE_IOERR_SHMMAP = c.SQLITE_IOERR_SHMMAP,
    SQLITE_IOERR_SHMOPEN = c.SQLITE_IOERR_SHMOPEN,
    SQLITE_IOERR_SHMSIZE = c.SQLITE_IOERR_SHMSIZE,
    SQLITE_IOERR_SHORT_READ = c.SQLITE_IOERR_SHORT_READ,
    SQLITE_IOERR_TRUNCATE = c.SQLITE_IOERR_TRUNCATE,
    SQLITE_IOERR_UNLOCK = c.SQLITE_IOERR_UNLOCK,
    SQLITE_IOERR_VNODE = c.SQLITE_IOERR_VNODE,
    SQLITE_IOERR_WRITE = c.SQLITE_IOERR_WRITE,
    SQLITE_LOCKED_SHAREDCACHE = c.SQLITE_LOCKED_SHAREDCACHE,
    SQLITE_LOCKED_VTAB = c.SQLITE_LOCKED_VTAB,
    SQLITE_NOTICE_RECOVER_ROLLBACK = c.SQLITE_NOTICE_RECOVER_ROLLBACK,
    SQLITE_NOTICE_RECOVER_WAL = c.SQLITE_NOTICE_RECOVER_WAL,
    SQLITE_OK_LOAD_PERMANENTLY = c.SQLITE_OK_LOAD_PERMANENTLY,
    SQLITE_READONLY_CANTINIT = c.SQLITE_READONLY_CANTINIT,
    SQLITE_READONLY_CANTLOCK = c.SQLITE_READONLY_CANTLOCK,
    SQLITE_READONLY_DBMOVED = c.SQLITE_READONLY_DBMOVED,
    SQLITE_READONLY_DIRECTORY = c.SQLITE_READONLY_DIRECTORY,
    SQLITE_READONLY_RECOVERY = c.SQLITE_READONLY_RECOVERY,
    SQLITE_READONLY_ROLLBACK = c.SQLITE_READONLY_ROLLBACK,
    SQLITE_WARNING_AUTOINDEX = c.SQLITE_WARNING_AUTOINDEX,
};

fn checkReturnCode(db_optional: ?*DataBase, code: c_int) !ResultCode {
    return errorFromResultCode(@enumFromInt(code)) catch |err| {
        // How to retrieve SQLite error codes: https://www.sqlite.org/c3ref/errcode.html
        std.debug.print("SQLite returned code '{s}' ({d}) with message: '{s}'\n", .{ @errorName(err), code, c.sqlite3_errstr(code) });
        if (db_optional) |db| {
            std.debug.print("SQLite message for non-null DB pointer: '{s}'\n", .{c.sqlite3_errmsg(db)});
        }

        return err;
    };
}

fn resultCodeFromError(err: @TypeOf(errors.SQLITE_ERROR)) ResultCode {
    return switch (err) {
        // Primary codes
        errors.SQLITE_ABORT => ResultCode.SQLITE_ABORT,
        errors.SQLITE_AUTH => ResultCode.SQLITE_AUTH,
        errors.SQLITE_BUSY => ResultCode.SQLITE_BUSY,
        errors.SQLITE_CANTOPEN => ResultCode.SQLITE_CANTOPEN,
        errors.SQLITE_CONSTRAINT => ResultCode.SQLITE_CONSTRAINT,
        errors.SQLITE_CORRUPT => ResultCode.SQLITE_CORRUPT,
        errors.SQLITE_EMPTY => ResultCode.SQLITE_EMPTY,
        errors.SQLITE_ERROR => ResultCode.SQLITE_ERROR,
        errors.SQLITE_FORMAT => ResultCode.SQLITE_FORMAT,
        errors.SQLITE_FULL => ResultCode.SQLITE_FULL,
        errors.SQLITE_INTERNAL => ResultCode.SQLITE_INTERNAL,
        errors.SQLITE_INTERRUPT => ResultCode.SQLITE_INTERRUPT,
        errors.SQLITE_IOERR => ResultCode.SQLITE_IOERR,
        errors.SQLITE_LOCKED => ResultCode.SQLITE_LOCKED,
        errors.SQLITE_MISMATCH => ResultCode.SQLITE_MISMATCH,
        errors.SQLITE_MISUSE => ResultCode.SQLITE_MISUSE,
        errors.SQLITE_NOLFS => ResultCode.SQLITE_NOLFS,
        errors.SQLITE_NOMEM => ResultCode.SQLITE_NOMEM,
        errors.SQLITE_NOTADB => ResultCode.SQLITE_NOTADB,
        errors.SQLITE_NOTFOUND => ResultCode.SQLITE_NOTFOUND,
        errors.SQLITE_NOTICE => ResultCode.SQLITE_NOTICE,
        errors.SQLITE_PERM => ResultCode.SQLITE_PERM,
        errors.SQLITE_PROTOCOL => ResultCode.SQLITE_PROTOCOL,
        errors.SQLITE_RANGE => ResultCode.SQLITE_RANGE,
        errors.SQLITE_READONLY => ResultCode.SQLITE_READONLY,
        errors.SQLITE_SCHEMA => ResultCode.SQLITE_SCHEMA,
        errors.SQLITE_TOOBIG => ResultCode.SQLITE_TOOBIG,
        errors.SQLITE_WARNING => ResultCode.SQLITE_WARNING,

        // Extended codes
        errors.SQLITE_ABORT_ROLLBACK => ResultCode.SQLITE_ABORT_ROLLBACK,
        errors.SQLITE_AUTH_USER => ResultCode.SQLITE_AUTH_USER,
        errors.SQLITE_BUSY_RECOVERY => ResultCode.SQLITE_BUSY_RECOVERY,
        errors.SQLITE_BUSY_SNAPSHOT => ResultCode.SQLITE_BUSY_SNAPSHOT,
        errors.SQLITE_BUSY_TIMEOUT => ResultCode.SQLITE_BUSY_TIMEOUT,
        errors.SQLITE_CANTOPEN_CONVPATH => ResultCode.SQLITE_CANTOPEN_CONVPATH,
        errors.SQLITE_CANTOPEN_DIRTYWAL => ResultCode.SQLITE_CANTOPEN_DIRTYWAL,
        errors.SQLITE_CANTOPEN_FULLPATH => ResultCode.SQLITE_CANTOPEN_FULLPATH,
        errors.SQLITE_CANTOPEN_ISDIR => ResultCode.SQLITE_CANTOPEN_ISDIR,
        errors.SQLITE_CANTOPEN_NOTEMPDIR => ResultCode.SQLITE_CANTOPEN_NOTEMPDIR,
        errors.SQLITE_CANTOPEN_SYMLINK => ResultCode.SQLITE_CANTOPEN_SYMLINK,
        errors.SQLITE_CONSTRAINT_CHECK => ResultCode.SQLITE_CONSTRAINT_CHECK,
        errors.SQLITE_CONSTRAINT_COMMITHOOK => ResultCode.SQLITE_CONSTRAINT_COMMITHOOK,
        errors.SQLITE_CONSTRAINT_DATATYPE => ResultCode.SQLITE_CONSTRAINT_DATATYPE,
        errors.SQLITE_CONSTRAINT_FOREIGNKEY => ResultCode.SQLITE_CONSTRAINT_FOREIGNKEY,
        errors.SQLITE_CONSTRAINT_FUNCTION => ResultCode.SQLITE_CONSTRAINT_FUNCTION,
        errors.SQLITE_CONSTRAINT_NOTNULL => ResultCode.SQLITE_CONSTRAINT_NOTNULL,
        errors.SQLITE_CONSTRAINT_PINNED => ResultCode.SQLITE_CONSTRAINT_PINNED,
        errors.SQLITE_CONSTRAINT_PRIMARYKEY => ResultCode.SQLITE_CONSTRAINT_PRIMARYKEY,
        errors.SQLITE_CONSTRAINT_ROWID => ResultCode.SQLITE_CONSTRAINT_ROWID,
        errors.SQLITE_CONSTRAINT_TRIGGER => ResultCode.SQLITE_CONSTRAINT_TRIGGER,
        errors.SQLITE_CONSTRAINT_UNIQUE => ResultCode.SQLITE_CONSTRAINT_UNIQUE,
        errors.SQLITE_CONSTRAINT_VTAB => ResultCode.SQLITE_CONSTRAINT_VTAB,
        errors.SQLITE_CORRUPT_INDEX => ResultCode.SQLITE_CORRUPT_INDEX,
        errors.SQLITE_CORRUPT_SEQUENCE => ResultCode.SQLITE_CORRUPT_SEQUENCE,
        errors.SQLITE_CORRUPT_VTAB => ResultCode.SQLITE_CORRUPT_VTAB,
        errors.SQLITE_ERROR_MISSING_COLLSEQ => ResultCode.SQLITE_ERROR_MISSING_COLLSEQ,
        errors.SQLITE_ERROR_RETRY => ResultCode.SQLITE_ERROR_RETRY,
        errors.SQLITE_ERROR_SNAPSHOT => ResultCode.SQLITE_ERROR_SNAPSHOT,
        errors.SQLITE_IOERR_ACCESS => ResultCode.SQLITE_IOERR_ACCESS,
        errors.SQLITE_IOERR_AUTH => ResultCode.SQLITE_IOERR_AUTH,
        errors.SQLITE_IOERR_BEGIN_ATOMIC => ResultCode.SQLITE_IOERR_BEGIN_ATOMIC,
        errors.SQLITE_IOERR_BLOCKED => ResultCode.SQLITE_IOERR_BLOCKED,
        errors.SQLITE_IOERR_CHECKRESERVEDLOCK => ResultCode.SQLITE_IOERR_CHECKRESERVEDLOCK,
        errors.SQLITE_IOERR_CLOSE => ResultCode.SQLITE_IOERR_CLOSE,
        errors.SQLITE_IOERR_COMMIT_ATOMIC => ResultCode.SQLITE_IOERR_COMMIT_ATOMIC,
        errors.SQLITE_IOERR_CONVPATH => ResultCode.SQLITE_IOERR_CONVPATH,
        errors.SQLITE_IOERR_CORRUPTFS => ResultCode.SQLITE_IOERR_CORRUPTFS,
        errors.SQLITE_IOERR_DATA => ResultCode.SQLITE_IOERR_DATA,
        errors.SQLITE_IOERR_DELETE => ResultCode.SQLITE_IOERR_DELETE,
        errors.SQLITE_IOERR_DELETE_NOENT => ResultCode.SQLITE_IOERR_DELETE_NOENT,
        errors.SQLITE_IOERR_DIR_CLOSE => ResultCode.SQLITE_IOERR_DIR_CLOSE,
        errors.SQLITE_IOERR_DIR_FSYNC => ResultCode.SQLITE_IOERR_DIR_FSYNC,
        errors.SQLITE_IOERR_FSTAT => ResultCode.SQLITE_IOERR_FSTAT,
        errors.SQLITE_IOERR_FSYNC => ResultCode.SQLITE_IOERR_FSYNC,
        errors.SQLITE_IOERR_GETTEMPPATH => ResultCode.SQLITE_IOERR_GETTEMPPATH,
        errors.SQLITE_IOERR_LOCK => ResultCode.SQLITE_IOERR_LOCK,
        errors.SQLITE_IOERR_MMAP => ResultCode.SQLITE_IOERR_MMAP,
        errors.SQLITE_IOERR_NOMEM => ResultCode.SQLITE_IOERR_NOMEM,
        errors.SQLITE_IOERR_RDLOCK => ResultCode.SQLITE_IOERR_RDLOCK,
        errors.SQLITE_IOERR_READ => ResultCode.SQLITE_IOERR_READ,
        errors.SQLITE_IOERR_ROLLBACK_ATOMIC => ResultCode.SQLITE_IOERR_ROLLBACK_ATOMIC,
        errors.SQLITE_IOERR_SEEK => ResultCode.SQLITE_IOERR_SEEK,
        errors.SQLITE_IOERR_SHMLOCK => ResultCode.SQLITE_IOERR_SHMLOCK,
        errors.SQLITE_IOERR_SHMMAP => ResultCode.SQLITE_IOERR_SHMMAP,
        errors.SQLITE_IOERR_SHMOPEN => ResultCode.SQLITE_IOERR_SHMOPEN,
        errors.SQLITE_IOERR_SHMSIZE => ResultCode.SQLITE_IOERR_SHMSIZE,
        errors.SQLITE_IOERR_SHORT_READ => ResultCode.SQLITE_IOERR_SHORT_READ,
        errors.SQLITE_IOERR_TRUNCATE => ResultCode.SQLITE_IOERR_TRUNCATE,
        errors.SQLITE_IOERR_UNLOCK => ResultCode.SQLITE_IOERR_UNLOCK,
        errors.SQLITE_IOERR_VNODE => ResultCode.SQLITE_IOERR_VNODE,
        errors.SQLITE_IOERR_WRITE => ResultCode.SQLITE_IOERR_WRITE,
        errors.SQLITE_LOCKED_SHAREDCACHE => ResultCode.SQLITE_LOCKED_SHAREDCACHE,
        errors.SQLITE_LOCKED_VTAB => ResultCode.SQLITE_LOCKED_VTAB,
        errors.SQLITE_NOTICE_RECOVER_ROLLBACK => ResultCode.SQLITE_NOTICE_RECOVER_ROLLBACK,
        errors.SQLITE_NOTICE_RECOVER_WAL => ResultCode.SQLITE_NOTICE_RECOVER_WAL,
        errors.SQLITE_OK_LOAD_PERMANENTLY => ResultCode.SQLITE_OK_LOAD_PERMANENTLY,
        errors.SQLITE_READONLY_CANTINIT => ResultCode.SQLITE_READONLY_CANTINIT,
        errors.SQLITE_READONLY_CANTLOCK => ResultCode.SQLITE_READONLY_CANTLOCK,
        errors.SQLITE_READONLY_DBMOVED => ResultCode.SQLITE_READONLY_DBMOVED,
        errors.SQLITE_READONLY_DIRECTORY => ResultCode.SQLITE_READONLY_DIRECTORY,
        errors.SQLITE_READONLY_RECOVERY => ResultCode.SQLITE_READONLY_RECOVERY,
        errors.SQLITE_READONLY_ROLLBACK => ResultCode.SQLITE_READONLY_ROLLBACK,
        errors.SQLITE_WARNING_AUTOINDEX => ResultCode.SQLITE_WARNING_AUTOINDEX,
    };
}

fn errorFromResultCode(code: ResultCode) !ResultCode {
    return switch (code) {
        // non-error result codes
        ResultCode.SQLITE_OK, ResultCode.SQLITE_DONE, ResultCode.SQLITE_ROW => code,

        // Primary codes
        ResultCode.SQLITE_ABORT => errors.SQLITE_ABORT,
        ResultCode.SQLITE_AUTH => errors.SQLITE_AUTH,
        ResultCode.SQLITE_BUSY => errors.SQLITE_BUSY,
        ResultCode.SQLITE_CANTOPEN => errors.SQLITE_CANTOPEN,
        ResultCode.SQLITE_CONSTRAINT => errors.SQLITE_CONSTRAINT,
        ResultCode.SQLITE_CORRUPT => errors.SQLITE_CORRUPT,
        ResultCode.SQLITE_EMPTY => errors.SQLITE_EMPTY,
        ResultCode.SQLITE_ERROR => errors.SQLITE_ERROR,
        ResultCode.SQLITE_FORMAT => errors.SQLITE_FORMAT,
        ResultCode.SQLITE_FULL => errors.SQLITE_FULL,
        ResultCode.SQLITE_INTERNAL => errors.SQLITE_INTERNAL,
        ResultCode.SQLITE_INTERRUPT => errors.SQLITE_INTERRUPT,
        ResultCode.SQLITE_IOERR => errors.SQLITE_IOERR,
        ResultCode.SQLITE_LOCKED => errors.SQLITE_LOCKED,
        ResultCode.SQLITE_MISMATCH => errors.SQLITE_MISMATCH,
        ResultCode.SQLITE_MISUSE => errors.SQLITE_MISUSE,
        ResultCode.SQLITE_NOLFS => errors.SQLITE_NOLFS,
        ResultCode.SQLITE_NOMEM => errors.SQLITE_NOMEM,
        ResultCode.SQLITE_NOTADB => errors.SQLITE_NOTADB,
        ResultCode.SQLITE_NOTFOUND => errors.SQLITE_NOTFOUND,
        ResultCode.SQLITE_NOTICE => errors.SQLITE_NOTICE,
        ResultCode.SQLITE_PERM => errors.SQLITE_PERM,
        ResultCode.SQLITE_PROTOCOL => errors.SQLITE_PROTOCOL,
        ResultCode.SQLITE_RANGE => errors.SQLITE_RANGE,
        ResultCode.SQLITE_READONLY => errors.SQLITE_READONLY,
        ResultCode.SQLITE_SCHEMA => errors.SQLITE_SCHEMA,
        ResultCode.SQLITE_TOOBIG => errors.SQLITE_TOOBIG,
        ResultCode.SQLITE_WARNING => errors.SQLITE_WARNING,

        // Extended codes
        ResultCode.SQLITE_ABORT_ROLLBACK => errors.SQLITE_ABORT_ROLLBACK,
        ResultCode.SQLITE_AUTH_USER => errors.SQLITE_AUTH_USER,
        ResultCode.SQLITE_BUSY_RECOVERY => errors.SQLITE_BUSY_RECOVERY,
        ResultCode.SQLITE_BUSY_SNAPSHOT => errors.SQLITE_BUSY_SNAPSHOT,
        ResultCode.SQLITE_BUSY_TIMEOUT => errors.SQLITE_BUSY_TIMEOUT,
        ResultCode.SQLITE_CANTOPEN_CONVPATH => errors.SQLITE_CANTOPEN_CONVPATH,
        ResultCode.SQLITE_CANTOPEN_DIRTYWAL => errors.SQLITE_CANTOPEN_DIRTYWAL,
        ResultCode.SQLITE_CANTOPEN_FULLPATH => errors.SQLITE_CANTOPEN_FULLPATH,
        ResultCode.SQLITE_CANTOPEN_ISDIR => errors.SQLITE_CANTOPEN_ISDIR,
        ResultCode.SQLITE_CANTOPEN_NOTEMPDIR => errors.SQLITE_CANTOPEN_NOTEMPDIR,
        ResultCode.SQLITE_CANTOPEN_SYMLINK => errors.SQLITE_CANTOPEN_SYMLINK,
        ResultCode.SQLITE_CONSTRAINT_CHECK => errors.SQLITE_CONSTRAINT_CHECK,
        ResultCode.SQLITE_CONSTRAINT_COMMITHOOK => errors.SQLITE_CONSTRAINT_COMMITHOOK,
        ResultCode.SQLITE_CONSTRAINT_DATATYPE => errors.SQLITE_CONSTRAINT_DATATYPE,
        ResultCode.SQLITE_CONSTRAINT_FOREIGNKEY => errors.SQLITE_CONSTRAINT_FOREIGNKEY,
        ResultCode.SQLITE_CONSTRAINT_FUNCTION => errors.SQLITE_CONSTRAINT_FUNCTION,
        ResultCode.SQLITE_CONSTRAINT_NOTNULL => errors.SQLITE_CONSTRAINT_NOTNULL,
        ResultCode.SQLITE_CONSTRAINT_PINNED => errors.SQLITE_CONSTRAINT_PINNED,
        ResultCode.SQLITE_CONSTRAINT_PRIMARYKEY => errors.SQLITE_CONSTRAINT_PRIMARYKEY,
        ResultCode.SQLITE_CONSTRAINT_ROWID => errors.SQLITE_CONSTRAINT_ROWID,
        ResultCode.SQLITE_CONSTRAINT_TRIGGER => errors.SQLITE_CONSTRAINT_TRIGGER,
        ResultCode.SQLITE_CONSTRAINT_UNIQUE => errors.SQLITE_CONSTRAINT_UNIQUE,
        ResultCode.SQLITE_CONSTRAINT_VTAB => errors.SQLITE_CONSTRAINT_VTAB,
        ResultCode.SQLITE_CORRUPT_INDEX => errors.SQLITE_CORRUPT_INDEX,
        ResultCode.SQLITE_CORRUPT_SEQUENCE => errors.SQLITE_CORRUPT_SEQUENCE,
        ResultCode.SQLITE_CORRUPT_VTAB => errors.SQLITE_CORRUPT_VTAB,
        ResultCode.SQLITE_ERROR_MISSING_COLLSEQ => error.SQLITE_ERROR_MISSING_COLLSEQ,
        ResultCode.SQLITE_ERROR_RETRY => error.SQLITE_ERROR_RETRY,
        ResultCode.SQLITE_ERROR_SNAPSHOT => error.SQLITE_ERROR_SNAPSHOT,
        ResultCode.SQLITE_IOERR_ACCESS => errors.SQLITE_IOERR_ACCESS,
        ResultCode.SQLITE_IOERR_AUTH => errors.SQLITE_IOERR_AUTH,
        ResultCode.SQLITE_IOERR_BEGIN_ATOMIC => errors.SQLITE_IOERR_BEGIN_ATOMIC,
        ResultCode.SQLITE_IOERR_BLOCKED => errors.SQLITE_IOERR_BLOCKED,
        ResultCode.SQLITE_IOERR_CHECKRESERVEDLOCK => errors.SQLITE_IOERR_CHECKRESERVEDLOCK,
        ResultCode.SQLITE_IOERR_CLOSE => errors.SQLITE_IOERR_CLOSE,
        ResultCode.SQLITE_IOERR_COMMIT_ATOMIC => errors.SQLITE_IOERR_COMMIT_ATOMIC,
        ResultCode.SQLITE_IOERR_CONVPATH => errors.SQLITE_IOERR_CONVPATH,
        ResultCode.SQLITE_IOERR_CORRUPTFS => errors.SQLITE_IOERR_CORRUPTFS,
        ResultCode.SQLITE_IOERR_DATA => errors.SQLITE_IOERR_DATA,
        ResultCode.SQLITE_IOERR_DELETE => errors.SQLITE_IOERR_DELETE,
        ResultCode.SQLITE_IOERR_DELETE_NOENT => errors.SQLITE_IOERR_DELETE_NOENT,
        ResultCode.SQLITE_IOERR_DIR_CLOSE => errors.SQLITE_IOERR_DIR_CLOSE,
        ResultCode.SQLITE_IOERR_DIR_FSYNC => errors.SQLITE_IOERR_DIR_FSYNC,
        ResultCode.SQLITE_IOERR_FSTAT => errors.SQLITE_IOERR_FSTAT,
        ResultCode.SQLITE_IOERR_FSYNC => errors.SQLITE_IOERR_FSYNC,
        ResultCode.SQLITE_IOERR_GETTEMPPATH => errors.SQLITE_IOERR_GETTEMPPATH,
        ResultCode.SQLITE_IOERR_LOCK => errors.SQLITE_IOERR_LOCK,
        ResultCode.SQLITE_IOERR_MMAP => errors.SQLITE_IOERR_MMAP,
        ResultCode.SQLITE_IOERR_NOMEM => errors.SQLITE_IOERR_NOMEM,
        ResultCode.SQLITE_IOERR_RDLOCK => errors.SQLITE_IOERR_RDLOCK,
        ResultCode.SQLITE_IOERR_READ => errors.SQLITE_IOERR_READ,
        ResultCode.SQLITE_IOERR_ROLLBACK_ATOMIC => errors.SQLITE_IOERR_ROLLBACK_ATOMIC,
        ResultCode.SQLITE_IOERR_SEEK => errors.SQLITE_IOERR_SEEK,
        ResultCode.SQLITE_IOERR_SHMLOCK => errors.SQLITE_IOERR_SHMLOCK,
        ResultCode.SQLITE_IOERR_SHMMAP => errors.SQLITE_IOERR_SHMMAP,
        ResultCode.SQLITE_IOERR_SHMOPEN => errors.SQLITE_IOERR_SHMOPEN,
        ResultCode.SQLITE_IOERR_SHMSIZE => errors.SQLITE_IOERR_SHMSIZE,
        ResultCode.SQLITE_IOERR_SHORT_READ => errors.SQLITE_IOERR_SHORT_READ,
        ResultCode.SQLITE_IOERR_TRUNCATE => errors.SQLITE_IOERR_TRUNCATE,
        ResultCode.SQLITE_IOERR_UNLOCK => errors.SQLITE_IOERR_UNLOCK,
        ResultCode.SQLITE_IOERR_VNODE => errors.SQLITE_IOERR_VNODE,
        ResultCode.SQLITE_IOERR_WRITE => errors.SQLITE_IOERR_WRITE,
        ResultCode.SQLITE_LOCKED_SHAREDCACHE => errors.SQLITE_LOCKED_SHAREDCACHE,
        ResultCode.SQLITE_LOCKED_VTAB => errors.SQLITE_LOCKED_VTAB,
        ResultCode.SQLITE_NOTICE_RECOVER_ROLLBACK => errors.SQLITE_NOTICE_RECOVER_ROLLBACK,
        ResultCode.SQLITE_NOTICE_RECOVER_WAL => errors.SQLITE_NOTICE_RECOVER_WAL,
        ResultCode.SQLITE_OK_LOAD_PERMANENTLY => errors.SQLITE_OK_LOAD_PERMANENTLY,
        ResultCode.SQLITE_READONLY_CANTINIT => errors.SQLITE_READONLY_CANTINIT,
        ResultCode.SQLITE_READONLY_CANTLOCK => errors.SQLITE_READONLY_CANTLOCK,
        ResultCode.SQLITE_READONLY_DBMOVED => errors.SQLITE_READONLY_DBMOVED,
        ResultCode.SQLITE_READONLY_DIRECTORY => errors.SQLITE_READONLY_DIRECTORY,
        ResultCode.SQLITE_READONLY_RECOVERY => errors.SQLITE_READONLY_RECOVERY,
        ResultCode.SQLITE_READONLY_ROLLBACK => errors.SQLITE_READONLY_ROLLBACK,
        ResultCode.SQLITE_WARNING_AUTOINDEX => errors.SQLITE_WARNING_AUTOINDEX,
    };
}

/// Open and return a pointer to a sqlite database or return an error if a
/// database pointer cannot be opened for some reason.
pub fn open(filename: [:0]const u8) !*DataBase {
    var db_optional: ?*DataBase = null;
    var rc: c_int = 0;

    rc = c.sqlite3_open(filename.ptr, &db_optional);
    errdefer close(db_optional) catch unreachable;
    _ = try checkReturnCode(db_optional, rc);

    // Enable extended error codes
    rc = c.sqlite3_extended_result_codes(db_optional, 1);
    _ = try checkReturnCode(db_optional, rc);

    if (db_optional) |db| {
        return db;
    } else {
        std.debug.print("SQLite did not indicate an error, but db_optional is still null: {any}\n", .{db_optional});
        unreachable;
    }
}

/// Close and free a pointer to a sqlite database or return an error if the
/// given database pointer cannot be closed for some reason.
pub fn close(db: ?*DataBase) !void {
    const rc = c.sqlite3_close(db);
    _ = try checkReturnCode(db, rc);
}

pub fn exec(db: *DataBase, stmt: [:0]const u8) !void {
    const rc = c.sqlite3_exec(db, stmt.ptr, null, null, null);
    _ = try checkReturnCode(db, rc);
}

/// Prepare a sql statement
pub fn prepare(db: ?*DataBase, stmt: [:0]const u8) !*PreparedStatement {
    var stmt_opt: ?*PreparedStatement = null;

    const rc = c.sqlite3_prepare_v2(db, stmt.ptr, @intCast(stmt.len + 1), &stmt_opt, null);
    _ = try checkReturnCode(db, rc);

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
pub fn bind(stmt: *PreparedStatement, index: u16, value: anytype) !void {
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
            std.debug.print("Not given a type that can be bound to SQLite: {any}\n", .{@TypeOf(value)});
            @compileError("Not given a type that can be bound to SQLite");
        },
    };

    _ = try checkReturnCode(null, rc);
}

/// Return all result codes except `SQLITE_DONE`
pub fn step(stmt: *PreparedStatement) !ResultCode {
    const code: ResultCode = @enumFromInt(c.sqlite3_step(stmt));

    if (code == ResultCode.SQLITE_DONE) {
        _ = try checkReturnCode(null, c.sqlite3_clear_bindings(stmt));
        _ = try checkReturnCode(null, c.sqlite3_reset(stmt));

        return error.StopIteration;
    } else {
        return try checkReturnCode(null, @intFromEnum(code));
    }
}

pub fn bind_text(stmt: *PreparedStatement, index: u16, value: [:0]const u8) !void {
    // Using text64 should make it so that we don't need to do any casting
    // to pass the len of the slice. Since it is null terminated, we add
    // one to the len for the null terminator. Using `c.SQLITE_TRANSIENT`
    // ensures that SQLite makes a its own copy of the string before returning
    // from the function.
    const rc = c.sqlite3_bind_text64(stmt, index, value.ptr, value.len + 1, c.SQLITE_TRANSIENT, c.SQLITE_UTF8);

    _ = try checkReturnCode(null, rc);
}

/// Finalize (i.e. "free") a prepared sql statement
pub fn finalize(stmt_opt: ?*PreparedStatement) !void {
    const rc = c.sqlite3_finalize(stmt_opt);
    _ = try checkReturnCode(null, rc);
}

test "sqlite3.h include" {
    std.debug.print("What is the value of SQLITE_OK? {any}\n", .{c.SQLITE_OK});
    try std.testing.expectEqual(0, c.SQLITE_OK);
    // var list = std.ArrayList(i32).init(std.testing.allocator);
    // defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    // try list.append(42);
    // try std.testing.expectEqual(@as(i32, 42), list.pop());
}