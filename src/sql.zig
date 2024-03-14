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
        branch1: [:0]const u8,
        branch2: [:0]const u8,
        tables: [:0]const u8,
        version: [:0]const u8,
    },
};

/// A Repo can be implemented in any SQL database that supports foreign key
/// constraints, unique (string) keys, and transacitons. For now, only sqlite
/// is being implemented. Once that is fully working, a DB abstraction layer
/// can be defined and other DBs like postgres can be implemented.
pub const Repo = struct {
    commit: struct {
        blob: [:0]const u8,
        blob_chunk: [:0]const u8,
        chunk: [:0]const u8,
        header: [:0]const u8,
    },

    init: struct {
        branch1: [:0]const u8,
        branch2: [:0]const u8,
        tables: [:0]const u8,
        version: [:0]const u8,
    },
};

pub const sqlite = .{
    .repo = Repo{
        .commit = .{
            .blob = @embedFile("embedded/sql/sqlite/repo/commit/blob.sql"),
            .blob_chunk = @embedFile("embedded/sql/sqlite/repo/commit/blob_chunk.sql"),
            .chunk = @embedFile("embedded/sql/sqlite/repo/commit/chunk.sql"),
            .header = @embedFile("embedded/sql/sqlite/repo/commit/header.sql"),
        },

        .init = .{
            .branch1 = @embedFile("embedded/sql/sqlite/repo/init/branch1.sql"),
            .branch2 = @embedFile("embedded/sql/sqlite/repo/init/branch2.sql"),
            .tables = @embedFile("embedded/sql/sqlite/repo/init/tables.sql"),
            .version = @embedFile("embedded/sql/sqlite/repo/init/version.sql"),
        },
    },
    .work_tree = WorkTree{
        .clear = @embedFile("embedded/sql/sqlite/work_tree/clear.sql"),

        .read_blob_chunks = @embedFile("embedded/sql/sqlite/work_tree/read_blob_chunks.sql"),
        .read_blobs = @embedFile("embedded/sql/sqlite/work_tree/read_blobs.sql"),
        .read_chunks = @embedFile("embedded/sql/sqlite/work_tree/read_chunks.sql"),
        .read_head_commit = @embedFile("embedded/sql/sqlite/work_tree/read_head_commit.sql"),

        .add = .{
            .blob = @embedFile("embedded/sql/sqlite/work_tree/add/blob.sql"),
            .blob_chunk = @embedFile("embedded/sql/sqlite/work_tree/add/blob_chunk.sql"),
            .file = @embedFile("embedded/sql/sqlite/work_tree/add/file.sql"),
        },

        .init = .{
            .branch1 = @embedFile("embedded/sql/sqlite/work_tree/init/branch1.sql"),
            .branch2 = @embedFile("embedded/sql/sqlite/work_tree/init/branch2.sql"),
            .tables = @embedFile("embedded/sql/sqlite/work_tree/init/tables.sql"),
            .version = @embedFile("embedded/sql/sqlite/work_tree/init/version.sql"),
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
