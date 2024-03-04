const std = @import("std");
const fspath = std.fs.path;
const Dir = std.fs.Dir;

const sqlite = @import("sqlite.zig");
const sql = @import("sql.zig");

const hvrt_dirname = ".hvrt";
const work_tree_db_name = "work_tree_state.sqlite";

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
        const tx = try sqlite.Transaction.init(db, null);
        errdefer tx.rollback() catch |err| {
            std.debug.panic("Caught error when attempting to rollback transaction named '{s}': {any}", .{ tx.name, err });
        };

        for (files) |file| {
            const file_path_parts = [_][]const u8{ abs_repo_path, file };
            const abs_path = try std.fs.path.joinZ(alloc, &file_path_parts);
            defer alloc.free(abs_path);

            std.debug.print("\nWhat is the file name? {s}\n", .{file});
            std.debug.print("\nWhat is the absolute path? {s}\n", .{abs_path});

            // TODO: actually add files to work tree DB
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
