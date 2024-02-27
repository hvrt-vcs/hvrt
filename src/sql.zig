const std = @import("std");

/// TODO: separate repo and worktree into two different types
/// worktree is always going to be SQLite, for the forseeable future, so it
/// doesn't make sense to force repo only DBs like postgres to fill out those
/// fields as well. I'm punting this for today because it is getting late :).
pub const SQLFiles = struct {
    repo: struct {
        init: [:0]const u8,

        commit: struct {
            blob: [:0]const u8,
            blob_chunk: [:0]const u8,
            chunk: [:0]const u8,
            header: [:0]const u8,
        },
    },
    work_tree: struct {
        clear: [:0]const u8,

        read_blob_chunks: [:0]const u8,
        read_blobs: [:0]const u8,
        read_chunks: [:0]const u8,
        read_head_commit: [:0]const u8,

        add: struct {
            blob: [:0]const u8,
            blob_chunk: [:0]const u8,
            file: [:0]const u8,
        },

        init: struct {
            branch: [:0]const u8,
            tables: [:0]const u8,
            version: [:0]const u8,
        },
    },
};

pub const sqlite: SQLFiles = .{
    .repo = .{
        .init = @embedFile("sql/sqlite/repo/init.sql"),

        .commit = .{
            .blob = @embedFile("sql/sqlite/repo/commit/blob.sql"),
            .blob_chunk = @embedFile("sql/sqlite/repo/commit/blob_chunk.sql"),
            .chunk = @embedFile("sql/sqlite/repo/commit/chunk.sql"),
            .header = @embedFile("sql/sqlite/repo/commit/header.sql"),
        },
    },
    .work_tree = .{
        .clear = @embedFile("sql/sqlite/work_tree/clear.sql"),

        .read_blob_chunks = @embedFile("sql/sqlite/work_tree/read_blob_chunks.sql"),
        .read_blobs = @embedFile("sql/sqlite/work_tree/read_blobs.sql"),
        .read_chunks = @embedFile("sql/sqlite/work_tree/read_chunks.sql"),
        .read_head_commit = @embedFile("sql/sqlite/work_tree/read_head_commit.sql"),

        .add = .{
            .blob = @embedFile("sql/sqlite/work_tree/add/blob.sql"),
            .blob_chunk = @embedFile("sql/sqlite/work_tree/add/blob_chunk.sql"),
            .file = @embedFile("sql/sqlite/work_tree/add/file.sql"),
        },

        .init = .{
            .branch = @embedFile("sql/sqlite/work_tree/init/branch.sql"),
            .tables = @embedFile("sql/sqlite/work_tree/init/tables.sql"),
            .version = @embedFile("sql/sqlite/work_tree/init/version.sql"),
        },
    },
};

/// TODO: add postgres support
pub const postgres: SQLFiles = @compileError("PostgreSQL is not implemented yet.");

test "check if sqlfiles compiles" {
    // std.debug.print("\nWhat does SQLFiles look like? {}\n", .{SQLFiles});
    // std.debug.print("\nWhat does sqlite look like? {}\n", .{sqlite});
    // std.debug.print("\nWhat does postgres look like? {}\n", .{postgres});

    try std.testing.expectEqual(SQLFiles, @TypeOf(sqlite));
}
