const std = @import("std");
const c = @import("c.zig");

const log = std.log.scoped(.libsqlite);

pub const SqliteError = @TypeOf(errors.SQLITE_ERROR);

pub const DataBase = struct {
    db: *c.sqlite3,

    /// Open and return a sqlite database or return an error if a database
    /// cannot be opened for some reason.
    pub fn open(filename: [:0]const u8) !DataBase {
        var db_optional: ?*c.sqlite3 = null;
        var rc: c_int = 0;

        const flags: c_int = c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_URI;

        rc = c.sqlite3_open_v2(filename.ptr, &db_optional, flags, null);
        errdefer if (db_optional) |db| DataBase.close(.{ .db = db }) catch unreachable;
        _ = try ResultCode.fromInt(rc).check(if (db_optional) |db| .{ .db = db } else null);

        // Enable extended error codes
        if (db_optional) |db| {
            const self: DataBase = .{ .db = db };
            rc = c.sqlite3_extended_result_codes(self.db, 1);
            _ = try ResultCode.fromInt(rc).check(self);

            // For Havarti, we almost always want to default these pragmas to
            // the values below.
            try self.exec("PRAGMA foreign_keys = true;");
            try self.exec("PRAGMA ignore_check_constraints = false;");
            try self.exec("PRAGMA automatic_index = true;");

            return self;
        } else {
            std.debug.panic("SQLite did not indicate an error, but db_optional is still null when opening file: {s}\n", .{filename});
        }
    }

    /// Close and free a sqlite database or return an error if the given database
    /// cannot be closed for some reason.
    pub fn close(db: DataBase) !void {
        const rc = c.sqlite3_close(db.db);
        _ = try ResultCode.fromInt(rc).check(db);
    }

    pub fn exec(db: DataBase, stmt: [:0]const u8) !void {
        const rc = c.sqlite3_exec(db.db, stmt.ptr, null, null, null);
        _ = try ResultCode.fromInt(rc).check(db);
    }
};

