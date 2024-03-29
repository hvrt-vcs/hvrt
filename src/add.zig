const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");

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

    const db_path_parts = [_][]const u8{ abs_repo_path, hvrt_dirname, work_tree_db_name };
    const db_path = try fspath.joinZ(alloc, &db_path_parts);
    defer alloc.free(db_path);
    std.log.debug("what is db_path: {s}\n", .{db_path});

    // Should fail if either the directory or db files do not exist
    const db = try sqlite.DataBase.open(db_path);
    defer db.close() catch unreachable;

    const fifo_buf = try alloc.alloc(u8, fifo_buffer_size);
    defer alloc.free(fifo_buf);

    var fifo = std.fifo.LinearFifo(u8, .Slice).init(fifo_buf);

    const sqlfiles = sql.sqlite;

    const file_stmt = try sqlite.Statement.prepare(db, sqlfiles.work_tree.add.file);
    defer file_stmt.finalize() catch unreachable;
    const blob_stmt = try sqlite.Statement.prepare(db, sqlfiles.work_tree.add.blob);
    defer blob_stmt.finalize() catch unreachable;
    const blob_chunk_stmt = try sqlite.Statement.prepare(db, sqlfiles.work_tree.add.blob_chunk);
    defer blob_chunk_stmt.finalize() catch unreachable;
    const chunk_stmt = try sqlite.Statement.prepare(db, sqlfiles.work_tree.add.chunk);
    defer chunk_stmt.finalize() catch unreachable;

    {
        var tx_ok = true;
        const tx = try sqlite.Transaction.init(db, "add_cmd");
        defer if (tx_ok) tx.commit() catch unreachable;
        errdefer {
            tx_ok = false;
            tx.rollback() catch unreachable;
        }

        const digest_length = std.crypto.hash.sha3.Sha3_256.digest_length;
        var digest_buf: [digest_length]u8 = undefined;

        const chunk_buffer = try alloc.alloc(u8, chunk_size);
        defer alloc.free(chunk_buffer);
        var chunk_buf_stream = std.io.fixedBufferStream(chunk_buffer);

        for (files) |file| {
            var file_tx_ok = true;
            const file_tx = try sqlite.Transaction.init(db, "add_single_file");
            defer if (file_tx_ok) file_tx.commit() catch unreachable;
            errdefer {
                file_tx_ok = false;
                file_tx.rollback() catch unreachable;
            }

            if (std.fs.path.isAbsolute(file)) {
                std.log.err("File to add to stage must be relative path: {s}", .{file});
                return error.AbsoluteFilePath;
            }

            var slashed_file = try alloc.dupeZ(u8, file);
            defer alloc.free(slashed_file);
            std.mem.replaceScalar(u8, slashed_file, std.fs.path.sep_windows, std.fs.path.sep_posix);

            const file_path_parts = [_][]const u8{ abs_repo_path, file };
            const abs_path = try std.fs.path.joinZ(alloc, &file_path_parts);
            defer alloc.free(abs_path);

            std.log.debug("What is the file name? {s}\n", .{file});
            std.log.debug("What is the absolute path? {s}\n", .{abs_path});

            var f_in = try std.fs.openFileAbsolute(abs_path, .{ .lock = .shared });
            defer f_in.close();

            const f_stat = try f_in.stat();
            const file_size = f_stat.size;
            // const file_size: i64 = @intCast(f_stat.size);
            // const file_size: i64 = f_stat.size;

            var hash = std.crypto.hash.sha3.Sha3_256.init(.{});
            const hash_algo: [:0]const u8 = "sha3_256";

            try fifo.pump(f_in.reader(), hash.writer());

            hash.final(&digest_buf);
            var file_digest_hex = std.fmt.bytesToHex(digest_buf, .lower);
            const file_digest_hexz = try alloc.dupeZ(u8, &file_digest_hex);
            defer alloc.free(file_digest_hexz);

            // _, err = tx.Exec(blob_script, file_hex_digest, "sha3_256", file_size)
            std.log.debug("blob_hash: {s}\nblob_hash_alg: {s}\nblob_size: {any}\n", .{ file_digest_hexz, hash_algo, file_size });
            try blob_stmt.reset();
            try blob_stmt.clear_bindings();
            try blob_stmt.bind(1, file_digest_hexz);
            try blob_stmt.bind(2, hash_algo);
            try blob_stmt.bind(3, @as(i64, @intCast(file_size)));
            try blob_stmt.auto_step();

            std.log.debug("file_path: {s}\nfile_hash: {s}\nfile_hash_alg: {s}\nfile_size: {any}\n", .{ slashed_file, file_digest_hexz, hash_algo, file_size });
            try file_stmt.reset();
            try file_stmt.clear_bindings();
            try file_stmt.bind(1, slashed_file);
            try file_stmt.bind(2, file_digest_hexz);
            try file_stmt.bind(3, hash_algo);
            try file_stmt.bind(4, @as(i64, @intCast(file_size)));
            try file_stmt.auto_step();

            // Rewind to beginning of file before chunking
            try f_in.seekTo(0);

            var cur_pos: @TypeOf(file_size) = 0;
            while (cur_pos < file_size) : (cur_pos = try f_in.getPos()) {
                chunk_buf_stream.reset();

                // const compression_algo: ?[:0]const u8 = "zstd";
                const compression_algo: ?[:0]const u8 = null;

                var chunk_hash = std.crypto.hash.sha3.Sha3_256.init(.{});
                var mwriter = std.io.multiWriter(.{ chunk_hash.writer(), chunk_buf_stream.writer() });

                var lr = std.io.limitedReader(f_in.reader(), chunk_size);

                try fifo.pump(lr.reader(), mwriter.writer());

                const end_pos = try f_in.getPos();

                chunk_hash.final(&digest_buf);
                var chunk_digest_hex = std.fmt.bytesToHex(digest_buf, .lower);
                const chunk_digest_hexz = try alloc.dupeZ(u8, &chunk_digest_hex);
                defer alloc.free(chunk_digest_hexz);

                const data: []const u8 = chunk_buf_stream.getWritten();

                std.log.debug("What is the contents of {s}? '{s}'\n", .{ file, chunk_buf_stream.getWritten() });
                std.log.debug("What is the hash contents of chunk for {s}? {s}\n", .{ file, chunk_digest_hex });

                std.log.debug("blob_hash: {s}, blob_hash_algo: {s}, chunk_hash: {s}, chunk_hash_algo: {s}, start_byte: {any}, end_byte: {any}, compression_algo: {?s}\n", .{ file_digest_hexz, hash_algo, chunk_digest_hex, hash_algo, cur_pos, end_pos, compression_algo });
                // std.debug.print("blob_hash: {s}, blob_hash_algo: {s}, chunk_hash: {s}, chunk_hash_algo: {s}, start_byte: {any}, end_byte: {any}, compression_algo: {?s}\n", .{ file_digest_hexz, hash_algo, chunk_digest_hex, hash_algo, cur_pos, end_pos, compression_algo });

                // INSERT INTO "chunks"
                try chunk_stmt.reset();
                try chunk_stmt.clear_bindings();
                try chunk_stmt.bind(1, chunk_digest_hexz); // chunk_hash
                try chunk_stmt.bind(2, hash_algo); // chunk_hash_algo
                try chunk_stmt.bind(3, compression_algo); // compression_algo
                try chunk_stmt.bind(4, data); // data
                try chunk_stmt.auto_step();

                // INSERT INTO "blob_chunks"
                try blob_chunk_stmt.reset();
                try blob_chunk_stmt.clear_bindings();
                try blob_chunk_stmt.bind(1, file_digest_hexz); // blob_hash
                try blob_chunk_stmt.bind(2, hash_algo); // blob_hash_algo
                try blob_chunk_stmt.bind(3, chunk_digest_hexz); // chunk_hash
                try blob_chunk_stmt.bind(4, hash_algo); // chunk_hash_algo
                try blob_chunk_stmt.bind(5, @as(i64, @intCast(cur_pos))); // start_byte
                try blob_chunk_stmt.bind(6, @as(i64, @intCast(end_pos))); // end_byte
                try blob_chunk_stmt.auto_step();

                // TODO: Add zstd compression
            }
        }
    }
}
