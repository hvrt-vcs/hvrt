const std = @import("std");
const c = @import("c.zig").cnamespace;

const log = std.log.scoped(.libsqlite);

pub const SqliteError = @TypeOf(Error.SQLITE_ERROR);

pub const DataBase = struct {
    db: *c.sqlite3,

    /// Direct mapping to Sqlite3 open flags.
    ///
    /// See Sqlite3 docs here: https://sqlite.org/c3ref/c_open_autoproxy.html
    ///
    /// This is a non-exhaustive enum, so values other than those explicitly
    /// defined can be used by casting with the @enumFromInt builtin function.
    pub const OpenFlags = enum(c_int) {
        readonly = c.SQLITE_OPEN_READONLY,
        readwrite = c.SQLITE_OPEN_READWRITE,
        create = c.SQLITE_OPEN_CREATE,
        uri = c.SQLITE_OPEN_URI,
        memory = c.SQLITE_OPEN_MEMORY,
        nomutex = c.SQLITE_OPEN_NOMUTEX,
        fullmutex = c.SQLITE_OPEN_FULLMUTEX,
        sharedcache = c.SQLITE_OPEN_SHAREDCACHE,
        privatecache = c.SQLITE_OPEN_PRIVATECACHE,
        nofollow = c.SQLITE_OPEN_NOFOLLOW,

        /// Extended result codes
        exrescode = c.SQLITE_OPEN_EXRESCODE,
        _,
    };

    /// Roughly based on open options from the following docs:
    /// https://sqlite.org/c3ref/open.html
    pub const Options = struct {
        /// Bit flags to pass to `sqlite3_open_v2`.
        flags: []const OpenFlags = &.{
            .readonly,
            .uri,
            .exrescode,
        },

        /// String name for a previously registered Sqlite VFS module.
        /// Optional.
        zVfs: ?[:0]const u8 = null,

        /// Set some default pragmas upon opening, such as enforcing
        /// `foreign_keys` by default. You can set this to `false` if you
        /// prefer full control over the database configuration. See the source
        /// code to inspect what pragmas are run by default.
        default_pragmas: bool = true,
    };

    /// Open and return a sqlite database or return an error if a database
    /// cannot be opened for some reason.
    pub fn open(filename: [:0]const u8, options: Options) !DataBase {
        var flags: c_int = 0;
        for (options.flags) |f| {
            flags |= @intFromEnum(f);
        }

        const zVfs = if (options.zVfs) |zVfs_slice| zVfs_slice.ptr else null;

        var db_optional: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open_v2(filename.ptr, &db_optional, flags, zVfs);
        errdefer if (db_optional) |db| DataBase.close(.{ .db = db }) catch unreachable; // NO_COV_LINE
        try ResultCode.fromInt(rc).check(if (db_optional) |db| .{ .db = db } else null);

        if (db_optional) |db| {
            const self: DataBase = .{ .db = db };

            if (options.default_pragmas) {
                // For Havarti, we almost always want to default these pragmas
                // to the values below.
                try self.exec("PRAGMA foreign_keys = true;");
                try self.exec("PRAGMA ignore_check_constraints = false;");
                try self.exec("PRAGMA automatic_index = true;");
            }

            return self;
        } else {
            std.debug.panic("SQLite did not indicate an error, but db_optional is still null when opening file: {s}\n", .{filename}); // NO_COV_LINE
        }
    }

    /// Close and free a sqlite database or return an error if the given database
    /// cannot be closed for some reason.
    pub fn close(db: DataBase) !void {
        const rc = c.sqlite3_close(db.db);
        try ResultCode.fromInt(rc).check(db);
    }

    pub fn exec(db: DataBase, stmt: [:0]const u8) !void {
        const rc = c.sqlite3_exec(db.db, stmt.ptr, null, null, null);
        try ResultCode.fromInt(rc).check(db);
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
        try ResultCode.fromInt(rc).check(db);

        if (stmt_opt) |stmt_ptr| {
            return .{ .stmt = stmt_ptr, .db = db };
        } else {
            std.debug.panic("SQLite did not indicate an error, but stmt_opt is still null: {s}\n", .{stmt}); // NO_COV_LINE
        }
    }

    /// Finalize (i.e. "free") a prepared sql statement
    pub fn finalize(stmt: Statement) !void {
        const rc = c.sqlite3_finalize(stmt.stmt);
        try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn clear_bindings(stmt: Statement) !void {
        const rc = c.sqlite3_clear_bindings(stmt.stmt);
        try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn reset(stmt: Statement) !void {
        const rc = c.sqlite3_reset(stmt.stmt);
        try ResultCode.fromInt(rc).check(stmt.db);
    }

    /// Return all result codes except `SQLITE_DONE`. When `SQLITE_DONE` is
    /// encountered, `null` is returned instead. If an error is returned,
    /// unless the return code is checked and the while loop broken, it is
    /// possible to get into an infinite loop. See `auto_step` for a simple
    /// example of how to check for errors in the return code.
    pub fn step(stmt: Statement) Error!?ResultCode {
        const rc = c.sqlite3_step(stmt.stmt);
        const code = ResultCode.fromInt(rc);
        try code.check(stmt.db);
        return if (code == ResultCode.SQLITE_DONE) null else code;
    }

    /// Step through all returned rows automatically. Useful for when a
    /// statement does not return any rows or when we don't care about any
    /// returned results. Similar to `DataBase.exec` except prepared Statements
    /// objects can only execute one statement, instead of several, and also
    /// parameters can be bound before stepping through results, unlike `exec`.
    pub fn auto_step(stmt: Statement) !void {
        while (try stmt.step()) |_| {}
    }

    /// Bind `null` to a parameter index
    pub fn bind_null(stmt: Statement, index: u16) !void {
        const rc = c.sqlite3_bind_null(stmt.stmt, index);
        try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn bind_float(stmt: Statement, index: u16, value: f64) !void {
        const rc = c.sqlite3_bind_double(stmt.stmt, index, value);
        try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn bind_int(stmt: Statement, index: u16, value: i64) !void {
        const rc = c.sqlite3_bind_int64(stmt.stmt, index, value);
        try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn bind_text(stmt: Statement, index: u16, mem_copy: bool, value_opt: ?[:0]const u8) !void {
        // Using text64 should make it so that we don't need to do any casting
        // to pass the len of the slice. Since it is null terminated, we add
        // one to the len for the null sentinel. Using `c.SQLITE_TRANSIENT`
        // ensures that SQLite makes its own copy of the string before
        // returning from the function. SQLite will manage the lifetime of its
        // private copy.
        const rc = blk: {
            if (value_opt) |value| {
                break :blk c.sqlite3_bind_text64(
                    stmt.stmt,
                    index,
                    value.ptr,
                    value.len,
                    (if (mem_copy) c.sqliteTransientAsDestructor() else c.SQLITE_STATIC),
                    c.SQLITE_UTF8,
                );
            } else {
                break :blk c.sqlite3_bind_null(stmt.stmt, index);
            }
        };
        try ResultCode.fromInt(rc).check(stmt.db);
    }

    pub fn bind_blob(stmt: Statement, index: u16, mem_copy: bool, value_opt: ?[]const u8) !void {
        // Using blob64 should make it so that we don't need to do any casting
        // to pass the len of the slice. Using `c.SQLITE_TRANSIENT` ensures that
        // SQLite makes a its own copy of the blob before returning from the
        // function. SQLite will manage the lifetime of its private copy.
        const rc = blk: {
            if (value_opt) |value| {
                break :blk c.sqlite3_bind_blob64(
                    stmt.stmt,
                    index,
                    value.ptr,
                    value.len,
                    (if (mem_copy) c.sqliteTransientAsDestructor() else c.SQLITE_STATIC),
                );
            } else {
                break :blk c.sqlite3_bind_null(stmt.stmt, index);
            }
        };
        try ResultCode.fromInt(rc).check(stmt.db);
    }

    /// Use comptime magic to bind parameters for SQLite prepared statements based
    /// on the type passed in. This can't stop the caller from making the mistake
    /// of binding values of the incorrect type to parameter indices. See docs here
    /// for the bind interface: https://www.sqlite.org/c3ref/bind_blob.html
    pub fn bind(stmt: Statement, index: u16, mem_copy: bool, value: anytype) !void {
        // TODO: use @typeInfo builtin to make this logic more robust for optionals, ints, etc.
        switch (@TypeOf(value)) {
            @TypeOf(null) => try stmt.bind_null(index),
            f16, f32, f64, comptime_float => try stmt.bind_float(index, value),
            u8, i8, u16, i16, i32, u32, i64, comptime_int => try stmt.bind_int(index, value),

            [:0]u8, [:0]const u8, ?[:0]u8, ?[:0]const u8 => try stmt.bind_text(index, mem_copy, value),

            // A slice without without a null sentinel is treated as a binary blob.
            []u8, []const u8, ?[]u8, ?[]const u8 => try stmt.bind_blob(index, mem_copy, value),

            else => @compileError("Cannot bind type: " ++ @typeName(@TypeOf(value))),
        }
    }

    pub fn column_f64(stmt: Statement, index: u16) f64 {
        return c.sqlite3_column_double(stmt.stmt, index);
    }

    pub fn column_i32(stmt: Statement, index: u16) i32 {
        return c.sqlite3_column_int(stmt.stmt, index);
    }

    pub fn column_i64(stmt: Statement, index: u16) i64 {
        return c.sqlite3_column_int64(stmt.stmt, index);
    }

    // According to SQLite3 docs : "The pointers returned are valid until a
    // type conversion occurs as described above, or until sqlite3_step() or
    // sqlite3_reset() or sqlite3_finalize() is called. The memory space used
    // to hold strings and BLOBs is freed automatically."
    //
    // Thus, returned slice is only guaranteed valid until one of the above
    // states occurs.
    pub fn column_text(stmt: Statement, index: u16) ?[:0]const u8 {
        const text_ptr = @as(?[*:0]const u8, c.sqlite3_column_text(stmt.stmt, index)) orelse return null;
        const text_size: i64 = c.sqlite3_column_bytes(stmt.stmt, index);
        std.debug.assert(text_size > 0);
        const coerced_size = @as(usize, @intCast(text_size));
        return text_ptr[0..coerced_size :0];
    }

    // According to SQLite3 docs : "The pointers returned are valid until a
    // type conversion occurs as described above, or until sqlite3_step() or
    // sqlite3_reset() or sqlite3_finalize() is called. The memory space used
    // to hold strings and BLOBs is freed automatically."
    //
    // Thus, returned slice is only guaranteed valid until one of the above
    // states occurs.
    pub fn column_blob(stmt: Statement, index: u16) ?[]const u8 {
        const blob_ptr = @as(?[*]const u8, @ptrCast(c.sqlite3_column_blob(stmt.stmt, index))) orelse return null;
        const blob_size: i64 = c.sqlite3_column_bytes(stmt.stmt, index);
        std.debug.assert(blob_size > 0);
        const coerced_size = @as(usize, @intCast(blob_size));
        return blob_ptr[0..coerced_size];
    }

    // Retrieve column value based on a comptime known return type:
    // https://www.sqlite.org/c3ref/column_blob.html
    pub fn column(stmt: Statement, comptime return_type: type, index: u16) !return_type {
        return switch (return_type) {
            f64 => try stmt.column_float(index),
            i32 => try stmt.column_i32(index),
            i64 => try stmt.column_i64(index),

            ?[:0]const u8 => try stmt.column_text(index),

            // A slice without without a null sentinel is treated as a binary blob.
            ?[]const u8 => try stmt.column_blob(index),

            else => @compileError("Cannot bind type: " ++ @typeName(return_type)),
        };
    }
};

pub const Savepoint = struct {
    const begin_fmt = "SAVEPOINT {s};";
    const commit_fmt = "RELEASE SAVEPOINT {s};";
    const rollback_fmt = "ROLLBACK TO SAVEPOINT {s};";
    const max_fmt_sz = @max(begin_fmt.len, commit_fmt.len, rollback_fmt.len);

    const Self = @This();
    const default_name = "default_savepoint_name";
    const buf_sz = 128;

    db: DataBase,
    name: [:0]const u8,

    /// Creates an (optionally) named transaction. This does not use parameter
    /// binding or escaping, so the name should be a valid SQLite identifier.
    pub fn init(db: DataBase, name: ?[:0]const u8) !Savepoint {
        const self: Savepoint = .{ .db = db, .name = name orelse default_name };

        if (self.name.len == 0) return error.NameTooShort;

        // Add 1 for the sentinel `0` value in the cstring.
        if (self.name.len + max_fmt_sz + 1 > buf_sz) return error.NameTooLong;

        // Name length check above already caught any values larger than a c_int,
        // so this cast is safe at this point.
        const len_cast: c_int = @intCast(self.name.len);

        // Attempt to check if the name is a keyword.
        const rc = c.sqlite3_keyword_check(self.name.ptr, len_cast);
        const name_is_keyword = rc != 0;
        if (name_is_keyword) {
            log.err("Name '{s}' is a SQLite keyword and cannot be used for a savepoint name.\n", .{self.name});
            return error.NameIsKeyword;
        }

        // XXX: We add extra spaces at the end to ensure that if the name fails
        // because it is too long, it will fail now (before executing anything)
        // instead of failing later when attempting to rollback a bad
        // statement, or commit a good statement.
        var stmt_buf: [buf_sz]u8 = undefined;
        const trans_stmt = try std.fmt.bufPrintZ(&stmt_buf, begin_fmt, .{self.name});

        try self.db.exec(trans_stmt);
        return self;
    }

    pub fn commit(self: *const Self) !void {
        var stmt_buf: [buf_sz]u8 = undefined;
        const trans_stmt = try std.fmt.bufPrintZ(&stmt_buf, commit_fmt, .{self.name});
        self.db.exec(trans_stmt) catch |err| {
            log.err("Savepoint '{s}' commit failed: {any}\n", .{ self.name, err });
            return err;
        };
    }

    pub fn rollback(self: *const Self) !void {
        var stmt_buf: [buf_sz]u8 = undefined;
        const trans_stmt = try std.fmt.bufPrintZ(&stmt_buf, rollback_fmt, .{self.name});
        self.db.exec(trans_stmt) catch |err| {
            log.err("Savepoint '{s}' rollback failed: {any}\n", .{ self.name, err });
            return err;
        };
    }
};

pub const Transaction = struct {
    const begin_stmt = "BEGIN TRANSACTION;";
    const commit_stmt = "COMMIT TRANSACTION;";
    const rollback_stmt = "ROLLBACK TRANSACTION;";

    const Self = @This();
    const default_name = "default_transaction_name";

    db: DataBase,
    name: [:0]const u8,

    /// Creates a transaction. This does not use parameter binding or escaping.
    /// The name is only used for logging.
    pub fn init(db: DataBase, name: ?[:0]const u8) !Transaction {
        const self: Transaction = .{ .db = db, .name = name orelse default_name };

        try self.db.exec(begin_stmt);
        return self;
    }

    pub fn commit(self: *const Self) !void {
        self.db.exec(commit_stmt) catch |err| {
            log.err("Transaction '{s}' commit failed: {any}\n", .{ self.name, err });
            return err;
        };
    }

    pub fn rollback(self: *const Self) !void {
        self.db.exec(rollback_stmt) catch |err| {
            log.err("Transaction '{s}' rollback failed: {any}\n", .{ self.name, err });
            return err;
        };
    }

    pub fn createSavepoint(self: *const Self, name: [:0]const u8) !Savepoint {
        return try Savepoint.init(self.db, name);
    }
};

/// All SQLite error codes as Zig errors
pub const Error = error{
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

    /// Return an error if the given ResultCode is an error.
    pub fn check(code: ResultCode, db_optional: ?DataBase) Error!void {
        if (code.toError()) |err| {
            // How to retrieve SQLite error codes: https://www.sqlite.org/c3ref/errcode.html
            log.err("SQLite returned code '{s}' ({d}) with message: '{s}'\n", .{ @errorName(err), code.toInt(), c.sqlite3_errstr(code.toInt()) });
            if (db_optional) |db| {
                log.err("SQLite message for non-null DB pointer: '{s}'\n", .{c.sqlite3_errmsg(db.db)});
            }

            return err;
        }
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
            Error.SQLITE_ABORT => ResultCode.SQLITE_ABORT,
            Error.SQLITE_AUTH => ResultCode.SQLITE_AUTH,
            Error.SQLITE_BUSY => ResultCode.SQLITE_BUSY,
            Error.SQLITE_CANTOPEN => ResultCode.SQLITE_CANTOPEN,
            Error.SQLITE_CONSTRAINT => ResultCode.SQLITE_CONSTRAINT,
            Error.SQLITE_CORRUPT => ResultCode.SQLITE_CORRUPT,
            Error.SQLITE_EMPTY => ResultCode.SQLITE_EMPTY,
            Error.SQLITE_ERROR => ResultCode.SQLITE_ERROR,
            Error.SQLITE_FORMAT => ResultCode.SQLITE_FORMAT,
            Error.SQLITE_FULL => ResultCode.SQLITE_FULL,
            Error.SQLITE_INTERNAL => ResultCode.SQLITE_INTERNAL,
            Error.SQLITE_INTERRUPT => ResultCode.SQLITE_INTERRUPT,
            Error.SQLITE_IOERR => ResultCode.SQLITE_IOERR,
            Error.SQLITE_LOCKED => ResultCode.SQLITE_LOCKED,
            Error.SQLITE_MISMATCH => ResultCode.SQLITE_MISMATCH,
            Error.SQLITE_MISUSE => ResultCode.SQLITE_MISUSE,
            Error.SQLITE_NOLFS => ResultCode.SQLITE_NOLFS,
            Error.SQLITE_NOMEM => ResultCode.SQLITE_NOMEM,
            Error.SQLITE_NOTADB => ResultCode.SQLITE_NOTADB,
            Error.SQLITE_NOTFOUND => ResultCode.SQLITE_NOTFOUND,
            Error.SQLITE_NOTICE => ResultCode.SQLITE_NOTICE,
            Error.SQLITE_PERM => ResultCode.SQLITE_PERM,
            Error.SQLITE_PROTOCOL => ResultCode.SQLITE_PROTOCOL,
            Error.SQLITE_RANGE => ResultCode.SQLITE_RANGE,
            Error.SQLITE_READONLY => ResultCode.SQLITE_READONLY,
            Error.SQLITE_SCHEMA => ResultCode.SQLITE_SCHEMA,
            Error.SQLITE_TOOBIG => ResultCode.SQLITE_TOOBIG,
            Error.SQLITE_WARNING => ResultCode.SQLITE_WARNING,

            // Extended codes
            Error.SQLITE_ABORT_ROLLBACK => ResultCode.SQLITE_ABORT_ROLLBACK,
            Error.SQLITE_AUTH_USER => ResultCode.SQLITE_AUTH_USER,
            Error.SQLITE_BUSY_RECOVERY => ResultCode.SQLITE_BUSY_RECOVERY,
            Error.SQLITE_BUSY_SNAPSHOT => ResultCode.SQLITE_BUSY_SNAPSHOT,
            Error.SQLITE_BUSY_TIMEOUT => ResultCode.SQLITE_BUSY_TIMEOUT,
            Error.SQLITE_CANTOPEN_CONVPATH => ResultCode.SQLITE_CANTOPEN_CONVPATH,
            Error.SQLITE_CANTOPEN_DIRTYWAL => ResultCode.SQLITE_CANTOPEN_DIRTYWAL,
            Error.SQLITE_CANTOPEN_FULLPATH => ResultCode.SQLITE_CANTOPEN_FULLPATH,
            Error.SQLITE_CANTOPEN_ISDIR => ResultCode.SQLITE_CANTOPEN_ISDIR,
            Error.SQLITE_CANTOPEN_NOTEMPDIR => ResultCode.SQLITE_CANTOPEN_NOTEMPDIR,
            Error.SQLITE_CANTOPEN_SYMLINK => ResultCode.SQLITE_CANTOPEN_SYMLINK,
            Error.SQLITE_CONSTRAINT_CHECK => ResultCode.SQLITE_CONSTRAINT_CHECK,
            Error.SQLITE_CONSTRAINT_COMMITHOOK => ResultCode.SQLITE_CONSTRAINT_COMMITHOOK,
            Error.SQLITE_CONSTRAINT_DATATYPE => ResultCode.SQLITE_CONSTRAINT_DATATYPE,
            Error.SQLITE_CONSTRAINT_FOREIGNKEY => ResultCode.SQLITE_CONSTRAINT_FOREIGNKEY,
            Error.SQLITE_CONSTRAINT_FUNCTION => ResultCode.SQLITE_CONSTRAINT_FUNCTION,
            Error.SQLITE_CONSTRAINT_NOTNULL => ResultCode.SQLITE_CONSTRAINT_NOTNULL,
            Error.SQLITE_CONSTRAINT_PINNED => ResultCode.SQLITE_CONSTRAINT_PINNED,
            Error.SQLITE_CONSTRAINT_PRIMARYKEY => ResultCode.SQLITE_CONSTRAINT_PRIMARYKEY,
            Error.SQLITE_CONSTRAINT_ROWID => ResultCode.SQLITE_CONSTRAINT_ROWID,
            Error.SQLITE_CONSTRAINT_TRIGGER => ResultCode.SQLITE_CONSTRAINT_TRIGGER,
            Error.SQLITE_CONSTRAINT_UNIQUE => ResultCode.SQLITE_CONSTRAINT_UNIQUE,
            Error.SQLITE_CONSTRAINT_VTAB => ResultCode.SQLITE_CONSTRAINT_VTAB,
            Error.SQLITE_CORRUPT_INDEX => ResultCode.SQLITE_CORRUPT_INDEX,
            Error.SQLITE_CORRUPT_SEQUENCE => ResultCode.SQLITE_CORRUPT_SEQUENCE,
            Error.SQLITE_CORRUPT_VTAB => ResultCode.SQLITE_CORRUPT_VTAB,
            Error.SQLITE_ERROR_MISSING_COLLSEQ => ResultCode.SQLITE_ERROR_MISSING_COLLSEQ,
            Error.SQLITE_ERROR_RETRY => ResultCode.SQLITE_ERROR_RETRY,
            Error.SQLITE_ERROR_SNAPSHOT => ResultCode.SQLITE_ERROR_SNAPSHOT,
            Error.SQLITE_IOERR_ACCESS => ResultCode.SQLITE_IOERR_ACCESS,
            Error.SQLITE_IOERR_AUTH => ResultCode.SQLITE_IOERR_AUTH,
            Error.SQLITE_IOERR_BEGIN_ATOMIC => ResultCode.SQLITE_IOERR_BEGIN_ATOMIC,
            Error.SQLITE_IOERR_BLOCKED => ResultCode.SQLITE_IOERR_BLOCKED,
            Error.SQLITE_IOERR_CHECKRESERVEDLOCK => ResultCode.SQLITE_IOERR_CHECKRESERVEDLOCK,
            Error.SQLITE_IOERR_CLOSE => ResultCode.SQLITE_IOERR_CLOSE,
            Error.SQLITE_IOERR_COMMIT_ATOMIC => ResultCode.SQLITE_IOERR_COMMIT_ATOMIC,
            Error.SQLITE_IOERR_CONVPATH => ResultCode.SQLITE_IOERR_CONVPATH,
            Error.SQLITE_IOERR_CORRUPTFS => ResultCode.SQLITE_IOERR_CORRUPTFS,
            Error.SQLITE_IOERR_DATA => ResultCode.SQLITE_IOERR_DATA,
            Error.SQLITE_IOERR_DELETE => ResultCode.SQLITE_IOERR_DELETE,
            Error.SQLITE_IOERR_DELETE_NOENT => ResultCode.SQLITE_IOERR_DELETE_NOENT,
            Error.SQLITE_IOERR_DIR_CLOSE => ResultCode.SQLITE_IOERR_DIR_CLOSE,
            Error.SQLITE_IOERR_DIR_FSYNC => ResultCode.SQLITE_IOERR_DIR_FSYNC,
            Error.SQLITE_IOERR_FSTAT => ResultCode.SQLITE_IOERR_FSTAT,
            Error.SQLITE_IOERR_FSYNC => ResultCode.SQLITE_IOERR_FSYNC,
            Error.SQLITE_IOERR_GETTEMPPATH => ResultCode.SQLITE_IOERR_GETTEMPPATH,
            Error.SQLITE_IOERR_LOCK => ResultCode.SQLITE_IOERR_LOCK,
            Error.SQLITE_IOERR_MMAP => ResultCode.SQLITE_IOERR_MMAP,
            Error.SQLITE_IOERR_NOMEM => ResultCode.SQLITE_IOERR_NOMEM,
            Error.SQLITE_IOERR_RDLOCK => ResultCode.SQLITE_IOERR_RDLOCK,
            Error.SQLITE_IOERR_READ => ResultCode.SQLITE_IOERR_READ,
            Error.SQLITE_IOERR_ROLLBACK_ATOMIC => ResultCode.SQLITE_IOERR_ROLLBACK_ATOMIC,
            Error.SQLITE_IOERR_SEEK => ResultCode.SQLITE_IOERR_SEEK,
            Error.SQLITE_IOERR_SHMLOCK => ResultCode.SQLITE_IOERR_SHMLOCK,
            Error.SQLITE_IOERR_SHMMAP => ResultCode.SQLITE_IOERR_SHMMAP,
            Error.SQLITE_IOERR_SHMOPEN => ResultCode.SQLITE_IOERR_SHMOPEN,
            Error.SQLITE_IOERR_SHMSIZE => ResultCode.SQLITE_IOERR_SHMSIZE,
            Error.SQLITE_IOERR_SHORT_READ => ResultCode.SQLITE_IOERR_SHORT_READ,
            Error.SQLITE_IOERR_TRUNCATE => ResultCode.SQLITE_IOERR_TRUNCATE,
            Error.SQLITE_IOERR_UNLOCK => ResultCode.SQLITE_IOERR_UNLOCK,
            Error.SQLITE_IOERR_VNODE => ResultCode.SQLITE_IOERR_VNODE,
            Error.SQLITE_IOERR_WRITE => ResultCode.SQLITE_IOERR_WRITE,
            Error.SQLITE_LOCKED_SHAREDCACHE => ResultCode.SQLITE_LOCKED_SHAREDCACHE,
            Error.SQLITE_LOCKED_VTAB => ResultCode.SQLITE_LOCKED_VTAB,
            Error.SQLITE_NOTICE_RECOVER_ROLLBACK => ResultCode.SQLITE_NOTICE_RECOVER_ROLLBACK,
            Error.SQLITE_NOTICE_RECOVER_WAL => ResultCode.SQLITE_NOTICE_RECOVER_WAL,
            Error.SQLITE_OK_LOAD_PERMANENTLY => ResultCode.SQLITE_OK_LOAD_PERMANENTLY,
            Error.SQLITE_READONLY_CANTINIT => ResultCode.SQLITE_READONLY_CANTINIT,
            Error.SQLITE_READONLY_CANTLOCK => ResultCode.SQLITE_READONLY_CANTLOCK,
            Error.SQLITE_READONLY_DBMOVED => ResultCode.SQLITE_READONLY_DBMOVED,
            Error.SQLITE_READONLY_DIRECTORY => ResultCode.SQLITE_READONLY_DIRECTORY,
            Error.SQLITE_READONLY_RECOVERY => ResultCode.SQLITE_READONLY_RECOVERY,
            Error.SQLITE_READONLY_ROLLBACK => ResultCode.SQLITE_READONLY_ROLLBACK,
            Error.SQLITE_WARNING_AUTOINDEX => ResultCode.SQLITE_WARNING_AUTOINDEX,
        };
    }

    pub fn toError(code: ResultCode) ?SqliteError {
        return switch (code) {
            // non-error result codes
            ResultCode.SQLITE_OK, ResultCode.SQLITE_DONE, ResultCode.SQLITE_ROW => null,

            // NO_COV_START
            // Primary codes
            ResultCode.SQLITE_ABORT => Error.SQLITE_ABORT,
            ResultCode.SQLITE_AUTH => Error.SQLITE_AUTH,
            ResultCode.SQLITE_BUSY => Error.SQLITE_BUSY,
            ResultCode.SQLITE_CANTOPEN => Error.SQLITE_CANTOPEN,
            ResultCode.SQLITE_CONSTRAINT => Error.SQLITE_CONSTRAINT,
            ResultCode.SQLITE_CORRUPT => Error.SQLITE_CORRUPT,
            ResultCode.SQLITE_EMPTY => Error.SQLITE_EMPTY,
            ResultCode.SQLITE_ERROR => Error.SQLITE_ERROR,
            ResultCode.SQLITE_FORMAT => Error.SQLITE_FORMAT,
            ResultCode.SQLITE_FULL => Error.SQLITE_FULL,
            ResultCode.SQLITE_INTERNAL => Error.SQLITE_INTERNAL,
            ResultCode.SQLITE_INTERRUPT => Error.SQLITE_INTERRUPT,
            ResultCode.SQLITE_IOERR => Error.SQLITE_IOERR,
            ResultCode.SQLITE_LOCKED => Error.SQLITE_LOCKED,
            ResultCode.SQLITE_MISMATCH => Error.SQLITE_MISMATCH,
            ResultCode.SQLITE_MISUSE => Error.SQLITE_MISUSE,
            ResultCode.SQLITE_NOLFS => Error.SQLITE_NOLFS,
            ResultCode.SQLITE_NOMEM => Error.SQLITE_NOMEM,
            ResultCode.SQLITE_NOTADB => Error.SQLITE_NOTADB,
            ResultCode.SQLITE_NOTFOUND => Error.SQLITE_NOTFOUND,
            ResultCode.SQLITE_NOTICE => Error.SQLITE_NOTICE,
            ResultCode.SQLITE_PERM => Error.SQLITE_PERM,
            ResultCode.SQLITE_PROTOCOL => Error.SQLITE_PROTOCOL,
            ResultCode.SQLITE_RANGE => Error.SQLITE_RANGE,
            ResultCode.SQLITE_READONLY => Error.SQLITE_READONLY,
            ResultCode.SQLITE_SCHEMA => Error.SQLITE_SCHEMA,
            ResultCode.SQLITE_TOOBIG => Error.SQLITE_TOOBIG,
            ResultCode.SQLITE_WARNING => Error.SQLITE_WARNING,

            // Extended codes
            ResultCode.SQLITE_ABORT_ROLLBACK => Error.SQLITE_ABORT_ROLLBACK,
            ResultCode.SQLITE_AUTH_USER => Error.SQLITE_AUTH_USER,
            ResultCode.SQLITE_BUSY_RECOVERY => Error.SQLITE_BUSY_RECOVERY,
            ResultCode.SQLITE_BUSY_SNAPSHOT => Error.SQLITE_BUSY_SNAPSHOT,
            ResultCode.SQLITE_BUSY_TIMEOUT => Error.SQLITE_BUSY_TIMEOUT,
            ResultCode.SQLITE_CANTOPEN_CONVPATH => Error.SQLITE_CANTOPEN_CONVPATH,
            ResultCode.SQLITE_CANTOPEN_DIRTYWAL => Error.SQLITE_CANTOPEN_DIRTYWAL,
            ResultCode.SQLITE_CANTOPEN_FULLPATH => Error.SQLITE_CANTOPEN_FULLPATH,
            ResultCode.SQLITE_CANTOPEN_ISDIR => Error.SQLITE_CANTOPEN_ISDIR,
            ResultCode.SQLITE_CANTOPEN_NOTEMPDIR => Error.SQLITE_CANTOPEN_NOTEMPDIR,
            ResultCode.SQLITE_CANTOPEN_SYMLINK => Error.SQLITE_CANTOPEN_SYMLINK,
            ResultCode.SQLITE_CONSTRAINT_CHECK => Error.SQLITE_CONSTRAINT_CHECK,
            ResultCode.SQLITE_CONSTRAINT_COMMITHOOK => Error.SQLITE_CONSTRAINT_COMMITHOOK,
            ResultCode.SQLITE_CONSTRAINT_DATATYPE => Error.SQLITE_CONSTRAINT_DATATYPE,
            ResultCode.SQLITE_CONSTRAINT_FOREIGNKEY => Error.SQLITE_CONSTRAINT_FOREIGNKEY,
            ResultCode.SQLITE_CONSTRAINT_FUNCTION => Error.SQLITE_CONSTRAINT_FUNCTION,
            ResultCode.SQLITE_CONSTRAINT_NOTNULL => Error.SQLITE_CONSTRAINT_NOTNULL,
            ResultCode.SQLITE_CONSTRAINT_PINNED => Error.SQLITE_CONSTRAINT_PINNED,
            ResultCode.SQLITE_CONSTRAINT_PRIMARYKEY => Error.SQLITE_CONSTRAINT_PRIMARYKEY,
            ResultCode.SQLITE_CONSTRAINT_ROWID => Error.SQLITE_CONSTRAINT_ROWID,
            ResultCode.SQLITE_CONSTRAINT_TRIGGER => Error.SQLITE_CONSTRAINT_TRIGGER,
            ResultCode.SQLITE_CONSTRAINT_UNIQUE => Error.SQLITE_CONSTRAINT_UNIQUE,
            ResultCode.SQLITE_CONSTRAINT_VTAB => Error.SQLITE_CONSTRAINT_VTAB,
            ResultCode.SQLITE_CORRUPT_INDEX => Error.SQLITE_CORRUPT_INDEX,
            ResultCode.SQLITE_CORRUPT_SEQUENCE => Error.SQLITE_CORRUPT_SEQUENCE,
            ResultCode.SQLITE_CORRUPT_VTAB => Error.SQLITE_CORRUPT_VTAB,
            ResultCode.SQLITE_ERROR_MISSING_COLLSEQ => Error.SQLITE_ERROR_MISSING_COLLSEQ,
            ResultCode.SQLITE_ERROR_RETRY => Error.SQLITE_ERROR_RETRY,
            ResultCode.SQLITE_ERROR_SNAPSHOT => Error.SQLITE_ERROR_SNAPSHOT,
            ResultCode.SQLITE_IOERR_ACCESS => Error.SQLITE_IOERR_ACCESS,
            ResultCode.SQLITE_IOERR_AUTH => Error.SQLITE_IOERR_AUTH,
            ResultCode.SQLITE_IOERR_BEGIN_ATOMIC => Error.SQLITE_IOERR_BEGIN_ATOMIC,
            ResultCode.SQLITE_IOERR_BLOCKED => Error.SQLITE_IOERR_BLOCKED,
            ResultCode.SQLITE_IOERR_CHECKRESERVEDLOCK => Error.SQLITE_IOERR_CHECKRESERVEDLOCK,
            ResultCode.SQLITE_IOERR_CLOSE => Error.SQLITE_IOERR_CLOSE,
            ResultCode.SQLITE_IOERR_COMMIT_ATOMIC => Error.SQLITE_IOERR_COMMIT_ATOMIC,
            ResultCode.SQLITE_IOERR_CONVPATH => Error.SQLITE_IOERR_CONVPATH,
            ResultCode.SQLITE_IOERR_CORRUPTFS => Error.SQLITE_IOERR_CORRUPTFS,
            ResultCode.SQLITE_IOERR_DATA => Error.SQLITE_IOERR_DATA,
            ResultCode.SQLITE_IOERR_DELETE => Error.SQLITE_IOERR_DELETE,
            ResultCode.SQLITE_IOERR_DELETE_NOENT => Error.SQLITE_IOERR_DELETE_NOENT,
            ResultCode.SQLITE_IOERR_DIR_CLOSE => Error.SQLITE_IOERR_DIR_CLOSE,
            ResultCode.SQLITE_IOERR_DIR_FSYNC => Error.SQLITE_IOERR_DIR_FSYNC,
            ResultCode.SQLITE_IOERR_FSTAT => Error.SQLITE_IOERR_FSTAT,
            ResultCode.SQLITE_IOERR_FSYNC => Error.SQLITE_IOERR_FSYNC,
            ResultCode.SQLITE_IOERR_GETTEMPPATH => Error.SQLITE_IOERR_GETTEMPPATH,
            ResultCode.SQLITE_IOERR_LOCK => Error.SQLITE_IOERR_LOCK,
            ResultCode.SQLITE_IOERR_MMAP => Error.SQLITE_IOERR_MMAP,
            ResultCode.SQLITE_IOERR_NOMEM => Error.SQLITE_IOERR_NOMEM,
            ResultCode.SQLITE_IOERR_RDLOCK => Error.SQLITE_IOERR_RDLOCK,
            ResultCode.SQLITE_IOERR_READ => Error.SQLITE_IOERR_READ,
            ResultCode.SQLITE_IOERR_ROLLBACK_ATOMIC => Error.SQLITE_IOERR_ROLLBACK_ATOMIC,
            ResultCode.SQLITE_IOERR_SEEK => Error.SQLITE_IOERR_SEEK,
            ResultCode.SQLITE_IOERR_SHMLOCK => Error.SQLITE_IOERR_SHMLOCK,
            ResultCode.SQLITE_IOERR_SHMMAP => Error.SQLITE_IOERR_SHMMAP,
            ResultCode.SQLITE_IOERR_SHMOPEN => Error.SQLITE_IOERR_SHMOPEN,
            ResultCode.SQLITE_IOERR_SHMSIZE => Error.SQLITE_IOERR_SHMSIZE,
            ResultCode.SQLITE_IOERR_SHORT_READ => Error.SQLITE_IOERR_SHORT_READ,
            ResultCode.SQLITE_IOERR_TRUNCATE => Error.SQLITE_IOERR_TRUNCATE,
            ResultCode.SQLITE_IOERR_UNLOCK => Error.SQLITE_IOERR_UNLOCK,
            ResultCode.SQLITE_IOERR_VNODE => Error.SQLITE_IOERR_VNODE,
            ResultCode.SQLITE_IOERR_WRITE => Error.SQLITE_IOERR_WRITE,
            ResultCode.SQLITE_LOCKED_SHAREDCACHE => Error.SQLITE_LOCKED_SHAREDCACHE,
            ResultCode.SQLITE_LOCKED_VTAB => Error.SQLITE_LOCKED_VTAB,
            ResultCode.SQLITE_NOTICE_RECOVER_ROLLBACK => Error.SQLITE_NOTICE_RECOVER_ROLLBACK,
            ResultCode.SQLITE_NOTICE_RECOVER_WAL => Error.SQLITE_NOTICE_RECOVER_WAL,
            ResultCode.SQLITE_OK_LOAD_PERMANENTLY => Error.SQLITE_OK_LOAD_PERMANENTLY,
            ResultCode.SQLITE_READONLY_CANTINIT => Error.SQLITE_READONLY_CANTINIT,
            ResultCode.SQLITE_READONLY_CANTLOCK => Error.SQLITE_READONLY_CANTLOCK,
            ResultCode.SQLITE_READONLY_DBMOVED => Error.SQLITE_READONLY_DBMOVED,
            ResultCode.SQLITE_READONLY_DIRECTORY => Error.SQLITE_READONLY_DIRECTORY,
            ResultCode.SQLITE_READONLY_RECOVERY => Error.SQLITE_READONLY_RECOVERY,
            ResultCode.SQLITE_READONLY_ROLLBACK => Error.SQLITE_READONLY_ROLLBACK,
            ResultCode.SQLITE_WARNING_AUTOINDEX => Error.SQLITE_WARNING_AUTOINDEX,
            // NO_COV_END
        };
    }
};

test "sqlite3.h include" {
    // std.debug.print("What is the value of SQLITE_OK? {any}\n", .{c.SQLITE_OK});
    try std.testing.expectEqual(0, c.SQLITE_OK);
}

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
