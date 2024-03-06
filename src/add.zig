const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");

const hvrt_dirname = ".hvrt";
const work_tree_db_name = "work_tree_state.sqlite";

const default_buffer_size = 1024 * 4;

/// It is the responsibility of the caller of `init` to deallocate and
/// deinit dir_path and alloc, if necessary.
pub fn add(alloc: std.mem.Allocator, repo_path: []const u8, files: []const []const u8) !void {
    const abs_repo_path = try std.fs.realpathAlloc(alloc, repo_path);
    defer alloc.free(abs_repo_path);

    const db_path_parts = [_][]const u8{ abs_repo_path, hvrt_dirname, work_tree_db_name };
    const db_path = try fspath.joinZ(alloc, &db_path_parts);
    defer alloc.free(db_path);
    std.debug.print("what is db_path: {s}\n", .{db_path});

    // Should fail if either the directory or db files do not exist
    const db = try sqlite.open(db_path);
    defer sqlite.close(db) catch unreachable;

    const sqlfiles = sql.sqlite;

    // std.fs.openIterableDirAbsolute(".", .{});

    const blob_stmt = try sqlite.prepare(db, sqlfiles.work_tree.add.blob);
    defer sqlite.finalize(blob_stmt) catch unreachable;

    {
        const tx = try sqlite.Transaction.init(db, "add_cmd");
        errdefer tx.rollback() catch |err| {
            std.debug.panic("Caught error when attempting to rollback transaction named '{s}': {any}", .{ tx.name, err });
        };

        for (files) |file| {
            const file_tx = try sqlite.Transaction.init(db, "add_single_file");
            errdefer file_tx.rollback() catch |err| {
                std.debug.panic("Caught error when attempting to rollback transaction named '{s}': {any}", .{ tx.name, err });
            };

            const file_path_parts = [_][]const u8{ abs_repo_path, file };
            const abs_path = try std.fs.path.joinZ(alloc, &file_path_parts);
            defer alloc.free(abs_path);

            std.debug.print("\nWhat is the file name? {s}\n", .{file});
            std.debug.print("\nWhat is the absolute path? {s}\n", .{abs_path});

            var f_in = try std.fs.openFileAbsolute(abs_path, .{ .lock = .shared });
            var f_in_buffed = std.io.bufferedReader(f_in.reader());
            _ = f_in_buffed;

            // TODO: use heap memory and a chunk size pulled from config
            var buffer: [default_buffer_size]u8 = undefined;
            var buf_writer = std.io.fixedBufferStream(&buffer);

            const digest_length = std.crypto.hash.sha3.Sha3_256.digest_length;
            var hash = std.crypto.hash.sha3.Sha3_256.init(.{});

            var mwriter = std.io.multiWriter(.{ hash.writer(), buf_writer.writer() });

            var fifo = std.fifo.LinearFifo(u8, .{ .Static = default_buffer_size }).init();

            try fifo.pump(f_in, mwriter);

            var digest_buf: [digest_length]u8 = undefined;
            hash.final(digest_buf);

            var digest_hex = std.fmt.bytesToHex(digest_buf, .lower);
            std.debug.print("WHat is the hash contents of {s}? {s}", .{ file, digest_hex });

            // TODO: actually add files to work tree DB

            // try to commit if everything went well
            try file_tx.commit();
        }

        // try to commit if everything went well
        try tx.commit();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
