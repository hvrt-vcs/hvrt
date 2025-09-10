const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const core_ds = @import("ds/core.zig");
const dir_walker = @import("dir_walker.zig");
const pcre = @import("pcre.zig");
const sql = @import("sql.zig");
const sqlite = @import("sqlite.zig");
const config = @import("config.zig");

const Sha3_256 = core_ds.Sha3_256;
const HashAlgo = core_ds.HashAlgo;

const log = std.log.scoped(.add);

const hvrt_dirname: [:0]const u8 = ".hvrt";
const work_tree_db_name: [:0]const u8 = "work_tree_state.sqlite";

/// Fallback for when config value isn't present.
const default_buffer_size = 1024 * 4;
/// Fallback for when config value isn't present.
const default_chunk_size = 1024 * 4;

/// It is the responsibility of the caller of `add` to deallocate and
/// deinit `gpa`, `repo_path`, and `files`, if necessary.
pub fn add(gpa: std.mem.Allocator, cfg: config.Config, repo_path: []const u8, files: []const []const u8) !void {
    var file_adder = try FileAdder.init(gpa, cfg, repo_path);
    defer file_adder.deinit();

    try file_adder.addPaths(files);
}

pub const FileAdder = struct {
    alloc: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    config: config.Config,
    repo_root: std.fs.Dir,
    wt_db: sqlite.DataBase,
    file_stmt: sqlite.Statement,
    blob_stmt: sqlite.Statement,
    blob_chunk_stmt: sqlite.Statement,
    chunk_stmt: sqlite.Statement,
    tx_opt: ?sqlite.Transaction = null,
    fifo_buffer_size: usize = default_buffer_size,
    chunk_size: usize = default_chunk_size,

    pub fn deinit(self: *FileAdder) void {
        const child_allocator = self.arena.child_allocator;
        self.arena.deinit();
        child_allocator.destroy(self.arena);

        self.chunk_stmt.finalize() catch unreachable;
        self.blob_chunk_stmt.finalize() catch unreachable;
        self.blob_stmt.finalize() catch unreachable;
        self.file_stmt.finalize() catch unreachable;
        if (self.tx_opt) |tx| tx.commit() catch unreachable;
        self.wt_db.close() catch unreachable;
        self.repo_root.close();
    }

    pub fn init(gpa: std.mem.Allocator, cfg: config.Config, repo_path: []const u8) !FileAdder {
        const arena = try gpa.create(std.heap.ArenaAllocator);
        arena.* = .init(gpa);
        errdefer {
            arena.deinit();
            gpa.destroy(arena);
        }

        const alloc = gpa;

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
        const wt_db = try sqlite.DataBase.open(db_path, .{
            .flags = &.{
                .readwrite,
                .uri,
                .exrescode,
            },
        });
        errdefer wt_db.close() catch unreachable;

        const wt_sql = sql.sqlite.work_tree;

        const file_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.add.file);
        errdefer file_stmt.finalize() catch unreachable;
        const blob_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.add.blob);
        errdefer blob_stmt.finalize() catch unreachable;
        const blob_chunk_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.add.blob_chunk);
        errdefer blob_chunk_stmt.finalize() catch unreachable;
        const chunk_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.add.chunk);
        errdefer chunk_stmt.finalize() catch unreachable;

        const buffer_size = if (cfg.get("buffer_size")) |v| (v.parseAsJsonInt(usize) catch default_buffer_size) else default_buffer_size;
        const chunk_size = if (cfg.get("chunk_size")) |v| (v.parseAsJsonInt(usize) catch default_chunk_size) else default_chunk_size;

        return .{
            .alloc = alloc,
            .arena = arena,
            .config = cfg,
            .repo_root = repo_root,
            .wt_db = wt_db,
            .file_stmt = file_stmt,
            .blob_stmt = blob_stmt,
            .blob_chunk_stmt = blob_chunk_stmt,
            .chunk_stmt = chunk_stmt,
            .fifo_buffer_size = buffer_size,
            .chunk_size = chunk_size,
        };
    }

    pub fn initTransaction(self: *FileAdder, name: ?[:0]const u8) !void {
        self.tx_opt = try sqlite.Transaction.init(self.wt_db, name);
    }

    pub fn commitTransaction(self: *FileAdder) !void {
        if (self.tx_opt) |tx| try tx.commit();
        self.tx_opt = null;
    }

    pub fn rollbackTransaction(self: *FileAdder) !void {
        if (self.tx_opt) |tx| try tx.rollback();
        self.tx_opt = null;
    }

    pub fn addPaths(self: *FileAdder, relative_paths: []const []const u8) !void {
        try self.initTransaction("add_cmd");
        errdefer self.rollbackTransaction() catch unreachable;

        for (relative_paths) |file| {
            const stat = self.repo_root.statFile(file) catch |e| {
                log.warn("Running `stat` on file \"{s}\" failed with error `{s}`\n", .{ file, @errorName(e) });
                continue;
            };

            switch (stat.kind) {
                .directory => {
                    var sub_dir = self.repo_root.openDir(file, .{ .access_sub_paths = true, .iterate = true }) catch |e| {
                        log.warn("Opening subdir \"{s}\" failed with error `{s}`\n", .{ file, @errorName(e) });
                        continue;
                    };
                    defer sub_dir.close();

                    self.addDir(&sub_dir, file) catch {
                        // log.warn("Failed adding directory \"{any}\" with error `{any}`\n", .{ file, @errorName(e) });
                        continue;
                    };
                },
                else => {
                    // Assume everything other than directories can be added.
                    self.addFile(file) catch |e| {
                        log.warn("Adding file \"{s}\" failed with error `{s}`\n", .{ file, @errorName(e) });
                        continue;
                    };
                },
            }
        }

        try self.commitTransaction();
    }

    pub fn addDir(self: *FileAdder, dir: *std.fs.Dir, path_from_repo_root: []const u8) !void {
        var dir_iter = dir.iterate();
        while (dir_iter.next()) |entry_opt| {
            if (entry_opt) |entry| {
                const joined_file = std.fs.path.join(self.alloc, &.{ path_from_repo_root, entry.name }) catch |e| {
                    log.warn("Joining filepath \"{s}\" with \"{s}\" failed with error `{s}`\n", .{ path_from_repo_root, entry.name, @errorName(e) });
                    continue;
                };
                defer self.alloc.free(joined_file);

                switch (entry.kind) {
                    .directory => {
                        var sub_dir = self.repo_root.openDir(joined_file, .{ .access_sub_paths = true, .iterate = true }) catch |e| {
                            log.warn("Walking subdir \"{s}\" failed with error `{s}`\n", .{ joined_file, @errorName(e) });
                            continue;
                        };
                        defer sub_dir.close();

                        self.addDir(&sub_dir, joined_file) catch |e| {
                            log.warn("Failed adding directory \"{s}\" with error `{s}`\n", .{ joined_file, @errorName(e) });
                            continue;
                        };
                    },
                    else => {
                        // Assume everything other than directories can be added.
                        self.addFile(joined_file) catch {
                            // log.warn("Adding file \"{s}\" failed with error `{s}`\n", .{ joined_file, @errorName(e) });
                            continue;
                        };
                    },
                }

                self.addFile(joined_file) catch |e| {
                    log.warn("Adding file \"{s}\" failed with error `{s}`\n", .{ joined_file, @errorName(e) });
                    continue;
                };
            } else break;
        } else |e| {
            log.warn("Failed iterating \"{s}\" with error `{s}`\n", .{ path_from_repo_root, @errorName(e) });
            return e;
        }
    }

    pub fn addFile(self: *FileAdder, rel_path: []const u8) !void {
        defer _ = self.arena.reset(.retain_capacity);
        const arena = self.arena.allocator();

        const file_sp_opt: ?sqlite.Savepoint = if (self.tx_opt) |tx| tx.createSavepoint("add_single_file") catch null else null;
        errdefer if (file_sp_opt) |file_sp| file_sp.rollback() catch unreachable;

        log.debug("What is the file name? {s}\n", .{rel_path});

        if (std.fs.path.isAbsolute(rel_path)) {
            log.err("File to add to stage must be relative path: {s}", .{rel_path});
            return error.AbsoluteFilePath;
        }

        const chunk_buffer = try arena.alloc(u8, self.chunk_size);
        const fifo_buf = try arena.alloc(u8, self.fifo_buffer_size);

        // const f_in_buffer = self.fifo_buffer_size
        var f_in = try self.repo_root.openFile(rel_path, .{ .lock = .shared });
        defer f_in.close();

        const f_stat = try f_in.stat();
        const file_size = f_stat.size;

        const slashed_file = try arena.dupeZ(u8, rel_path);
        std.mem.replaceScalar(u8, slashed_file, std.fs.path.sep_windows, std.fs.path.sep_posix);

        var hash_buf: [1]u8 = undefined;
        var hasher = Sha3_256.init(&hash_buf);
        var hasher_writer = &hasher.hasher.writer;
        const hash_algo: [:0]const u8 = @tagName(hasher.hash_algo);

        var f_in_reader1 = f_in.reader(fifo_buf);
        var f_in_reader1_int = &f_in_reader1.interface;
        _ = try f_in_reader1_int.streamRemaining(hasher_writer);
        try hasher_writer.flush();
        // try fifo.pump(f_in.reader(), hasher.writer());
        // FIXME: COPY FILE GUTS!

        const file_digest_hexz = hasher.hexDigest();

        log.debug("blob_hash: {s}\nblob_hash_alg: {s}\nblob_size: {any}\n", .{ &file_digest_hexz, hash_algo, file_size });
        try self.blob_stmt.reset();
        try self.blob_stmt.clear_bindings();
        try self.blob_stmt.bind_text(1, false, &file_digest_hexz);
        try self.blob_stmt.bind_text(2, false, hash_algo);
        try self.blob_stmt.bind_int(3, @intCast(file_size));
        try self.blob_stmt.auto_step();
        try self.blob_stmt.reset();
        try self.blob_stmt.clear_bindings();

        log.debug("file_path: {s}\nfile_hash: {s}\nfile_hash_alg: {s}\nfile_size: {any}\n", .{ slashed_file, &file_digest_hexz, hash_algo, file_size });
        try self.file_stmt.reset();
        try self.file_stmt.clear_bindings();
        try self.file_stmt.bind_text(1, false, slashed_file);
        try self.file_stmt.bind_text(2, false, &file_digest_hexz);
        try self.file_stmt.bind_text(3, false, hash_algo);
        try self.file_stmt.bind_int(4, @intCast(file_size));
        try self.file_stmt.auto_step();
        try self.file_stmt.reset();
        try self.file_stmt.clear_bindings();

        // Rewind to beginning of file before chunking
        try f_in.seekTo(0);

        var cur_pos: @TypeOf(file_size) = 0;
        while (cur_pos < file_size) : (cur_pos = try f_in.getPos()) {
            // const compression_algo: [:0]const u8 = "zstd";
            const compression_algo: [:0]const u8 = "none";

            var chunk_hasher = Sha3_256.init(&hash_buf);
            const chunk_hash_algo: [:0]const u8 = @tagName(chunk_hasher.hash_algo);

            var chunk_buf_stream = std.Io.Writer.fixed(chunk_buffer);

            var f_in_reader2_buf: [1024 * 4]u8 = undefined;
            var f_in_reader2 = f_in.readerStreaming(&f_in_reader2_buf);
            const f_in_reader2_int = &f_in_reader2.interface;

            f_in_reader2_int.streamExact(&chunk_buf_stream, chunk_buffer.len) catch |e| {
                switch (e) {
                    error.EndOfStream => {},
                    else => return e,
                }
            };

            const chunk = chunk_buf_stream.buffered();

            chunk_hasher.hasher.hasher.update(chunk);

            const true_end_pos = try f_in.getPos();
            std.debug.assert(true_end_pos > cur_pos);

            const end_pos = true_end_pos - 1;

            const chunk_digest_hexz = chunk_hasher.hexDigest();

            const data: []const u8 = chunk;

            log.debug("What is the contents of {s}? '{s}'\n", .{ rel_path, chunk });
            log.debug("What is the hash contents of chunk for {s}? {s}\n", .{ rel_path, &chunk_digest_hexz });

            // log.debug("blob_hash: {s}, blob_hash_algo: {s}, chunk_hash: {s}, chunk_hash_algo: {s}, start_byte: {any}, end_byte: {any}, compression_algo: {?s}\n", .{ file_digest_hexz, hash_algo, chunk_digest_hexz, hash_algo, cur_pos, end_pos, compression_algo });

            // INSERT INTO "chunks"
            try self.chunk_stmt.reset();
            try self.chunk_stmt.clear_bindings();
            try self.chunk_stmt.bind_text(1, false, &chunk_digest_hexz); // chunk_hash
            try self.chunk_stmt.bind_text(2, false, chunk_hash_algo); // chunk_hash_algo
            try self.chunk_stmt.bind_text(3, false, compression_algo); // compression_algo
            try self.chunk_stmt.bind_blob(4, false, data); // data
            try self.chunk_stmt.auto_step();
            try self.chunk_stmt.reset();
            try self.chunk_stmt.clear_bindings();

            // INSERT INTO "blob_chunks"
            try self.blob_chunk_stmt.reset();
            try self.blob_chunk_stmt.clear_bindings();
            try self.blob_chunk_stmt.bind_text(1, false, &file_digest_hexz); // blob_hash
            try self.blob_chunk_stmt.bind_text(2, false, hash_algo); // blob_hash_algo
            try self.blob_chunk_stmt.bind_text(3, false, &chunk_digest_hexz); // chunk_hash
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

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