pub const Statement = struct {
    db: DataBase,
    stmt: *c.sqlite3_stmt,

    /// Prepare a sql statement. `finalize` must eventually be called or a
    /// resources will be leaked.
    pub fn prepare(db: DataBase, stmt: [:0]const u8) !Statement {
        var stmt_opt: ?*c.sqlite3_stmt = null;

        const rc = c.sqlite3_prepare_v2(db.db, stmt.ptr, @intCast(stmt.len + 1), &stmt_opt, null);
        _ = try ResultCode.fromInt(rc).check(db);

        if (stmt_opt) |stmt_ptr| {
            return .{ .stmt = stmt_ptr, .db = db };
        } else {
            std.debug.panic("SQLite did not indicate an error, but stmt_opt is still null: {s}\n", .{stmt});
        }
    }

    /// Finalize (i.e. "free") a prepared sql statement
    pub fn finalize(stmt: Statement) !void {
        const rc = c.sqlite3_finalize(stmt.stmt);
        _ = try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn clear_bindings(stmt: Statement) !void {
        _ = try ResultCode.fromInt(c.sqlite3_clear_bindings(stmt.stmt)).check(stmt.db);
    }

    pub fn reset(stmt: Statement) !void {
        _ = try ResultCode.fromInt(c.sqlite3_reset(stmt.stmt)).check(stmt.db);
    }

    /// Return all result codes except `SQLITE_DONE`. When `SQLITE_DONE` is
    /// encountered, `null` is returned instead. If an error is returned,
    /// unless the return code is checked and the while loop broken, it is
    /// possible to get into an infinite loop. See `auto_step` for a simple
    /// example of how to check for errors in the return code.
    pub fn step(stmt: Statement) ?ResultCode {
        const code = ResultCode.fromInt(c.sqlite3_step(stmt.stmt));
        return if (code == ResultCode.SQLITE_DONE) null else code;
    }

    /// Step through all returned rows automatically. Useful for when a
    /// statement does not return any rows or when we don't care about any
    /// returned results. Similar to `DataBase.exec` except prepared Statements
    /// objects can only execute one statement, instead of several, and also
    /// parameters can be bound before stepping through results, unlike `exec`.
    pub fn auto_step(stmt: Statement) !void {
        while (stmt.step()) |rc| {
            _ = try rc.check(stmt.db);
        }
    }

    /// Bind `null` to a parameter index
    pub fn bind_null(stmt: Statement, index: u16) !void {
        const rc = c.sqlite3_bind_null(stmt.stmt, index);
        _ = try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn bind_float(stmt: Statement, index: u16, value: f64) !void {
        const rc = c.sqlite3_bind_double(stmt.stmt, index, value);
        _ = try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn bind_int(stmt: Statement, index: u16, value: anytype) !void {
        const rc = c.sqlite3_bind_int64(stmt.stmt, index, value);
        _ = try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn bind_text(stmt: Statement, index: u16, value_opt: ?[:0]const u8) !void {
        // Using text64 should make it so that we don't need to do any casting
        // to pass the len of the slice. Since it is null terminated, we add
        // one to the len for the null sentinel. Using `c.SQLITE_TRANSIENT`
        // ensures that SQLite makes its own copy of the string before
        // returning from the function. SQLite will manage the lifetime of its
        // private copy.
        const rc = blk: {
            if (value_opt) |value| {
                break :blk c.sqlite3_bind_text64(stmt.stmt, index, value.ptr, value.len + 1, c.SQLITE_TRANSIENT, c.SQLITE_UTF8);
            } else {
                break :blk c.sqlite3_bind_null(stmt.stmt, index);
            }
        };
        _ = try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn bind_blob(stmt: Statement, index: u16, value_opt: ?[]const u8) !void {
        // Using blob64 should make it so that we don't need to do any casting
        // to pass the len of the slice. Using `c.SQLITE_TRANSIENT` ensures that
        // SQLite makes a its own copy of the blob before returning from the
        // function. SQLite will manage the lifetime of its private copy.
        const rc = blk: {
            if (value_opt) |value| {
                break :blk c.sqlite3_bind_blob64(stmt.stmt, index, value.ptr, value.len, c.SQLITE_TRANSIENT);
            } else {
                break :blk c.sqlite3_bind_null(stmt.stmt, index);
            }
        };
        _ = try ResultCode.fromInt(rc).check(stmt.db);
    }

    /// Use comptime magic to bind parameters for SQLite prepared statements based
    /// on the type passed in. This can't stop the caller from making the mistake
    /// of binding values of the incorrect type to parameter indices. See docs here
    /// for the bind interface: https://www.sqlite.org/c3ref/bind_blob.html
    pub fn bind(stmt: Statement, index: u16, value: anytype) !void {
        // TODO: use @typeInfo builtin to make this logic more robust for optionals, ints, etc.
        switch (@TypeOf(value)) {
            @TypeOf(null) => try stmt.bind_null(index),
            f16, f32, f64, comptime_float => try stmt.bind_float(index, value),
            u8, i8, u16, i16, i32, u32, i64, comptime_int => try stmt.bind_int(index, value),

            [:0]u8, [:0]const u8, ?[:0]u8, ?[:0]const u8 => try stmt.bind_text(index, value),

            // A slice without without a null sentinel is treated as a binary blob.
            []u8, []const u8, ?[]u8, ?[]const u8 => try stmt.bind_blob(index, value),

            else => @compileError("Cannot bind type: " ++ @typeName(@TypeOf(value))),
        }
    }
};

pub const Savepoint = struct {
    const _begin_fmt = "SAVEPOINT {s};";
    const _commit_fmt = "RELEASE SAVEPOINT {s};";
    const _rollback_fmt = "ROLLBACK TO SAVEPOINT {s};";
    const _max_fmt_sz = @max(@max(_begin_fmt.len, _commit_fmt.len), _rollback_fmt.len);

    const Self = @This();
    const default_name = "default_savepoint_name";
    const buf_sz = 128;

    db: DataBase,
    name: [:0]const u8,

    /// Creates an (optionally) named transaction. This does not use parameter
    /// binding or escaping, so the name should be a valid SQLite identifier.
    pub fn init(db: DataBase, name: ?[:0]const u8) !Savepoint {
        const self: Savepoint = .{ .db = db, .name = name orelse default_name };

        // Add 1 for the sentinel `0` value in the cstring.
        if (self.name.len + _max_fmt_sz + 1 > buf_sz) return error.NameTooLong;

        // Attempt to check if the name is a keyword.
        const rc = c.sqlite3_keyword_check(self.name.ptr, 0);
        _ = try ResultCode.fromInt(rc).check(self.db);

        // XXX: We add extra spaces at the end to ensure that if the name fails
        // because it is too long, it will fail now (before executing anything)
        // instead of failing later when attempting to rollback a bad
        // statement, or commit a good statement.
        var stmt_buf: [buf_sz]u8 = undefined;
        const trans_stmt = try std.fmt.bufPrintZ(&stmt_buf, _begin_fmt, .{self.name});

        try self.db.exec(trans_stmt);
        return self;
    }

    pub fn commit(self: *const Self) !void {
        var stmt_buf: [buf_sz]u8 = undefined;
        const trans_stmt = try std.fmt.bufPrintZ(&stmt_buf, _commit_fmt, .{self.name});
        self.db.exec(trans_stmt) catch |err| {
            log.err("Savepoint '{s}' commit failed: {any}\n", .{ self.name, err });
            return err;
        };
    }

    pub fn rollback(self: *const Self) !void {
        var stmt_buf: [buf_sz]u8 = undefined;
        const trans_stmt = try std.fmt.bufPrintZ(&stmt_buf, _rollback_fmt, .{self.name});
        self.db.exec(trans_stmt) catch |err| {
            log.err("Savepoint '{s}' rollback failed: {any}\n", .{ self.name, err });
            return err;
        };
    }
};

pub const Transaction = struct {
    const _begin_stmt = "BEGIN TRANSACTION;";
    const _commit_stmt = "COMMIT TRANSACTION;";
    const _rollback_stmt = "ROLLBACK TRANSACTION;";

    const Self = @This();
    const default_name = "default_transaction_name";
    const buf_sz = 128;

    db: DataBase,
    name: [:0]const u8,

    /// Creates an (optionally) named transaction. This does not use parameter
    /// binding or escaping, so the name should be a valid SQLite identifier.
    pub fn init(db: DataBase, name: ?[:0]const u8) !Transaction {
        const self: Transaction = .{ .db = db, .name = name orelse default_name };

        try self.db.exec(_begin_stmt);
        return self;
    }

    pub fn commit(self: *const Self) !void {
        self.db.exec(_commit_stmt) catch |err| {
            log.err("Transaction '{s}' commit failed: {any}\n", .{ self.name, err });
            return err;
        };
    }

    pub fn rollback(self: *const Self) !void {
        self.db.exec(_rollback_stmt) catch |err| {
            log.err("Transaction '{s}' rollback failed: {any}\n", .{ self.name, err });
            return err;
        };
    }

    pub fn createSavepoint(self: *const Self, name: [:0]const u8) !Savepoint {
        return try Savepoint.init(self.db, name);
    }
};

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

    pub fn check(code: ResultCode, db_optional: ?DataBase) !ResultCode {
        return if (code.toError()) |err| {
            // How to retrieve SQLite error codes: https://www.sqlite.org/c3ref/errcode.html
            log.err("SQLite returned code '{s}' ({d}) with message: '{s}'\n", .{ @errorName(err), code.toInt(), c.sqlite3_errstr(code.toInt()) });
            if (db_optional) |db| {
                log.err("SQLite message for non-null DB pointer: '{s}'\n", .{c.sqlite3_errmsg(db.db)});
            }

            return err;
        } else {
            return code;
        };
    }

    pub inline fn fromInt(int: anytype) ResultCode {
        return @enumFromInt(int);
    }

    pub inline fn toInt(code: ResultCode) c_int {
        return @intFromEnum(code);
    }

    pub fn fromError(err: SqliteError) ResultCode {
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

    pub fn toError(code: ResultCode) ?SqliteError {
        return switch (code) {
            // non-error result codes
            ResultCode.SQLITE_OK, ResultCode.SQLITE_DONE, ResultCode.SQLITE_ROW => null,

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
};

test "sqlite3.h include" {
    // std.debug.print("What is the value of SQLITE_OK? {any}\n", .{c.SQLITE_OK});
    try std.testing.expectEqual(0, c.SQLITE_OK);
}
