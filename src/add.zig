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
pub fn add(alloc: std.mem.Allocator, repo_path: [:0]const u8, files: []const [:0]const u8) !void {
    const abs_repo_path = try std.fs.realpathAlloc(alloc, repo_path);
    defer alloc.free(abs_repo_path);

    var repo_dir = try std.fs.openDirAbsolute(
        abs_repo_path,
        .{ .access_sub_paths = true, .iterate = true, .no_follow = true },
    );
    defer repo_dir.close();

    var repo_walker = try repo_dir.walk(alloc);
    defer repo_walker.deinit();

    // TODO: can we use a .hvrtignore file with a stdlib walker? I don't think
    // so. We will probably need to implement our own walker based on or
    // similar to the stdlib code.
    while (try repo_walker.next()) |entry| {
        log.debug("\n\n@typeName(@TypeOf(entry)): {s}\n\n", .{@typeName(@TypeOf(entry))});
        log.debug("\n\nkind: {s}, name: {s}\n\n", .{ @tagName(entry.kind), entry.path });
    }

    const db_path_parts = [_][]const u8{ abs_repo_path, hvrt_dirname, work_tree_db_name };
    const db_path = try fspath.joinZ(alloc, &db_path_parts);
    defer alloc.free(db_path);
    log.debug("what is db_path: {s}\n", .{db_path});

    // Should fail if either the directory or db files do not exist
    const db = try sqlite.DataBase.open(db_path);
    defer db.close() catch unreachable;

    const fifo_buf = try alloc.alloc(u8, fifo_buffer_size);
    defer alloc.free(fifo_buf);

    var fifo = std.fifo.LinearFifo(u8, .Slice).init(fifo_buf);

    const wt_sql = sql.sqlite.work_tree orelse unreachable;

    const file_stmt = try sqlite.Statement.prepare(db, wt_sql.add.file);
    defer file_stmt.finalize() catch unreachable;
    const blob_stmt = try sqlite.Statement.prepare(db, wt_sql.add.blob);
    defer blob_stmt.finalize() catch unreachable;
    const blob_chunk_stmt = try sqlite.Statement.prepare(db, wt_sql.add.blob_chunk);
    defer blob_chunk_stmt.finalize() catch unreachable;
    const chunk_stmt = try sqlite.Statement.prepare(db, wt_sql.add.chunk);
    defer chunk_stmt.finalize() catch unreachable;

    {
        var tx_ok = true;
        const tx = try sqlite.Transaction.init(db, "add_cmd");
        defer if (tx_ok) tx.commit() catch unreachable;
        errdefer {
            tx_ok = false;
            tx.rollback() catch unreachable;
        }

        const chunk_buffer = try alloc.alloc(u8, chunk_size);
        defer alloc.free(chunk_buffer);
        var chunk_buf_stream = std.io.fixedBufferStream(chunk_buffer);

        for (files) |file| {
            var file_sp_ok = true;
            const file_sp = try tx.createSavepoint("add_single_file");
            defer if (file_sp_ok) file_sp.commit() catch unreachable;
            errdefer {
                file_sp_ok = false;
                file_sp.rollback() catch unreachable;
            }

            if (std.fs.path.isAbsolute(file)) {
                log.err("File to add to stage must be relative path: {s}", .{file});
                return error.AbsoluteFilePath;
            }

            const slashed_file = try alloc.dupeZ(u8, file);
            defer alloc.free(slashed_file);
            std.mem.replaceScalar(u8, slashed_file, std.fs.path.sep_windows, std.fs.path.sep_posix);

            const file_path_parts = [_][]const u8{ abs_repo_path, file };
            const abs_path = try std.fs.path.joinZ(alloc, &file_path_parts);
            defer alloc.free(abs_path);

            log.debug("What is the file name? {s}\n", .{file});
            log.debug("What is the absolute path? {s}\n", .{abs_path});

            var f_in = try std.fs.openFileAbsolute(abs_path, .{ .lock = .shared });
            defer f_in.close();

            const f_stat = try f_in.stat();
            const file_size = f_stat.size;
            // const file_size: i64 = @intCast(f_stat.size);
            // const file_size: i64 = f_stat.size;

            var hasher = Hasher.init(null);
            const hash_algo = @tagName(hasher);

            try fifo.pump(f_in.reader(), hasher.writer());

            var hexz_buf: Hasher.Buffer = undefined;
            const file_digest_hexz = hasher.hexFinal(&hexz_buf);

            log.debug("blob_hash: {s}\nblob_hash_alg: {s}\nblob_size: {any}\n", .{ file_digest_hexz, hash_algo, file_size });
            try blob_stmt.bind(1, false, file_digest_hexz);
            try blob_stmt.bind(2, false, hash_algo);
            try blob_stmt.bind(3, false, @as(i64, @intCast(file_size)));
            try blob_stmt.auto_step();
            try blob_stmt.reset();
            try blob_stmt.clear_bindings();

            log.debug("file_path: {s}\nfile_hash: {s}\nfile_hash_alg: {s}\nfile_size: {any}\n", .{ slashed_file, file_digest_hexz, hash_algo, file_size });
            try file_stmt.bind(1, false, slashed_file);
            try file_stmt.bind(2, false, file_digest_hexz);
            try file_stmt.bind(3, false, hash_algo);
            try file_stmt.bind(4, false, @as(i64, @intCast(file_size)));
            try file_stmt.auto_step();
            try file_stmt.reset();
            try file_stmt.clear_bindings();

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
                try chunk_stmt.bind(1, false, chunk_digest_hexz); // chunk_hash
                try chunk_stmt.bind(2, false, chunk_hash_algo); // chunk_hash_algo
                try chunk_stmt.bind(3, false, compression_algo); // compression_algo
                try chunk_stmt.bind(4, false, data); // data
                try chunk_stmt.auto_step();
                try chunk_stmt.reset();
                try chunk_stmt.clear_bindings();

                // INSERT INTO "blob_chunks"
                try blob_chunk_stmt.bind(1, false, file_digest_hexz); // blob_hash
                try blob_chunk_stmt.bind(2, false, hash_algo); // blob_hash_algo
                try blob_chunk_stmt.bind(3, false, chunk_digest_hexz); // chunk_hash
                try blob_chunk_stmt.bind(4, false, chunk_hash_algo); // chunk_hash_algo
                try blob_chunk_stmt.bind(5, false, @as(i64, @intCast(cur_pos))); // start_byte
                try blob_chunk_stmt.bind(6, false, @as(i64, @intCast(end_pos))); // end_byte
                try blob_chunk_stmt.auto_step();
                try blob_chunk_stmt.reset();
                try blob_chunk_stmt.clear_bindings();

                // TODO: Add zstd compression
            }
        }
    }
}

pub const FileAdder = struct {
    repo_root: std.fs.Dir,
    wt_db: sqlite.DataBase,
    file_stmt: sqlite.Statement,
    blob_stmt: sqlite.Statement,
    blob_chunk_stmt: sqlite.Statement,
    chunk_stmt: sqlite.Statement,

    pub fn deinit(self: *FileAdder) void {
        self.chunk_stmt.finalize() catch unreachable;
        self.blob_chunk_stmt.finalize() catch unreachable;
        self.blob_stmt.finalize() catch unreachable;
        self.file_stmt.finalize() catch unreachable;
        self.wt_db.close() catch unreachable;
        self.repo_root.close();
    }

    pub fn init(repo_path: [:0]const u8) !FileAdder {
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
};

test {
    _ = FileAdder;
    _ = core_ds;
    _ = dir_walker;
    _ = pcre;
    _ = sql;
    _ = sqlite;
}
