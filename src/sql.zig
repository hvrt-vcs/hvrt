const std = @import("std");

/// Although a type is defined for WorkTree, the worktree DB is always going to
/// be SQLite, for the forseeable future.
pub const WorkTree = struct {
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
};

/// A Repo can be implemented in any SQL database that supports foreign key
/// constraints, unique (string) keys, and transacitons. For now, only sqlite
/// is being implemented. Once that is fully working, a DB abstraction layer
/// can be defined and other DBs like postgres can be implemented.
pub const Repo = struct {
    init: [:0]const u8,

    commit: struct {
        blob: [:0]const u8,
        blob_chunk: [:0]const u8,
        chunk: [:0]const u8,
        header: [:0]const u8,
    },
};

pub const sqlite = .{
    .repo = Repo{
        .init = @embedFile("sql/sqlite/repo/init.sql"),

        .commit = .{
            .blob = @embedFile("sql/sqlite/repo/commit/blob.sql"),
            .blob_chunk = @embedFile("sql/sqlite/repo/commit/blob_chunk.sql"),
            .chunk = @embedFile("sql/sqlite/repo/commit/chunk.sql"),
            .header = @embedFile("sql/sqlite/repo/commit/header.sql"),
        },
    },
    .work_tree = WorkTree{
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
pub const postgres = .{ .repo = @compileError("PostgreSQL is not implemented yet.") };

test "check if sqlfiles compiles" {
    try std.testing.expectEqual(WorkTree, @TypeOf(sqlite.work_tree));
    try std.testing.expectEqual(Repo, @TypeOf(sqlite.repo));
    // try std.testing.expectEqual(Repo, @TypeOf(postgres.repo));
}
