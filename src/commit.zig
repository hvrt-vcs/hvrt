const std = @import("std");
const fspath = std.fs.path;

const Dir = std.fs.Dir;

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");
const config = @import("config.zig");

const core_ds = @import("ds/core.zig");
const Hasher = core_ds.Hasher;
const HashKey = core_ds.HashKey;
const CommitParent = core_ds.CommitParent;
const ParentType = core_ds.ParentType;

const log = std.log.scoped(.commit);

const hvrt_dirname: [:0]const u8 = ".hvrt";

const work_tree_db_name: [:0]const u8 = "work_tree_state.sqlite";
const repo_db_name: [:0]const u8 = "repo.hvrt";

// TODO: use fifo buffer size pulled from config
const default_buffer_size = 1024 * 4;

// TODO: use chunk size pulled from config
const default_chunk_size = 1024 * 4;

// TODO: maybe use fba size pulled from config, or somewhere else dynamic, like
// getting the max chunk size in the work tree database, and allocate double
// that size for the fba.
const fba_size = 1024 * 64;

/// It is the responsibility of the caller of `commit` to deallocate and
/// deinit gpa, repo_path, and files, if necessary.
pub fn commit(gpa: std.mem.Allocator, cfg: config.Config, repo_path: []const u8, message: []const u8) !void {
    _ = cfg;
    log.debug("what is the message: {s}\n", .{message});

    // We allocate lots of short lived memory for copying between databases.
    // Use an arena to speed things up.
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    var arena = arena_state.allocator();

    // const chunk_size = if (cfg.get("chunk_size")) |v| (v.parseAsJsonInt(usize) catch default_chunk_size) else default_chunk_size;
    // const buffer_size = if (cfg.get("buffer_size")) |v| (v.parseAsJsonInt(usize) catch default_buffer_size) else default_buffer_size;

    const abs_repo_path = try std.fs.realpathAlloc(gpa, repo_path);
    defer gpa.free(abs_repo_path);

    const wt_db_path_parts = [_][]const u8{ abs_repo_path, hvrt_dirname, work_tree_db_name };
    const wt_db_path = try fspath.joinZ(gpa, &wt_db_path_parts);
    defer gpa.free(wt_db_path);
    log.debug("what is wt_db_path: {s}\n", .{wt_db_path});

    // Should fail if either the directory or db files do not exist
    const wt_db = try sqlite.DataBase.open(wt_db_path);
    defer wt_db.close() catch unreachable;

    const repo_db_path_parts = [_][]const u8{ abs_repo_path, hvrt_dirname, repo_db_name };
    const repo_db_path = try fspath.joinZ(gpa, &repo_db_path_parts);
    defer gpa.free(repo_db_path);
    log.debug("what is repo_db_path: {s}\n", .{repo_db_path});

    // Should fail if either the directory or db files do not exist
    const repo_db = try sqlite.DataBase.open(repo_db_path);
    defer repo_db.close() catch unreachable;

    const wt_sql = sql.sqlite.work_tree;
    const repo_sql = sql.sqlite.repo;

    // worktree statements
    const read_blobs_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.read_blobs);
    defer read_blobs_stmt.finalize() catch unreachable;
    const read_blob_chunks_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.read_blob_chunks);
    defer read_blob_chunks_stmt.finalize() catch unreachable;
    const read_chunks_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.read_chunks);
    defer read_chunks_stmt.finalize() catch unreachable;
    const read_head_commit_stmt = try sqlite.Statement.prepare(wt_db, wt_sql.read_head_commit);
    defer read_head_commit_stmt.finalize() catch unreachable;

    // Repo statements
    const blob_stmt = try sqlite.Statement.prepare(repo_db, repo_sql.commit.blob);
    defer blob_stmt.finalize() catch unreachable;
    const blob_chunk_stmt = try sqlite.Statement.prepare(repo_db, repo_sql.commit.blob_chunk);
    defer blob_chunk_stmt.finalize() catch unreachable;
    const chunk_stmt = try sqlite.Statement.prepare(repo_db, repo_sql.commit.chunk);
    defer chunk_stmt.finalize() catch unreachable;
    const header_stmt = try sqlite.Statement.prepare(repo_db, repo_sql.commit.header);
    defer header_stmt.finalize() catch unreachable;

    {
        const repo_tx = try sqlite.Transaction.init(repo_db, "repo_commit_cmd");
        errdefer repo_tx.rollback() catch unreachable;

        const wt_tx = try sqlite.Transaction.init(wt_db, "work_tree_commit_cmd");
        errdefer wt_tx.rollback() catch unreachable;

        log.debug("\nIterating over blob entries in work tree.\n", .{});
        var i: u64 = 0;
        while (try read_blobs_stmt.step()) |rc| : (i += 1) {
            if (rc != sqlite.ResultCode.SQLITE_ROW) {
                log.debug("What is the result code? {s}\n", .{@tagName(rc)});
                return error.NotImplemented;
            }
            _ = arena_state.reset(.retain_capacity);

            const hash_tmp = read_blobs_stmt.column_text(0) orelse unreachable;
            const hash = try arena.dupeZ(u8, hash_tmp);

            const hash_algo_tmp = read_blobs_stmt.column_text(1) orelse unreachable;
            const hash_algo = try arena.dupeZ(u8, hash_algo_tmp);

            const byte_length = read_blobs_stmt.column_i64(2);

            log.debug("blob_entry: {}, hash: {s}, hash_algo: {s}, byte_length: {}\n", .{ i, hash_algo, hash, byte_length });

            try blob_stmt.bind(1, false, hash);
            try blob_stmt.bind(2, false, hash_algo);
            try blob_stmt.bind(3, false, byte_length);
            try blob_stmt.auto_step();
            try blob_stmt.reset();
            try blob_stmt.clear_bindings();
        }

        i = 0;
        while (try read_chunks_stmt.step()) |rc| : (i += 1) {
            if (rc != sqlite.ResultCode.SQLITE_ROW) {
                log.debug("What is the result code? {s}\n", .{@tagName(rc)});
                return error.NotImplemented;
            }
            _ = arena_state.reset(.retain_capacity);

            const hash_tmp = read_chunks_stmt.column_text(0) orelse unreachable;
            const hash = try arena.dupeZ(u8, hash_tmp);

            const hash_algo_tmp = read_chunks_stmt.column_text(1) orelse unreachable;
            const hash_algo = try arena.dupeZ(u8, hash_algo_tmp);

            const compression_algo_tmp = read_chunks_stmt.column_text(2) orelse unreachable;
            const compression_algo = try arena.dupeZ(u8, compression_algo_tmp);

            const data_blob_tmp = read_chunks_stmt.column_blob(3) orelse unreachable;
            const data_blob = try arena.dupe(u8, data_blob_tmp);

            log.debug("chunk_entry: {}, hash_algo: {s}, hash: {s}, compression_algo: {s}, data_blob.len: {}\n", .{ i, hash_algo, hash, compression_algo, data_blob.len });

            try chunk_stmt.bind(1, false, hash);
            try chunk_stmt.bind(2, false, hash_algo);
            try chunk_stmt.bind(3, false, compression_algo);
            try chunk_stmt.bind(4, false, data_blob);
            try chunk_stmt.auto_step();
            try chunk_stmt.reset();
            try chunk_stmt.clear_bindings();
        }

        i = 0;
        while (try read_blob_chunks_stmt.step()) |rc| : (i += 1) {
            if (rc != sqlite.ResultCode.SQLITE_ROW) {
                log.debug("What is the result code? {s}\n", .{@tagName(rc)});
                return error.NotImplemented;
            }
            _ = arena_state.reset(.retain_capacity);

            // SELECT "blob_hash", "blob_hash_algo", "chunk_hash", "chunk_hash_algo", "start_byte", "end_byte" FROM "blob_chunks";

            const blob_hash_tmp = read_blob_chunks_stmt.column_text(0) orelse unreachable;
            const blob_hash = try arena.dupeZ(u8, blob_hash_tmp);

            const blob_hash_algo_tmp = read_blob_chunks_stmt.column_text(1) orelse unreachable;
            const blob_hash_algo = try arena.dupeZ(u8, blob_hash_algo_tmp);

            const chunk_hash_tmp = read_blob_chunks_stmt.column_text(2) orelse unreachable;
            const chunk_hash = try arena.dupeZ(u8, chunk_hash_tmp);

            const chunk_hash_algo_tmp = read_blob_chunks_stmt.column_text(3) orelse unreachable;
            const chunk_hash_algo = try arena.dupeZ(u8, chunk_hash_algo_tmp);

            const start_byte = read_blob_chunks_stmt.column_i64(4);
            const end_byte = read_blob_chunks_stmt.column_i64(5);

            try blob_chunk_stmt.bind(1, false, blob_hash);
            try blob_chunk_stmt.bind(2, false, blob_hash_algo);
            try blob_chunk_stmt.bind(3, false, chunk_hash);
            try blob_chunk_stmt.bind(4, false, chunk_hash_algo);
            try blob_chunk_stmt.bind(5, false, start_byte);
            try blob_chunk_stmt.bind(6, false, end_byte);
            try blob_chunk_stmt.auto_step();
            try blob_chunk_stmt.reset();
            try blob_chunk_stmt.clear_bindings();

            log.debug(
                \\blob_chunk_entry: {}
                \\    blob_hash_algo: {s}
                \\    blob_hash: {s}
                \\    chunk_hash_algo: {s}
                \\    chunk_hash: {s}
                \\    start_byte: {}
                \\    end_byte: {}
                \\
            ,
                .{
                    i,
                    blob_hash_algo,
                    blob_hash,
                    chunk_hash_algo,
                    chunk_hash,
                    start_byte,
                    end_byte,
                },
            );
        }

        // Should only be run when no errors have occurred.
        try wt_db.exec(wt_sql.clear);

        try repo_tx.commit();
        try wt_tx.commit();
    }
}

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
}
