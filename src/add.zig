const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const core_ds = @import("ds/core.zig");
const dir_walker = @import("dir_walker.zig");
const pcre = @import("pcre.zig");
const sql = @import("sql.zig");
const sqlite = @import("sqlite.zig");

const Hasher = core_ds.Hasher;

const log = std.log.scoped(.add);

const hvrt_dirname: [:0]const u8 = ".hvrt";
const work_tree_db_name: [:0]const u8 = "work_tree_state.sqlite";

// TODO: use fifo buffer size pulled from config
const fifo_buffer_size = 1024 * 4;
// TODO: use chunk size pulled from config
const chunk_size = 1024 * 4;

/// It is the responsibility of the caller of `add` to deallocate and
/// deinit alloc, repo_path, and files, if necessary.
pub fn add(alloc: std.mem.Allocator, repo_path: []const u8, files: []const []const u8) !void {
    var fa = try FileAdder.init(repo_path);
    defer fa.deinit();

    try fa.addFiles(alloc, files);
}

pub const FileAdder = struct {
    repo_root: std.fs.Dir,
    wt_db: sqlite.DataBase,
    file_stmt: sqlite.Statement,
    blob_stmt: sqlite.Statement,
    blob_chunk_stmt: sqlite.Statement,
    chunk_stmt: sqlite.Statement,
    tx_opt: ?sqlite.Transaction = null,

    pub fn deinit(self: *FileAdder) void {
        self.chunk_stmt.finalize() catch unreachable;
        self.blob_chunk_stmt.finalize() catch unreachable;
        self.blob_stmt.finalize() catch unreachable;
        self.file_stmt.finalize() catch unreachable;
        if (self.tx_opt) |tx| tx.commit() catch unreachable;
        self.wt_db.close() catch unreachable;
        self.repo_root.close();
    }

    pub fn init(repo_path: []const u8) !FileAdder {
        var fba_buf: [std.fs.max_path_bytes * 2]u8 = undefined;
        var fba_state = std.heap.FixedBufferAllocator.init(&fba_buf);
        const alloc = fba_state.allocator();

        const abs_repo_path = try std.fs.realpathAlloc(alloc, repo_path);
        defer alloc.free(abs_repo_path);

        var repo_root = try std.fs.openDirAbsolute(
            abs_repo_path,
            .{ .access_sub_paths = true, .iterate = true, .no_follow = true },
        );
        errdefer repo_root.close();

        const db_path_parts = [_][]const u8{ abs_repo_path, hvrt_dirname, work_tree_db_name };
        const db_path = try fspath.joinZ(alloc, &db_path_parts);
        defer alloc.free(db_path);
        log.debug("what is db_path: {s}\n", .{db_path});

        // Should fail if either the directory or db files do not exist
        const wt_db = try sqlite.DataBase.open(db_path);
        errdefer wt_db.close() catch unreachable;

        const wt_sql = sql.sqlite.work_tree orelse unreachable;

        const file_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.add.file);
        errdefer file_stmt.finalize() catch unreachable;
        const blob_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.add.blob);
        errdefer blob_stmt.finalize() catch unreachable;
        const blob_chunk_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.add.blob_chunk);
        errdefer blob_chunk_stmt.finalize() catch unreachable;
        const chunk_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.add.chunk);
        errdefer chunk_stmt.finalize() catch unreachable;

        return .{
            .repo_root = repo_root,
            .wt_db = wt_db,
            .file_stmt = file_stmt,
            .blob_stmt = blob_stmt,
            .blob_chunk_stmt = blob_chunk_stmt,
            .chunk_stmt = chunk_stmt,
        };
    }

    pub fn addFiles(self: *FileAdder, scratch: std.mem.Allocator, files: []const []const u8) !void {
        const tx = try sqlite.Transaction.init(self.wt_db, "add_cmd");
        errdefer tx.rollback() catch unreachable;

        self.tx_opt = tx;
        defer self.tx_opt = null;

        const chunk_buffer = try scratch.alloc(u8, chunk_size);
        defer scratch.free(chunk_buffer);

        const fifo_buf = try scratch.alloc(u8, fifo_buffer_size);
        defer scratch.free(fifo_buf);

        for (files) |file| {
            self.addFile(file) catch |e| {
                log.warn("Adding file \"{s}\" failed with error `{s}`\n", .{ file, @errorName(e) });
                log.warn("Ignoring error and moving to next file", .{});
                continue;
            };
        }

        try tx.commit();
    }

    pub fn addFile(self: *FileAdder, file: []const u8) !void {
        const file_sp_opt: ?sqlite.Savepoint = if (self.tx_opt) |tx| tx.createSavepoint("add_single_file") catch null else null;
        errdefer if (file_sp_opt) |file_sp| file_sp.rollback() catch unreachable;

        log.debug("What is the file name? {s}\n", .{file});

        if (std.fs.path.isAbsolute(file)) {
            log.err("File to add to stage must be relative path: {s}", .{file});
            return error.AbsoluteFilePath;
        }

        var fba_buf: [1024 * 64]u8 = undefined;
        var fba_state = std.heap.FixedBufferAllocator.init(&fba_buf);
        const alloc = fba_state.allocator();

        const chunk_buffer = try alloc.alloc(u8, chunk_size);
        defer alloc.free(chunk_buffer);

        const fifo_buf = try alloc.alloc(u8, fifo_buffer_size);
        defer alloc.free(fifo_buf);

        var chunk_buf_stream = std.io.fixedBufferStream(chunk_buffer);
        var fifo = std.fifo.LinearFifo(u8, .Slice).init(fifo_buf);

        var f_in = try self.repo_root.openFile(file, .{ .lock = .shared });
        defer f_in.close();

        const f_stat = try f_in.stat();
        const file_size = f_stat.size;

        const slashed_file = try alloc.dupeZ(u8, file);
        defer alloc.free(slashed_file);
        std.mem.replaceScalar(u8, slashed_file, std.fs.path.sep_windows, std.fs.path.sep_posix);

        var hasher = Hasher.init(null);
        const hash_algo = @tagName(hasher);

        try fifo.pump(f_in.reader(), hasher.writer());

        var hexz_buf: Hasher.Buffer = undefined;
        const file_digest_hexz = hasher.hexFinal(&hexz_buf);

        log.debug("blob_hash: {s}\nblob_hash_alg: {s}\nblob_size: {any}\n", .{ file_digest_hexz, hash_algo, file_size });
        try self.blob_stmt.reset();
        try self.blob_stmt.clear_bindings();
        try self.blob_stmt.bind_text(1, false, file_digest_hexz);
        try self.blob_stmt.bind_text(2, false, hash_algo);
        try self.blob_stmt.bind_int(3, @intCast(file_size));
        try self.blob_stmt.auto_step();
        try self.blob_stmt.reset();
        try self.blob_stmt.clear_bindings();

        log.debug("file_path: {s}\nfile_hash: {s}\nfile_hash_alg: {s}\nfile_size: {any}\n", .{ slashed_file, file_digest_hexz, hash_algo, file_size });
        try self.file_stmt.reset();
        try self.file_stmt.clear_bindings();
        try self.file_stmt.bind_text(1, false, slashed_file);
        try self.file_stmt.bind_text(2, false, file_digest_hexz);
        try self.file_stmt.bind_text(3, false, hash_algo);
        try self.file_stmt.bind_int(4, @intCast(file_size));
        try self.file_stmt.auto_step();
        try self.file_stmt.reset();
        try self.file_stmt.clear_bindings();

        // Rewind to beginning of file before chunking
        try f_in.seekTo(0);

        var cur_pos: @TypeOf(file_size) = 0;
        while (cur_pos < file_size) : (cur_pos = try f_in.getPos()) {
            chunk_buf_stream.reset();

            // const compression_algo: [:0]const u8 = "zstd";
            const compression_algo: [:0]const u8 = "none";

            var chunk_hasher = Hasher.init(null);
            const chunk_hash_algo = @tagName(chunk_hasher);

            var mwriter = std.io.multiWriter(.{ chunk_hasher.writer(), chunk_buf_stream.writer() });

            var lr = std.io.limitedReader(f_in.reader(), chunk_size);

            try fifo.pump(lr.reader(), mwriter.writer());

            const true_end_pos = try f_in.getPos();
            std.debug.assert(true_end_pos > cur_pos);

            const end_pos = true_end_pos - 1;

            var chunk_hexz_buf: Hasher.Buffer = undefined;
            const chunk_digest_hexz = chunk_hasher.hexFinal(&chunk_hexz_buf);

            const data: []const u8 = chunk_buf_stream.getWritten();

            log.debug("What is the contents of {s}? '{s}'\n", .{ file, chunk_buf_stream.getWritten() });
            log.debug("What is the hash contents of chunk for {s}? {s}\n", .{ file, chunk_digest_hexz });

            log.debug("blob_hash: {s}, blob_hash_algo: {s}, chunk_hash: {s}, chunk_hash_algo: {s}, start_byte: {any}, end_byte: {any}, compression_algo: {?s}\n", .{ file_digest_hexz, hash_algo, chunk_digest_hexz, hash_algo, cur_pos, end_pos, compression_algo });

            // INSERT INTO "chunks"
            try self.chunk_stmt.reset();
            try self.chunk_stmt.clear_bindings();
            try self.chunk_stmt.bind_text(1, false, chunk_digest_hexz); // chunk_hash
            try self.chunk_stmt.bind_text(2, false, chunk_hash_algo); // chunk_hash_algo
            try self.chunk_stmt.bind_text(3, false, compression_algo); // compression_algo
            try self.chunk_stmt.bind_blob(4, false, data); // data
            try self.chunk_stmt.auto_step();
            try self.chunk_stmt.reset();
            try self.chunk_stmt.clear_bindings();

            // INSERT INTO "blob_chunks"
            try self.blob_chunk_stmt.reset();
            try self.blob_chunk_stmt.clear_bindings();
            try self.blob_chunk_stmt.bind_text(1, false, file_digest_hexz); // blob_hash
            try self.blob_chunk_stmt.bind_text(2, false, hash_algo); // blob_hash_algo
            try self.blob_chunk_stmt.bind_text(3, false, chunk_digest_hexz); // chunk_hash
            try self.blob_chunk_stmt.bind_text(4, false, chunk_hash_algo); // chunk_hash_algo
            try self.blob_chunk_stmt.bind_int(5, @intCast(cur_pos)); // start_byte
            try self.blob_chunk_stmt.bind_int(6, @intCast(end_pos)); // end_byte
            try self.blob_chunk_stmt.auto_step();
            try self.blob_chunk_stmt.reset();
            try self.blob_chunk_stmt.clear_bindings();

            // TODO: Add zstd compression
        }

        if (file_sp_opt) |file_sp| try file_sp.commit();
    }
};

test {
    _ = FileAdder;
    _ = core_ds;
    _ = dir_walker;
    _ = pcre;
    _ = sql;
    _ = sqlite;
}
