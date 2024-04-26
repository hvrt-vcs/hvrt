const std = @import("std");
const fspath = std.fs.path;

const Dir = std.fs.Dir;

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");

const hvrt_dirname: [:0]const u8 = ".hvrt";

const work_tree_db_name: [:0]const u8 = "work_tree_state.sqlite";
const repo_db_name: [:0]const u8 = "repo.hvrt";

// TODO: use fifo buffer size pulled from config
const fifo_buffer_size = 1024 * 4;
// TODO: use chunk size pulled from config
const chunk_size = 1024 * 4;

/// It is the responsibility of the caller of `commit` to deallocate and
/// deinit alloc, repo_path, and files, if necessary.
pub fn commit(alloc: std.mem.Allocator, repo_path: [:0]const u8, message: [:0]const u8) !void {
    std.log.debug("what is the message: {s}\n", .{message});

    const abs_repo_path = try std.fs.realpathAlloc(alloc, repo_path);
    defer alloc.free(abs_repo_path);

    const wt_db_path_parts = [_][]const u8{ abs_repo_path, hvrt_dirname, work_tree_db_name };
    const wt_db_path = try fspath.joinZ(alloc, &wt_db_path_parts);
    defer alloc.free(wt_db_path);
    std.log.debug("what is wt_db_path: {s}\n", .{wt_db_path});

    // Should fail if either the directory or db files do not exist
    const wt_db = try sqlite.DataBase.open(wt_db_path);
    defer wt_db.close() catch unreachable;

    const repo_db_path_parts = [_][]const u8{ abs_repo_path, hvrt_dirname, repo_db_name };
    const repo_db_path = try fspath.joinZ(alloc, &repo_db_path_parts);
    defer alloc.free(repo_db_path);
    std.log.debug("what is repo_db_path: {s}\n", .{repo_db_path});

    // Should fail if either the directory or db files do not exist
    const repo_db = try sqlite.DataBase.open(repo_db_path);
    defer repo_db.close() catch unreachable;

    const fifo_buf = try alloc.alloc(u8, fifo_buffer_size);
    defer alloc.free(fifo_buf);

    // var fifo = std.fifo.LinearFifo(u8, .Slice).init(fifo_buf);
    // _ = fifo;

    const sqlfiles = sql.sqlite;

    // worktree statements
    const read_blobs_stmt = try sqlite.Statement.prepare(wt_db, sqlfiles.work_tree.read_blobs);
    defer read_blobs_stmt.finalize() catch unreachable;
    const read_blob_chunks_stmt = try sqlite.Statement.prepare(wt_db, sqlfiles.work_tree.read_blob_chunks);
    defer read_blob_chunks_stmt.finalize() catch unreachable;
    const read_chunks_stmt = try sqlite.Statement.prepare(wt_db, sqlfiles.work_tree.read_chunks);
    defer read_chunks_stmt.finalize() catch unreachable;
    const read_head_commit_stmt = try sqlite.Statement.prepare(wt_db, sqlfiles.work_tree.read_head_commit);
    defer read_head_commit_stmt.finalize() catch unreachable;

    // Repo statements
    const blob_stmt = try sqlite.Statement.prepare(repo_db, sqlfiles.repo.commit.blob);
    defer blob_stmt.finalize() catch unreachable;
    const blob_chunk_stmt = try sqlite.Statement.prepare(repo_db, sqlfiles.repo.commit.blob_chunk);
    defer blob_chunk_stmt.finalize() catch unreachable;
    const chunk_stmt = try sqlite.Statement.prepare(repo_db, sqlfiles.repo.commit.chunk);
    defer chunk_stmt.finalize() catch unreachable;
    const header_stmt = try sqlite.Statement.prepare(repo_db, sqlfiles.repo.commit.header);
    defer header_stmt.finalize() catch unreachable;

    {
        var repo_tx_ok = true;
        const repo_tx = try sqlite.Transaction.init(repo_db, "repo_commit_cmd");
        defer if (repo_tx_ok) repo_tx.commit() catch unreachable;
        errdefer {
            repo_tx_ok = false;
            repo_tx.rollback() catch unreachable;
        }

        var wt_tx_ok = true;
        const wt_tx = try sqlite.Transaction.init(wt_db, "work_tree_commit_cmd");
        defer if (wt_tx_ok) wt_tx.commit() catch unreachable;
        errdefer {
            wt_tx_ok = false;
            wt_tx.rollback() catch unreachable;
        }

        // SELECT "hash", "hash_algo", "byte_length" FROM "blobs";

        var hash_buffer: [128]u8 = undefined;
        var hash_algo_buffer: [16]u8 = undefined;
        std.debug.print("\nIterating over blob entries in work tree.\n", .{});
        var entry_count = @as(u64, 0);
        while (read_blobs_stmt.step()) |rc| {
            try rc.check(read_blobs_stmt.db);
            entry_count += 1;
            std.debug.print("blob entry # {}\n", .{entry_count});

            if (rc != sqlite.ResultCode.SQLITE_ROW) {
                std.debug.print("What is the result code? {s}\n", .{@tagName(rc)});
                return error.NotImplemented;
            }

            const hash_tmp = read_blobs_stmt.column_text(0) orelse continue;
            std.mem.copyForwards(u8, &hash_buffer, hash_tmp);
            hash_buffer[hash_tmp.len] = 0;
            const hash = hash_buffer[0..hash_tmp.len :0];

            const hash_algo_tmp = read_blobs_stmt.column_text(1) orelse continue;
            std.mem.copyForwards(u8, &hash_algo_buffer, hash_algo_tmp);
            hash_algo_buffer[hash_algo_tmp.len] = 0;
            const hash_algo = hash_algo_buffer[0..hash_algo_tmp.len :0];

            const byte_length = read_blobs_stmt.column_i64(2);

            std.debug.print("entry: {}, hash: {s}, hash_algo: {s}, byte_length: {}\n", .{ entry_count, hash_algo, hash, byte_length });

            try blob_stmt.bind(1, false, hash);
            try blob_stmt.bind(2, false, hash_algo);
            try blob_stmt.bind(3, false, byte_length);
            try blob_stmt.auto_step();
            try blob_stmt.reset();
            try blob_stmt.clear_bindings();
        }

        const digest_length = std.crypto.hash.sha3.Sha3_256.digest_length;
        _ = digest_length;
        // var digest_buf: [digest_length]u8 = undefined;
        // _ = digest_buf;

        const chunk_buffer = try alloc.alloc(u8, chunk_size);
        defer alloc.free(chunk_buffer);
        // var chunk_buf_stream = std.io.fixedBufferStream(chunk_buffer);
        // _ = chunk_buf_stream;

        try wt_db.exec(sqlfiles.work_tree.clear);
    }
}
