const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");

const hvrt_dirname = ".hvrt";
const work_tree_db_name = "work_tree_state.sqlite";

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
    std.debug.print("what is db_path: {s}\n", .{db_path});

    // Should fail if either the directory or db files do not exist
    const db = try sqlite.DataBase.open(db_path);
    defer db.close() catch unreachable;

    const fifo_buf = try alloc.alloc(u8, fifo_buffer_size);
    defer alloc.free(fifo_buf);

    var fifo = std.fifo.LinearFifo(u8, .Slice).init(fifo_buf);

    const sqlfiles = sql.sqlite;

    const blob_stmt = try sqlite.Statement.prepare(db, sqlfiles.work_tree.add.blob);
    defer blob_stmt.finalize() catch unreachable;

    {
        var tx_ok = true;
        const tx = try sqlite.Transaction.init(db, "add_cmd");
        defer if (tx_ok) tx.commit() catch unreachable;
        errdefer tx.rollback() catch |err| {
            tx_ok = false;
            std.debug.print("Transaction '{s}' rollback failed: {any}\n", .{ tx.name, err });
        };

        for (files) |file| {
            var file_tx_ok = true;
            const file_tx = try sqlite.Transaction.init(db, "add_single_file");
            defer if (file_tx_ok) file_tx.commit() catch unreachable;
            errdefer file_tx.rollback() catch |err| {
                file_tx_ok = false;
                std.debug.print("Transaction '{s}' rollback failed: {any}\n", .{ tx.name, err });
            };

            const file_path_parts = [_][]const u8{ abs_repo_path, file };
            const abs_path = try std.fs.path.joinZ(alloc, &file_path_parts);
            defer alloc.free(abs_path);

            std.debug.print("What is the file name? {s}\n", .{file});
            std.debug.print("What is the absolute path? {s}\n", .{abs_path});

            var f_in = try std.fs.openFileAbsolute(abs_path, .{ .lock = .shared });

            const digest_length = std.crypto.hash.sha3.Sha3_256.digest_length;
            var hash = std.crypto.hash.sha3.Sha3_256.init(.{});
            var file_digest_buf: [digest_length]u8 = undefined;

            try fifo.pump(f_in.reader(), hash.writer());

            hash.final(&file_digest_buf);
            var file_digest_hex = std.fmt.bytesToHex(file_digest_buf, .lower);

            // Rewind to beginning of file before chunking
            try f_in.seekTo(0);

            const chunk_buffer = try alloc.alloc(u8, chunk_size);
            defer alloc.free(chunk_buffer);
            var chunk_buf_stream = std.io.fixedBufferStream(chunk_buffer);

            var chunk_hash = std.crypto.hash.sha3.Sha3_256.init(.{});
            var lr = std.io.limitedReader(f_in.reader(), chunk_size);

            var mwriter = std.io.multiWriter(.{ chunk_hash.writer(), chunk_buf_stream.writer() });

            try fifo.pump(lr.reader(), mwriter.writer());

            var chunk_digest_buf: [digest_length]u8 = undefined;
            chunk_hash.final(&chunk_digest_buf);

            var chunk_digest_hex = std.fmt.bytesToHex(chunk_digest_buf, .lower);
            std.debug.print("What is the contents of {s}? '{s}'\n", .{ file, chunk_buf_stream.getWritten() });
            std.debug.print("What is the hash contents of {s}? {s}\n", .{ file, file_digest_hex });
            std.debug.print("What is the hash contents of chunk for {s}? {s}\n", .{ file, chunk_digest_hex });
        }
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
